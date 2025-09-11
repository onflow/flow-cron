import "FlowTransactionScheduler"
import "FlowTransactionSchedulerUtils"
import "FlowCronParser"
import "FlowToken"
import "FungibleToken"

/// FlowCron: Lightweight cron-based scheduling for recurring transactions on Flow blockchain.
/// 
/// This utility contract wraps any TransactionHandler with autonomous cron functionality,
/// enabling recurring executions based on cron expressions parsed into efficient bitmasks.
/// Built on FlowTransactionScheduler and FlowTransactionSchedulerUtils for seamless integration.
access(all) contract FlowCron {
    
    /// Emitted when a new cron job is created
    access(all) event CronJobCreated(
        handlerAddress: Address,
        firstExecution: UFix64,
        executionEffort: UInt64,
        priority: UInt8
    )
    
    /// Emitted after each cron job execution (before rescheduling next execution)
    access(all) event CronJobExecuted(
        transactionId: UInt64, 
        nextExecution: UFix64?,
        executionTimestamp: UFix64
    )
    
    /// Emitted when a cron job is canceled through FlowCron
    access(all) event CronJobCanceled(transactionId: UInt64)

    /// Configuration struct for cron jobs
    /// 
    /// Contains all necessary information for cron job execution and rescheduling.
    /// This struct is stored as data in FlowTransactionScheduler and passed to CronManager
    /// during transaction execution for automatic rescheduling.
    access(all) struct CronJobConfig {
        access(all) let handler: Capability<auth(FlowTransactionScheduler.Execute) &{FlowTransactionScheduler.TransactionHandler}>
        access(all) let manager: Capability<auth(FlowTransactionSchedulerUtils.Owner) &FlowTransactionSchedulerUtils.Manager>
        access(all) let data: AnyStruct?
        access(all) let cronSpec: FlowCronParser.CronSpec
        access(all) let priority: FlowTransactionScheduler.Priority
        access(all) let executionEffort: UInt64
        access(all) let feeProvider: Capability<auth(FungibleToken.Withdraw) &FlowToken.Vault>

        init(
            handler: Capability<auth(FlowTransactionScheduler.Execute) &{FlowTransactionScheduler.TransactionHandler}>,
            manager: Capability<auth(FlowTransactionSchedulerUtils.Owner) &FlowTransactionSchedulerUtils.Manager>,
            data: AnyStruct?,
            cronSpec: FlowCronParser.CronSpec,
            priority: FlowTransactionScheduler.Priority,
            executionEffort: UInt64,
            feeProvider: Capability<auth(FungibleToken.Withdraw) &FlowToken.Vault>
        ) {
            self.handler = handler
            self.manager = manager
            self.data = data
            self.cronSpec = cronSpec
            self.priority = priority
            self.executionEffort = executionEffort
            self.feeProvider = feeProvider
        }
    }

    /// Display data for cron jobs in client applications
    /// 
    /// Contains essential information for building cron job management interfaces.
    /// All data is sourced from FlowTransactionScheduler.TransactionData for consistency.
    access(all) struct CronJobDisplayData {
        access(all) let transactionId: UInt64
        access(all) let name: String
        access(all) let status: FlowTransactionScheduler.Status
        access(all) let nextExecution: UFix64
        access(all) let priority: FlowTransactionScheduler.Priority
        access(all) let executionEffort: UInt64
        access(all) let fees: UFix64
        access(all) let owner: Address
        
        init(
            transactionId: UInt64,
            name: String,
            status: FlowTransactionScheduler.Status,
            nextExecution: UFix64,
            priority: FlowTransactionScheduler.Priority,
            executionEffort: UInt64,
            fees: UFix64,
            owner: Address
        ) {
            self.transactionId = transactionId
            self.name = name
            self.status = status
            self.nextExecution = nextExecution
            self.priority = priority
            self.executionEffort = executionEffort
            self.fees = fees
            self.owner = owner
        }
    }

    /// Centralized manager that handles cron job execution for all users
    /// 
    /// Implements TransactionHandler interface to receive scheduled transactions from FlowTransactionScheduler.
    /// When a cron job executes, this manager:
    /// 1. Executes the user's wrapped handler
    /// 2. Calculates the next execution time using efficient cron algorithm  
    /// 3. Reschedules the job through the user's Manager for proper management integration
    access(all) resource CronManager: FlowTransactionScheduler.TransactionHandler {
        access(all) let name: String
        access(all) let description: String

        init(name: String, description: String) {
            pre {
                name.length < 40: "Callback handler name must be less than 40 characters"
                description.length < 200: "Callback handler description must be less than 200 characters"
            }
            self.name = name
            self.description = description
        }
        
        /// Executes a cron job and automatically reschedules the next execution
        /// Called by FlowTransactionScheduler when a scheduled transaction is triggered
        access(FlowTransactionScheduler.Execute)
        fun executeTransaction(id: UInt64, data: AnyStruct?) {
            let config = data as! CronJobConfig
            
            log("Executing cron job ID: ".concat(id.toString()))
            
            // Execute the user's handler
            let userHandler = config.handler.borrow()
                ?? panic("Cannot borrow user handler capability")
            userHandler.executeTransaction(id: id, data: config.data)
            
            // Use user's Manager for rescheduling
            let userManager = config.manager.borrow()
                ?? panic("Cannot borrow user's transaction manager capability for rescheduling")
            
            // Calculate and schedule next execution using internal helper
            let currentTime = UInt64(getCurrentBlock().timestamp)
            let nextTimeUFix64 = FlowCron.internalSchedule(
                config: config,
                afterUnix: currentTime,
                manager: userManager
            )
            
            emit CronJobExecuted(
                transactionId: id, 
                nextExecution: nextTimeUFix64,
                executionTimestamp: getCurrentBlock().timestamp
            )
        }

        access(all) view fun getViews(): [Type] {
            return []
        }

        access(all) fun resolveView(_ view: Type): AnyStruct? {
            return nil
        }
    }

    /// Schedule a cron job using the user's CallbackManager
    /// @param handler: The callback handler to wrap with cron scheduling
    /// @param callbackManager: User's CallbackManager for managing the scheduled callback
    /// @param data: Data to pass to the handler on each execution
    /// @param cronSpec: CronSpec bitmasks defining the schedule
    /// @param priority: Priority level for execution (High/Medium/Low)
    /// @param executionEffort: Computational effort required for execution
    /// @param feeProvider: Capability to withdraw fees for scheduling (fees calculated automatically)
    access(all) fun scheduleCronJob(
        handler: Capability<auth(FlowTransactionScheduler.Execute) &{FlowTransactionScheduler.TransactionHandler}>,
        manager: Capability<auth(FlowTransactionSchedulerUtils.Owner) &FlowTransactionSchedulerUtils.Manager>,
        data: AnyStruct?,
        cronSpec: FlowCronParser.CronSpec,
        priority: FlowTransactionScheduler.Priority,
        executionEffort: UInt64,
        feeProvider: Capability<auth(FungibleToken.Withdraw) &FlowToken.Vault>
    ) {
        pre {
            handler.check(): "Handler capability must be valid"
            manager.check(): "Transaction manager capability must be valid"
            feeProvider.check(): "Fee provider capability must be valid"
            executionEffort > 0: "Execution effort must be greater than 0"
            cronSpec.minMask > 0 && cronSpec.hourMask > 0 && cronSpec.domMask > 0 && cronSpec.monthMask > 0 && cronSpec.dowMask > 0: "CronSpec must have valid bitmasks"
        }
        
        // Create cron configuration
        let cronConfig = CronJobConfig(
            handler: handler,
            manager: manager,
            data: data,
            cronSpec: cronSpec,
            priority: priority,
            executionEffort: executionEffort,
            feeProvider: feeProvider
        )
        
        // Use Manager for scheduling
        let userManager = manager.borrow()
            ?? panic("Cannot borrow transaction manager capability")
        
        // Calculate and schedule first execution using internal helper
        let currentTime = UInt64(getCurrentBlock().timestamp)
        let nextTimeUFix64 = self.internalSchedule(
            config: cronConfig,
            afterUnix: currentTime,
            manager: userManager
        ) ?? panic("Cannot find next execution time within horizon")
        
        emit CronJobCreated(
            handlerAddress: handler.address,
            firstExecution: nextTimeUFix64,
            executionEffort: executionEffort,
            priority: priority.rawValue
        )
    }

    /// Cancel a cron job using the user's Manager
    /// @param manager: User's Manager
    /// @param transactionId: The transaction ID of the cron job to cancel
    /// @return: Refunded fees from the canceled transaction
    access(all) fun cancelCronJob(
        manager: Capability<auth(FlowTransactionSchedulerUtils.Owner) &FlowTransactionSchedulerUtils.Manager>,
        transactionId: UInt64
    ): @FlowToken.Vault {
        // First verify this is actually a cron job managed by FlowCron
        if !self.isCronJob(transactionId: transactionId) {
            panic("Cannot cancel transaction: ID \(transactionId) is not a FlowCron-managed cron job")
        }
        
        let userManager = manager.borrow()
            ?? panic("Cannot borrow transaction manager capability")
        
        emit CronJobCanceled(transactionId: transactionId)
        
        return <-userManager.cancel(id: transactionId)
    }

    /// Get all cron job IDs from a user's Manager
    /// Filters transactions to only return those managed by FlowCron
    /// @param manager: User's Manager
    /// @return: Array of transaction IDs that are cron jobs
    access(all) fun getAllCronJobIDs(
        manager: Capability<&FlowTransactionSchedulerUtils.Manager>
    ): [UInt64] {
        let userManager = manager.borrow()
            ?? panic("Cannot borrow transaction manager capability")
        let allTransactions = userManager.getTransactionIDs()
        let cronJobIDs: [UInt64] = []
        
        // Filter for transactions that are managed by our CronManager
        for transactionId in allTransactions {
            if self.isCronJob(transactionId: transactionId) {
                cronJobIDs.append(transactionId)
            }
        }
        
        return cronJobIDs
    }

    /// Get cron job metadata for display in UI using only native FlowTransactionScheduler data
    /// @param transactionId: The transaction ID of the cron job
    /// @return: CronJobDisplayData for the UI, or nil if not found/not a cron job
    access(all) fun getCronJobDisplayData(transactionId: UInt64): CronJobDisplayData? {
        if let transactionData = FlowTransactionScheduler.getTransactionData(id: transactionId) {
            // Verify this is a FlowCron managed transaction
            if !self.isCronJob(transactionId: transactionId) {
                return nil
            }
            
            return CronJobDisplayData(
                transactionId: transactionId,
                name: transactionData.handlerTypeIdentifier,
                status: transactionData.status,
                nextExecution: transactionData.scheduledTimestamp,
                priority: transactionData.priority,
                executionEffort: transactionData.executionEffort,
                fees: transactionData.fees,
                owner: transactionData.handlerAddress
            )
        }
        
        return nil
    }

    /// Get all cron jobs for a user with full display data
    /// @param manager: User's Manager
    /// @return: Array of CronJobDisplayData for all user's cron jobs
    access(all) fun getAllCronJobsForUser(
        manager: Capability<&FlowTransactionSchedulerUtils.Manager>
    ): [CronJobDisplayData] {
        let cronJobIds = self.getAllCronJobIDs(manager: manager)
        let cronJobs: [CronJobDisplayData] = []
        
        for transactionId in cronJobIds {
            if let displayData = self.getCronJobDisplayData(transactionId: transactionId) {
                cronJobs.append(displayData)
            }
        }
        
        return cronJobs
    }

    /// Get cron job status using the user's Manager
    /// @param manager: User's Manager
    /// @param transactionId: The transaction ID of the cron job
    /// @return: Status of the transaction, or nil if not found or not a cron job
    access(all) fun getCronJobStatus(
        manager: Capability<&FlowTransactionSchedulerUtils.Manager>,
        transactionId: UInt64
    ): FlowTransactionScheduler.Status? {
        // First verify this is actually a cron job managed by FlowCron
        if !self.isCronJob(transactionId: transactionId) {
            return nil // Not a cron job or not found
        }
        
        let userManager = manager.borrow()
            ?? panic("Cannot borrow transaction manager capability")
        return userManager.getTransactionStatus(id: transactionId)
    }

    /// Calculate next execution time for a cron spec
    /// @param cronSpec: CronSpec bitmasks defining the schedule
    /// @param from: Starting timestamp
    /// @return: Next valid execution timestamp, or nil if none found within horizon
    access(all) fun getNextExecutionTime(cronSpec: FlowCronParser.CronSpec, from: UFix64): UFix64? {
        let fromUnix = UInt64(from)
        if let nextUnix = FlowCronParser.nextTick(spec: cronSpec, afterUnix: fromUnix) {
            return UFix64(nextUnix)
        }
        return nil
    }

    /// Parse a cron expression string into CronSpec bitmasks
    /// @param expression: Cron expression string (e.g., "0 2 * * *")
    /// @return: CronSpec or nil if invalid
    access(all) fun parseCronExpression(expression: String): FlowCronParser.CronSpec? {
        return FlowCronParser.parse(expression: expression)
    }

    /// Internal helper function for scheduling transactions with common logic
    /// Used by both initial scheduling and rescheduling to ensure consistent behavior
    /// @param config: CronJobConfig containing all scheduling parameters
    /// @param afterUnix: Calculate next execution time after this timestamp
    /// @param manager: Manager to use for scheduling
    /// @return: Next execution timestamp, or nil if no valid time found
    access(self) fun internalSchedule(
        config: CronJobConfig,
        afterUnix: UInt64,
        manager: auth(FlowTransactionSchedulerUtils.Owner) &FlowTransactionSchedulerUtils.Manager
    ): UFix64? {
        // Calculate next execution time
        let nextTime = FlowCronParser.nextTick(spec: config.cronSpec, afterUnix: afterUnix)
        if nextTime == nil { return nil }
        
        // Use FlowTransactionScheduler.estimate() to calculate exact fee needed
        let estimate = FlowTransactionScheduler.estimate(
            data: config,
            timestamp: UFix64(nextTime!),
            priority: config.priority,
            executionEffort: config.executionEffort
        )
        
        // Check if estimation failed
        if estimate.flowFee == nil {
            panic(estimate.error ?? "Failed to estimate transaction fee")
        }
        
        // Get fees for execution using calculated amount
        let feeVault = config.feeProvider.borrow()
            ?? panic("Cannot borrow fee provider capability")
        let fees <- feeVault.withdraw(amount: estimate.flowFee!)
        
        // Get FlowCron's manager capability
        let cronManagerCap = FlowCron.account.capabilities.get<
            auth(FlowTransactionScheduler.Execute) &{FlowTransactionScheduler.TransactionHandler}
        >(/public/cronManager)
        
        // Schedule using Manager
        manager.schedule(
            handlerCap: cronManagerCap,
            data: config,
            timestamp: UFix64(nextTime!),
            priority: config.priority,
            executionEffort: config.executionEffort,
            fees: <-fees as! @FlowToken.Vault
        )
        
        return UFix64(nextTime!)
    }

    /// Internal helper to verify if a transaction ID belongs to a FlowCron-managed cron job
    /// @param transactionId: The transaction ID to check
    /// @return: True if it's a FlowCron cron job, false otherwise
    access(self) fun isCronJob(transactionId: UInt64): Bool {
        if let transactionData = FlowTransactionScheduler.getTransactionData(id: transactionId) {
            return transactionData.handlerAddress == FlowCron.account.address
        }
        return false
    }

    /// Contract initialization - creates centralized CronManager and publishes capability
    init() {
        // Create and store the centralized CronManager
        let cronManager <- create CronManager(
            name: "FlowCron Manager",
            description: "Centralized manager for all cron jobs"
        )
        self.account.storage.save(<-cronManager, to: /storage/cronManager)
        
        // Publish capability to the CronManager
        let cronManagerCap = self.account.capabilities.storage.issue<
            auth(FlowTransactionScheduler.Execute) &{FlowTransactionScheduler.TransactionHandler}
        >(/storage/cronManager)
        self.account.capabilities.publish(cronManagerCap, at: /public/cronManager)
    }
}
