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

    /// Fixed execution effort for keeper operations
    /// Empirically measured: 1 nextTick calculation + 2 scheduleExecution calls + event emission
    access(all) let KEEPER_EXECUTION_EFFORT: UInt64
    /// Fixed priority for keeper operations
    /// Medium priority ensures reliable scheduling without slot filling issues
    access(all) let KEEPER_PRIORITY: FlowTransactionScheduler.Priority
    /// Offset in seconds for keeper scheduling relative to executor
    /// Essential for being scheduled after executor to prevent collision at T+1
    access(all) let KEEPER_OFFSET_SECONDS: UInt64

    /// Emitted when keeper successfully schedules next cycle
    access(all) event CronKeeperExecuted(
        txID: UInt64,
        nextExecutorTxID: UInt64?,
        nextKeeperTxID: UInt64,
        nextExecutorTime: UInt64,
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

    /// Emitted when executor scheduling falls back to Medium priority
    access(all) event CronExecutorFallback(
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
        access(all) let cronExpression: String
        /// Cron spec for scheduling
        access(all) let cronSpec: FlowCronUtils.CronSpec

        /// The handler that performs the actual work
        access(self) let wrappedHandlerCap: Capability<auth(FlowTransactionScheduler.Execute) &{FlowTransactionScheduler.TransactionHandler}>

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
            wrappedHandlerCap: Capability<auth(FlowTransactionScheduler.Execute) &{FlowTransactionScheduler.TransactionHandler}>
        ) {
            pre {
                cronExpression.length > 0: "Cron expression cannot be empty"
                wrappedHandlerCap.check(): "Invalid wrapped handler capability provided"
            }

            self.cronExpression = cronExpression
            self.cronSpec = FlowCronUtils.parse(expression: cronExpression) ?? panic("Invalid cron expression: ".concat(cronExpression))
            self.wrappedHandlerCap = wrappedHandlerCap
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

            // Schedule executor FIRST at exact cron tick (user's work runs exactly on time)
            // Returns nil if scheduling fails so we can tolerate executor failures
            var executorTxID = self.scheduleCronTransaction(
                txID: txID,
                mode: ExecutionMode.Executor,
                timestamp: nextTick,
                priority: context.priority,
                executionEffort: context.executionEffort,
                context: context
            )
            // Priority fallback: if High priority failed, retry with Medium that is guaranteed to find a slot
            if executorTxID == nil && context.priority == FlowTransactionScheduler.Priority.High {
                executorTxID = self.scheduleCronTransaction(
                    txID: txID,
                    mode: ExecutionMode.Executor,
                    timestamp: nextTick,
                    priority: FlowTransactionScheduler.Priority.Medium,
                    executionEffort: context.executionEffort,
                    context: context
                )
                let wrappedHandler = self.wrappedHandlerCap.borrow()
                emit CronExecutorFallback(
                    txID: txID,
                    cronExpression: self.cronExpression,
                    handlerUUID: self.uuid,
                    wrappedHandlerType: wrappedHandler?.getType()?.identifier,
                    wrappedHandlerUUID: wrappedHandler?.uuid
                )
            }
            // Store executor transaction ID for cancellation support
            self.nextScheduledExecutorID = executorTxID

            // Schedule keeper SECOND with 1 second offset to prevent race condition
            // Offset ensures different timestamp slots -> different blocks -> no collision
            let keeperTxID = self.scheduleCronTransaction(
                txID: txID,
                mode: ExecutionMode.Keeper,
                timestamp: nextTick + FlowCron.KEEPER_OFFSET_SECONDS,
                priority: FlowCron.KEEPER_PRIORITY,
                executionEffort: FlowCron.KEEPER_EXECUTION_EFFORT,
                context: context
            )!
            // Store keeper transaction ID to prevent duplicate scheduling
            self.nextScheduledKeeperID = keeperTxID

            // Emit keeper executed event
            let wrappedHandler = self.wrappedHandlerCap.borrow()
            emit CronKeeperExecuted(
                txID: txID,
                nextExecutorTxID: executorTxID,
                nextKeeperTxID: keeperTxID,
                nextExecutorTime: nextTick,
                nextKeeperTime: nextTick + FlowCron.KEEPER_OFFSET_SECONDS,
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
            mode: ExecutionMode,
            timestamp: UInt64,
            priority: FlowTransactionScheduler.Priority,
            executionEffort: UInt64,
            context: CronContext
        ): UInt64? {
            // Borrow capabilities
            let schedulerManager = context.schedulerManagerCap.borrow() ?? panic("Cannot borrow scheduler manager")
            let feeVault = context.feeProviderCap.borrow() ?? panic("Cannot borrow fee provider")

            // Create execution context
            let execContext = CronContext(
                schedulerManagerCap: context.schedulerManagerCap,
                feeProviderCap: context.feeProviderCap,
                priority: priority,
                executionEffort: executionEffort,
                wrappedData: context.wrappedData,
                executionMode: mode
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
                        executionMode: mode.rawValue,
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
                executionMode: mode.rawValue,
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

    /// Context passed to each cron execution containing scheduler and fee capabilities
    access(all) struct CronContext {
        access(all) let schedulerManagerCap: Capability<auth(FlowTransactionSchedulerUtils.Owner) &{FlowTransactionSchedulerUtils.Manager}>
        access(all) let feeProviderCap: Capability<auth(FungibleToken.Withdraw) &FlowToken.Vault>
        access(all) let priority: FlowTransactionScheduler.Priority
        access(all) let executionEffort: UInt64
        access(all) let wrappedData: AnyStruct?
        access(all) let executionMode: ExecutionMode

        init(
            schedulerManagerCap: Capability<auth(FlowTransactionSchedulerUtils.Owner) &{FlowTransactionSchedulerUtils.Manager}>,
            feeProviderCap: Capability<auth(FungibleToken.Withdraw) &FlowToken.Vault>,
            priority: FlowTransactionScheduler.Priority,
            executionEffort: UInt64,
            wrappedData: AnyStruct?,
            executionMode: ExecutionMode
        ) {
            pre {
                schedulerManagerCap.check(): "Invalid scheduler manager capability"
                feeProviderCap.check(): "Invalid fee provider capability"
                executionEffort >= 10: "Execution effort must be at least 10 (scheduler minimum)"
                executionEffort <= 9999: "Execution effort must be at most 9999 (scheduler maximum)"
            }

            self.schedulerManagerCap = schedulerManagerCap
            self.feeProviderCap = feeProviderCap
            self.priority = priority
            self.executionEffort = executionEffort
            self.wrappedData = wrappedData
            self.executionMode = executionMode
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
        wrappedHandlerCap: Capability<auth(FlowTransactionScheduler.Execute) &{FlowTransactionScheduler.TransactionHandler}>
    ): @CronHandler {
        return <- create CronHandler(
            cronExpression: cronExpression,
            wrappedHandlerCap: wrappedHandlerCap
        )
    }
    
    init() {
        // Set fixed execution effort for keeper operations measured based on its double scheduling workload
        self.KEEPER_EXECUTION_EFFORT = 5000
        // Set fixed medium priority for keeper operations to balance reliability with cost efficiency
        self.KEEPER_PRIORITY = FlowTransactionScheduler.Priority.Medium
        // Keeper offset of 1 second to prevent race condition
        self.KEEPER_OFFSET_SECONDS = 1
    }
}