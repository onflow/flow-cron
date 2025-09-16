import "FlowTransactionScheduler"
import "FlowTransactionSchedulerUtils"

/// Get upcoming schedules -> get list of scheduled transactions with status "Scheduled"
/// Returns an array of upcoming scheduled transactions from a manager's account
access(all) fun main(managerAddress: Address): [{UInt64: FlowTransactionScheduler.TransactionData}] {
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
    
    // Filter for transactions with "Scheduled" status
    let upcomingSchedules: [{UInt64: FlowTransactionScheduler.TransactionData}] = []
    
    for transactionID in allTransactionIDs {
        if let transactionData = manager.getTransactionData(id: transactionID) {
            // Check if the transaction status is Scheduled
            if transactionData.status == FlowTransactionScheduler.Status.Scheduled {
                let transactionInfo: {UInt64: FlowTransactionScheduler.TransactionData} = {}
                transactionInfo[transactionID] = transactionData
                upcomingSchedules.append(transactionInfo)
            }
        }
    }
    
    return upcomingSchedules
}