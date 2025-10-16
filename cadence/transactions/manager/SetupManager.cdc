import "FlowTransactionSchedulerUtils"

transaction() {
    prepare(signer: auth(BorrowValue, IssueStorageCapabilityController, SaveValue, PublishCapability) &Account) {
        // Save a manager resource to storage if not already present
        if signer.storage.borrow<&AnyResource>(from: FlowTransactionSchedulerUtils.managerStoragePath) == nil {
            let manager <- FlowTransactionSchedulerUtils.createManager()
            signer.storage.save(<-manager, to: FlowTransactionSchedulerUtils.managerStoragePath)
        }

        // Check if capability is already published
        let existingCap = signer.capabilities.get<&{FlowTransactionSchedulerUtils.Manager}>(
            FlowTransactionSchedulerUtils.managerPublicPath
        )
        // Only issue and publish if not already published or invalid
        if !existingCap.check() {
            // Create a new capability for the Manager
            let managerCap = signer.capabilities.storage.issue<&{FlowTransactionSchedulerUtils.Manager}>(
                FlowTransactionSchedulerUtils.managerStoragePath
            )
            signer.capabilities.publish(managerCap, at: FlowTransactionSchedulerUtils.managerPublicPath)
        }
    }
}