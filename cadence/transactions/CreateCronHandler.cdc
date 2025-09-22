import "FlowCron"
import "FlowTransactionSchedulerUtils"
import "FlowTransactionScheduler"

/// Creates a CronHandler wrapping an existing TransactionHandler with cron scheduling
transaction(
    cronExpression: String,
    wrappedHandlerStoragePath: StoragePath,
    cronHandlerStoragePath: StoragePath
) {
    prepare(acct: auth(BorrowValue, IssueStorageCapabilityController, SaveValue) &Account) {
        // Create and store CronHandler
        let wrappedHandlerCap = acct.capabilities.storage.issue<auth(FlowTransactionScheduler.Execute) &{FlowTransactionScheduler.TransactionHandler}>(
            wrappedHandlerStoragePath
        )
        
        let cronHandler <- FlowCron.createCronHandler(
            cronExpression: cronExpression,
            wrappedHandlerCap: wrappedHandlerCap
        )
        acct.storage.save(<-cronHandler, to: cronHandlerStoragePath)
    }
}