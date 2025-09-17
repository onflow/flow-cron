import "FlowTransactionScheduler"
import "FlowTransactionSchedulerUtils"

access(all) struct HandlerInfo {
    access(all) let handlerTypeIdentifier: String
    access(all) let resolvedViews: {Type: AnyStruct}
    
    init(handlerTypeIdentifier: String, resolvedViews: {Type: AnyStruct}) {
        self.handlerTypeIdentifier = handlerTypeIdentifier
        self.resolvedViews = resolvedViews
    }
}

access(all) fun main(accountAddress: Address, handlerTypeIdentifier: String): HandlerInfo? {
    let account = getAccount(accountAddress)
    
    // Try to get the Manager if it exists
    let managerCap = account.capabilities.get<&FlowTransactionSchedulerUtils.Manager>(
        FlowTransactionSchedulerUtils.managerPublicPath
    )
    
    if let manager = managerCap.borrow() {
        // Get the handler reference using getHandlerByTypeIdentifier
        if let handler = manager.getHandlerByTypeIdentifier(handlerTypeIdentifier: handlerTypeIdentifier) {
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
                handlerTypeIdentifier: handlerTypeIdentifier,
                resolvedViews: resolvedViews
            )
        }
    }
    
    return nil
}