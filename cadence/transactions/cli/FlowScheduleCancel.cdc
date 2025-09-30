import "FlowTransactionSchedulerUtils"
import "FlowToken"
import "FungibleToken"

/// Cancels a scheduled transaction by ID
/// This transaction is used by: flow schedule cancel <transaction-id> [--signer account]
transaction(transactionId: UInt64) {
    let manager: auth(FlowTransactionSchedulerUtils.Owner) &{FlowTransactionSchedulerUtils.Manager}
    let receiverRef: &{FungibleToken.Receiver}
    
    prepare(signer: auth(BorrowValue) &Account) {
        // Borrow the Manager with Owner entitlement
        self.manager = signer.storage.borrow<auth(FlowTransactionSchedulerUtils.Owner) &{FlowTransactionSchedulerUtils.Manager}>(
            from: FlowTransactionSchedulerUtils.managerStoragePath
        ) ?? panic("Could not borrow Manager with Owner entitlement from account")
        
        // Get receiver reference from signer's account
        self.receiverRef = signer.capabilities.borrow<&{FungibleToken.Receiver}>(/public/flowTokenReceiver)
            ?? panic("Could not borrow receiver reference")
    }
    
    execute {
        // Cancel the transaction and receive refunded fees
        let refundedFees <- self.manager.cancel(id: transactionId)
        
        // Deposit refunded fees back to the signer's vault
        self.receiverRef.deposit(from: <-refundedFees)
    }
}