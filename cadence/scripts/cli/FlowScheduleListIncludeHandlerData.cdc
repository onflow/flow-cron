import "FlowTransactionScheduler"
import "FlowTransactionSchedulerUtils"

/// Combined transaction info with handler data
access(all) struct TransactionInfoWithHandler {
    // Transaction fields
    access(all) let id: UInt64
    access(all) let priority: UInt8
    access(all) let executionEffort: UInt64
    access(all) let status: UInt8
    access(all) let fees: UFix64
    access(all) let scheduledTimestamp: UFix64
    access(all) let handlerTypeIdentifier: String
    access(all) let handlerAddress: Address
    
    // Handler fields
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
        
        // Initialize handler fields
        self.handlerUUID = handlerUUID
        self.handlerResolvedViews = resolvedViews
    }
}

/// Lists all transactions for an account with handler data
/// This script is used by: flow schedule list <account> --include-handler-data
access(all) fun main(account: Address): [TransactionInfoWithHandler] {
    // Borrow the Manager
    let manager = FlowTransactionSchedulerUtils.borrowManager(at: account)
        ?? panic("Could not borrow Manager from account")
    
    let transactionIds = manager.getTransactionIDs()
    var transactions: [TransactionInfoWithHandler] = []
    
    // Get transaction data with handler views
    for id in transactionIds {
        if let txData = manager.getTransactionData(id) {
            // Borrow handler to get its UUID
            let handler = txData.borrowHandler()
            
            // Get handler views through the manager
            let availableViews = manager.getHandlerViewsFromTransactionID(id)
            var resolvedViews: {Type: AnyStruct} = {}
            
            for viewType in availableViews {
                if let resolvedView = manager.resolveHandlerViewFromTransactionID(id, viewType: viewType) {
                    resolvedViews[viewType] = resolvedView
                }
            }
            
            transactions.append(TransactionInfoWithHandler(
                data: txData,
                handlerUUID: handler.uuid,
                resolvedViews: resolvedViews
            ))
        }
    }
    
    return transactions
}