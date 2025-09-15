import "FlowCron"
import "FlowCronUtils"
import "FlowTransactionScheduler"
import "FlowTransactionSchedulerUtils"
import "FlowToken"
import "FungibleToken"

transaction(
    cronSpec: FlowCronUtils.CronSpec,
    wrappedHandlerStoragePath: StoragePath,
    data: AnyStruct?,
    priority: FlowTransactionScheduler.Priority,
    executionEffort: UInt64
) {
    let cronHandler: auth(FlowCron.Owner) &FlowCron.CronHandler
    let cronHandlerCap: Capability<auth(FlowTransactionScheduler.Execute) &{FlowTransactionScheduler.TransactionHandler}>
    let wrappedHandlerCap: Capability<auth(FlowTransactionScheduler.Execute) &{FlowTransactionScheduler.TransactionHandler}>
    let schedulerManagerCap: Capability<auth(FlowTransactionSchedulerUtils.Owner) &FlowTransactionSchedulerUtils.Manager>
    let feeProviderCap: Capability<auth(FungibleToken.Withdraw) &FlowToken.Vault>

    prepare(signer: auth(BorrowValue, IssueStorageCapabilityController, SaveValue) &Account) {
        // 1. Create CronHandler if it doesn't exist
        if signer.storage.borrow<&FlowCron.CronHandler>(from: FlowCron.CronHandlerStoragePath) == nil {
            signer.storage.save(<-FlowCron.createHandler(), to: FlowCron.CronHandlerStoragePath)
        }

        // 2. Create TransactionSchedulerUtils Manager if it doesn't exist
        let schedulerManagerPath = FlowTransactionSchedulerUtils.managerStoragePath
        if signer.storage.borrow<&FlowTransactionSchedulerUtils.Manager>(from: schedulerManagerPath) == nil {
            signer.storage.save(<-FlowTransactionSchedulerUtils.createManager(), to: schedulerManagerPath)
        }

        // 3. Borrow CronHandler reference
        self.cronHandler = signer.storage.borrow<auth(FlowCron.Owner) &FlowCron.CronHandler>(
            from: FlowCron.CronHandlerStoragePath
        ) ?? panic("Could not borrow CronHandler from storage")

        // 4. Issue private capability for CronHandler (not published)
        self.cronHandlerCap = signer.capabilities.storage.issue<auth(FlowTransactionScheduler.Execute) &{FlowTransactionScheduler.TransactionHandler}>(
            FlowCron.CronHandlerStoragePath
        )

        // 5. Issue private capability for wrapped handler (not published)
        // Verify the handler exists first
        assert(
            signer.storage.check<@AnyResource>(from: wrappedHandlerStoragePath),
            message: "No handler found at storage path: ".concat(wrappedHandlerStoragePath.toString()).concat(". Please ensure you have created and saved your TransactionHandler at this path.")
        )
        self.wrappedHandlerCap = signer.capabilities.storage.issue<auth(FlowTransactionScheduler.Execute) &{FlowTransactionScheduler.TransactionHandler}>(
            wrappedHandlerStoragePath
        )

        // 6. Issue private capability for scheduler manager (not published)
        self.schedulerManagerCap = signer.capabilities.storage.issue<auth(FlowTransactionSchedulerUtils.Owner) &FlowTransactionSchedulerUtils.Manager>(
            schedulerManagerPath
        )

        // 7. Issue private capability for fee provider (not published)
        let flowTokenVaultPath = /storage/flowTokenVault
        assert(
            signer.storage.borrow<&FlowToken.Vault>(from: flowTokenVaultPath) != nil,
            message: "FlowToken Vault not found. Please ensure you have FLOW tokens."
        )
        self.feeProviderCap = signer.capabilities.storage.issue<auth(FungibleToken.Withdraw) &FlowToken.Vault>(
            flowTokenVaultPath
        )
    }

    execute {
        // Schedule the cron job with all private capabilities
        let jobId = self.cronHandler.scheduleJob(
            cronSpec: cronSpec,
            cronHandlerCap: self.cronHandlerCap,
            wrappedHandlerCap: self.wrappedHandlerCap,
            schedulerManagerCap: self.schedulerManagerCap,
            feeProviderCap: self.feeProviderCap,
            data: data,
            priority: priority,
            executionEffort: executionEffort
        )
    }
}