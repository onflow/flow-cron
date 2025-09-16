import "FlowTransactionScheduler"
import "FlowTransactionSchedulerUtils"

/// Get all transactions that scheduled a handler -> get all transactions and filter by handler address and type
/// Returns a dictionary of transaction IDs mapped to their transaction data for a specific handler
access(all) fun main(
    managerAddress: Address, 
    handlerAddress: Address, 
    handlerTypeIdentifier: String?
): {UInt64: FlowTransactionScheduler.TransactionData} {
    let account = getAccount(managerAddress)
    
    // Get the Manager capability
    let managerCap = account.capabilities.get<&FlowTransactionSchedulerUtils.Manager>(
        FlowTransactionSchedulerUtils.managerPublicPath
    )
    
    // Borrow the Manager reference
    let manager = managerCap.borrow()
        ?? panic("Could not borrow Manager from account. Please ensure the account has a Manager set up.")
    
    // Get all transaction IDs from the manager
    let allTransactionIDs = manager.getTransactionIDs()
    
    // Filter transactions by handler address and optionally by type
    let filteredTransactions: {UInt64: FlowTransactionScheduler.TransactionData} = {}
    
    for transactionID in allTransactionIDs {
        if let transactionData = manager.getTransactionData(id: transactionID) {
            // Filter by handler address
            if transactionData.handlerAddress == handlerAddress {
                // If handlerTypeIdentifier is provided, filter by that too
                if handlerTypeIdentifier == nil || transactionData.handlerTypeIdentifier == handlerTypeIdentifier {
                    filteredTransactions[transactionID] = transactionData
                }
            }
        }
    }
    
    return filteredTransactions
}