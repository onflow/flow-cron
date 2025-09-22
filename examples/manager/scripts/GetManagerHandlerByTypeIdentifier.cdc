import "FlowTransactionScheduler"
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

access(all) fun main(managerAddress: Address, handlerTypeIdentifier: String, handlerUUID: UInt64?): HandlerData? {
    // Use the helper function to borrow the manager
    if let manager = FlowTransactionSchedulerUtils.borrowManager(at: managerAddress) {
        // Get the handler reference using borrowHandler with optional UUID
        if let handler = manager.borrowHandler(handlerTypeIdentifier: handlerTypeIdentifier, handlerUUID: handlerUUID) {
            // Get the actual UUID from the handler
            let actualUUID = handler.uuid
            
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
                handlerTypeIdentifier: handlerTypeIdentifier,
                handlerUUID: actualUUID
            )
            
            // Return HandlerData with all information
            return HandlerData(
                handlerTypeIdentifier: handlerTypeIdentifier,
                handlerUUID: actualUUID,
                transactionIDs: transactionIDs,
                resolvedViews: resolvedViews
            )
        }
    }
    
    return nil
}