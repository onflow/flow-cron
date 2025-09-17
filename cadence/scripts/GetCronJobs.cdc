import "FlowCron"

access(all) struct JobInfo {
    access(all) let jobId: UInt64
    access(all) let resolvedViews: {Type: AnyStruct}
    
    init(jobId: UInt64, resolvedViews: {Type: AnyStruct}) {
        self.jobId = jobId
        self.resolvedViews = resolvedViews
    }
}

access(all) fun main(accountAddress: Address): [JobInfo] {
    let account = getAccount(accountAddress)
    let jobs: [JobInfo] = []
    
    // Try to get the CronHandler if it exists
    let cronHandlerCap = account.capabilities.get<&FlowCron.CronHandler>(
        FlowCron.CronHandlerPublicPath
    )
    
    if let cronHandler = cronHandlerCap.borrow() {
        let jobIds = cronHandler.getJobIds()
        
        for jobId in jobIds {
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
                
                // Add JobInfo with all resolved views
                jobs.append(JobInfo(
                    jobId: jobId,
                    resolvedViews: resolvedViews
                ))
            }
        }
    }
    
    return jobs
}