import "FlowCron"

transaction() {
    let cronHandler: auth(FlowCron.Owner) &FlowCron.CronHandler

    prepare(signer: auth(BorrowValue) &Account) {
        // Borrow the CronHandler
        self.cronHandler = signer.storage.borrow<auth(FlowCron.Owner) &FlowCron.CronHandler>(
            from: FlowCron.CronHandlerStoragePath
        ) ?? panic("Could not borrow CronHandler. Please ensure you have a CronHandler set up.")
    }

    execute {
        // Perform cleanup
        let cleanedUpCount = self.cronHandler.cleanup()
    }
}