import "FlowTransactionScheduler"
import "FlowTransactionSchedulerUtils"

access(all) fun main(managerAddress: Address): [FlowTransactionScheduler.TransactionData] {
    // Use the helper function to borrow the Manager
    let manager = FlowTransactionSchedulerUtils.borrowManager(at: managerAddress)
        ?? panic("Could not borrow Manager from account")
    
    let transactionIds = manager.getTransactionIDs()
    var transactions: [FlowTransactionScheduler.TransactionData] = []
    
    // Get transaction data through the Manager instead of directly from FlowTransactionScheduler
    for id in transactionIds {
        if let txData = manager.getTransactionData(id) {
            transactions.append(txData)
        }
    }
    
    return transactions
}