import "FlowTransactionScheduler"

access(all) struct HandlerInfo {
    access(all) let handlerTypeIdentifier: String
    access(all) let resolvedViews: {Type: AnyStruct}
    
    init(handlerTypeIdentifier: String, resolvedViews: {Type: AnyStruct}) {
        self.handlerTypeIdentifier = handlerTypeIdentifier
        self.resolvedViews = resolvedViews
    }
}

access(all) fun main(transactionId: UInt64): HandlerInfo? {
    // Get transaction data directly from FlowTransactionScheduler
    if let txData = FlowTransactionScheduler.getTransactionData(id: transactionId) {
        // Get the unentitled handler reference from the transaction data
        let handler = txData.getUnentitledHandlerReference()
        
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
        
        // Return HandlerInfo with all resolved views
        return HandlerInfo(
            handlerTypeIdentifier: txData.handlerTypeIdentifier,
            resolvedViews: resolvedViews
        )
    }
    
    return nil
}