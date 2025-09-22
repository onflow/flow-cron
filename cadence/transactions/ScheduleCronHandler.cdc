import "FlowCron"
import "FlowTransactionSchedulerUtils"
import "FlowTransactionScheduler"
import "FlowToken"
import "FungibleToken"

/// Schedules a CronHandler for recurring execution
transaction(
    cronHandlerStoragePath: StoragePath,
    wrappedData: AnyStruct?,
    priority: FlowTransactionScheduler.Priority,
    executionEffort: UInt64
) {
    let managerCap: Capability<auth(FlowTransactionSchedulerUtils.Owner) &{FlowTransactionSchedulerUtils.Manager}>
    let cronHandlerCap: Capability<auth(FlowTransactionScheduler.Execute) &{FlowTransactionScheduler.TransactionHandler}>
    let feeProviderCap: Capability<auth(FungibleToken.Withdraw) &FlowToken.Vault>
    
    prepare(signer: auth(BorrowValue, IssueStorageCapabilityController, SaveValue) &Account) {
        // Check if Manager already exists
        if signer.storage.borrow<&{FlowTransactionSchedulerUtils.Manager}>(from: FlowTransactionSchedulerUtils.managerStoragePath) == nil {
            // Create and save Manager
            signer.storage.save(
                <-FlowTransactionSchedulerUtils.createManager(),
                to: FlowTransactionSchedulerUtils.managerStoragePath
            )
        }
        assert(
            signer.storage.borrow<&{FlowTransactionScheduler.TransactionHandler}>(from: cronHandlerStoragePath) != nil,
            message: "CronHandler not found at specified path"
        )
        assert(
            signer.storage.borrow<&{FungibleToken.Vault}>(from: /storage/flowTokenVault) != nil,
            message: "Flow token vault not found"
        )
        
        // Create capabilities
        self.managerCap = signer.capabilities.storage.issue<auth(FlowTransactionSchedulerUtils.Owner) &{FlowTransactionSchedulerUtils.Manager}>(
            FlowTransactionSchedulerUtils.managerStoragePath
        )
        self.cronHandlerCap = signer.capabilities.storage.issue<auth(FlowTransactionScheduler.Execute) &{FlowTransactionScheduler.TransactionHandler}>(
            cronHandlerStoragePath
        )
        self.feeProviderCap = signer.capabilities.storage.issue<auth(FungibleToken.Withdraw) &FlowToken.Vault>(
            /storage/flowTokenVault
        )
    }
    
    execute {
        FlowCron.scheduleCronHandler(
            cronHandlerCap: self.cronHandlerCap,
            schedulerManagerCap: self.managerCap,
            feeProviderCap: self.feeProviderCap,
            data: wrappedData,
            priority: priority,
            executionEffort: executionEffort
        )
    }
}