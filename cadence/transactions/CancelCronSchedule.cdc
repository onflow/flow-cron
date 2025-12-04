import "FlowCron"
import "FlowTransactionSchedulerUtils"
import "FlowTransactionScheduler"
import "FlowToken"
import "FungibleToken"

/// Cancels both scheduled transactions (executor and keeper) for a CronHandler
/// This completely stops the cron job
transaction(cronHandlerStoragePath: StoragePath) {
    let manager: auth(FlowTransactionSchedulerUtils.Owner) &{FlowTransactionSchedulerUtils.Manager}
    let feeReceiver: &{FungibleToken.Receiver}
    let executorID: UInt64?
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

        // Get both transaction IDs from CronHandler
        let cronHandler = signer.storage.borrow<&FlowCron.CronHandler>(from: cronHandlerStoragePath)
            ?? panic("CronHandler not found at specified path")

        self.executorID = cronHandler.getNextScheduledExecutorID()
        self.keeperID = cronHandler.getNextScheduledKeeperID()
    }

    execute {
        var cancelledCount = 0

        // Cancel executor transaction
        if let id = self.executorID {
            if let txData = FlowTransactionScheduler.getTransactionData(id: id) {
                if txData.status == FlowTransactionScheduler.Status.Scheduled {
                    let refund <- self.manager.cancel(id: id)
                    self.feeReceiver.deposit(from: <-refund)
                    cancelledCount = cancelledCount + 1
                }
            }
        }

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

        log("Cancelled ".concat(cancelledCount.toString()).concat(" transaction(s)"))
    }
}
