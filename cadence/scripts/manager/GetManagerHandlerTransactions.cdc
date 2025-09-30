import "FlowTransactionScheduler"
import "FlowTransactionSchedulerUtils"

access(all) fun main(managerAddress: Address, handlerTypeIdentifier: String, handlerUUID: UInt64?): [FlowTransactionScheduler.TransactionData] {
    // Use the helper function to borrow the manager
    let manager = FlowTransactionSchedulerUtils.borrowManager(at: managerAddress)
        ?? panic("Could not borrow Manager from account")
    
    let transactionIds = manager.getTransactionIDsByHandler(handlerTypeIdentifier: handlerTypeIdentifier, handlerUUID: handlerUUID)
    var transactions: [FlowTransactionScheduler.TransactionData] = []
    
    for id in transactionIds {
        // Use manager's getTransactionData method instead of direct access
        if let txData = manager.getTransactionData(id) {
            transactions.append(txData)
        }
    }
    
    return transactions
}