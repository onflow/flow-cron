import "FlowTransactionSchedulerUtils"

access(all) struct HandlerData {
    access(all) let handlerTypeIdentifier: String
    access(all) let handlerUUID: UInt64
    access(all) let transactionIDs: [UInt64]
    access(all) let resolvedViews: {Type: AnyStruct}

    init(
        handlerTypeIdentifier: String, 
        handlerUUID: UInt64, 
        transactionIDs: [UInt64],
        resolvedViews: {Type: AnyStruct}
    ) {
        self.handlerTypeIdentifier = handlerTypeIdentifier
        self.handlerUUID = handlerUUID
        self.transactionIDs = transactionIDs
        self.resolvedViews = resolvedViews
    }
}

access(all) fun main(managerAddress: Address, transactionId: UInt64): HandlerData? {
    // Borrow the Manager from the provided address
    let manager = FlowTransactionSchedulerUtils.borrowManager(at: managerAddress)
        ?? panic("Could not borrow Manager at address")
    
    // Get transaction data through the Manager
    if let txData = manager.getTransactionData(transactionId) {
        // Borrow the handler directly from transaction data
        let handler = txData.borrowHandler()
        
        // Get all available views from the handler
        let availableViews = handler.getViews()
        
        // Resolve all available views
        var resolvedViews: {Type: AnyStruct} = {}
        
        for viewType in availableViews {
            if let resolvedView = handler.resolveView(viewType) {
                // Store the resolved view with its type as key
                resolvedViews[viewType] = resolvedView
            }
        }
        
        // Get all transaction IDs for this handler
        let transactionIDs = manager.getTransactionIDsByHandler(
            handlerTypeIdentifier: txData.handlerTypeIdentifier,
            handlerUUID: handler.uuid
        )
        
        // Return HandlerData with all information
        return HandlerData(
            handlerTypeIdentifier: txData.handlerTypeIdentifier,
            handlerUUID: handler.uuid,
            transactionIDs: transactionIDs,
            resolvedViews: resolvedViews
        )
    }
    
    return nil
}