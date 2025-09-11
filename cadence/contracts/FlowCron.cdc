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
    
    /// Singleton instance used to store the shared CronManager capability
    /// and route all cron job functionality
    access(self) var sharedCronManager: Capability<auth(FlowTransactionScheduler.Execute) &{FlowTransactionScheduler.TransactionHandler}>
    
    /// Storage path for the singleton CronManager resource
    access(all) let storagePath: StoragePath
    
    /// Emitted when a cron job is rescheduled for its next execution
    access(all) event CronJobRescheduled(
        transactionId: UInt64,
        nextExecution: UFix64?
    )

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
        /// 
        /// IMPORTANT: Next execution is scheduled BEFORE attempting user handler execution.
        /// This ensures that even if the user's handler fails, the cron job continues recurring.
        /// Failed executions only affect the current run, not future scheduled executions.
        access(FlowTransactionScheduler.Execute)
        fun executeTransaction(id: UInt64, data: AnyStruct?) {
            // Validate data type first to provide better error messages
            let config = data as? CronJobConfig
                ?? panic("Invalid cron job data: Expected CronJobConfig but got \(data?.getType()?.identifier ?? "nil")")
            
            log("Executing cron job ID: ".concat(id.toString()))
            
            // STEP 1: RESCHEDULE FIRST - ensures continuity even if execution fails
            let userManager = config.manager.borrow()
                ?? panic("Cannot borrow user's transaction manager capability for rescheduling")
            
            let currentTime = UInt64(getCurrentBlock().timestamp)
            let nextTimeUFix64 = FlowCron.internalSchedule(
                config: config,
                afterUnix: currentTime,
                manager: userManager
            )
            
            // STEP 2: EMIT RESCHEDULED EVENT - shows next execution was scheduled
            emit CronJobRescheduled(
                transactionId: id,
                nextExecution: nextTimeUFix64
            )
            
            // STEP 3: EXECUTE USER HANDLER - failures here won't break the recurring schedule
            let userHandler = config.handler.borrow()
                ?? panic("Cannot borrow user handler capability")
            userHandler.executeTransaction(id: id, data: config.data)
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
        
        // Schedule using Manager with shared CronManager capability
        manager.schedule(
            handlerCap: FlowCron.sharedCronManager,
            data: config,
            timestamp: UFix64(nextTime!),
            priority: config.priority,
            executionEffort: config.executionEffort,
            fees: <-fees as! @FlowToken.Vault
        )
        
        return UFix64(nextTime!)
    }

    /// Contract initialization - creates centralized CronManager 
    init() {
        // Initialize storage path
        self.storagePath = /storage/flowCronManager
        
        // Create and store the centralized CronManager
        let cronManager <- create CronManager(
            name: "FlowCron Manager",
            description: "Centralized manager for all cron jobs"
        )
        self.account.storage.save(<-cronManager, to: self.storagePath)
        
        // Issue and store the shared capability
        self.sharedCronManager = self.account.capabilities.storage.issue<
            auth(FlowTransactionScheduler.Execute) &{FlowTransactionScheduler.TransactionHandler}
        >(self.storagePath)
    }
}
