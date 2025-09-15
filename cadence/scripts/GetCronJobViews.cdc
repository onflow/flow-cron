import "FlowCron"

access(all) fun main(handlerAddress: Address, jobId: UInt64): [Type] {
    let account = getAccount(handlerAddress)
    
    let cronHandlerCap = account.capabilities.get<&FlowCron.CronHandler>(
        FlowCron.CronHandlerPublicPath
    )
    
    let cronHandler = cronHandlerCap.borrow()
        ?? panic("Could not borrow CronHandler from account")
    
    let job = cronHandler.getJob(jobId: jobId)
    if job == nil {
        return []
    }
    
    return job!.getViews()
}