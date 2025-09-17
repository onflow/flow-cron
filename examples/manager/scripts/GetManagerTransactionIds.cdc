import "FlowTransactionSchedulerUtils"

access(all) fun main(managerAddress: Address): [UInt64] {
    let account = getAccount(managerAddress)
    
    let managerCap = account.capabilities.get<&FlowTransactionSchedulerUtils.Manager>(
        FlowTransactionSchedulerUtils.managerPublicPath
    )
    
    let manager = managerCap.borrow()
        ?? panic("Could not borrow Manager from account")
    
    return manager.getTransactionIDs()
}