import "FlowCron"
import "ViewResolver"

/// Gets CronInfo metadata from a CronHandler
access(all) fun main(
    handlerAddress: Address,
    handlerStoragePath: StoragePath
): FlowCron.CronInfo? {
    let account = getAuthAccount<auth(BorrowValue) &Account>(handlerAddress)

    if let handler = account.storage.borrow<&FlowCron.CronHandler>(from: handlerStoragePath) {
        return handler.resolveView(Type<FlowCron.CronInfo>()) as? FlowCron.CronInfo
    }

    return nil
}