import "FlowTransactionScheduler"
import "FlowTransactionSchedulerUtils"
import "FlowCronUtils"
import "FlowToken"
import "FungibleToken"
import "ViewResolver"
import "MetadataViews"

/// FlowCron: Wraps any TransactionHandler with cron scheduling.
///
/// FEATURES:
/// - Dual-mode architecture (Keeper/Executor) for fault isolation
/// - Keeper mode: Pure scheduling logic (only scheduling)
/// - Executor mode: Runs user code (isolated failures)
/// - Offset execution: First tick runs both together, subsequent ticks have 1s keeper offset
/// - User schedules both executor and keeper for first tick
/// - Standard cron syntax (5-field expressions)
///
/// LIFECYCLE:
/// 1. Create: FlowCron.createCronHandler(expression, wrappedCap)
/// 2. Bootstrap: User schedules both executor and keeper for next cron tick
/// 3. Execute: At each cron tick, TWO transactions run:
///    - Keeper: Schedules next cycle (both keeper + executor)
///    - Executor: Runs user code
/// 4. Forever: Perpetual execution at every cron tick
/// 5. Stop: Cancel all scheduled transactions
///
/// FAULT TOLERANCE:
/// - Executor failure is isolated (emits event, keeper continues)
/// - Keeper failure panics with detailed error (prevents silent death)
/// - System survives wrapped handler panics/failures
access(all) contract FlowCron {

    /// Fixed priority for keeper operations
    /// Low priority aligns with cron semantics (best-effort timing, not precise)
    access(all) let keeperPriority: FlowTransactionScheduler.Priority
    /// Offset in seconds for keeper scheduling relative to executor
    /// Essential for being scheduled after executor to prevent collision at T+1
    access(all) let keeperOffset: UInt64

    /// Emitted when keeper successfully schedules next cycle
    access(all) event CronKeeperExecuted(
        txID: UInt64,
        nextExecutorTxID: UInt64?,
        nextKeeperTxID: UInt64,
        nextExecutorTime: UInt64?,
        nextKeeperTime: UInt64,
        cronExpression: String,
        handlerUUID: UInt64,
        wrappedHandlerType: String?,
        wrappedHandlerUUID: UInt64?
    )

    /// Emitted when executor successfully completes user code
    access(all) event CronExecutorExecuted(
        txID: UInt64,
        cronExpression: String,
        handlerUUID: UInt64,
        wrappedHandlerType: String?,
        wrappedHandlerUUID: UInt64?
    )

    /// Emitted when scheduling is rejected (due to duplicate/unauthorized scheduling)
    access(all) event CronScheduleRejected(
        txID: UInt64,
        cronExpression: String,
        handlerUUID: UInt64,
        wrappedHandlerType: String?,
        wrappedHandlerUUID: UInt64?
    )

    /// Emitted when scheduling fails due to insufficient funds
    access(all) event CronScheduleFailed(
        txID: UInt64,
        executionMode: UInt8,
        requiredAmount: UFix64,
        availableAmount: UFix64,
        cronExpression: String,
        handlerUUID: UInt64,
        wrappedHandlerType: String?,
        wrappedHandlerUUID: UInt64?
    )

    /// Emitted when fee estimation fails
    access(all) event CronEstimationFailed(
        txID: UInt64,
        executionMode: UInt8,
        priority: UInt8,
        executionEffort: UInt64,
        error: String?,
        cronExpression: String,
        handlerUUID: UInt64,
        wrappedHandlerType: String?,
        wrappedHandlerUUID: UInt64?
    )

    /// Execution mode selector for dual-mode handler
    access(all) enum ExecutionMode: UInt8 {
        access(all) case Keeper
        access(all) case Executor
    }

    /// CronHandler resource wraps any TransactionHandler with fault-tolerant cron scheduling
    access(all) resource CronHandler: FlowTransactionScheduler.TransactionHandler, ViewResolver.Resolver {

        /// Cron expression for scheduling
        access(self) let cronExpression: String
        /// Cron spec for scheduling
        access(self) let cronSpec: FlowCronUtils.CronSpec

        /// The handler that performs the actual work
        access(self) let wrappedHandlerCap: Capability<auth(FlowTransactionScheduler.Execute) &{FlowTransactionScheduler.TransactionHandler}>
        /// Vault capability for fee payments for rescheduling
        access(self) let feeProviderCap: Capability<auth(FungibleToken.Withdraw) &FlowToken.Vault>
        /// Scheduler manager capability for rescheduling
        access(self) let schedulerManagerCap: Capability<auth(FlowTransactionSchedulerUtils.Owner) &{FlowTransactionSchedulerUtils.Manager}>

        /// Next scheduled keeper transaction ID
        /// - nil: Cron not running (bootstrap required) or restart case
        /// - non-nil: ID of the NEXT keeper transaction that will execute
        /// Used to prevent duplicate/unauthorized keeper scheduling
        access(self) var nextScheduledKeeperID: UInt64?

        /// Next scheduled executor transaction ID
        /// - nil: No executor scheduled yet
        /// - non-nil: ID of the NEXT executor transaction that will run user code
        /// Used for complete cancellation support
        access(self) var nextScheduledExecutorID: UInt64?

        init(
            cronExpression: String,
            wrappedHandlerCap: Capability<auth(FlowTransactionScheduler.Execute) &{FlowTransactionScheduler.TransactionHandler}>,
            feeProviderCap: Capability<auth(FungibleToken.Withdraw) &FlowToken.Vault>,
            schedulerManagerCap: Capability<auth(FlowTransactionSchedulerUtils.Owner) &{FlowTransactionSchedulerUtils.Manager}>
        ) {
            pre {
                cronExpression.length > 0: "Cron expression cannot be empty"
                wrappedHandlerCap.check(): "Invalid wrapped handler capability provided"
                feeProviderCap.check(): "Invalid fee provider capability"
                schedulerManagerCap.check(): "Invalid scheduler manager capability"
            }

            self.cronExpression = cronExpression
            self.cronSpec = FlowCronUtils.parse(expression: cronExpression) ?? panic("Invalid cron expression: ".concat(cronExpression))
            self.wrappedHandlerCap = wrappedHandlerCap
            self.feeProviderCap = feeProviderCap
            self.schedulerManagerCap = schedulerManagerCap
            self.nextScheduledKeeperID = nil
            self.nextScheduledExecutorID = nil
        }
        
        /// Main execution entry point for scheduled transactions
        /// Routes to keeper or executor mode based on context
        access(FlowTransactionScheduler.Execute) fun executeTransaction(id: UInt64, data: AnyStruct?) {
            // Parse execution context
            let context = data as? CronContext ?? panic("Invalid execution data: expected CronContext")

            // Route based on execution mode
            if context.executionMode == ExecutionMode.Keeper {
                // Keeper verification: Prevent duplicate/unauthorized keeper scheduling
                // This ensures only the keeper we scheduled can execute, blocking duplicate schedules while cron is running
                if let storedID = self.nextScheduledKeeperID {
                    // We have a stored keeper ID, verify this execution matches it
                    if let txData = FlowTransactionScheduler.getTransactionData(id: storedID) {
                        // Data exists so transaction is scheduled, check this is the expected keeper
                        if id != storedID {
                            let wrappedHandler = self.wrappedHandlerCap.borrow()
                            emit CronScheduleRejected(
                                txID: id,
                                cronExpression: self.cronExpression,
                                handlerUUID: self.uuid,
                                wrappedHandlerType: wrappedHandler?.getType()?.identifier,
                                wrappedHandlerUUID: wrappedHandler?.uuid
                            )
                            return
                        }
                    }
                }
                // No stored ID or verification passed so execute keeper mode
                self.executeKeeperMode(txID: id, context: context)
            } else {
                // Executor mode with no verification so they run independently without affecting the keeper chain
                self.executeExecutorMode(txID: id, context: context)
            }
        }

        /// Keeper mode: Pure scheduling logic, no user code execution
        /// Only calculates times and schedules transactions
        /// Schedules executor at cron tick and keeper with 1s offset (separate slots)
        access(self) fun executeKeeperMode(txID: UInt64, context: CronContext) {
            // Calculate next cron tick (for BOTH executor and keeper)
            let currentTime = UInt64(getCurrentBlock().timestamp)
            let nextTick = FlowCronUtils.nextTick(spec: self.cronSpec, afterUnix: currentTime) ?? panic("Cannot calculate next cron tick")

            // Schedule executor FIRST at exact cron tick
            // Returns nil if scheduling fails (only possible with High priority slot full)
            // No fallback to execute exactly as user meant it to run so that its work is explicit
            let executorTxID = self.scheduleCronTransaction(
                txID: txID,
                executionMode: ExecutionMode.Executor,
                timestamp: nextTick,
                priority: context.executorPriority,
                executionEffort: context.executorExecutionEffort,
                context: context
            )
            // Store executor transaction ID for cancellation support (nil if scheduling failed)
            self.nextScheduledExecutorID = executorTxID

            // Determine keeper timestamp based on actual executor schedule
            // For Medium/Low priority, actual scheduled time may differ from requested nextTick
            // Keeper must run AFTER executor, so use actual executor timestamp + offset
            var actualExecutorTime: UInt64? = nil
            var keeperTimestamp = nextTick + FlowCron.keeperOffset
            if let execID = executorTxID {
                if let txData = FlowTransactionScheduler.getTransactionData(id: execID) {
                    actualExecutorTime = UInt64(txData.scheduledTimestamp)
                    keeperTimestamp = actualExecutorTime! + FlowCron.keeperOffset
                }
            }
            // Schedule keeper with offset from actual executor time (or nextTick if executor failed)
            let keeperTxID = self.scheduleCronTransaction(
                txID: txID,
                executionMode: ExecutionMode.Keeper,
                timestamp: keeperTimestamp,
                priority: FlowCron.keeperPriority,
                executionEffort: context.keeperExecutionEffort,
                context: context
            )!
            // Store keeper transaction ID to prevent duplicate scheduling
            self.nextScheduledKeeperID = keeperTxID

            // Emit keeper executed event with actual scheduled times
            let wrappedHandler = self.wrappedHandlerCap.borrow()
            emit CronKeeperExecuted(
                txID: txID,
                nextExecutorTxID: executorTxID,
                nextKeeperTxID: keeperTxID,
                nextExecutorTime: actualExecutorTime,
                nextKeeperTime: keeperTimestamp,
                cronExpression: self.cronExpression,
                handlerUUID: self.uuid,
                wrappedHandlerType: wrappedHandler?.getType()?.identifier,
                wrappedHandlerUUID: wrappedHandler?.uuid
            )
        }

        /// Executor mode: Runs user's wrapped handler
        /// Executes arbitrary user code which may panic
        access(self) fun executeExecutorMode(txID: UInt64, context: CronContext) {
            // Execute wrapped handler
            // If this panics, transaction reverts but keeper was already scheduled in a keeper execution
            let wrappedHandler = self.wrappedHandlerCap.borrow() ?? panic("Cannot borrow wrapped handler capability")
            wrappedHandler.executeTransaction(id: txID, data: context.wrappedData)

            // Emit completion event
            emit CronExecutorExecuted(
                txID: txID,
                cronExpression: self.cronExpression,
                handlerUUID: self.uuid,
                wrappedHandlerType: wrappedHandler.getType().identifier,
                wrappedHandlerUUID: wrappedHandler.uuid
            )
        }

        /// Unified scheduling function with explicit parameters and error handling
        /// Schedules a cron transaction (keeper or executor) with specified priority
        access(self) fun scheduleCronTransaction(
            txID: UInt64,
            executionMode: ExecutionMode,
            timestamp: UInt64,
            priority: FlowTransactionScheduler.Priority,
            executionEffort: UInt64,
            context: CronContext
        ): UInt64? {
            // Borrow capabilities
            let schedulerManager = self.schedulerManagerCap.borrow() ?? panic("Cannot borrow scheduler manager")
            let feeVault = self.feeProviderCap.borrow() ?? panic("Cannot borrow fee provider")

            // Create execution context preserving original executor/keeper config
            let execContext = CronContext(
                executionMode: executionMode,
                executorPriority: context.executorPriority,
                executorExecutionEffort: context.executorExecutionEffort,
                keeperExecutionEffort: context.keeperExecutionEffort,
                wrappedData: context.wrappedData
            )
            // Estimate fees
            let estimate = FlowTransactionScheduler.estimate(
                data: execContext,
                timestamp: UFix64(timestamp),
                priority: priority,
                executionEffort: executionEffort
            )

            // Handle estimation result
            let wrappedHandler = self.wrappedHandlerCap.borrow()
            if let requiredFee = estimate.flowFee {
                // Check sufficient balance
                if feeVault.balance >= requiredFee {
                    // Schedule transaction
                    let fees <- feeVault.withdraw(amount: requiredFee)
                    let txID = schedulerManager.scheduleByHandler(
                        handlerTypeIdentifier: self.getType().identifier,
                        handlerUUID: self.uuid,
                        data: execContext,
                        timestamp: UFix64(timestamp),
                        priority: priority,
                        executionEffort: executionEffort,
                        fees: <-fees as! @FlowToken.Vault
                    )
                    return txID
                } else {
                    // Insufficient funds, emits event
                    emit CronScheduleFailed(
                        txID: txID,
                        executionMode: executionMode.rawValue,
                        requiredAmount: requiredFee,
                        availableAmount: feeVault.balance,
                        cronExpression: self.cronExpression,
                        handlerUUID: self.uuid,
                        wrappedHandlerType: wrappedHandler?.getType()?.identifier,
                        wrappedHandlerUUID: wrappedHandler?.uuid
                    )
                    return nil
                }
            }

            // If we arrive here, estimation failed so emit event and return nil
            emit CronEstimationFailed(
                txID: txID,
                executionMode: executionMode.rawValue,
                priority: priority.rawValue,
                executionEffort: executionEffort,
                error: estimate.error,
                cronExpression: self.cronExpression,
                handlerUUID: self.uuid,
                wrappedHandlerType: wrappedHandler?.getType()?.identifier,
                wrappedHandlerUUID: wrappedHandler?.uuid
            )
            return nil
        }

        /// Returns the cron expression
        access(all) view fun getCronExpression(): String {
            return self.cronExpression
        }

        /// Returns a copy of the cron spec for use in calculations
        access(all) view fun getCronSpec(): FlowCronUtils.CronSpec {
            return self.cronSpec
        }

        /// Returns the next scheduled keeper transaction ID if one exists
        access(all) view fun getNextScheduledKeeperID(): UInt64? {
            return self.nextScheduledKeeperID
        }

        /// Returns the next scheduled executor transaction ID if one exists
        access(all) view fun getNextScheduledExecutorID(): UInt64? {
            return self.nextScheduledExecutorID
        }

        access(all) view fun getViews(): [Type] {
            var views: [Type] = [
                Type<MetadataViews.Display>(),
                Type<CronInfo>()
            ]

            // Add wrapped handler views, but deduplicate to avoid collisions
            if let handler = self.wrappedHandlerCap.borrow() {
                for viewType in handler.getViews() {
                    if !views.contains(viewType) {
                        views = views.concat([viewType])
                    }
                }
            }
            return views
        }
        
        access(all) fun resolveView(_ view: Type): AnyStruct? {
            let wrappedHandler = self.wrappedHandlerCap.borrow()
            switch view {
                case Type<MetadataViews.Display>():
                    // Try to get wrapped handler's display
                    let wrappedDisplay = wrappedHandler?.resolveView(Type<MetadataViews.Display>()) as? MetadataViews.Display

                    if let wrapped = wrappedDisplay {
                        // Merge: Enrich wrapped handler's display with cron info
                        return MetadataViews.Display(
                            name: wrapped.name.concat(" (Cron)"),
                            description: wrapped.description
                                .concat(" (Cron: ").concat(self.cronExpression).concat(")"),
                            thumbnail: wrapped.thumbnail
                        )
                    } else {
                        // Fallback: Cron-only display (when wrapped handler doesn't provide display)
                        let handlerType = wrappedHandler?.getType()?.identifier ?? "Unknown"
                        return MetadataViews.Display(
                            name: "Cron Handler",
                            description: "Scheduled handler: ".concat(handlerType)
                                .concat(" (Cron: ").concat(self.cronExpression).concat(")"),
                            thumbnail: MetadataViews.HTTPFile(url: "")
                        )
                    }
                case Type<CronInfo>():
                    return CronInfo(
                        cronExpression: self.cronExpression,
                        cronSpec: self.cronSpec,
                        nextScheduledKeeperID: self.nextScheduledKeeperID,
                        nextScheduledExecutorID: self.nextScheduledExecutorID,
                        wrappedHandlerType: wrappedHandler?.getType()?.identifier,
                        wrappedHandlerUUID: wrappedHandler?.uuid
                    )
                default:
                    return wrappedHandler?.resolveView(view)
            }
        }
    }

    /// Context passed to each cron execution
    access(all) struct CronContext {
        access(contract) let executionMode: ExecutionMode
        access(contract) let executorPriority: FlowTransactionScheduler.Priority
        access(contract) let executorExecutionEffort: UInt64
        access(contract) let keeperExecutionEffort: UInt64
        access(contract) let wrappedData: AnyStruct?

        init(
            executionMode: ExecutionMode,
            executorPriority: FlowTransactionScheduler.Priority,
            executorExecutionEffort: UInt64,
            keeperExecutionEffort: UInt64,
            wrappedData: AnyStruct?
        ) {
            pre {
                executorExecutionEffort >= 100: "Executor execution effort must be at least 100 (scheduler minimum)"
                executorExecutionEffort <= 9999: "Executor execution effort must be at most 9999 (scheduler maximum)"
                keeperExecutionEffort >= 100: "Keeper execution effort must be at least 100 (scheduler minimum)"
                keeperExecutionEffort <= 9999: "Keeper execution effort must be at most 9999 (scheduler maximum)"
            }

            self.executionMode = executionMode
            self.executorPriority = executorPriority
            self.executorExecutionEffort = executorExecutionEffort
            self.keeperExecutionEffort = keeperExecutionEffort
            self.wrappedData = wrappedData
        }
    }
    
    /// View structure exposing cron handler metadata
    access(all) struct CronInfo {
        /// The original cron expression string
        access(all) let cronExpression: String
        /// Parsed cron specification for execution
        access(all) let cronSpec: FlowCronUtils.CronSpec
        /// Next scheduled keeper transaction ID
        access(all) let nextScheduledKeeperID: UInt64?
        /// Next scheduled executor transaction ID
        access(all) let nextScheduledExecutorID: UInt64?
        /// Type identifier of wrapped handler
        access(all) let wrappedHandlerType: String?
        /// UUID of wrapped handler resource
        access(all) let wrappedHandlerUUID: UInt64?

        init(
            cronExpression: String,
            cronSpec: FlowCronUtils.CronSpec,
            nextScheduledKeeperID: UInt64?,
            nextScheduledExecutorID: UInt64?,
            wrappedHandlerType: String?,
            wrappedHandlerUUID: UInt64?
        ) {
            self.cronExpression = cronExpression
            self.cronSpec = cronSpec
            self.nextScheduledKeeperID = nextScheduledKeeperID
            self.nextScheduledExecutorID = nextScheduledExecutorID
            self.wrappedHandlerType = wrappedHandlerType
            self.wrappedHandlerUUID = wrappedHandlerUUID
        }
    }

    /// Create a new CronHandler resource
    access(all) fun createCronHandler(
        cronExpression: String,
        wrappedHandlerCap: Capability<auth(FlowTransactionScheduler.Execute) &{FlowTransactionScheduler.TransactionHandler}>,
        feeProviderCap: Capability<auth(FungibleToken.Withdraw) &FlowToken.Vault>,
        schedulerManagerCap: Capability<auth(FlowTransactionSchedulerUtils.Owner) &{FlowTransactionSchedulerUtils.Manager}>
    ): @CronHandler {
        return <- create CronHandler(
            cronExpression: cronExpression,
            wrappedHandlerCap: wrappedHandlerCap,
            feeProviderCap: feeProviderCap,
            schedulerManagerCap: schedulerManagerCap
        )
    }

    init() {
        // Set fixed low priority for keeper operations as cron semantics don't require precise timing
        self.keeperPriority = FlowTransactionScheduler.Priority.Low
        // Keeper offset of 1 second to prevent race condition
        self.keeperOffset = 1
    }
}