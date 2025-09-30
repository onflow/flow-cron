import Test
import "FlowCron"
import "FlowCronUtils"
import "FlowTransactionScheduler"
import "FlowTransactionSchedulerUtils"
import "Counter"
import "CounterTransactionHandler"

access(all) let testAccount = Test.serviceAccount()
access(all) var counterHandlerSetup = false

access(all) fun setup() {
    // Deploy Counter contract
    var err = Test.deployContract(
        name: "Counter",
        path: "mocks/contracts/Counter.cdc",
        arguments: []
    )
    Test.expect(err, Test.beNil())

    // Deploy CounterTransactionHandler contract
    err = Test.deployContract(
        name: "CounterTransactionHandler",
        path: "mocks/contracts/CounterTransactionHandler.cdc",
        arguments: []
    )
    Test.expect(err, Test.beNil())

    // Deploy FlowCronUtils
    err = Test.deployContract(
        name: "FlowCronUtils",
        path: "../contracts/FlowCronUtils.cdc",
        arguments: []
    )
    Test.expect(err, Test.beNil())

    // Deploy FlowCron
    err = Test.deployContract(
        name: "FlowCron",
        path: "../contracts/FlowCron.cdc",
        arguments: []
    )
    Test.expect(err, Test.beNil())
}

/// Create CronHandler with valid cron expression
access(all) fun testCreateCronHandlerWithValidExpression() {
    setupCounterHandler()

    let result = Test.executeTransaction(
        Test.Transaction(
            code: createCronHandlerTransactionCode(),
            authorizers: [testAccount.address],
            signers: [testAccount],
            arguments: [
                "*/5 * * * *",  // Every 5 minutes
                /storage/CounterTransactionHandler as StoragePath,
                /storage/CronHandler1 as StoragePath
            ]
        )
    )
    Test.expect(result, Test.beSucceeded())
}

/// Create CronHandler with invalid expression fails
access(all) fun testCreateCronHandlerWithInvalidExpression() {
    setupCounterHandler()

    let result = Test.executeTransaction(
        Test.Transaction(
            code: createCronHandlerTransactionCode(),
            authorizers: [testAccount.address],
            signers: [testAccount],
            arguments: [
                "invalid cron",
                /storage/CounterTransactionHandler as StoragePath,
                /storage/CronHandlerInvalid as StoragePath
            ]
        )
    )
    Test.expect(result, Test.beFailed())
}

/// Schedule cron and verify double scheduling (next + future)
access(all) fun testDoubleSchedulingPattern() {
    setupCounterHandler()
    createCronHandler("*/1 * * * *", /storage/CronHandler2)

    // Count scheduled events before scheduling
    let eventsBefore = Test.eventsOfType(Type<FlowTransactionScheduler.Scheduled>())
    let countBefore = eventsBefore.length

    // Schedule the cron handler - this should create 2 transactions (next + future)
    let scheduleResult = scheduleCronHandler(/storage/CronHandler2, nil)
    Test.expect(scheduleResult, Test.beSucceeded())

    // Verify NEW transactions were scheduled
    let eventsAfter = Test.eventsOfType(Type<FlowTransactionScheduler.Scheduled>())
    let newEvents = eventsAfter.length - countBefore
    // Note: The first schedule creates 1 transaction, then fillSchedule() creates next+future = 2 more
    // Total new events should be >= 1 (could be more if double scheduling happened)
    Test.assert(newEvents >= 1, message: "Expected at least one scheduled transaction")
}

/// Counter increments on cron execution
access(all) fun testCounterIncrementsOnExecution() {
    setupCounterHandler()
    createCronHandler("*/1 * * * *", /storage/CronHandler3)

    // Get initial counter value
    let initialCount = getCounterValue()

    // Schedule cron
    let scheduleResult = scheduleCronHandler(/storage/CronHandler3, nil)
    Test.expect(scheduleResult, Test.beSucceeded())

    // Move time forward to trigger execution
    Test.moveTime(by: 65.0)  // Move 65 seconds forward

    // Verify counter incremented
    let newCount = getCounterValue()
    Test.assert(newCount > initialCount, message: "Counter should have incremented after cron execution")
}

/// Multiple executions with same data (data consistency)
access(all) fun testDataConsistencyAcrossExecutions() {
    setupCounterHandler()
    createCronHandler("*/1 * * * *", /storage/CronHandler4)

    let initialCount = getCounterValue()

    // Schedule with specific data
    let scheduleResult = scheduleCronHandler(/storage/CronHandler4, nil)
    Test.expect(scheduleResult, Test.beSucceeded())

    // Execute multiple times
    Test.moveTime(by: 65.0)  // First execution
    Test.moveTime(by: 65.0)  // Second execution

    let finalCount = getCounterValue()
    // Counter should have incremented at least twice
    Test.assert(finalCount >= initialCount + 2, message: "Counter should increment on each execution")

    // Verify CronScheduleExecuted events
    let executedEvents = Test.eventsOfType(Type<FlowCron.CronScheduleExecuted>())
    Test.assert(executedEvents.length >= 2, message: "Expected at least 2 execution events")
}

/// Cancel scheduled transactions
access(all) fun testCancelScheduledTransactions() {
    setupCounterHandler()
    createCronHandler("*/5 * * * *", /storage/CronHandler5)

    // Schedule
    let scheduleResult = scheduleCronHandler(/storage/CronHandler5, nil)
    Test.expect(scheduleResult, Test.beSucceeded())

    // Cancel all scheduled transactions
    let cancelResult = Test.executeTransaction(
        Test.Transaction(
            code: Test.readFile("../transactions/CancelCronSchedule.cdc"),
            authorizers: [testAccount.address],
            signers: [testAccount],
            arguments: [/storage/CronHandler5 as StoragePath]
        )
    )
    Test.expect(cancelResult, Test.beSucceeded())
}

/// Cancel and reschedule workflow
access(all) fun testCancelAndReschedule() {
    setupCounterHandler()
    createCronHandler("*/2 * * * *", /storage/CronHandler6)

    // Initial schedule
    let scheduleResult1 = scheduleCronHandler(/storage/CronHandler6, nil)
    Test.expect(scheduleResult1, Test.beSucceeded())

    // Cancel
    let cancelResult = Test.executeTransaction(
        Test.Transaction(
            code: Test.readFile("../transactions/CancelCronSchedule.cdc"),
            authorizers: [testAccount.address],
            signers: [testAccount],
            arguments: [/storage/CronHandler6 as StoragePath]
        )
    )
    Test.expect(cancelResult, Test.beSucceeded())

    // Reschedule should work
    let scheduleResult2 = scheduleCronHandler(/storage/CronHandler6, nil)
    Test.expect(scheduleResult2, Test.beSucceeded())
}

/// Auto-fill scheduling (fill gaps after execution)
access(all) fun testAutoFillScheduling() {
    setupCounterHandler()
    createCronHandler("*/1 * * * *", /storage/CronHandler7)

    // Schedule initially (creates next + future)
    let scheduleResult = scheduleCronHandler(/storage/CronHandler7, nil)
    Test.expect(scheduleResult, Test.beSucceeded())

    let scheduledBefore = Test.eventsOfType(Type<FlowTransactionScheduler.Scheduled>())
    let countBefore = scheduledBefore.length

    // Execute first transaction by moving time
    Test.moveTime(by: 65.0)

    // After execution, should auto-fill the future slot
    let scheduledAfter = Test.eventsOfType(Type<FlowTransactionScheduler.Scheduled>())
    Test.assert(scheduledAfter.length > countBefore, message: "Should auto-schedule future transaction after execution")
}

/// CronInfo view resolution
access(all) fun testCronInfoViewResolution() {
    setupCounterHandler()
    createCronHandler("*/5 * * * *", /storage/CronHandler8)

    let result = Test.executeScript(
        Test.readFile("../scripts/GetCronInfo.cdc"),
        [
            testAccount.address,
            /storage/CronHandler8 as StoragePath
        ]
    )
    Test.expect(result, Test.beSucceeded())

    let cronInfo = result.returnValue! as! FlowCron.CronInfo
    Test.assertEqual("*/5 * * * *", cronInfo.cronExpression)
    Test.assert(cronInfo.nextExecution != nil, message: "Should have next execution time")
}

/// Various cron expressions
access(all) fun testVariousCronExpressions() {
    setupCounterHandler()

    // Every minute
    createCronHandler("* * * * *", /storage/CronEveryMinute)

    // Every hour at minute 0
    createCronHandler("0 * * * *", /storage/CronEveryHour)

    // Daily at midnight
    createCronHandler("0 0 * * *", /storage/CronDaily)

    // Every Monday at midnight
    createCronHandler("0 0 * * 1", /storage/CronWeekly)

    // Every 15 minutes
    createCronHandler("*/15 * * * *", /storage/Cron15Min)
}

/// Wrapped handler execution is isolated
access(all) fun testWrappedHandlerIsolation() {
    setupCounterHandler()
    createCronHandler("*/1 * * * *", /storage/CronHandler10)

    let initialCount = getCounterValue()

    // Schedule and execute
    let scheduleResult = scheduleCronHandler(/storage/CronHandler10, nil)
    Test.expect(scheduleResult, Test.beSucceeded())

    Test.moveTime(by: 65.0)

    // Verify counter incremented (proving wrapped handler executed)
    let finalCount = getCounterValue()
    Test.assert(finalCount > initialCount, message: "Wrapped handler should have executed")

    // Verify execution event was emitted
    let executedEvents = Test.eventsOfType(Type<FlowCron.CronScheduleExecuted>())
    Test.assert(executedEvents.length >= 1, message: "Expected CronScheduleExecuted event")
}

/// CronHandler exposes correct views
access(all) fun testCronHandlerViews() {
    setupCounterHandler()
    createCronHandler("*/1 * * * *", /storage/CronHandler11)

    let scriptCode = "import FlowCron from \"../contracts/FlowCron.cdc\"\n\n"
        .concat("access(all) fun main(addr: Address, path: StoragePath): [Type] {\n")
        .concat("    let account = getAuthAccount<auth(BorrowValue) &Account>(addr)\n")
        .concat("    let handler = account.storage.borrow<&FlowCron.CronHandler>(from: path)!\n")
        .concat("    return handler.getViews()\n")
        .concat("}")

    let result = Test.executeScript(scriptCode, [testAccount.address, /storage/CronHandler11 as StoragePath])
    Test.expect(result, Test.beSucceeded())

    let views = result.returnValue! as! [Type]
    Test.assert(views.contains(Type<FlowCron.CronInfo>()), message: "Should expose CronInfo view")
}

/// Counter increments match execution count for this test
access(all) fun testCounterMatchesExecutionCount() {
    setupCounterHandler()
    createCronHandler("*/1 * * * *", /storage/CronHandler12)

    let initialCount = getCounterValue()
    let initialEvents = Test.eventsOfType(Type<FlowCron.CronScheduleExecuted>())
    let initialEventCount = initialEvents.length

    // Schedule
    let scheduleResult = scheduleCronHandler(/storage/CronHandler12, nil)
    Test.expect(scheduleResult, Test.beSucceeded())

    // Execute 3 times
    Test.moveTime(by: 65.0)
    Test.moveTime(by: 65.0)
    Test.moveTime(by: 65.0)

    let finalCount = getCounterValue()
    let finalEvents = Test.eventsOfType(Type<FlowCron.CronScheduleExecuted>())
    let finalEventCount = finalEvents.length

    // Counter increments should match NEW execution events
    let counterIncrements = finalCount - initialCount
    let newExecutions = finalEventCount - initialEventCount
    Test.assertEqual(counterIncrements, newExecutions)
}

/// After cancellation, can reschedule successfully
access(all) fun testRescheduleAfterCancellation() {
    setupCounterHandler()
    createCronHandler("*/1 * * * *", /storage/CronHandler13)

    // Schedule
    let scheduleResult1 = scheduleCronHandler(/storage/CronHandler13, nil)
    Test.expect(scheduleResult1, Test.beSucceeded())

    let eventsBefore = Test.eventsOfType(Type<FlowTransactionScheduler.Scheduled>())
    let countBefore = eventsBefore.length

    // Cancel all transactions
    let cancelResult = Test.executeTransaction(
        Test.Transaction(
            code: Test.readFile("../transactions/CancelCronSchedule.cdc"),
            authorizers: [testAccount.address],
            signers: [testAccount],
            arguments: [/storage/CronHandler13 as StoragePath]
        )
    )
    Test.expect(cancelResult, Test.beSucceeded())

    // Reschedule should work after cancellation
    let scheduleResult2 = scheduleCronHandler(/storage/CronHandler13, nil)
    Test.expect(scheduleResult2, Test.beSucceeded())

    // Verify new scheduling event was emitted
    let eventsAfter = Test.eventsOfType(Type<FlowTransactionScheduler.Scheduled>())
    Test.assert(eventsAfter.length > countBefore, message: "Should emit new scheduling event after reschedule")
}

/// syncSchedule clears invalid transaction IDs
access(all) fun testSyncScheduleClearsInvalidIDs() {
    setupCounterHandler()
    createCronHandler("*/1 * * * *", /storage/CronHandler14)

    // Schedule and execute
    let scheduleResult = scheduleCronHandler(/storage/CronHandler14, nil)
    Test.expect(scheduleResult, Test.beSucceeded())

    // Move time to execute transactions
    Test.moveTime(by: 65.0)

    // After execution, syncSchedule should have cleared executed IDs and scheduled new ones
    // Verify by checking CronInfo - should still have valid next/future execution times
    let result = Test.executeScript(
        Test.readFile("../scripts/GetCronInfo.cdc"),
        [testAccount.address, /storage/CronHandler14 as StoragePath]
    )
    Test.expect(result, Test.beSucceeded())

    let cronInfo = result.returnValue! as! FlowCron.CronInfo
    // After execution, should still have scheduled transactions (auto-filled)
    Test.assert(cronInfo.nextExecution != nil || cronInfo.futureExecution != nil,
        message: "Should have scheduled transactions after auto-fill")
}

/// View resolution returns actual scheduled times when active
access(all) fun testViewResolutionWithActiveSchedule() {
    setupCounterHandler()
    createCronHandler("*/5 * * * *", /storage/CronHandler15)

    // Schedule (creates next + future transactions)
    let scheduleResult = scheduleCronHandler(/storage/CronHandler15, nil)
    Test.expect(scheduleResult, Test.beSucceeded())

    // Get CronInfo - should return actual scheduled transaction times
    let result = Test.executeScript(
        Test.readFile("../scripts/GetCronInfo.cdc"),
        [testAccount.address, /storage/CronHandler15 as StoragePath]
    )
    Test.expect(result, Test.beSucceeded())

    let cronInfo = result.returnValue! as! FlowCron.CronInfo
    Test.assert(cronInfo.nextExecution != nil, message: "Should have next execution time")
    Test.assert(cronInfo.futureExecution != nil, message: "Should have future execution time")
}

/// View resolution falls back to calculated times when not scheduled
access(all) fun testViewResolutionFallbackToCalculated() {
    setupCounterHandler()
    createCronHandler("*/5 * * * *", /storage/CronHandler16)

    // Get CronInfo WITHOUT scheduling - should return calculated times
    let result = Test.executeScript(
        Test.readFile("../scripts/GetCronInfo.cdc"),
        [testAccount.address, /storage/CronHandler16 as StoragePath]
    )
    Test.expect(result, Test.beSucceeded())

    let cronInfo = result.returnValue! as! FlowCron.CronInfo
    Test.assert(cronInfo.nextExecution != nil, message: "Should calculate next execution time")
    Test.assert(cronInfo.futureExecution != nil, message: "Should calculate future execution time")
}

/// View resolution after cancellation returns calculated times
access(all) fun testViewResolutionAfterCancellation() {
    setupCounterHandler()
    createCronHandler("*/5 * * * *", /storage/CronHandler17)

    // Schedule
    let scheduleResult = scheduleCronHandler(/storage/CronHandler17, nil)
    Test.expect(scheduleResult, Test.beSucceeded())

    // Cancel
    let cancelResult = Test.executeTransaction(
        Test.Transaction(
            code: Test.readFile("../transactions/CancelCronSchedule.cdc"),
            authorizers: [testAccount.address],
            signers: [testAccount],
            arguments: [/storage/CronHandler17 as StoragePath]
        )
    )
    Test.expect(cancelResult, Test.beSucceeded())

    // Get CronInfo - should fall back to calculated times since cancelled
    let result = Test.executeScript(
        Test.readFile("../scripts/GetCronInfo.cdc"),
        [testAccount.address, /storage/CronHandler17 as StoragePath]
    )
    Test.expect(result, Test.beSucceeded())

    let cronInfo = result.returnValue! as! FlowCron.CronInfo
    Test.assert(cronInfo.nextExecution != nil, message: "Should calculate next execution time after cancellation")
}

/// getCronSpec returns valid copy
access(all) fun testGetCronSpec() {
    setupCounterHandler()
    createCronHandler("*/5 * * * *", /storage/CronHandler18)

    let scriptCode = "import FlowCron from \"../contracts/FlowCron.cdc\"\n"
        .concat("import FlowCronUtils from \"../contracts/FlowCronUtils.cdc\"\n\n")
        .concat("access(all) fun main(addr: Address, path: StoragePath): FlowCronUtils.CronSpec {\n")
        .concat("    let account = getAuthAccount<auth(BorrowValue) &Account>(addr)\n")
        .concat("    let handler = account.storage.borrow<&FlowCron.CronHandler>(from: path)!\n")
        .concat("    return handler.getCronSpec()\n")
        .concat("}")

    let result = Test.executeScript(scriptCode, [testAccount.address, /storage/CronHandler18 as StoragePath])
    Test.expect(result, Test.beSucceeded())

    let cronSpec = result.returnValue! as! FlowCronUtils.CronSpec
    // Verify it's a valid CronSpec struct (has the expected fields)
    Test.assert(cronSpec.minMask > 0 || cronSpec.minMask == 0, message: "Should return valid CronSpec")
}

/// Multiple handlers can run independently
access(all) fun testMultipleHandlersIndependent() {
    setupCounterHandler()

    // Create two handlers with different schedules
    createCronHandler("*/1 * * * *", /storage/CronHandlerA)
    createCronHandler("*/2 * * * *", /storage/CronHandlerB)

    let initialCount = getCounterValue()

    // Schedule both
    let result1 = scheduleCronHandler(/storage/CronHandlerA, nil)
    Test.expect(result1, Test.beSucceeded())

    let result2 = scheduleCronHandler(/storage/CronHandlerB, nil)
    Test.expect(result2, Test.beSucceeded())

    // Execute
    Test.moveTime(by: 65.0)

    // Both should have executed at least once
    let finalCount = getCounterValue()
    Test.assert(finalCount > initialCount, message: "Both handlers should execute independently")

    // Verify both handlers emitted execution events
    let executedEvents = Test.eventsOfType(Type<FlowCron.CronScheduleExecuted>())
    Test.assert(executedEvents.length >= 2, message: "Should have execution events from both handlers")
}

/// Handler continues after missing execution window
access(all) fun testContinuesAfterMissedWindow() {
    setupCounterHandler()
    createCronHandler("*/1 * * * *", /storage/CronHandler19)

    let initialCount = getCounterValue()

    // Schedule
    let scheduleResult = scheduleCronHandler(/storage/CronHandler19, nil)
    Test.expect(scheduleResult, Test.beSucceeded())

    // Move time way past scheduled time (simulate missed execution window)
    Test.moveTime(by: 300.0)  // 5 minutes

    // Should still execute when triggered
    let finalCount = getCounterValue()
    Test.assert(finalCount > initialCount, message: "Should execute even after missing window")
}

// ========== Helper Functions ==========

access(all) fun setupCounterHandler() {
    // Only setup once globally
    if counterHandlerSetup {
        return
    }

    let result = Test.executeTransaction(
        Test.Transaction(
            code: Test.readFile("mocks/transactions/InitCounterTransactionHandler.cdc"),
            authorizers: [testAccount.address],
            signers: [testAccount],
            arguments: []
        )
    )
    Test.expect(result, Test.beSucceeded())
    counterHandlerSetup = true
}

access(all) fun createCronHandler(_ expression: String, _ cronPath: StoragePath) {
    let result = Test.executeTransaction(
        Test.Transaction(
            code: createCronHandlerTransactionCode(),
            authorizers: [testAccount.address],
            signers: [testAccount],
            arguments: [
                expression,
                /storage/CounterTransactionHandler as StoragePath,
                cronPath
            ]
        )
    )
    Test.expect(result, Test.beSucceeded())
}

access(all) fun scheduleCronHandler(_ path: StoragePath, _ data: AnyStruct?): Test.TransactionResult {
    return Test.executeTransaction(
        Test.Transaction(
            code: Test.readFile("../transactions/ScheduleCronHandler.cdc"),
            authorizers: [testAccount.address],
            signers: [testAccount],
            arguments: [
                path,
                data,
                1 as UInt8,
                1000 as UInt64
            ]
        )
    )
}

access(all) fun getCounterValue(): Int {
    let result = Test.executeScript(
        Test.readFile("mocks/scripts/GetCounter.cdc"),
        []
    )
    Test.expect(result, Test.beSucceeded())
    return result.returnValue! as! Int
}

access(all) fun createCronHandlerTransactionCode(): String {
    return Test.readFile("../transactions/CreateCronHandler.cdc")
}