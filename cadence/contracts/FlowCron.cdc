import "FlowCallbackScheduler"
import "FlowCallbackUtils"
import "FlowCronParser"
import "FlowToken"
import "FungibleToken"

/// FlowCron: Lightweight cron-based scheduling for recurring callbacks on Flow blockchain.
/// 
/// This utility contract wraps any CallbackHandler with autonomous cron functionality,
/// enabling recurring executions based on cron expressions parsed into efficient bitmasks.
/// Built on FlowCallbackScheduler and FlowCallbackUtils for seamless integration.
/// 
/// Key Features:
/// - Bitmask-based scheduling for optimal performance
/// - Automatic rescheduling with robust error handling
/// - Full integration with Flow's callback management system
/// - Comprehensive monitoring and statistics
/// - Lightweight and gas-efficient design
access(all) contract FlowCron {
    
    /// Emitted when a new cron job is created
    access(all) event CronJobCreated(
        cronSpec: FlowCronParser.CronSpec, 
        handlerTypeIdentifier: String, 
        handlerAddress: Address,
        firstExecution: UFix64,
        executionEffort: UInt64,
        priority: UInt8
    )
    
    /// Emitted after each cron job execution (before rescheduling next execution)
    access(all) event CronJobExecuted(
        callbackId: UInt64, 
        nextExecution: UFix64?,
        executionTimestamp: UFix64
    )
    
    /// Emitted when a cron job is canceled by the user
    access(all) event CronJobCanceled(callbackId: UInt64, reason: String)

    /// Configuration struct for cron jobs
    /// 
    /// Contains all necessary information for cron job execution and rescheduling.
    /// This struct is stored as data in FlowCallbackScheduler and passed to CronManager
    /// during callback execution for automatic rescheduling.
    access(all) struct CronJobConfig {
        access(all) let cronSpec: FlowCronParser.CronSpec
        access(all) let wrappedHandler: Capability<auth(FlowCallbackScheduler.Execute) &{FlowCallbackScheduler.CallbackHandler}>
        access(all) let data: AnyStruct?
        access(all) let feeProvider: Capability<auth(FungibleToken.Withdraw) &FlowToken.Vault>
        access(all) let executionEffort: UInt64
        access(all) let priority: FlowCallbackScheduler.Priority
        /// User's CallbackManager for proper callback management integration
        access(all) let callbackManager: Capability<auth(FlowCallbackUtils.Owner) &FlowCallbackUtils.CallbackManager>

        init(
            cronSpec: FlowCronParser.CronSpec,
            wrappedHandler: Capability<auth(FlowCallbackScheduler.Execute) &{FlowCallbackScheduler.CallbackHandler}>,
            data: AnyStruct?,
            feeProvider: Capability<auth(FungibleToken.Withdraw) &FlowToken.Vault>,
            executionEffort: UInt64,
            priority: FlowCallbackScheduler.Priority,
            callbackManager: Capability<auth(FlowCallbackUtils.Owner) &FlowCallbackUtils.CallbackManager>
        ) {
            self.cronSpec = cronSpec
            self.wrappedHandler = wrappedHandler
            self.data = data
            self.feeProvider = feeProvider
            self.executionEffort = executionEffort
            self.priority = priority
            self.callbackManager = callbackManager
        }
    }

    /// Display data for cron jobs in client applications
    /// 
    /// Contains essential information for building cron job management interfaces.
    /// All data is sourced from FlowCallbackScheduler.CallbackData for consistency.
    access(all) struct CronJobDisplayData {
        access(all) let callbackId: UInt64
        access(all) let name: String
        access(all) let status: FlowCallbackScheduler.Status
        access(all) let nextExecution: UFix64
        access(all) let priority: FlowCallbackScheduler.Priority
        access(all) let executionEffort: UInt64
        access(all) let fees: UFix64
        access(all) let owner: Address
        
        init(
            callbackId: UInt64,
            name: String,
            status: FlowCallbackScheduler.Status,
            nextExecution: UFix64,
            priority: FlowCallbackScheduler.Priority,
            executionEffort: UInt64,
            fees: UFix64,
            owner: Address
        ) {
            self.callbackId = callbackId
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
    /// Implements CallbackHandler interface to receive scheduled callbacks from FlowCallbackScheduler.
    /// When a cron job executes, this manager:
    /// 1. Executes the user's wrapped handler
    /// 2. Calculates the next execution time using efficient cron algorithm  
    /// 3. Reschedules the job through the user's CallbackManager for proper management integration
    access(all) resource CronManager: FlowCallbackScheduler.CallbackHandler {
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
        /// Called by FlowCallbackScheduler when a scheduled callback is triggered
        access(FlowCallbackScheduler.Execute)
        fun executeCallback(id: UInt64, data: AnyStruct?) {
            let config = data as! CronJobConfig
            
            log("Executing cron job ID: ".concat(id.toString()))
            
            // Execute the user's wrapped handler
            let userHandler = config.wrappedHandler.borrow()
                ?? panic("Cannot borrow user handler capability")
            userHandler.executeCallback(id: id, data: config.data)
            
            // Use user's CallbackManager for rescheduling
            let userCallbackManager = config.callbackManager.borrow()
                ?? panic("Cannot borrow user's callback manager capability for rescheduling")
            
            // Calculate and schedule next execution using internal helper
            let currentTime = UInt64(getCurrentBlock().timestamp)
            let nextTimeUFix64 = FlowCron.internalSchedule(
                config: config,
                afterUnix: currentTime,
                callbackManager: userCallbackManager
            )
            
            emit CronJobExecuted(
                callbackId: id, 
                nextExecution: nextTimeUFix64,
                executionTimestamp: getCurrentBlock().timestamp
            )
        }

        /// ViewResolver.Resolver implementation
        access(all) view fun getViews(): [Type] {
            return []
        }

        access(all) fun resolveView(_ view: Type): AnyStruct? {
            return nil
        }
    }

    /// Internal helper function for scheduling callbacks with common logic
    /// Used by both initial scheduling and rescheduling to ensure consistent behavior
    /// @param config: CronJobConfig containing all scheduling parameters
    /// @param afterUnix: Calculate next execution time after this timestamp
    /// @param callbackManager: CallbackManager to use for scheduling
    /// @return: Next execution timestamp, or nil if no valid time found
    access(self) fun internalSchedule(
        config: CronJobConfig,
        afterUnix: UInt64,
        callbackManager: auth(FlowCallbackUtils.Owner) &FlowCallbackUtils.CallbackManager
    ): UFix64? {
        // Calculate next execution time
        let nextTime = FlowCronParser.nextTick(spec: config.cronSpec, afterUnix: afterUnix)
        if nextTime == nil { return nil }
        
        // Use FlowCallbackScheduler.estimate() to calculate exact fee needed
        let estimate = FlowCallbackScheduler.estimate(
            data: config,
            timestamp: UFix64(nextTime!),
            priority: config.priority,
            executionEffort: config.executionEffort
        )
        
        // Check if estimation failed
        if estimate.flowFee == nil {
            panic(estimate.error ?? "Failed to estimate callback fee")
        }
        
        // Get fees for execution using calculated amount
        let feeVault = config.feeProvider.borrow()
            ?? panic("Cannot borrow fee provider capability")
        let fees <- feeVault.withdraw(amount: estimate.flowFee!)
        
        // Get FlowCron's manager capability
        let cronManagerCap = FlowCron.account.capabilities.get<
            auth(FlowCallbackScheduler.Execute) &{FlowCallbackScheduler.CallbackHandler}
        >(/public/cronManager)
        
        // Schedule using CallbackManager
        callbackManager.schedule(
            callback: cronManagerCap,
            data: config,
            timestamp: UFix64(nextTime!),
            priority: config.priority,
            executionEffort: config.executionEffort,
            fees: <-fees as! @FlowToken.Vault
        )
        
        return UFix64(nextTime!)
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
        handler: Capability<auth(FlowCallbackScheduler.Execute) &{FlowCallbackScheduler.CallbackHandler}>,
        callbackManager: Capability<auth(FlowCallbackUtils.Owner) &FlowCallbackUtils.CallbackManager>,
        data: AnyStruct?,
        cronSpec: FlowCronParser.CronSpec,
        priority: FlowCallbackScheduler.Priority,
        executionEffort: UInt64,
        feeProvider: Capability<auth(FungibleToken.Withdraw) &FlowToken.Vault>
    ) {
        pre {
            handler.check(): "Handler capability must be valid"
            callbackManager.check(): "Callback manager capability must be valid"
            feeProvider.check(): "Fee provider capability must be valid"
            executionEffort > 0: "Execution effort must be greater than 0"
            cronSpec.minMask > 0 && cronSpec.hourMask > 0 && cronSpec.domMask > 0 && cronSpec.monthMask > 0 && cronSpec.dowMask > 0: "CronSpec must have valid bitmasks"
        }
        
        // Create cron configuration
        let cronConfig = CronJobConfig(
            cronSpec: cronSpec,
            wrappedHandler: handler,
            data: data,
            feeProvider: feeProvider,
            executionEffort: executionEffort,
            priority: priority,
            callbackManager: callbackManager
        )
        
        // Use CallbackManager for scheduling
        let manager = callbackManager.borrow()
            ?? panic("Cannot borrow callback manager capability")
        
        // Calculate and schedule first execution using internal helper
        let currentTime = UInt64(getCurrentBlock().timestamp)
        let nextTimeUFix64 = self.internalSchedule(
            config: cronConfig,
            afterUnix: currentTime,
            callbackManager: manager
        ) ?? panic("Cannot find next execution time within horizon")
        
        // Get handler info for event
        let handlerRef = handler.borrow()
            ?? panic("Cannot borrow handler capability for event")
        
        emit CronJobCreated(
            cronSpec: cronSpec,
            handlerTypeIdentifier: handlerRef.getType().identifier,
            handlerAddress: handler.address,
            firstExecution: nextTimeUFix64,
            executionEffort: executionEffort,
            priority: priority.rawValue
        )
    }

    /// Cancel a cron job using the user's CallbackManager
    /// @param callbackManager: User's CallbackManager
    /// @param callbackId: The callback ID of the cron job to cancel
    /// @return: Refunded fees from the canceled callback
    access(all) fun cancelCronJob(
        callbackManager: Capability<auth(FlowCallbackUtils.Owner) &FlowCallbackUtils.CallbackManager>,
        callbackId: UInt64
    ): @FlowToken.Vault {
        let manager = callbackManager.borrow()
            ?? panic("Cannot borrow callback manager capability")
        
        emit CronJobCanceled(callbackId: callbackId, reason: "User canceled")
        
        return <-manager.cancel(id: callbackId)
    }

    /// Get all cron job IDs from a user's CallbackManager
    /// Filters callbacks to only return those managed by FlowCron
    /// @param callbackManager: User's CallbackManager
    /// @return: Array of callback IDs that are cron jobs
    access(all) fun getAllCronJobIDs(
        callbackManager: Capability<&FlowCallbackUtils.CallbackManager>
    ): [UInt64] {
        let manager = callbackManager.borrow()
            ?? panic("Cannot borrow callback manager capability")
        let allCallbacks = manager.getCallbackIDs()
        let cronJobIDs: [UInt64] = []
        
        // Filter for callbacks that are managed by our CronManager
        for callbackId in allCallbacks {
            if let callbackData = FlowCallbackScheduler.getCallbackData(id: callbackId) {
                // Check if the callback handler is our CronManager
                if callbackData.handlerTypeIdentifier.contains("FlowCron.CronManager") {
                    cronJobIDs.append(callbackId)
                }
            }
        }
        
        return cronJobIDs
    }

    /// Get cron job metadata for display in UI using only native FlowCallbackScheduler data
    /// @param callbackId: The callback ID of the cron job
    /// @return: CronJobDisplayData for the UI, or nil if not found/not a cron job
    access(all) fun getCronJobDisplayData(callbackId: UInt64): CronJobDisplayData? {
        if let callbackData = FlowCallbackScheduler.getCallbackData(id: callbackId) {
            // Verify this is a FlowCron managed callback
            if !callbackData.handlerTypeIdentifier.contains("FlowCron.CronManager") {
                return nil
            }
            
            return CronJobDisplayData(
                callbackId: callbackId,
                name: callbackData.name,
                status: callbackData.status,
                nextExecution: callbackData.scheduledTimestamp,
                priority: callbackData.priority,
                executionEffort: callbackData.executionEffort,
                fees: callbackData.fees,
                owner: callbackData.handlerAddress
            )
        }
        
        return nil
    }

    /// Get all cron jobs for a user with full display data
    /// @param callbackManager: User's CallbackManager
    /// @return: Array of CronJobDisplayData for all user's cron jobs
    access(all) fun getAllCronJobsForUser(
        callbackManager: Capability<&FlowCallbackUtils.CallbackManager>
    ): [CronJobDisplayData] {
        let cronJobIds = self.getAllCronJobIDs(callbackManager: callbackManager)
        let cronJobs: [CronJobDisplayData] = []
        
        for callbackId in cronJobIds {
            if let displayData = self.getCronJobDisplayData(callbackId: callbackId) {
                cronJobs.append(displayData)
            }
        }
        
        return cronJobs
    }

    /// Get cron job status using the user's CallbackManager
    /// @param callbackManager: User's CallbackManager
    /// @param callbackId: The callback ID of the cron job
    /// @return: Status of the callback, or nil if not found
    access(all) fun getCronJobStatus(
        callbackManager: Capability<&FlowCallbackUtils.CallbackManager>,
        callbackId: UInt64
    ): FlowCallbackScheduler.Status? {
        let manager = callbackManager.borrow()
            ?? panic("Cannot borrow callback manager capability")
        return manager.getCallbackStatus(id: callbackId)
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

    /// Validate that a CronSpec has valid bitmask values
    /// @param cronSpec: CronSpec to validate
    /// @return: True if valid
    access(all) fun validateCronSpec(cronSpec: FlowCronParser.CronSpec): Bool {
        // Basic validation - ensure at least one bit is set in each field
        return cronSpec.minMask > 0 &&
               cronSpec.hourMask > 0 &&
               cronSpec.domMask > 0 &&
               cronSpec.monthMask > 0 &&
               cronSpec.dowMask > 0
    }

    /// Get a human-readable description of a CronSpec (simplified)
    /// @param cronSpec: CronSpec to describe
    /// @return: Simple description string
    access(all) fun describeCronSpec(cronSpec: FlowCronParser.CronSpec): String {
        var description = "Runs"
        
        // Simple frequency detection
        if cronSpec.minMask == 0x1 && cronSpec.hourMask == 0xFFFFFF && 
           cronSpec.domMask == 0xFFFFFFFE && cronSpec.monthMask == 0x1FFE && cronSpec.dowMask == 0x7F {
            description = description.concat(" every minute")
        } else if cronSpec.hourMask == 0x1 && cronSpec.domMask == 0xFFFFFFFE && 
                  cronSpec.monthMask == 0x1FFE && cronSpec.dowMask == 0x7F {
            description = description.concat(" hourly")
        } else if cronSpec.domMask == 0x2 && cronSpec.monthMask == 0x1FFE && cronSpec.dowMask == 0x7F {
            description = description.concat(" daily")
        } else if cronSpec.domMask == 0x2 && cronSpec.monthMask == 0x1FFE {
            description = description.concat(" weekly")
        } else if cronSpec.domMask == 0x2 {
            description = description.concat(" monthly")
        } else {
            description = description.concat(" on custom schedule")
        }
        
        return description
    }

    /// Helper function to create common CronSpec patterns
    /// @param pattern: Pattern name ("every_minute", "hourly", "daily", "weekly", "monthly")
    /// @param minute: Minute for hourly+ patterns (0-59)
    /// @param hour: Hour for daily+ patterns (0-23)
    /// @param dayOfMonth: Day of month for monthly pattern (1-31)
    /// @param dayOfWeek: Day of week for weekly pattern (0-6, 0=Sunday)
    /// @return: CronSpec for the pattern, or nil if invalid
    access(all) fun createCommonCronSpec(
        pattern: String,
        minute: Int?,
        hour: Int?,
        dayOfMonth: Int?,
        dayOfWeek: Int?
    ): FlowCronParser.CronSpec? {
        switch pattern {
        case "every_minute":
            return FlowCronParser.CronSpec(
                minMask: 0xFFFFFFFFFFFFFFF, // all minutes (bits 0-59)
                hourMask: 0xFFFFFF,         // all hours (bits 0-23)
                domMask: 0xFFFFFFFE,        // all days (bits 1-31)
                monthMask: 0x1FFE,          // all months (bits 1-12) 
                dowMask: 0x7F,              // all weekdays (bits 0-6)
                domIsStar: true,
                dowIsStar: true
            )
        case "hourly":
            let min = minute ?? 0
            if min < 0 || min > 59 { return nil }
            return FlowCronParser.CronSpec(
                minMask: UInt64(1) << UInt64(min),
                hourMask: 0xFFFFFF,         // all hours
                domMask: 0xFFFFFFFE,        // all days
                monthMask: 0x1FFE,          // all months
                dowMask: 0x7F,              // all weekdays
                domIsStar: true,
                dowIsStar: true
            )
        case "daily":
            let min = minute ?? 0
            let hr = hour ?? 0
            if min < 0 || min > 59 || hr < 0 || hr > 23 { return nil }
            return FlowCronParser.CronSpec(
                minMask: UInt64(1) << UInt64(min),
                hourMask: UInt32(1) << UInt32(hr),
                domMask: 0xFFFFFFFE,        // all days
                monthMask: 0x1FFE,          // all months
                dowMask: 0x7F,              // all weekdays
                domIsStar: true,
                dowIsStar: true
            )
        case "weekly":
            let min = minute ?? 0
            let hr = hour ?? 0
            let dow = dayOfWeek ?? 0
            if min < 0 || min > 59 || hr < 0 || hr > 23 || dow < 0 || dow > 6 { return nil }
            return FlowCronParser.CronSpec(
                minMask: UInt64(1) << UInt64(min),
                hourMask: UInt32(1) << UInt32(hr),
                domMask: 0xFFFFFFFE,        // all days (will be ignored due to DOW)
                monthMask: 0x1FFE,          // all months
                dowMask: UInt8(1) << UInt8(dow),
                domIsStar: true,
                dowIsStar: false
            )
        case "monthly":
            let min = minute ?? 0
            let hr = hour ?? 0
            let dom = dayOfMonth ?? 1
            if min < 0 || min > 59 || hr < 0 || hr > 23 || dom < 1 || dom > 31 { return nil }
            return FlowCronParser.CronSpec(
                minMask: UInt64(1) << UInt64(min),
                hourMask: UInt32(1) << UInt32(hr),
                domMask: UInt32(1) << UInt32(dom),
                monthMask: 0x1FFE,          // all months
                dowMask: 0x7F,              // all weekdays (will be ignored due to DOM)
                domIsStar: false,
                dowIsStar: true
            )
        default:
            return nil
        }
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
            auth(FlowCallbackScheduler.Execute) &{FlowCallbackScheduler.CallbackHandler}
        >(/storage/cronManager)
        self.account.capabilities.publish(cronManagerCap, at: /public/cronManager)
    }
}
