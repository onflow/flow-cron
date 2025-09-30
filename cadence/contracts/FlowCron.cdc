import "FlowTransactionScheduler"
import "FlowTransactionSchedulerUtils"
import "FlowCronUtils"
import "FlowToken"
import "FungibleToken"
import "ViewResolver"
import "MetadataViews"

/// FlowCron: Wraps any TransactionHandler with cron scheduling functionality.
///
/// FEATURES:
/// - Deterministic scheduling with consistent execution context
/// - Double scheduling pattern (next + future) for reliability
/// - Automatic gap-filling when transactions are missed
/// - Strict data consistency - rejects rescheduling once active
///
/// LIFECYCLE:
/// 1. Create: FlowCron.createCronHandler(expression, wrappedCap)
/// 2. Schedule: Use Flow scheduler with CronContext as data parameter
/// 3. Execute: Automatic execution with self-rescheduling
/// 4. Stop: Cancel both scheduled transactions
/// 5. Restart: Schedule again (allowed after all canceled)
///
/// DATA CONSISTENCY:
/// Once scheduled, the handler locks to the initial CronContext.
/// All executions use the same context (fees, priority, wrapped data).
/// To change parameters, cancel all transactions first.
access(all) contract FlowCron {
    
    /// Events
    access(all) event CronScheduleExecuted(handlerUUID: UInt64, txID: UInt64)
    access(all) event CronScheduleRejected(handlerUUID: UInt64, txID: UInt64)
    access(all) event CronScheduleFailed(handlerUUID: UInt64, requiredAmount: UFix64, availableAmount: UFix64)
    access(all) event CronEstimationFailed(handlerUUID: UInt64)
    
    /// CronHandler resource wraps any TransactionHandler with cron scheduling functionality
    access(all) resource CronHandler: FlowTransactionScheduler.TransactionHandler, ViewResolver.Resolver {

        /// Cron expression for scheduling
        access(all) let cronExpression: String
        /// Cron spec for scheduling
        access(all) let cronSpec: FlowCronUtils.CronSpec

        /// The handler that performs the actual work
        access(self) let wrappedHandlerCap: Capability<auth(FlowTransactionScheduler.Execute) &{FlowTransactionScheduler.TransactionHandler}>
        
        /// Internal state to track our scheduled transactions
        access(all) var nextScheduledTransactionID: UInt64?
        access(all) var futureScheduledTransactionID: UInt64?
        
        /// Track if this handler is scheduled to reject subsequent scheduling attempts
        access(self) var isScheduled: Bool
        
        init(
            cronExpression: String,
            wrappedHandlerCap: Capability<auth(FlowTransactionScheduler.Execute) &{FlowTransactionScheduler.TransactionHandler}>
        ) {
            pre {
                cronExpression.length > 0: "Cron expression cannot be empty"
                wrappedHandlerCap.check(): "Invalid wrapped handler capability provided"
            }

            self.cronExpression = cronExpression
            self.cronSpec = FlowCronUtils.parse(expression: cronExpression) ?? panic("Invalid cron expression: ".concat(cronExpression))
            self.wrappedHandlerCap = wrappedHandlerCap
            self.nextScheduledTransactionID = nil
            self.futureScheduledTransactionID = nil
            self.isScheduled = false
        }
        
        access(FlowTransactionScheduler.Execute) fun executeTransaction(id: UInt64, data: AnyStruct?) {
            // Sync schedule state and determine execution type
            self.syncSchedule()

            // Handle execution based on type
            if self.isExpectedTransaction(id: id) {
                self.updateSchedule(executedID: id)
            } else {
                // Reject subsequent scheduling once handler is scheduled
                // This ensures that the handler is not scheduled multiple times with different data
                if self.isScheduled {
                    emit CronScheduleRejected(handlerUUID: self.uuid, txID: id)
                    return
                }
            }

            // Extract execution context
            let context = data as? CronContext ?? panic("Invalid execution data: expected CronContext")        
            // Ensure double scheduling filling the schedule with the next and future transactions if needed
            self.fillSchedule(context: context)
            
            // Execute wrapped handler last to ensure cron scheduling completes first
            let wrappedHandler = self.wrappedHandlerCap.borrow() ?? panic("Cannot borrow wrapped handler capability")
            wrappedHandler.executeTransaction(id: id, data: context.wrappedData)
            
            // Emit event only after successful execution
            emit CronScheduleExecuted(handlerUUID: self.uuid, txID: id)
        }

        /// Syncs internal schedule state with external transaction scheduler
        access(self) fun syncSchedule() {
            var hasValidNext = false
            var hasValidFuture = false
            
            if let nextID = self.nextScheduledTransactionID {
                if let txData = FlowTransactionScheduler.getTransactionData(id: nextID) {
                    if txData.status == FlowTransactionScheduler.Status.Scheduled {
                        hasValidNext = true
                    } else {
                        self.nextScheduledTransactionID = nil
                    }
                } else {
                    self.nextScheduledTransactionID = nil
                }
            }
            if let futureID = self.futureScheduledTransactionID {
                if let txData = FlowTransactionScheduler.getTransactionData(id: futureID) {
                    if txData.status == FlowTransactionScheduler.Status.Scheduled {
                        hasValidFuture = true
                    } else {
                        self.futureScheduledTransactionID = nil
                    }
                } else {
                    self.futureScheduledTransactionID = nil
                }
            }
            
            // Update scheduled status based on transaction state
            if !hasValidNext && !hasValidFuture {
                // Reset if no valid transactions remain (allows rescheduling)
                self.isScheduled = false
            } else if !self.isScheduled {
                // Mark as scheduled if we have valid transactions but flag isn't set yet
                self.isScheduled = true
            }
        }
        
        /// Checks if the given transaction ID is one we're expecting to execute
        access(self) view fun isExpectedTransaction(id: UInt64): Bool {
            return id == self.nextScheduledTransactionID || id == self.futureScheduledTransactionID
        }
        
        /// Updates internal state after executing an expected transaction
        access(self) fun updateSchedule(executedID: UInt64) {
            // Update state based on the executed transaction ID
            if executedID == self.nextScheduledTransactionID {
                self.nextScheduledTransactionID = self.futureScheduledTransactionID
                self.futureScheduledTransactionID = nil
            } else if executedID == self.futureScheduledTransactionID {
                self.futureScheduledTransactionID = nil
            }
        }
        
        /// Ensures double scheduling by filling gaps in next/future transactions
        access(self) fun fillSchedule(context: CronContext) {
            // Check what we need to schedule
            let needsNext = self.nextScheduledTransactionID == nil
            let needsFuture = self.futureScheduledTransactionID == nil
            // If both are already scheduled, nothing to do
            if !needsNext && !needsFuture {
                return
            }

            // Get current time and calculate next and future execution time from cron spec
            let currentTime = UInt64(getCurrentBlock().timestamp)
            let nextTime = FlowCronUtils.nextTick(spec: self.cronSpec, afterUnix: currentTime) ?? panic("Cannot find next execution time for cron expression")
            let futureTime = FlowCronUtils.nextTick(spec: self.cronSpec, afterUnix: nextTime) ?? panic("Cannot find future execution time for cron expression")

            // Borrow capabilities we'll need
            let schedulerManager = context.schedulerManagerCap.borrow() ?? panic("Cannot borrow scheduler manager capability")
            let feeVault = context.feeProviderCap.borrow() ?? panic("Cannot borrow fee provider capability")
            // Schedule next transaction if needed
            if needsNext {
                // Estimate fees for next transaction
                let estimateNext = FlowTransactionScheduler.estimate(
                    data: context,
                    timestamp: UFix64(nextTime),
                    priority: context.priority,
                    executionEffort: context.executionEffort
                )
                
                // Check if we got a fee estimate
                if let requiredFee = estimateNext.flowFee {
                    // Check if we have enough funds
                    if feeVault.balance >= requiredFee {
                        // Withdraw fees and schedule
                        let fees <- feeVault.withdraw(amount: requiredFee)
                        let transactionId = schedulerManager.scheduleByHandler(
                            handlerTypeIdentifier: self.getType().identifier,
                            handlerUUID: self.uuid,
                            data: context,
                            timestamp: UFix64(nextTime),
                            priority: context.priority,
                            executionEffort: context.executionEffort,
                            fees: <-fees as! @FlowToken.Vault
                        )
                        self.nextScheduledTransactionID = transactionId
                    } else {
                        // Not enough funds
                        emit CronScheduleFailed(
                            handlerUUID: self.uuid,
                            requiredAmount: requiredFee,
                            availableAmount: feeVault.balance
                        )
                    }
                } else {
                    // Fee estimation failed
                    emit CronEstimationFailed(handlerUUID: self.uuid)
                }
            }
            
            // Schedule future transaction if needed
            if needsFuture {
                // Estimate fees for future transaction
                let estimateFuture = FlowTransactionScheduler.estimate(
                    data: context,
                    timestamp: UFix64(futureTime),
                    priority: context.priority,
                    executionEffort: context.executionEffort
                )
                
                // Check if we got a fee estimate
                if let requiredFee = estimateFuture.flowFee {
                    // Check if we have enough funds
                    if feeVault.balance >= requiredFee {
                        // Withdraw fees and schedule
                        let fees <- feeVault.withdraw(amount: requiredFee)
                        let transactionId = schedulerManager.scheduleByHandler(
                            handlerTypeIdentifier: self.getType().identifier,
                            handlerUUID: self.uuid,
                            data: context,
                            timestamp: UFix64(futureTime),
                            priority: context.priority,
                            executionEffort: context.executionEffort,
                            fees: <-fees as! @FlowToken.Vault
                        )
                        self.futureScheduledTransactionID = transactionId
                    } else {
                        // Not enough funds
                        emit CronScheduleFailed(
                            handlerUUID: self.uuid,
                            requiredAmount: requiredFee,
                            availableAmount: feeVault.balance
                        )
                    }
                } else {
                    // Fee estimation failed
                    emit CronEstimationFailed(handlerUUID: self.uuid)
                }
            }
        }

        /// Returns a copy of the cron spec for use in calculations
        access(all) fun getCronSpec(): FlowCronUtils.CronSpec {
            return self.cronSpec
        }
        
        access(all) view fun getViews(): [Type] {
            var views: [Type] = [
                Type<MetadataViews.Display>(),
                Type<CronInfo>()
            ]
            
            if let handler = self.wrappedHandlerCap.borrow() {
                views = views.concat(handler.getViews())
            }
            return views
        }
        
        access(all) fun resolveView(_ view: Type): AnyStruct? {
            let wrappedHandler = self.wrappedHandlerCap.borrow()
            switch view {  
                case Type<MetadataViews.Display>():
                    return MetadataViews.Display(
                        name: "Cron Handler",
                        description: "Cron expression: ".concat(self.cronExpression).concat(" for handler: ").concat(wrappedHandler?.getType()?.identifier ?? ""),
                        thumbnail: MetadataViews.HTTPFile(url: "")
                    )
                case Type<CronInfo>():
                    // Check actual scheduled transaction times instead of calculating from cron spec
                    // This ensures we return accurate state even if transactions were cancelled
                    var nextExecution: UInt64? = nil
                    var futureExecution: UInt64? = nil

                    // Try to get actual scheduled transaction times
                    if let nextID = self.nextScheduledTransactionID {
                        if let txData = FlowTransactionScheduler.getTransactionData(id: nextID) {
                            if txData.status == FlowTransactionScheduler.Status.Scheduled {
                                nextExecution = UInt64(txData.scheduledTimestamp)
                            }
                        }
                    }

                    if let futureID = self.futureScheduledTransactionID {
                        if let txData = FlowTransactionScheduler.getTransactionData(id: futureID) {
                            if txData.status == FlowTransactionScheduler.Status.Scheduled {
                                futureExecution = UInt64(txData.scheduledTimestamp)
                            }
                        }
                    }

                    // Fall back to calculated times if no active scheduled transactions
                    if nextExecution == nil && futureExecution == nil {
                        let currentTime = UInt64(getCurrentBlock().timestamp)
                        nextExecution = FlowCronUtils.nextTick(spec: self.cronSpec, afterUnix: currentTime)
                        if let next = nextExecution {
                            futureExecution = FlowCronUtils.nextTick(spec: self.cronSpec, afterUnix: next)
                        }
                    }

                    return CronInfo(
                        cronExpression: self.cronExpression,
                        cronSpec: self.cronSpec,
                        nextExecution: nextExecution,
                        futureExecution: futureExecution,
                        wrappedHandlerType: wrappedHandler?.getType()?.identifier,
                        wrappedHandlerUUID: wrappedHandler?.uuid
                    )
                default:
                    return wrappedHandler?.resolveView(view)
            }
        }
    }

    /// Context passed to each cron execution containing scheduler and fee capabilities
    access(all) struct CronContext {
        access(all) let schedulerManagerCap: Capability<auth(FlowTransactionSchedulerUtils.Owner) &{FlowTransactionSchedulerUtils.Manager}>
        access(all) let feeProviderCap: Capability<auth(FungibleToken.Withdraw) &FlowToken.Vault>
        access(all) let priority: FlowTransactionScheduler.Priority
        access(all) let executionEffort: UInt64
        access(all) let wrappedData: AnyStruct?
        
        init(
            schedulerManagerCap: Capability<auth(FlowTransactionSchedulerUtils.Owner) &{FlowTransactionSchedulerUtils.Manager}>,
            feeProviderCap: Capability<auth(FungibleToken.Withdraw) &FlowToken.Vault>,
            priority: FlowTransactionScheduler.Priority,
            executionEffort: UInt64,
            wrappedData: AnyStruct?
        ) {
            pre {
                schedulerManagerCap.check(): "Invalid scheduler manager capability"
                feeProviderCap.check(): "Invalid fee provider capability"
                executionEffort > 0: "Execution effort must be greater than 0"
            }
            
            self.schedulerManagerCap = schedulerManagerCap
            self.feeProviderCap = feeProviderCap
            self.priority = priority
            self.executionEffort = executionEffort
            self.wrappedData = wrappedData
        }
    }
    
    /// View structure exposing cron handler metadata and schedule information
    access(all) struct CronInfo {
        /// The original cron expression string
        access(all) let cronExpression: String
        /// Parsed cron specification for execution
        access(all) let cronSpec: FlowCronUtils.CronSpec
        /// Unix timestamp of next scheduled execution
        access(all) let nextExecution: UInt64?
        /// Unix timestamp of future scheduled execution
        access(all) let futureExecution: UInt64?
        /// Type identifier of wrapped handler
        access(all) let wrappedHandlerType: String?
        /// UUID of wrapped handler resource
        access(all) let wrappedHandlerUUID: UInt64?
        
        init(
            cronExpression: String,
            cronSpec: FlowCronUtils.CronSpec,
            nextExecution: UInt64?,
            futureExecution: UInt64?,
            wrappedHandlerType: String?,
            wrappedHandlerUUID: UInt64?
        ) {
            self.cronExpression = cronExpression
            self.cronSpec = cronSpec
            self.nextExecution = nextExecution
            self.futureExecution = futureExecution
            self.wrappedHandlerType = wrappedHandlerType
            self.wrappedHandlerUUID = wrappedHandlerUUID
        }
    }

    /// Create a new CronHandler resource
    access(all) fun createCronHandler(
        cronExpression: String,
        wrappedHandlerCap: Capability<auth(FlowTransactionScheduler.Execute) &{FlowTransactionScheduler.TransactionHandler}>
    ): @CronHandler {
        return <- create CronHandler(
            cronExpression: cronExpression,
            wrappedHandlerCap: wrappedHandlerCap
        )
    }
    
    init() {}
}