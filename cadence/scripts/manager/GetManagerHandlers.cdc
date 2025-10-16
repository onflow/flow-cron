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

access(all) fun main(managerAddress: Address): {String: {UInt64: HandlerData}} {
    let handlers: {String: {UInt64: HandlerData}} = {}
    
    // Use the helper function to borrow the manager
    if let manager = FlowTransactionSchedulerUtils.borrowManager(at: managerAddress) {
        // Get all handler type identifiers and their UUIDs
        let handlerTypesWithUUIDs = manager.getHandlerTypeIdentifiers()
        
        for handlerType in handlerTypesWithUUIDs.keys {
            let handlerUUIDs = handlerTypesWithUUIDs[handlerType]!
            let handlersForType: {UInt64: HandlerData} = {}
            
            // Process each handler UUID for this type
            for handlerUUID in handlerUUIDs {
                // Get the handler reference using borrowHandler
                if let handler = manager.borrowHandler(handlerTypeIdentifier: handlerType, handlerUUID: handlerUUID) {
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
                        handlerTypeIdentifier: handlerType,
                        handlerUUID: handlerUUID
                    )
                    
                    // Create HandlerData and add to the type's dictionary
                    handlersForType[handlerUUID] = HandlerData(
                        handlerTypeIdentifier: handlerType,
                        handlerUUID: handlerUUID,
                        transactionIDs: transactionIDs,
                        resolvedViews: resolvedViews
                    )
                }
            }
            
            // Only add to main dictionary if we have handlers for this type
            if handlersForType.length > 0 {
                handlers[handlerType] = handlersForType
            }
        }
    }
    
    return handlers
}