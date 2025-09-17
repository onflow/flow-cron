import "FlowTransactionScheduler"
import "FlowTransactionSchedulerUtils"

access(all) fun main(managerAddress: Address, transactionId: UInt64): FlowTransactionScheduler.Status? {
    let account = getAccount(managerAddress)
    
    let managerCap = account.capabilities.get<&FlowTransactionSchedulerUtils.Manager>(
        FlowTransactionSchedulerUtils.managerPublicPath
    )
    
    let manager = managerCap.borrow()
        ?? panic("Could not borrow Manager from account")
    
    return manager.getTransactionStatus(id: transactionId)
}