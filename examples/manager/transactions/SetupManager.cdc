import "FlowTransactionSchedulerUtils"

transaction() {
    prepare(signer: auth(BorrowValue, SaveValue) &Account) {
        // Check if Manager already exists
        if signer.storage.borrow<&{FlowTransactionSchedulerUtils.Manager}>(from: FlowTransactionSchedulerUtils.managerStoragePath) == nil {
            // Create and save Manager
            signer.storage.save(
                <-FlowTransactionSchedulerUtils.createManager(),
                to: FlowTransactionSchedulerUtils.managerStoragePath
            )
        }
    }
}