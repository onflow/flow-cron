import "FlowCron"

/// Gets the current scheduling status of a CronHandler
access(all) fun main(
    handlerAddress: Address,
    handlerStoragePath: StoragePath
): {String: AnyStruct} {
    let account = getAuthAccount<auth(BorrowValue) &Account>(handlerAddress)

    if let cronHandler = account.storage.borrow<&FlowCron.CronHandler>(from: handlerStoragePath) {
        return {
            "cronExpression": cronHandler.cronExpression,
            "nextScheduledTransactionID": cronHandler.nextScheduledTransactionID,
            "futureScheduledTransactionID": cronHandler.futureScheduledTransactionID,
            "hasNextScheduled": cronHandler.nextScheduledTransactionID != nil,
            "hasFutureScheduled": cronHandler.futureScheduledTransactionID != nil,
            "isFullyScheduled": cronHandler.nextScheduledTransactionID != nil && cronHandler.futureScheduledTransactionID != nil
        }
    }

    return {}
}