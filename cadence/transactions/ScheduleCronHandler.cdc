import "FlowCron"
import "FlowTransactionSchedulerUtils"
import "FlowTransactionScheduler"
import "FlowToken"
import "FungibleToken"
import "FlowCronUtils"

/// Schedules a CronHandler for recurring execution
/// The system will automatically handle double scheduling and rescheduling
transaction(
    cronHandlerStoragePath: StoragePath,
    wrappedData: AnyStruct?,
    priority: FlowTransactionScheduler.Priority,
    executionEffort: UInt64
) {
    let manager: auth(FlowTransactionSchedulerUtils.Owner) &{FlowTransactionSchedulerUtils.Manager}
    let nextExecutionTime: UInt64
    let cronHandlerCap: Capability<auth(FlowTransactionScheduler.Execute) &{FlowTransactionScheduler.TransactionHandler}>
    let feeProviderCap: Capability<auth(FungibleToken.Withdraw) &FlowToken.Vault>
    let managerCap: Capability<auth(FlowTransactionSchedulerUtils.Owner) &{FlowTransactionSchedulerUtils.Manager}>
    let context: FlowCron.CronContext
    let fees: @FlowToken.Vault

    prepare(signer: auth(BorrowValue, IssueStorageCapabilityController, SaveValue) &Account) {
        // Ensure Manager exists
        if signer.storage.borrow<&{FlowTransactionSchedulerUtils.Manager}>(from: FlowTransactionSchedulerUtils.managerStoragePath) == nil {
            signer.storage.save(<-FlowTransactionSchedulerUtils.createManager(), to: FlowTransactionSchedulerUtils.managerStoragePath)
        }

        // Borrow manager
        self.manager = signer.storage.borrow<auth(FlowTransactionSchedulerUtils.Owner) &{FlowTransactionSchedulerUtils.Manager}>(
            from: FlowTransactionSchedulerUtils.managerStoragePath
        ) ?? panic("Cannot borrow manager")

        // Borrow cron handler to get cron info
        let cronHandler = signer.storage.borrow<&FlowCron.CronHandler>(from: cronHandlerStoragePath)
            ?? panic("CronHandler not found at specified path")

        // Get CronInfo from resolved view
        let cronInfo = cronHandler.resolveView(Type<FlowCron.CronInfo>()) as? FlowCron.CronInfo
            ?? panic("Cannot resolve CronInfo view")

        // Calculate next execution time
        let currentTime = UInt64(getCurrentBlock().timestamp)
        self.nextExecutionTime = FlowCronUtils.nextTick(spec: cronInfo.cronSpec, afterUnix: currentTime)
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

        // Create CronContext
        self.context = FlowCron.CronContext(
            schedulerManagerCap: self.managerCap,
            feeProviderCap: self.feeProviderCap,
            priority: priority,
            executionEffort: executionEffort,
            wrappedData: wrappedData
        )

        // Estimate and withdraw fees
        let estimate = FlowTransactionScheduler.estimate(
            data: self.context,
            timestamp: UFix64(self.nextExecutionTime),
            priority: priority,
            executionEffort: executionEffort
        )

        let requiredFee = estimate.flowFee ?? panic("Cannot estimate transaction fee")

        let feeVault = signer.storage.borrow<auth(FungibleToken.Withdraw) &FlowToken.Vault>(from: /storage/flowTokenVault)
            ?? panic("Flow token vault not found")

        if feeVault.balance < requiredFee {
            panic("Insufficient funds: required ".concat(requiredFee.toString()).concat(", available ").concat(feeVault.balance.toString()))
        }

        self.fees <- feeVault.withdraw(amount: requiredFee) as! @FlowToken.Vault
    }

    execute {
        // Schedule the cron transaction
        let transactionId = self.manager.schedule(
            handlerCap: self.cronHandlerCap,
            data: self.context,
            timestamp: UFix64(self.nextExecutionTime),
            priority: priority,
            executionEffort: executionEffort,
            fees: <-self.fees
        )

        log("Scheduled cron transaction with ID: ".concat(transactionId.toString()).concat(" at time: ").concat(self.nextExecutionTime.toString()))
    }
}