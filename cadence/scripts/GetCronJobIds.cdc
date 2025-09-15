import "FlowCron"

access(all) fun main(handlerAddress: Address): [UInt64] {
    let account = getAccount(handlerAddress)
    
    let cronHandlerCap = account.capabilities.get<&FlowCron.CronHandler>(
        FlowCron.CronHandlerPublicPath
    )
    
    let cronHandler = cronHandlerCap.borrow()
        ?? panic("Could not borrow CronHandler from account")
    
    return cronHandler.getJobIds()
}