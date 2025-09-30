import "FlowTransactionScheduler"
import "FlowTransactionSchedulerUtils"

access(all) struct TransactionInfo {
    access(all) let id: UInt64
    access(all) let priority: UInt8
    access(all) let executionEffort: UInt64
    access(all) let status: UInt8
    access(all) let fees: UFix64
    access(all) let scheduledTimestamp: UFix64
    access(all) let handlerTypeIdentifier: String
    access(all) let handlerAddress: Address
    
    init(data: FlowTransactionScheduler.TransactionData) {
        self.id = data.id
        self.priority = data.priority.rawValue
        self.executionEffort = data.executionEffort
        self.status = data.status.rawValue
        self.fees = data.fees
        self.scheduledTimestamp = data.scheduledTimestamp
        self.handlerTypeIdentifier = data.handlerTypeIdentifier
        self.handlerAddress = data.handlerAddress
    }
}

/// Lists all transactions for an account
/// This script is used by: flow schedule list <account>
access(all) fun main(account: Address): [TransactionInfo] {
    // Borrow the Manager
    let manager = FlowTransactionSchedulerUtils.borrowManager(at: account)
        ?? panic("Could not borrow Manager from account")
    
    let transactionIds = manager.getTransactionIDs()
    var transactions: [TransactionInfo] = []
    
    // Get transaction data through the Manager
    for id in transactionIds {
        if let txData = manager.getTransactionData(id) {
            transactions.append(TransactionInfo(data: txData))
        }
    }
    
    return transactions
}