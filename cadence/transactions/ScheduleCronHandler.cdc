import "FlowCron"
import "FlowTransactionSchedulerUtils"
import "FlowTransactionScheduler"
import "FlowToken"
import "FungibleToken"
import "FlowCronUtils"

/// Schedules a CronHandler for recurring execution
/// Schedules BOTH executor and keeper for the first cron tick to bootstrap the perpetual chain
transaction(
    cronHandlerStoragePath: StoragePath,
    wrappedData: AnyStruct?,
    priority: UInt8,
    executionEffort: UInt64
) {
    let manager: auth(FlowTransactionSchedulerUtils.Owner) &{FlowTransactionSchedulerUtils.Manager}
    let executorTime: UInt64
    let keeperTime: UInt64
    let cronHandlerCap: Capability<auth(FlowTransactionScheduler.Execute) &{FlowTransactionScheduler.TransactionHandler}>
    let executorContext: FlowCron.CronContext
    let keeperContext: FlowCron.CronContext
    let executorFees: @FlowToken.Vault
    let keeperFees: @FlowToken.Vault

    prepare(signer: auth(BorrowValue, IssueStorageCapabilityController, SaveValue) &Account) {
        // Ensure Manager exists
        if signer.storage.borrow<&{FlowTransactionSchedulerUtils.Manager}>(from: FlowTransactionSchedulerUtils.managerStoragePath) == nil {
            signer.storage.save(<-FlowTransactionSchedulerUtils.createManager(), to: FlowTransactionSchedulerUtils.managerStoragePath)
        }

        // Borrow manager
        self.manager = signer.storage.borrow<auth(FlowTransactionSchedulerUtils.Owner) &{FlowTransactionSchedulerUtils.Manager}>(
            from: FlowTransactionSchedulerUtils.managerStoragePath
        ) ?? panic("Cannot borrow manager")

        // Borrow cron handler to get cron spec
        let cronHandler = signer.storage.borrow<&FlowCron.CronHandler>(from: cronHandlerStoragePath)
            ?? panic("CronHandler not found at specified path")

        // Get a copy of the cron spec via getter function
        let cronSpec = cronHandler.getCronSpec()

        // Calculate execution times: executor at cron tick, keeper 1 second later
        let currentTime = UInt64(getCurrentBlock().timestamp)
        self.executorTime = FlowCronUtils.nextTick(spec: cronSpec, afterUnix: currentTime)
            ?? panic("Cannot find next execution time for cron expression")
        self.keeperTime = self.executorTime + FlowCron.keeperOffset

        // Issue capability for cron handler (needed for scheduling)
        self.cronHandlerCap = signer.capabilities.storage.issue<auth(FlowTransactionScheduler.Execute) &{FlowTransactionScheduler.TransactionHandler}>(
            cronHandlerStoragePath
        )

        // Create EXECUTOR context (user's priority and effort)
        self.executorContext = FlowCron.CronContext(
            executionMode: FlowCron.ExecutionMode.Executor,
            priority: FlowTransactionScheduler.Priority(rawValue: priority)!,
            executionEffort: executionEffort,
            wrappedData: wrappedData
        )

        // Create KEEPER context (fixed priority and effort)
        self.keeperContext = FlowCron.CronContext(
            executionMode: FlowCron.ExecutionMode.Keeper,
            priority: FlowCron.keeperPriority,
            executionEffort: FlowCron.keeperExecutionEffort,
            wrappedData: wrappedData
        )

        // Estimate fees for EXECUTOR
        let executorEstimate = FlowTransactionScheduler.estimate(
            data: self.executorContext,
            timestamp: UFix64(self.executorTime),
            priority: FlowTransactionScheduler.Priority(rawValue: priority)!,
            executionEffort: executionEffort
        )

        let executorFee = executorEstimate.flowFee ?? panic("Cannot estimate executor fee")

        // Estimate fees for KEEPER (scheduled 1 second after executor)
        let keeperEstimate = FlowTransactionScheduler.estimate(
            data: self.keeperContext,
            timestamp: UFix64(self.keeperTime),
            priority: FlowCron.keeperPriority,
            executionEffort: FlowCron.keeperExecutionEffort
        )

        let keeperFee = keeperEstimate.flowFee ?? panic("Cannot estimate keeper fee")

        // Calculate total fees
        let totalFee = executorFee + keeperFee

        // Borrow fee vault and check balance
        let feeVault = signer.storage.borrow<auth(FungibleToken.Withdraw) &FlowToken.Vault>(from: /storage/flowTokenVault)
            ?? panic("Flow token vault not found")

        if feeVault.balance < totalFee {
            panic("Insufficient funds: required ".concat(totalFee.toString()).concat(" FLOW (executor: ").concat(executorFee.toString()).concat(", keeper: ").concat(keeperFee.toString()).concat("), available ").concat(feeVault.balance.toString()))
        }

        // Withdraw fees for BOTH transactions
        self.executorFees <- feeVault.withdraw(amount: executorFee) as! @FlowToken.Vault
        self.keeperFees <- feeVault.withdraw(amount: keeperFee) as! @FlowToken.Vault
    }

    execute {
        // Schedule EXECUTOR transaction (user code runs at cron tick)
        let executorTxID = self.manager.schedule(
            handlerCap: self.cronHandlerCap,
            data: self.executorContext,
            timestamp: UFix64(self.executorTime),
            priority: FlowTransactionScheduler.Priority(rawValue: priority)!,
            executionEffort: executionEffort,
            fees: <-self.executorFees
        )

        // Schedule KEEPER transaction (1 second after executor to prevent race conditions)
        let keeperTxID = self.manager.schedule(
            handlerCap: self.cronHandlerCap,
            data: self.keeperContext,
            timestamp: UFix64(self.keeperTime),
            priority: FlowCron.keeperPriority,
            executionEffort: FlowCron.keeperExecutionEffort,
            fees: <-self.keeperFees
        )
    }
}
