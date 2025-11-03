import "CounterTransactionHandler"

/// Creates and stores a CounterTransactionHandler
transaction {
    prepare(acct: auth(SaveValue) &Account) {
        let handler <- CounterTransactionHandler.createHandler()
        acct.storage.save(<-handler, to: /storage/CounterHandler)
    }
}
