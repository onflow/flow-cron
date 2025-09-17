import "FlowCron"

access(all) struct JobInfo {
    access(all) let jobId: UInt64
    access(all) let resolvedViews: {Type: AnyStruct}
    
    init(jobId: UInt64, resolvedViews: {Type: AnyStruct}) {
        self.jobId = jobId
        self.resolvedViews = resolvedViews
    }
}

access(all) fun main(accountAddress: Address, jobId: UInt64): JobInfo? {
    let account = getAccount(accountAddress)
    
    // Try to get the CronHandler if it exists
    let cronHandlerCap = account.capabilities.get<&FlowCron.CronHandler>(
        FlowCron.CronHandlerPublicPath
    )
    
    if let cronHandler = cronHandlerCap.borrow() {
        // Get the job reference
        if let jobRef = cronHandler.getJob(jobId: jobId) {
            // Get all available views from the job
            let availableViews = jobRef.getViews()
            
            // Resolve all available views
            var resolvedViews: {Type: AnyStruct} = {}
            
            for viewType in availableViews {
                if let resolvedView = jobRef.resolveView(viewType) {
                    // Store the resolved view with its type as key
                    resolvedViews[viewType] = resolvedView
                }
            }
            
            // Return JobInfo with all resolved views
            return JobInfo(
                jobId: jobId,
                resolvedViews: resolvedViews
            )
        }
    }
    
    return nil
}