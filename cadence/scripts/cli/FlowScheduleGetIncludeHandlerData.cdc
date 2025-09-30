import "FlowTransactionScheduler"

access(all) struct TransactionInfoWithHandler {
    access(all) let id: UInt64
    access(all) let priority: UInt8
    access(all) let executionEffort: UInt64
    access(all) let status: UInt8
    access(all) let fees: UFix64
    access(all) let scheduledTimestamp: UFix64
    access(all) let handlerTypeIdentifier: String
    access(all) let handlerAddress: Address
    
    access(all) let handlerUUID: UInt64
    access(all) let handlerResolvedViews: {Type: AnyStruct}
    
    init(data: FlowTransactionScheduler.TransactionData, handlerUUID: UInt64, resolvedViews: {Type: AnyStruct}) {
        // Initialize transaction fields
        self.id = data.id
        self.priority = data.priority.rawValue
        self.executionEffort = data.executionEffort
        self.status = data.status.rawValue
        self.fees = data.fees
        self.scheduledTimestamp = data.scheduledTimestamp
        self.handlerTypeIdentifier = data.handlerTypeIdentifier
        self.handlerAddress = data.handlerAddress
        
        self.handlerUUID = handlerUUID
        self.handlerResolvedViews = resolvedViews
    }
}

/// Gets a transaction by ID with handler data (checks globally, not manager-specific)
/// This script is used by: flow schedule get <transaction-id> --include-handler-data
access(all) fun main(transactionId: UInt64): TransactionInfoWithHandler? {
    // Get transaction data directly from FlowTransactionScheduler
    if let txData = FlowTransactionScheduler.getTransactionData(id: transactionId) {
        // Borrow handler and resolve views
        let handler = txData.borrowHandler()
        let availableViews = handler.getViews()
        var resolvedViews: {Type: AnyStruct} = {}
        
        for viewType in availableViews {
            if let resolvedView = handler.resolveView(viewType) {
                resolvedViews[viewType] = resolvedView
            }
        }
        
        return TransactionInfoWithHandler(
            data: txData,
            handlerUUID: handler.uuid,
            resolvedViews: resolvedViews
        )
    }
    
    return nil
}