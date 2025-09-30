import "FlowTransactionSchedulerUtils"
import "FlowToken"
import "FungibleToken"

transaction(transactionId: UInt64) {
    let manager: auth(FlowTransactionSchedulerUtils.Owner) &{FlowTransactionSchedulerUtils.Manager}
    let tokenReceiver: &{FungibleToken.Receiver}

    prepare(signer: auth(BorrowValue) &Account) {
        // 1. Borrow Manager reference
        self.manager = signer.storage.borrow<auth(FlowTransactionSchedulerUtils.Owner) &{FlowTransactionSchedulerUtils.Manager}>(
            from: FlowTransactionSchedulerUtils.managerStoragePath
        ) ?? panic("Could not borrow Manager. Please ensure you have a Manager set up.")

         // Verify transaction exists in manager
        assert(
            self.manager.getTransactionIDs().contains(transactionId),
            message: "Transaction with ID ".concat(transactionId.toString()).concat(" not found in manager")
        )

        // 2. Get FlowToken receiver to deposit refunds
        self.tokenReceiver = signer.capabilities.get<&{FungibleToken.Receiver}>(/public/flowTokenReceiver)
            .borrow()
            ?? panic("Could not borrow FlowToken receiver")
    }

    execute {
        // Cancel the transaction and receive refunded fees
        let refundVault <- self.manager.cancel(id: transactionId)
        
        // Deposit refunded fees back to the account
        self.tokenReceiver.deposit(from: <-refundVault)
    }
}