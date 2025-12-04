import "FlowCron"
import "FlowTransactionSchedulerUtils"
import "FlowTransactionScheduler"
import "FlowToken"
import "FungibleToken"

/// Cancels the scheduled keeper transaction for a CronHandler
/// Note: This only cancels the keeper. Any pending executor will still run once.
transaction(cronHandlerStoragePath: StoragePath) {
    let manager: auth(FlowTransactionSchedulerUtils.Owner) &{FlowTransactionSchedulerUtils.Manager}
    let feeReceiver: &{FungibleToken.Receiver}
    let keeperID: UInt64?

    prepare(signer: auth(BorrowValue, IssueStorageCapabilityController, SaveValue) &Account) {
        // Ensure Manager exists
        if signer.storage.borrow<&{FlowTransactionSchedulerUtils.Manager}>(from: FlowTransactionSchedulerUtils.managerStoragePath) == nil {
            signer.storage.save(<-FlowTransactionSchedulerUtils.createManager(), to: FlowTransactionSchedulerUtils.managerStoragePath)
        }

        // Borrow manager
        self.manager = signer.storage.borrow<auth(FlowTransactionSchedulerUtils.Owner) &{FlowTransactionSchedulerUtils.Manager}>(
            from: FlowTransactionSchedulerUtils.managerStoragePath
        ) ?? panic("Cannot borrow manager")

        // Borrow fee receiver for refunds
        self.feeReceiver = signer.storage.borrow<&{FungibleToken.Receiver}>(from: /storage/flowTokenVault)
            ?? panic("Could not borrow FlowToken receiver")

        // Get keeper transaction ID from CronHandler
        let cronHandler = signer.storage.borrow<&FlowCron.CronHandler>(from: cronHandlerStoragePath)
            ?? panic("CronHandler not found at specified path")

        self.keeperID = cronHandler.getNextScheduledKeeperID()
    }

    execute {
        var cancelledCount = 0

        // Cancel keeper transaction
        if let id = self.keeperID {
            if let txData = FlowTransactionScheduler.getTransactionData(id: id) {
                if txData.status == FlowTransactionScheduler.Status.Scheduled {
                    let refund <- self.manager.cancel(id: id)
                    self.feeReceiver.deposit(from: <-refund)
                    cancelledCount = cancelledCount + 1
                }
            }
        }

        log("Cancelled ".concat(cancelledCount.toString()).concat(" keeper transaction(s)"))
        log("Note: Any pending executor transaction will still run once")
    }
}
