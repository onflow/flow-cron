import "FlowCron"
import "FlowTransactionScheduler"

/// Returns information about a CronHandler's scheduled keeper transaction
access(all) fun main(address: Address, storagePath: StoragePath): {String: AnyStruct?} {
    let account = getAuthAccount<auth(BorrowValue) &Account>(address)

    let handler = account.storage.borrow<&FlowCron.CronHandler>(from: storagePath)
        ?? panic("CronHandler not found at path")

    let keeperID = handler.getNextScheduledKeeperID()

    var keeperTxData: FlowTransactionScheduler.TransactionData? = nil

    if let id = keeperID {
        keeperTxData = FlowTransactionScheduler.getTransactionData(id: id)
    }

    return {
        "cronExpression": handler.getCronExpression(),
        "nextScheduledKeeperID": keeperID,
        "keeperTxStatus": keeperTxData?.status?.rawValue,
        "keeperTxTimestamp": keeperTxData?.scheduledTimestamp
    }
}
