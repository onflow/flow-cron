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
    let nextExecutionTime: UInt64
    let cronHandlerCap: Capability<auth(FlowTransactionScheduler.Execute) &{FlowTransactionScheduler.TransactionHandler}>
    let feeProviderCap: Capability<auth(FungibleToken.Withdraw) &FlowToken.Vault>
    let managerCap: Capability<auth(FlowTransactionSchedulerUtils.Owner) &{FlowTransactionSchedulerUtils.Manager}>
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

        // Calculate next execution time
        let currentTime = UInt64(getCurrentBlock().timestamp)
        self.nextExecutionTime = FlowCronUtils.nextTick(spec: cronSpec, afterUnix: currentTime)
            ?? panic("Cannot find next execution time for cron expression")

        // Create capabilities for CronContext
        self.cronHandlerCap = signer.capabilities.storage.issue<auth(FlowTransactionScheduler.Execute) &{FlowTransactionScheduler.TransactionHandler}>(
            cronHandlerStoragePath
        )

        self.feeProviderCap = signer.capabilities.storage.issue<auth(FungibleToken.Withdraw) &FlowToken.Vault>(
            /storage/flowTokenVault
        )

        self.managerCap = signer.capabilities.storage.issue<auth(FlowTransactionSchedulerUtils.Owner) &{FlowTransactionSchedulerUtils.Manager}>(
            FlowTransactionSchedulerUtils.managerStoragePath
        )

        // Create EXECUTOR context (user's priority and effort)
        self.executorContext = FlowCron.CronContext(
            schedulerManagerCap: self.managerCap,
            feeProviderCap: self.feeProviderCap,
            priority: FlowTransactionScheduler.Priority(rawValue: priority)!,
            executionEffort: executionEffort,
            wrappedData: wrappedData,
            executionMode: FlowCron.ExecutionMode.Executor
        )

        // Create KEEPER context (fixed priority and effort)
        self.keeperContext = FlowCron.CronContext(
            schedulerManagerCap: self.managerCap,
            feeProviderCap: self.feeProviderCap,
            priority: FlowCron.KEEPER_PRIORITY,
            executionEffort: FlowCron.KEEPER_EXECUTION_EFFORT,
            wrappedData: wrappedData,
            executionMode: FlowCron.ExecutionMode.Keeper
        )

        // Estimate fees for EXECUTOR
        let executorEstimate = FlowTransactionScheduler.estimate(
            data: self.executorContext,
            timestamp: UFix64(self.nextExecutionTime),
            priority: FlowTransactionScheduler.Priority(rawValue: priority)!,
            executionEffort: executionEffort
        )

        let executorFee = executorEstimate.flowFee ?? panic("Cannot estimate executor fee")

        // Estimate fees for KEEPER
        let keeperEstimate = FlowTransactionScheduler.estimate(
            data: self.keeperContext,
            timestamp: UFix64(self.nextExecutionTime),
            priority: FlowCron.KEEPER_PRIORITY,
            executionEffort: FlowCron.KEEPER_EXECUTION_EFFORT
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
        // Schedule EXECUTOR transaction (user code runs at first tick)
        let executorTxID = self.manager.schedule(
            handlerCap: self.cronHandlerCap,
            data: self.executorContext,
            timestamp: UFix64(self.nextExecutionTime),
            priority: FlowTransactionScheduler.Priority(rawValue: priority)!,
            executionEffort: executionEffort,
            fees: <-self.executorFees
        )

        // Schedule KEEPER transaction (schedules next cycle at first tick)
        let keeperTxID = self.manager.schedule(
            handlerCap: self.cronHandlerCap,
            data: self.keeperContext,
            timestamp: UFix64(self.nextExecutionTime),
            priority: FlowCron.KEEPER_PRIORITY,
            executionEffort: FlowCron.KEEPER_EXECUTION_EFFORT,
            fees: <-self.keeperFees
        )

        log("Cron handler initialized successfully")
        log("First execution at: ".concat(self.nextExecutionTime.toString()))
        log("Executor TX ID: ".concat(executorTxID.toString()))
        log("Keeper TX ID: ".concat(keeperTxID.toString()))
    }
}