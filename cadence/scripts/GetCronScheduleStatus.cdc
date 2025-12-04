import "FlowCron"
import "FlowTransactionScheduler"

/// Returns information about a CronHandler's scheduled transactions (both executor and keeper)
access(all) fun main(address: Address, storagePath: StoragePath): {String: AnyStruct?} {
    let account = getAuthAccount<auth(BorrowValue) &Account>(address)

    let handler = account.storage.borrow<&FlowCron.CronHandler>(from: storagePath)
        ?? panic("CronHandler not found at path")

    let executorID = handler.getNextScheduledExecutorID()
    let keeperID = handler.getNextScheduledKeeperID()

    var executorTxData: FlowTransactionScheduler.TransactionData? = nil
    var keeperTxData: FlowTransactionScheduler.TransactionData? = nil

    if let id = executorID {
        executorTxData = FlowTransactionScheduler.getTransactionData(id: id)
    }
    if let id = keeperID {
        keeperTxData = FlowTransactionScheduler.getTransactionData(id: id)
    }

    return {
        "cronExpression": handler.getCronExpression(),
        "nextScheduledExecutorID": executorID,
        "nextScheduledKeeperID": keeperID,
        "executorTxStatus": executorTxData?.status?.rawValue,
        "executorTxTimestamp": executorTxData?.scheduledTimestamp,
        "keeperTxStatus": keeperTxData?.status?.rawValue,
        "keeperTxTimestamp": keeperTxData?.scheduledTimestamp
    }
}
