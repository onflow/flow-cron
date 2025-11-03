import "FlowTransactionScheduler"

access(all) fun main(txID: UInt64): {String: AnyStruct}? {
    if let txData = FlowTransactionScheduler.getTransactionData(id: txID) {
        return {
            "id": txData.id,
            "status": txData.status.rawValue,
            "scheduledTimestamp": txData.scheduledTimestamp
        }
    }
    return nil
}
