import "FlowTransactionScheduler"
import "FlowTransactionSchedulerUtils"

access(all) struct HandlerInfo {
    access(all) let id: UInt64
    access(all) let handlerAddress: Address
    access(all) let handlerType: String
    
    init(id: UInt64, handlerAddress: Address, handlerType: String) {
        self.id = id
        self.handlerAddress = handlerAddress
        self.handlerType = handlerType
    }
}

access(all) fun main(managerAddress: Address, transactionId: UInt64): HandlerInfo? {
    let account = getAccount(managerAddress)
    
    // Get the Manager capability
    let managerCap = account.capabilities.get<&FlowTransactionSchedulerUtils.Manager>(
        FlowTransactionSchedulerUtils.managerPublicPath
    )
    
    // Borrow the Manager reference
    let manager = managerCap.borrow()
        ?? panic("Could not borrow Manager from account. Please ensure the account has a Manager set up.")
    
    // Get the transaction data for the specified handler ID
    if let transactionData = manager.getTransactionData(id: transactionId) {
        return HandlerInfo(
            id: transactionId,
            handlerAddress: transactionData.handlerAddress,
            handlerType: transactionData.handlerTypeIdentifier
        )
    }
    
    return nil
}