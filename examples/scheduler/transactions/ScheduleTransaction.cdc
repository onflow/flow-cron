import "FlowTransactionScheduler"
import "FlowTransactionSchedulerUtils"
import "FlowToken"
import "FungibleToken"

transaction(
    handlerStoragePath: StoragePath,
    data: AnyStruct?,
    timestamp: UFix64,
    priority: FlowTransactionScheduler.Priority,
    executionEffort: UInt64,
    feeAmount: UFix64
) {
    let manager: auth(FlowTransactionSchedulerUtils.Owner) &FlowTransactionSchedulerUtils.Manager
    let handlerCap: Capability<auth(FlowTransactionScheduler.Execute) &{FlowTransactionScheduler.TransactionHandler}>
    let fees: @FlowToken.Vault

    prepare(signer: auth(BorrowValue, IssueStorageCapabilityController) &Account) {
        // 1. Borrow Manager reference
        self.manager = signer.storage.borrow<auth(FlowTransactionSchedulerUtils.Owner) &FlowTransactionSchedulerUtils.Manager>(
            from: FlowTransactionSchedulerUtils.managerStoragePath
        ) ?? panic("Could not borrow Manager. Please run SetupManager transaction first.")

        // 2. Issue private capability for handler (not published)
        assert(
            signer.storage.check<@AnyResource>(from: handlerStoragePath),
            message: "No handler found at storage path: ".concat(handlerStoragePath.toString()).concat(". Please ensure you have created and saved your TransactionHandler at this path.")
        )
        self.handlerCap = signer.capabilities.storage.issue<auth(FlowTransactionScheduler.Execute) &{FlowTransactionScheduler.TransactionHandler}>(
            handlerStoragePath
        )

        // 3. Withdraw fees from FlowToken vault
        let vault = signer.storage.borrow<auth(FungibleToken.Withdraw) &FlowToken.Vault>(
            from: /storage/flowTokenVault
        ) ?? panic("Could not borrow FlowToken vault")
        
        self.fees <- vault.withdraw(amount: feeAmount) as! @FlowToken.Vault
    }

    execute {
        // Schedule the transaction
        let transactionId = self.manager.schedule(
            handlerCap: self.handlerCap,
            data: data,
            timestamp: timestamp,
            priority: priority,
            executionEffort: executionEffort,
            fees: <-self.fees
        )
    }
}