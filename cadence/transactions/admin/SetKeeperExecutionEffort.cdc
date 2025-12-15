import "FlowCron"

/// Updates the keeper execution effort configuration
/// Can only be executed by the account holding the Admin resource (contract deployer)
transaction(newEffort: UInt64) {
    let admin: auth(FlowCron.Owner) &FlowCron.Admin

    prepare(signer: auth(BorrowValue) &Account) {
        self.admin = signer.storage.borrow<auth(FlowCron.Owner) &FlowCron.Admin>(
            from: FlowCron.adminStoragePath
        ) ?? panic("Admin resource not found. Only contract deployer can update config.")
    }

    execute {
        self.admin.setKeeperExecutionEffort(newEffort)
    }
}
