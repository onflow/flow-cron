import "FlowCron"
import "FlowTransactionSchedulerUtils"
import "FlowTransactionScheduler"
import "FlowToken"
import "FungibleToken"

/// Creates a CronHandler wrapping an existing TransactionHandler with cron scheduling
transaction(
    cronExpression: String,
    wrappedHandlerStoragePath: StoragePath,
    cronHandlerStoragePath: StoragePath
) {
    prepare(acct: auth(BorrowValue, IssueStorageCapabilityController, SaveValue) &Account) {
        // Ensure Manager exists
        if acct.storage.borrow<&{FlowTransactionSchedulerUtils.Manager}>(from: FlowTransactionSchedulerUtils.managerStoragePath) == nil {
            acct.storage.save(<-FlowTransactionSchedulerUtils.createManager(), to: FlowTransactionSchedulerUtils.managerStoragePath)
        }

        // Issue wrapped handler capability
        let wrappedHandlerCap = acct.capabilities.storage.issue<auth(FlowTransactionScheduler.Execute) &{FlowTransactionScheduler.TransactionHandler}>(
            wrappedHandlerStoragePath
        )

        // Issue fee provider capability
        let feeProviderCap = acct.capabilities.storage.issue<auth(FungibleToken.Withdraw) &FlowToken.Vault>(
            /storage/flowTokenVault
        )

        // Issue scheduler manager capability
        let schedulerManagerCap = acct.capabilities.storage.issue<auth(FlowTransactionSchedulerUtils.Owner) &{FlowTransactionSchedulerUtils.Manager}>(
            FlowTransactionSchedulerUtils.managerStoragePath
        )

        // Create handler with all capabilities
        let cronHandler <- FlowCron.createCronHandler(
            cronExpression: cronExpression,
            wrappedHandlerCap: wrappedHandlerCap,
            feeProviderCap: feeProviderCap,
            schedulerManagerCap: schedulerManagerCap
        )
        acct.storage.save(<-cronHandler, to: cronHandlerStoragePath)
    }
}
