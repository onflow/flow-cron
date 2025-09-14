import "FlowTransactionScheduler"
import "FlowTransactionSchedulerUtils"
import "FlowCronUtils"
import "FlowToken"
import "FungibleToken"
import "ViewResolver"

/// FlowCron: A utility for scheduling recurring transactions using cron expressions.
access(all) contract FlowCron {
    
    /// Storage and public paths for CronHandler resources
    access(all) let CronHandlerStoragePath: StoragePath
    access(all) let CronHandlerPublicPath: PublicPath
    
    /// Entitlements
    access(all) entitlement Owner
    
    /// Events
    access(all) event CronJobScheduled(jobId: UInt64, nextExecution: UFix64)
    access(all) event CronJobExecuted(jobId: UInt64, executionCount: UInt64)
    access(all) event CronJobCancelled(jobId: UInt64)
    
    /// CronHandler resource that manages cron jobs for a user
    access(all) resource CronHandler: FlowTransactionScheduler.TransactionHandler, ViewResolver.Resolver {
        
        /// Dictionary of cron jobs
        access(self) var jobs: @{UInt64: CronJob}
        
        /// Next job Id to assign
        access(contract) var nextJobId: UInt64
        
        /// Mapping of transaction Ids to job Ids
        /// This is the single source of truth for job-transaction relationships
        access(self) var transactionToJob: {UInt64: UInt64}
        
        init() {
            self.jobs <- {}
            self.nextJobId = 1
            self.transactionToJob = {}
        }
        
        /// Method for scheduling cron jobs with all capabilities
        access(Owner) fun scheduleJob(
            cronSpec: FlowCronUtils.CronSpec,
            cronHandlerCap: Capability<auth(FlowTransactionScheduler.Execute) &{FlowTransactionScheduler.TransactionHandler}>,
            wrappedHandlerCap: Capability<auth(FlowTransactionScheduler.Execute) &{FlowTransactionScheduler.TransactionHandler}>,
            schedulerManagerCap: Capability<auth(FlowTransactionSchedulerUtils.Owner) &FlowTransactionSchedulerUtils.Manager>,
            feeProviderCap: Capability<auth(FungibleToken.Withdraw) &FlowToken.Vault>,
            data: AnyStruct?,
            priority: FlowTransactionScheduler.Priority,
            executionEffort: UInt64
        ): UInt64 {
            // Verify the cronHandler capability belongs to this account exactly
            // This is enough because there could be only one cron handler per account
            assert(
                cronHandlerCap.address == self.owner?.address,
                message: "The cronHandler capability must belong to this CronHandler's owner"
            )

            // Clean up completed or invalid jobs
            let _ = self.cleanup()
            
            // Get job Id and increment counter
            let jobId = self.nextJobId
            self.nextJobId = self.nextJobId + 1
            
            // Create and store cron job internally
            let job <- create CronJob(
                id: jobId,
                cronSpec: cronSpec,
                wrappedHandlerCap: wrappedHandlerCap,
                createdAt: getCurrentBlock().timestamp
            )
            self.jobs[jobId] <-! job

            // Create execution context that will be used to execute the cron job
            // It contains all the necessary information to execute the cron job and to reschedule it
            let context = CronJobContext(
                jobId: jobId,
                cronSpec: cronSpec,
                cronHandlerCap: cronHandlerCap,
                schedulerManagerCap: schedulerManagerCap,
                feeProviderCap: feeProviderCap,
                data: data,
                priority: priority,
                executionEffort: executionEffort
            )
            
            // Calculate next execution time
            let currentTime = UInt64(getCurrentBlock().timestamp)
            let nextTime = FlowCronUtils.nextTick(spec: cronSpec, afterUnix: currentTime)
                ?? panic("Cannot find next execution time for cron expression")
            // Calculate future execution time for double scheduling
            // To add redundancy and be sure that the cron job continues even if the next execution fails
            // We will always keep 2 scheduled executions 1 for the next and the 2 for the future
            let futureTime = FlowCronUtils.nextTick(spec: cronSpec, afterUnix: nextTime)
                ?? panic("Cannot find future execution time for cron expression")
            
            // Schedule both next and future transactions
            let nextTransactionId = self.scheduleTransaction(
                jobId: jobId,
                context: context,
                timestamp: UFix64(nextTime),
            )
            let futureTransactionId = self.scheduleTransaction(
                jobId: jobId,
                context: context,
                timestamp: UFix64(futureTime)
            )
            
            // Update job's execution time
            let jobRef = &self.jobs[jobId] as &CronJob?
            jobRef!.setExecutionTime(lastExecution: nil, nextExecution: UFix64(nextTime), futureExecution: UFix64(futureTime))
            
            return jobId
        }
        
        /// Execute a scheduled cron job and reschedule for next execution
        access(FlowTransactionScheduler.Execute) fun executeTransaction(id: UInt64, data: AnyStruct?) {
            // Extract execution context
            let context = data as? CronJobContext
                ?? panic("Invalid execution data: expected CronJobContext")
            
            // Get the job Id associated with the transaction through context
            let jobId = context.jobId
            // Get the cron job
            let jobRef = &self.jobs[jobId] as &CronJob?
                ?? panic("Cron job not found: ".concat(jobId.toString()))

            // 1. SCHEDULE FUTURE TRANSACTION FIRST (ensure continuity)
            // Get the future execution time for rescheduling that is the next execution after the next execution (future)
            // This will prevent the cron job from being blocked if the next execution fails
            let futureTime = FlowCronUtils.nextTick(spec: context.cronSpec, afterUnix: UInt64(jobRef.nextExecution!))
                ?? panic("Cannot find future execution time for cron expression")
            // Schedule the new future transaction using helper function
            let futureTransactionId = self.scheduleTransaction(
                jobId: jobId,
                context: context,
                timestamp: UFix64(futureTime),
            )

            // 2. UPDATE JOB STATE (move execution times forward)
            jobRef.setExecutionTime(lastExecution: jobRef.nextExecution!, nextExecution: jobRef.futureExecution!, futureExecution: UFix64(futureTime))
            
            // 3. CLEAN UP OLD TRANSACTION MAPPINGS
            let _ = self.transactionToJob.remove(key: id)
            
            // 4. EXECUTE THE CURRENT JOB (Last risky user code that may fail)
            // This is isolated so that if it fails, all cron infrastructure is already updated
            jobRef.executeJob(id: id, data: context.data)
            // Emit execution event (only if execution succeeded)
            emit CronJobExecuted(
                jobId: jobId,
                executionCount: jobRef.executionCount
            )
        }

        /// Cancel a cron job
        access(Owner) fun cancelJob(
            jobId: UInt64,
            schedulerManagerCap: Capability<auth(FlowTransactionSchedulerUtils.Owner) &FlowTransactionSchedulerUtils.Manager>
        ): @FlowToken.Vault {
            pre {
                self.jobs.containsKey(jobId): "Cron job not found"
            }
            
            // Clean up first to remove any invalid/executed transactions
            let _ = self.cleanup()
            
            // Prepare refund vault to collect refunds
            var totalRefund <- FlowToken.createEmptyVault(vaultType: Type<@FlowToken.Vault>())
            
            // Borrow scheduler manager to cancel transactions if needed
            let schedulerManager = schedulerManagerCap.borrow()
                ?? panic("Cannot borrow scheduler manager capability")
            // Find and cancel all transactions for this job, after this, only scheduled transactions remain
            for transactionId in self.transactionToJob.keys {
                if self.transactionToJob[transactionId] == jobId {
                    let refund <- schedulerManager.cancel(id: transactionId)
                    totalRefund.deposit(from: <-refund)
                    let _ = self.transactionToJob.remove(key: transactionId)
                }
            }
            
            // Remove job destroying it
            destroy self.jobs.remove(key: jobId)!
            // Emit event (always, even if no transactions were actually cancelled)
            emit CronJobCancelled(jobId: jobId)
            
            return <-totalRefund
        }
        
        /// Clean up completed or invalid jobs
        /// Only removes jobs that have no scheduled transactions remaining
        access(Owner) fun cleanup(): Int {
            var cleanedUpCount = 0
            var jobsWithScheduledTransactions: {UInt64: Bool} = {}
            
            // Single loop: clean invalid transactions and track jobs with scheduled ones
            for transactionId in self.transactionToJob.keys {
                let jobId = self.transactionToJob[transactionId]!
                
                // Check if job still exists
                if !self.jobs.containsKey(jobId) {
                    let _ = self.transactionToJob.remove(key: transactionId)
                    cleanedUpCount = cleanedUpCount + 1
                    continue
                }
                
                // Check if transaction is still scheduled
                let status = FlowTransactionScheduler.getStatus(id: transactionId)
                if status == FlowTransactionScheduler.Status.Scheduled {
                    // Mark job as having scheduled transactions
                    jobsWithScheduledTransactions[jobId] = true
                } else {
                    // Remove non-scheduled transaction
                    let _ = self.transactionToJob.remove(key: transactionId)
                    cleanedUpCount = cleanedUpCount + 1
                }
            }
            
            // Remove jobs that have no scheduled transactions
            for jobId in self.jobs.keys {
                if jobsWithScheduledTransactions[jobId] != true {
                    destroy self.jobs.remove(key: jobId)
                    cleanedUpCount = cleanedUpCount + 1
                }
            }     
            return cleanedUpCount
        }

        /// Get a reference to a specific job
        access(all) fun getJob(jobId: UInt64): &CronJob? {
            return &self.jobs[jobId]
        }
        
        /// Get all job Ids
        access(all) fun getJobIds(): [UInt64] {
            return self.jobs.keys
        }
        
        /// Get all transaction IDs for a specific job
        access(all) fun getTransactionIdsForJob(jobId: UInt64): [UInt64] {
            var transactionIds: [UInt64] = []
            for transactionId in self.transactionToJob.keys {
                if self.transactionToJob[transactionId] == jobId {
                    transactionIds.append(transactionId)
                }
            }
            return transactionIds
        }
        
        /// ViewResolver implementation
        access(all) view fun getViews(): [Type] {
            return [
                Type<CronJobListView>()
            ]
        }
        
        access(all) fun resolveView(_ view: Type): AnyStruct? {
            switch view {
                case Type<CronJobListView>():
                    var jobs: {UInt64: CronJobView} = {}
                    for jobId in self.jobs.keys {
                        let jobRef = &self.jobs[jobId] as &CronJob?
                        if jobRef != nil {
                            // Get job info using the job's ViewResolver
                            let jobInfo = jobRef!.resolveView(Type<CronJobInfo>()) as! CronJobInfo?
                            if jobInfo != nil {
                                jobs[jobId] = CronJobView(
                                    jobInfo: jobInfo!,
                                    transactionIds: self.getTransactionIdsForJob(jobId: jobId)
                                )
                            }
                        }
                    }
                    return CronJobListView(jobs: jobs)
            }
            return nil
        }

        /// Internal helper function to schedule a single transaction
        /// Handles fee estimation, withdrawal, and scheduling
        access(self) fun scheduleTransaction(
            jobId: UInt64,
            context: CronJobContext,
            timestamp: UFix64,
        ): UInt64 {
            // Estimate fees
            let estimate = FlowTransactionScheduler.estimate(
                data: context,
                timestamp: timestamp,
                priority: context.priority,
                executionEffort: context.executionEffort
            )
            if estimate.flowFee == nil {
                panic(estimate.error ?? "Failed to estimate transaction fee")
            }
            
            // Borrow fee provider and withdraw fees
            let feeVault = context.feeProviderCap.borrow()
                ?? panic("Cannot borrow fee provider capability")
            let fees <- feeVault.withdraw(amount: estimate.flowFee!)
            
            // Borrow scheduler manager and schedule transaction
            let schedulerManager = context.schedulerManagerCap.borrow()
                ?? panic("Cannot borrow scheduler manager capability")
            let transactionId = schedulerManager.schedule(
                handlerCap: context.cronHandlerCap,
                data: context,
                timestamp: timestamp,
                priority: context.priority,
                executionEffort: context.executionEffort,
                fees: <-fees as! @FlowToken.Vault
            )
            // Update mappings
            self.transactionToJob[transactionId] = jobId
            
            // Always emit event when scheduling a transaction
            emit CronJobScheduled(
                jobId: jobId,
                nextExecution: timestamp
            )
            
            return transactionId
        }
    }
    
    /// View structure for individual cron job information
    access(all) struct CronJobInfo {
        access(all) let id: UInt64
        access(all) let executionCount: UInt64
        access(all) let lastExecution: UFix64?
        access(all) let nextExecution: UFix64?
        access(all) let futureExecution: UFix64?
        access(all) let createdAt: UFix64
        
        init(
            id: UInt64,
            executionCount: UInt64,
            lastExecution: UFix64?,
            nextExecution: UFix64?,
            futureExecution: UFix64?,
            createdAt: UFix64
        ) {
            self.id = id
            self.executionCount = executionCount
            self.lastExecution = lastExecution
            self.nextExecution = nextExecution
            self.futureExecution = futureExecution
            self.createdAt = createdAt
        }
    }
    
    /// Individual cron job resource
    access(all) resource CronJob: ViewResolver.Resolver {

        // The id of the cron job
        access(all) let id: UInt64
        // The cron spec of the cron job
        access(all) let cronSpec: FlowCronUtils.CronSpec

        // Wrapped handler cap is into the cron job to be able to retrieve its data for views
        // If it was just in context we wouldn't be able to retrieve the data for views
        access(contract) let wrappedHandlerCap: Capability<auth(FlowTransactionScheduler.Execute) &{FlowTransactionScheduler.TransactionHandler}>
        
        // The timestamp of the creation of the cron job
        access(all) let createdAt: UFix64
        
        // The number of times the cron job has been executed
        access(all) var executionCount: UInt64

        // The timestamp of the last execution
        access(all) var lastExecution: UFix64?
        // The timestamp of the next execution
        access(all) var nextExecution: UFix64?
        // The timestamp of the future execution
        access(all) var futureExecution: UFix64?
        
        init(
            id: UInt64,
            cronSpec: FlowCronUtils.CronSpec,
            wrappedHandlerCap: Capability<auth(FlowTransactionScheduler.Execute) &{FlowTransactionScheduler.TransactionHandler}>,
            createdAt: UFix64
        ) {
            self.id = id
            self.cronSpec = cronSpec
            self.wrappedHandlerCap = wrappedHandlerCap
            self.createdAt = createdAt
            self.executionCount = 0
            self.lastExecution = nil
            self.nextExecution = nil
            self.futureExecution = nil
        }
        
        /// Execute the wrapped handler
        access(contract) fun executeJob(id: UInt64, data: AnyStruct?) {
            let wrappedHandler = self.wrappedHandlerCap.borrow()
                ?? panic("Cannot borrow handler capability")
            
            // Execute the wrapped handler with the same data as it would receive if it was executed directly
            wrappedHandler.executeTransaction(id: id, data: data)
            
            // Here we just update state stats or data
            self.executionCount = self.executionCount + 1
        }
        
        /// ViewResolver implementation
        access(all) view fun getViews(): [Type] {
            var allViews: [Type] = [Type<CronJobInfo>()] // job's own views
            
            // Add wrapped handler views
            if let handler = self.wrappedHandlerCap.borrow() {
                allViews = allViews.concat(handler.getViews())
            }
            
            return allViews
        }
        
        access(all) fun resolveView(_ view: Type): AnyStruct? {
            switch view {
                case Type<CronJobInfo>():
                    return CronJobInfo(
                        id: self.id,
                        executionCount: self.executionCount,
                        lastExecution: self.lastExecution,
                        nextExecution: self.nextExecution,
                        futureExecution: self.futureExecution,
                        createdAt: self.createdAt
                    )
            }
            
            // Try wrapped handler views
            if let handler = self.wrappedHandlerCap.borrow() {
                return handler.resolveView(view)
            }
            
            return nil
        }
        
        /// Set execution time for last, next and future execution
        access(contract) fun setExecutionTime(lastExecution: UFix64?, nextExecution: UFix64?, futureExecution: UFix64?) {
            self.lastExecution = lastExecution
            self.nextExecution = nextExecution
            self.futureExecution = futureExecution
        }
    }
    
    /// Context passed with each execution for rescheduling
    // It contains all the necessary information to execute the cron job and to reschedule it
    // This data is unaccessible and it's just what is needed to execute and reschedule the cron job
    access(all) struct CronJobContext {
        access(all) let jobId: UInt64
        access(all) let cronSpec: FlowCronUtils.CronSpec
        access(all) let cronHandlerCap: Capability<auth(FlowTransactionScheduler.Execute) &{FlowTransactionScheduler.TransactionHandler}>
        access(all) let schedulerManagerCap: Capability<auth(FlowTransactionSchedulerUtils.Owner) &FlowTransactionSchedulerUtils.Manager>
        access(all) let feeProviderCap: Capability<auth(FungibleToken.Withdraw) &FlowToken.Vault>
        access(all) let data: AnyStruct?
        access(all) let priority: FlowTransactionScheduler.Priority
        access(all) let executionEffort: UInt64
        
        init(
            jobId: UInt64,
            cronSpec: FlowCronUtils.CronSpec,
            cronHandlerCap: Capability<auth(FlowTransactionScheduler.Execute) &{FlowTransactionScheduler.TransactionHandler}>,
            schedulerManagerCap: Capability<auth(FlowTransactionSchedulerUtils.Owner) &FlowTransactionSchedulerUtils.Manager>,
            feeProviderCap: Capability<auth(FungibleToken.Withdraw) &FlowToken.Vault>,
            data: AnyStruct?,
            priority: FlowTransactionScheduler.Priority,
            executionEffort: UInt64
        ) {
            self.jobId = jobId
            self.cronSpec = cronSpec
            self.cronHandlerCap = cronHandlerCap
            self.schedulerManagerCap = schedulerManagerCap
            self.feeProviderCap = feeProviderCap
            self.data = data
            self.priority = priority
            self.executionEffort = executionEffort
        }
    }
    
    /// View structures
    access(all) struct CronJobView {
        access(all) let jobInfo: CronJobInfo
        access(all) let transactionIds: [UInt64]
        
        init(
            jobInfo: CronJobInfo,
            transactionIds: [UInt64]
        ) {
            self.jobInfo = jobInfo
            self.transactionIds = transactionIds
        }
    }
    
    access(all) struct CronJobListView {
        access(all) let jobs: {UInt64: CronJobView}
        
        init(jobs: {UInt64: CronJobView}) {
            self.jobs = jobs
        }
    }
    
    /// Create a new CronHandler instance
    access(all) fun createHandler(): @CronHandler {
        return <-create CronHandler()
    }
    
    init() {
        self.CronHandlerStoragePath = /storage/flowCronHandler
        self.CronHandlerPublicPath = /public/flowCronHandler
    }
}