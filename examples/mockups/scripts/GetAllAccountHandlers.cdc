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

access(all) fun main(accountAddress: Address): [HandlerInfo] {
    let account = getAccount(accountAddress)
    let handlers: [HandlerInfo] = []
    
    // Try to get the Manager if it exists
    let managerCap = account.capabilities.get<&FlowTransactionSchedulerUtils.Manager>(
        FlowTransactionSchedulerUtils.managerPublicPath
    )
    
    if let manager = managerCap.borrow() {
        // Get all transaction IDs from the manager
        let transactionIDs = manager.getTransactionIDs()
        
        for id in transactionIDs {
            if let transactionData = manager.getTransactionData(id: id) {
                handlers.append(HandlerInfo(
                    id: id,
                    handlerAddress: transactionData.handlerAddress,
                    handlerType: transactionData.handlerTypeIdentifier
                ))
            }
        }
    }
    
    return handlers
}