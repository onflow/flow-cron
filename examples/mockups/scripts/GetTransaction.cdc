import "FlowTransactionScheduler"

access(all) fun main(transactionID: UInt64): FlowTransactionScheduler.TransactionData? {
    // Get the transaction data directly from the FlowTransactionScheduler contract
    return FlowTransactionScheduler.getTransactionData(id: transactionID)
}