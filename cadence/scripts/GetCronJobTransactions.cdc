import "FlowCron"
import "FlowTransactionScheduler"

access(all) fun main(handlerAddress: Address, jobId: UInt64): [FlowTransactionScheduler.TransactionData] {
    let account = getAccount(handlerAddress)
    
    let cronHandlerCap = account.capabilities.get<&FlowCron.CronHandler>(
        FlowCron.CronHandlerPublicPath
    )
    
    let cronHandler = cronHandlerCap.borrow()
        ?? panic("Could not borrow CronHandler from account")
    
    let transactionIds = cronHandler.getJobTransactionIds(jobId: jobId)
    var transactions: [FlowTransactionScheduler.TransactionData] = []
    
    for id in transactionIds {
        if let txData = FlowTransactionScheduler.getTransactionData(id: id) {
            transactions.append(txData)
        }
    }
    
    return transactions
}