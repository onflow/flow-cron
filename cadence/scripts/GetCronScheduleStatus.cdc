import "FlowCron"
import "FlowTransactionScheduler"

/// Returns detailed information about a CronHandler's scheduled transactions
access(all) fun main(address: Address, storagePath: StoragePath): {String: AnyStruct?} {
    let account = getAuthAccount<auth(BorrowValue) &Account>(address)

    let handler = account.storage.borrow<&FlowCron.CronHandler>(from: storagePath)
        ?? panic("CronHandler not found at path")

    let nextID = handler.getNextScheduledTransactionID()
    let futureID = handler.getFutureScheduledTransactionID()

    var nextTxData: FlowTransactionScheduler.TransactionData? = nil
    var futureTxData: FlowTransactionScheduler.TransactionData? = nil

    if let id = nextID {
        nextTxData = FlowTransactionScheduler.getTransactionData(id: id)
    }

    if let id = futureID {
        futureTxData = FlowTransactionScheduler.getTransactionData(id: id)
    }

    return {
        "nextTransactionID": nextID,
        "futureTransactionID": futureID,
        "nextTxStatus": nextTxData?.status?.rawValue,
        "nextTxTimestamp": nextTxData?.scheduledTimestamp,
        "futureTxStatus": futureTxData?.status?.rawValue,
        "futureTxTimestamp": futureTxData?.scheduledTimestamp
    }
}
