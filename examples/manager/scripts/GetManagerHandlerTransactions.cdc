import "FlowTransactionScheduler"
import "FlowTransactionSchedulerUtils"

access(all) fun main(managerAddress: Address, handlerTypeIdentifier: String): [FlowTransactionScheduler.TransactionData] {
    let account = getAccount(managerAddress)
    
    let managerCap = account.capabilities.get<&FlowTransactionSchedulerUtils.Manager>(
        FlowTransactionSchedulerUtils.managerPublicPath
    )
    
    let manager = managerCap.borrow()
        ?? panic("Could not borrow Manager from account")
    
    let transactionIds = manager.getTransactionIDsByHandler(handlerTypeIdentifier: handlerTypeIdentifier)
    var transactions: [FlowTransactionScheduler.TransactionData] = []
    
    for id in transactionIds {
        if let txData = FlowTransactionScheduler.getTransactionData(id: id) {
            transactions.append(txData)
        }
    }
    
    return transactions
}