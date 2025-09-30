import "FlowCron"
import "FlowTransactionSchedulerUtils"
import "FlowTransactionScheduler"
import "FlowToken"
import "FungibleToken"

/// Cancels all scheduled cron transactions for a CronHandler
/// Refunds unused fees back to the signer's FlowToken vault
transaction(cronHandlerStoragePath: StoragePath) {
    let manager: auth(FlowTransactionSchedulerUtils.Owner) &{FlowTransactionSchedulerUtils.Manager}
    let feeReceiver: &{FungibleToken.Receiver}
    let transactionIDs: [UInt64]

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

        // Get transaction IDs from CronHandler
        let cronHandler = signer.storage.borrow<&FlowCron.CronHandler>(from: cronHandlerStoragePath)
            ?? panic("CronHandler not found at specified path")

        self.transactionIDs = []
        if let nextID = cronHandler.nextScheduledTransactionID {
            self.transactionIDs.append(nextID)
        }
        if let futureID = cronHandler.futureScheduledTransactionID {
            self.transactionIDs.append(futureID)
        }
    }

    execute {
        var cancelledCount = 0

        for id in self.transactionIDs {
            if let txData = FlowTransactionScheduler.getTransactionData(id: id) {
                if txData.status == FlowTransactionScheduler.Status.Scheduled {
                    let refund <- self.manager.cancel(id: id)
                    self.feeReceiver.deposit(from: <-refund)
                    cancelledCount = cancelledCount + 1
                    log("Cancelled transaction: ".concat(id.toString()))
                }
            }
        }

        log("Cancelled ".concat(cancelledCount.toString()).concat(" of ").concat(self.transactionIDs.length.toString()).concat(" transactions"))
    }
}