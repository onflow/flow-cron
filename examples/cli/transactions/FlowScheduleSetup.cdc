import "FlowTransactionSchedulerUtils"

/// Sets up a Manager resource in the signer's account if not already done
/// This transaction is used by: flow schedule setup [--signer account]
transaction {
    prepare(signer: auth(BorrowValue, SaveValue, IssueStorageCapabilityController) &Account) {
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