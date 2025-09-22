import "FlowTransactionSchedulerUtils"

access(all) fun main(managerAddress: Address, handlerTypeIdentifier: String, handlerUUID: UInt64?): [UInt64] {
    // Use the helper function to borrow the manager
    let manager = FlowTransactionSchedulerUtils.borrowManager(at: managerAddress)
        ?? panic("Could not borrow Manager from account")
    
    return manager.getTransactionIDsByHandler(handlerTypeIdentifier: handlerTypeIdentifier, handlerUUID: handlerUUID)
}