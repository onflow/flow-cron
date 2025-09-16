import "FlowTransactionScheduler"
import "FlowTransactionSchedulerUtils"
import "FlowToken"
import "FungibleToken"

/// Schedule a handler -> schedule a transaction with input handler
/// This transaction schedules a transaction handler for future execution
transaction(
    handlerStoragePath: StoragePath,
    data: AnyStruct?,
    timestamp: UFix64,
    priority: FlowTransactionScheduler.Priority,
    executionEffort: UInt64
) {
    let manager: auth(FlowTransactionSchedulerUtils.Owner) &FlowTransactionSchedulerUtils.Manager
    let handlerCap: Capability<auth(FlowTransactionScheduler.Execute) &{FlowTransactionScheduler.TransactionHandler}>
    let feeAmount: UFix64
    let paymentVault: @FlowToken.Vault
    
    prepare(signer: auth(BorrowValue, IssueStorageCapabilityController, SaveValue) &Account) {
        // 1. Create TransactionSchedulerUtils Manager if it doesn't exist
        let schedulerManagerPath = FlowTransactionSchedulerUtils.managerStoragePath
        if signer.storage.borrow<&FlowTransactionSchedulerUtils.Manager>(from: schedulerManagerPath) == nil {
            signer.storage.save(<-FlowTransactionSchedulerUtils.createManager(), to: schedulerManagerPath)
        }
        
        // 2. Borrow Manager reference
        self.manager = signer.storage.borrow<auth(FlowTransactionSchedulerUtils.Owner) &FlowTransactionSchedulerUtils.Manager>(
            from: schedulerManagerPath
        ) ?? panic("Could not borrow Manager from storage")
        
        // 3. Verify the handler exists at the specified path
        assert(
            signer.storage.check<@AnyResource>(from: handlerStoragePath),
            message: "No handler found at storage path: ".concat(handlerStoragePath.toString()).concat(". Please ensure you have created and saved your TransactionHandler at this path.")
        )
        
        // 4. Issue private capability for the handler (not published)
        self.handlerCap = signer.capabilities.storage.issue<auth(FlowTransactionScheduler.Execute) &{FlowTransactionScheduler.TransactionHandler}>(
            handlerStoragePath
        )
        
        // 5. Estimate fees for the transaction
        let estimate = FlowTransactionScheduler.estimate(
            data: data,
            timestamp: timestamp,
            priority: priority,
            executionEffort: executionEffort
        )
        
        assert(
            estimate.flowFee != nil,
            message: "Could not estimate fees: ".concat(estimate.error ?? "Unknown error")
        )
        
        self.feeAmount = estimate.flowFee!
        
        // 6. Verify FlowToken vault exists
        let flowTokenVaultPath = /storage/flowTokenVault
        assert(
            signer.storage.borrow<&FlowToken.Vault>(from: flowTokenVaultPath) != nil,
            message: "FlowToken Vault not found. Please ensure you have FLOW tokens."
        )
        
        // 7. Withdraw fees from the signer's FlowToken vault
        let flowTokenVault = signer.storage.borrow<auth(FungibleToken.Withdraw) &FlowToken.Vault>(
            from: flowTokenVaultPath
        ) ?? panic("Could not borrow FlowToken vault")
        
        self.paymentVault <- flowTokenVault.withdraw(amount: self.feeAmount) as! @FlowToken.Vault
    }
    
    execute {
        // Schedule the transaction through the manager
        let transactionID = self.manager.schedule(
            handlerCap: self.handlerCap,
            data: data,
            timestamp: timestamp,
            priority: priority,
            executionEffort: executionEffort,
            fees: <-self.paymentVault
        )
    }
}