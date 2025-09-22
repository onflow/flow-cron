import "FlowTransactionScheduler"
import "FlowTransactionSchedulerUtils"

access(all) fun main(managerAddress: Address, transactionId: UInt64): FlowTransactionScheduler.Status? {
    // Use the helper function to borrow the manager
    let manager = FlowTransactionSchedulerUtils.borrowManager(at: managerAddress)
        ?? panic("Could not borrow Manager from account")
    
    return manager.getTransactionStatus(id: transactionId)
}