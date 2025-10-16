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
    access(all) event CronScheduleExecuted(
        txID: UInt64,
        nextTxID: UInt64?,
        futureTxID: UInt64?,
        cronExpression: String,
        handlerUUID: UInt64,
        handlerOwner: Address,
        wrappedHandlerType: String?,
        wrappedHandlerUUID: UInt64?,
        wrappedHandlerOwner: Address?
    )
    access(all) event CronScheduleRejected(
        txID: UInt64,
        nextTxID: UInt64?,
        futureTxID: UInt64?,
        cronExpression: String,
        handlerUUID: UInt64,
        handlerOwner: Address,
        wrappedHandlerType: String?,
        wrappedHandlerUUID: UInt64?,
        wrappedHandlerOwner: Address?
    )
    access(all) event CronScheduleFailed(
        txID: UInt64,
        scheduleType: UInt8,
        requiredAmount: UFix64,
        availableAmount: UFix64,
        cronExpression: String,
        handlerUUID: UInt64,
        handlerOwner: Address,
        wrappedHandlerType: String?,
        wrappedHandlerUUID: UInt64?,
        wrappedHandlerOwner: Address?
    )
    access(all) event CronEstimationFailed(
        txID: UInt64,
        scheduleType: UInt8,
        cronExpression: String,
        handlerUUID: UInt64,
        handlerOwner: Address,
        wrappedHandlerType: String?,
        wrappedHandlerUUID: UInt64?,
        wrappedHandlerOwner: Address?
    )

    /// Enum representing the type of cron schedule slot
    access(all) enum CronScheduleType: UInt8 {
        access(all) case Next
        access(all) case Future
    }

    /// CronHandler resource wraps any TransactionHandler with cron scheduling functionality
    access(all) resource CronHandler: FlowTransactionScheduler.TransactionHandler, ViewResolver.Resolver {

        /// Cron expression for scheduling
        access(all) let cronExpression: String
        /// Cron spec for scheduling
        access(all) let cronSpec: FlowCronUtils.CronSpec

        /// The handler that performs the actual work
        access(self) let wrappedHandlerCap: Capability<auth(FlowTransactionScheduler.Execute) &{FlowTransactionScheduler.TransactionHandler}>
        
        /// Internal state to track our scheduled transactions
        access(self) var currentScheduledTransactionID: UInt64?
        access(self) var nextScheduledTransactionID: UInt64?
        access(self) var futureScheduledTransactionID: UInt64?

        /// Indicates whether this handler has an active schedule, preventing new scheduling with different contexts
        access(self) var hasActiveSchedule: Bool
        
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
            self.currentScheduledTransactionID = nil
            self.nextScheduledTransactionID = nil
            self.futureScheduledTransactionID = nil
            self.hasActiveSchedule = false
        }
        
        access(FlowTransactionScheduler.Execute) fun executeTransaction(id: UInt64, data: AnyStruct?) {
            // Store the current transaction ID for event emissions
            self.currentScheduledTransactionID = id

            // Sync schedule state and determine execution type
            self.syncSchedule()

            // Handle execution based on type
            if self.isExpectedTransaction(id: id) {
                self.updateSchedule(executedID: id)
            } else {
                if self.hasActiveSchedule {
                    let wrappedHandler = self.wrappedHandlerCap.borrow()
                    emit CronScheduleRejected(
                        txID: id,
                        nextTxID: self.nextScheduledTransactionID,
                        futureTxID: self.futureScheduledTransactionID,
                        cronExpression: self.cronExpression,
                        handlerUUID: self.uuid,
                        handlerOwner: self.wrappedHandlerCap.address,
                        wrappedHandlerType: wrappedHandler?.getType()?.identifier,
                        wrappedHandlerUUID: wrappedHandler?.uuid,
                        wrappedHandlerOwner: self.wrappedHandlerCap.address
                    )
                    return
                }
            }

            let context = data as? CronContext ?? panic("Invalid execution data: expected CronContext")
            self.fillSchedule(context: context)

            let wrappedHandler = self.wrappedHandlerCap.borrow() ?? panic("Cannot borrow wrapped handler capability")
            wrappedHandler.executeTransaction(id: id, data: context.wrappedData)

            emit CronScheduleExecuted(
                txID: id,
                nextTxID: self.nextScheduledTransactionID,
                futureTxID: self.futureScheduledTransactionID,
                cronExpression: self.cronExpression,
                handlerUUID: self.uuid,
                handlerOwner: self.wrappedHandlerCap.address,
                wrappedHandlerType: wrappedHandler.getType().identifier,
                wrappedHandlerUUID: wrappedHandler.uuid,
                wrappedHandlerOwner: self.wrappedHandlerCap.address
            )
        }

        /// Syncs internal schedule state with external transaction scheduler
        ///
        /// Ensures consistency between our internal state and the actual scheduler.
        /// - Validates that stored transaction IDs still exist and are in Scheduled status
        /// - Clears stale IDs (executed, cancelled, or missing transactions)
        /// - Updates hasActiveSchedule flag to control whether new scheduling is allowed
        ///
        /// Why this matters:
        /// - Transactions can be cancelled externally via FlowTransactionScheduler
        /// - Transactions execute and change status from Scheduled to other states
        /// - We need accurate state to decide: accept new scheduling vs. reject with different context
        /// - When both IDs are cleared, hasActiveSchedule becomes false, allowing fresh scheduling
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
                self.hasActiveSchedule = false
            } else if !self.hasActiveSchedule {
                // Mark as scheduled if we have valid transactions but flag isn't set yet
                self.hasActiveSchedule = true
            }
        }
        
        /// Checks if the given transaction ID is one we're expecting to execute
        ///
        /// Returns true for BOTH nextScheduledTransactionID and futureScheduledTransactionID.
        /// This is intentional as part of the double-buffer pattern:
        /// - Normal case: Only the next transaction executes, future remains queued
        /// - Failure recovery: If next fails to execute, future can execute instead
        /// - Both are valid execution paths that should trigger rescheduling
        access(self) view fun isExpectedTransaction(id: UInt64): Bool {
            return id == self.nextScheduledTransactionID || id == self.futureScheduledTransactionID
        }
        
        /// Helper function to update internal state after executing an expected transaction
        access(self) fun updateSchedule(executedID: UInt64) {
            // Update state based on the executed transaction ID
            if executedID == self.nextScheduledTransactionID {
                self.nextScheduledTransactionID = self.futureScheduledTransactionID
                self.futureScheduledTransactionID = nil
            } else if executedID == self.futureScheduledTransactionID {
                self.futureScheduledTransactionID = nil
            }
        }

        /// Helper function to attempt scheduling a single transaction
        /// Returns the transaction ID if successful, nil if failed (fee estimation or insufficient funds)
        access(self) fun scheduleTransaction(
            scheduleType: CronScheduleType,
            timestamp: UInt64,
            context: CronContext
        ): UInt64? {
            // Borrow capabilities we'll need
            let schedulerManager = context.schedulerManagerCap.borrow() ?? panic("Cannot borrow scheduler manager capability")
            let feeVault = context.feeProviderCap.borrow() ?? panic("Cannot borrow fee provider capability")

            // Estimate fees
            let estimate = FlowTransactionScheduler.estimate(
                data: context,
                timestamp: UFix64(timestamp),
                priority: context.priority,
                executionEffort: context.executionEffort
            )

            // Check if we got a fee estimate
            if let requiredFee = estimate.flowFee {
                // Check if we have enough funds
                if feeVault.balance >= requiredFee {
                    // Withdraw fees and schedule
                    let fees <- feeVault.withdraw(amount: requiredFee)
                    let transactionId = schedulerManager.scheduleByHandler(
                        handlerTypeIdentifier: self.getType().identifier,
                        handlerUUID: self.uuid,
                        data: context,
                        timestamp: UFix64(timestamp),
                        priority: context.priority,
                        executionEffort: context.executionEffort,
                        fees: <-fees as! @FlowToken.Vault
                    )
                    return transactionId
                } else {
                    // Insufficient funds
                    let wrappedHandler = self.wrappedHandlerCap.borrow()
                    emit CronScheduleFailed(
                        txID: self.currentScheduledTransactionID!,
                        scheduleType: scheduleType.rawValue,
                        requiredAmount: requiredFee,
                        availableAmount: feeVault.balance,
                        cronExpression: self.cronExpression,
                        handlerUUID: self.uuid,
                        handlerOwner: self.wrappedHandlerCap.address,
                        wrappedHandlerType: wrappedHandler?.getType()?.identifier,
                        wrappedHandlerUUID: wrappedHandler?.uuid,
                        wrappedHandlerOwner: self.wrappedHandlerCap.address
                    )
                    return nil
                }
            } else {
                // Fee estimation failed
                let wrappedHandler = self.wrappedHandlerCap.borrow()
                emit CronEstimationFailed(
                    txID: self.currentScheduledTransactionID!,
                    scheduleType: scheduleType.rawValue,
                    cronExpression: self.cronExpression,
                    handlerUUID: self.uuid,
                    handlerOwner: self.wrappedHandlerCap.address,
                    wrappedHandlerType: wrappedHandler?.getType()?.identifier,
                    wrappedHandlerUUID: wrappedHandler?.uuid,
                    wrappedHandlerOwner: self.wrappedHandlerCap.address
                )
                return nil
            }
        }

        /// Ensures double scheduling by filling gaps in next/future transactions
        ///
        /// Implements the double-buffer pattern for cron scheduling:
        /// - Maintains two scheduled transactions at all times (next + future)
        /// - Called BEFORE executing the wrapped handler to ensure continuity
        /// - Automatically calculates execution times based on cron expression
        /// - Handles fee estimation and vault balance checking
        /// - Emits failure events if scheduling cannot be completed
        ///
        /// The double-buffer ensures:
        /// - Continuous operation even if one transaction fails
        /// - Automatic gap-filling when transactions are missed
        /// - Reliability through redundancy
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

            // Schedule next transaction if needed
            if needsNext {
                if let nextTxId = self.scheduleTransaction(
                    scheduleType: CronScheduleType.Next,
                    timestamp: nextTime,
                    context: context
                ) {
                    self.nextScheduledTransactionID = nextTxId
                }
            }
            // Schedule future transaction if needed
            if needsFuture {
                if let futureTxId = self.scheduleTransaction(
                    scheduleType: CronScheduleType.Future,
                    timestamp: futureTime,
                    context: context
                ) {
                    self.futureScheduledTransactionID = futureTxId
                }
            }
        }

        /// Returns the cron expression
        access(all) view fun getCronExpression(): String {
            return self.cronExpression
        }

        /// Returns a copy of the cron spec for use in calculations
        access(all) view fun getCronSpec(): FlowCronUtils.CronSpec {
            return self.cronSpec
        }

        /// Returns the next scheduled transaction ID if one exists
        access(all) view fun getNextScheduledTransactionID(): UInt64? {
            return self.nextScheduledTransactionID
        }

        /// Returns the future scheduled transaction ID if one exists
        access(all) view fun getFutureScheduledTransactionID(): UInt64? {
            return self.futureScheduledTransactionID
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