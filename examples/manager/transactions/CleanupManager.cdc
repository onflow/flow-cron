import "FlowTransactionSchedulerUtils"

transaction() {
    let manager: auth(FlowTransactionSchedulerUtils.Owner) &FlowTransactionSchedulerUtils.Manager

    prepare(signer: auth(BorrowValue) &Account) {
        // Borrow Manager reference
        self.manager = signer.storage.borrow<auth(FlowTransactionSchedulerUtils.Owner) &FlowTransactionSchedulerUtils.Manager>(
            from: FlowTransactionSchedulerUtils.managerStoragePath
        ) ?? panic("Could not borrow Manager. Please ensure you have a Manager set up.")
    }

    execute {
        // Perform cleanup
        let cleanedUpCount = self.manager.cleanup()
    }
}