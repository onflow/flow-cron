import "FlowCron"
import "FlowTransactionSchedulerUtils"
import "FlowToken"
import "FungibleToken"

transaction(jobId: UInt64) {
    let cronHandler: auth(FlowCron.Owner) &FlowCron.CronHandler
    let schedulerManagerCap: Capability<auth(FlowTransactionSchedulerUtils.Owner) &FlowTransactionSchedulerUtils.Manager>
    let tokenReceiver: &{FungibleToken.Receiver}

    prepare(signer: auth(BorrowValue, IssueStorageCapabilityController) &Account) {
        // 1. Borrow the CronHandler
        self.cronHandler = signer.storage.borrow<auth(FlowCron.Owner) &FlowCron.CronHandler>(
            from: FlowCron.CronHandlerStoragePath
        ) ?? panic("Could not borrow CronHandler. Please ensure you have a CronHandler set up.")

        // 2. Issue private capability for scheduler manager (not published)
        let schedulerManagerPath = FlowTransactionSchedulerUtils.managerStoragePath
        assert(
            signer.storage.borrow<&FlowTransactionSchedulerUtils.Manager>(from: schedulerManagerPath) != nil,
            message: "TransactionSchedulerUtils.Manager not found. Please ensure you have a Manager set up."
        )
        self.schedulerManagerCap = signer.capabilities.storage.issue<auth(FlowTransactionSchedulerUtils.Owner) &FlowTransactionSchedulerUtils.Manager>(
            schedulerManagerPath
        )

        // 3. Get FlowToken receiver to deposit refunds
        self.tokenReceiver = signer.capabilities.get<&{FungibleToken.Receiver}>(/public/flowTokenReceiver)
            .borrow()
            ?? panic("Could not borrow FlowToken receiver")
    }

    execute {
        // Verify job exists before canceling
        assert(
            self.cronHandler.getJob(jobId: jobId) != nil,
            message: "Cron job with ID ".concat(jobId.toString()).concat(" does not exist")
        )
        
        // Cancel the job and receive refunded fees
        let refundVault <- self.cronHandler.cancelJob(
            jobId: jobId,
            schedulerManagerCap: self.schedulerManagerCap
        )
        // Deposit refunded fees back to the account
        self.tokenReceiver.deposit(from: <-refundVault)
    }
}