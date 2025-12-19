import Test
import "FlowCron"
import "FlowCronUtils"
import "FlowTransactionScheduler"
import "FlowTransactionSchedulerUtils"
import "MetadataViews"
import "Counter"
import "CounterTransactionHandler"

access(all) let testAccount = Test.serviceAccount()

// Setup runs once before all tests
access(all) fun setup() {
    // Deploy Counter contract
    var err = Test.deployContract(
        name: "Counter",
        path: "mocks/contracts/Counter.cdc",
        arguments: []
    )
    Test.expect(err, Test.beNil())

    // Deploy CounterTransactionHandler
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

    // Initialize CounterTransactionHandler
    let initResult = Test.executeTransaction(
        Test.Transaction(
            code: Test.readFile("mocks/transactions/InitCounterTransactionHandler.cdc"),
            authorizers: [testAccount.address],
            signers: [testAccount],
            arguments: []
        )
    )
    Test.expect(initResult, Test.beSucceeded())
}

// BeforeEach runs before each individual test
access(all) fun beforeEach() {
    // Reset the counter before each test
    let resetCode = "import Counter from \"Counter\"\n\n"
        .concat("transaction {\n")
        .concat("    execute {\n")
        .concat("        Counter.reset()\n")
        .concat("    }\n")
        .concat("}")

    let resetResult = Test.executeTransaction(
        Test.Transaction(
            code: resetCode,
            authorizers: [],
            signers: [],
            arguments: []
        )
    )
    Test.expect(resetResult, Test.beSucceeded())
}

access(all) fun afterEach() {
    // Move time forward to ensure all scheduled transactions execute
    // This allows the keeper to run and store the next transaction IDs
    // so CancelCronSchedule can find and cancel them
    Test.moveTime(by: 120.0)

    // Cancel any pending transactions
    let cancelResult = Test.executeTransaction(
        Test.Transaction(
            code: Test.readFile("../transactions/CancelCronSchedule.cdc"),
            authorizers: [testAccount.address],
            signers: [testAccount],
            arguments: [/storage/TestCronHandler as StoragePath]
        )
    )

    // Destroy handler to start fresh next test
    let destroyCode = "import FlowCron from \"FlowCron\"\n\n"
        .concat("transaction(path: StoragePath) {\n")
        .concat("    prepare(signer: auth(LoadValue) &Account) {\n")
        .concat("        if let handler <- signer.storage.load<@FlowCron.CronHandler>(from: path) {\n")
        .concat("            destroy handler\n")
        .concat("        }\n")
        .concat("    }\n")
        .concat("}")

    let destroyResult = Test.executeTransaction(
        Test.Transaction(
            code: destroyCode,
            authorizers: [testAccount.address],
            signers: [testAccount],
            arguments: [/storage/TestCronHandler as StoragePath]
        )
    )
}

// ============================================================================
// BASIC FUNCTIONALITY TESTS
// ============================================================================

/// Test that initial scheduling creates both executor and keeper transactions
access(all) fun test_InitialScheduleCreatesTwoTransactions() {
    // Create cron handler
    let createResult = Test.executeTransaction(
        Test.Transaction(
            code: Test.readFile("../transactions/CreateCronHandler.cdc"),
            authorizers: [testAccount.address],
            signers: [testAccount],
            arguments: [
                "* * * * *",
                /storage/CounterTransactionHandler as StoragePath,
                /storage/TestCronHandler as StoragePath
            ]
        )
    )
    Test.expect(createResult, Test.beSucceeded())

    let eventsBeforeSchedule = Test.eventsOfType(Type<FlowTransactionScheduler.Scheduled>())

    // Schedule the cron handler
    let scheduleResult = Test.executeTransaction(
        Test.Transaction(
            code: Test.readFile("../transactions/ScheduleCronHandler.cdc"),
            authorizers: [testAccount.address],
            signers: [testAccount],
            arguments: [
                /storage/TestCronHandler as StoragePath,
                nil as AnyStruct?,
                1 as UInt8,
                1000 as UInt64,
                2500 as UInt64
            ]
        )
    )
    Test.expect(scheduleResult, Test.beSucceeded())

    // Verify 2 transactions were scheduled (executor + keeper)
    let eventsAfterSchedule = Test.eventsOfType(Type<FlowTransactionScheduler.Scheduled>())
    let newEvents = eventsAfterSchedule.length - eventsBeforeSchedule.length
    Test.assertEqual(2, newEvents)
}

/// Test that first execution increments counter and schedules next cycle
access(all) fun test_FirstExecutionIncrementsCounter() {
    // Record counter value BEFORE any actions (should be 0 after beforeEach reset)
    let counterBefore = getCounterValue()
    Test.assertEqual(0, counterBefore)

    // Create and schedule cron handler
    let createResult = Test.executeTransaction(
        Test.Transaction(
            code: Test.readFile("../transactions/CreateCronHandler.cdc"),
            authorizers: [testAccount.address],
            signers: [testAccount],
            arguments: [
                "* * * * *",
                /storage/CounterTransactionHandler as StoragePath,
                /storage/TestCronHandler as StoragePath
            ]
        )
    )
    Test.expect(createResult, Test.beSucceeded())

    let initialTimestamp = getTimestamp()

    // Capture executor events BEFORE scheduling
    let executorEventsBefore = Test.eventsOfType(Type<FlowCron.CronExecutorExecuted>())

    // Schedule the cron handler
    let scheduleResult = Test.executeTransaction(
        Test.Transaction(
            code: Test.readFile("../transactions/ScheduleCronHandler.cdc"),
            authorizers: [testAccount.address],
            signers: [testAccount],
            arguments: [
                /storage/TestCronHandler as StoragePath,
                nil as AnyStruct?,
                1 as UInt8,
                1000 as UInt64,
                2500 as UInt64
            ]
        )
    )
    Test.expect(scheduleResult, Test.beSucceeded())

    // Get the executor scheduled event (second to last - executor runs at exact cron tick)
    let scheduledEvents = Test.eventsOfType(Type<FlowTransactionScheduler.Scheduled>())
    let executorEvent = scheduledEvents[scheduledEvents.length - 2] as! FlowTransactionScheduler.Scheduled
    let scheduledTimestamp = executorEvent.timestamp

    // Move time forward past the executor time (but before keeper)
    // This ensures only the executor runs, not the keeper
    let timeToAdvance = (scheduledTimestamp - initialTimestamp) + 0.5
    Test.moveTime(by: Fix64(timeToAdvance))

    // Verify exactly 1 executor event was emitted
    let executorEventsAfter = Test.eventsOfType(Type<FlowCron.CronExecutorExecuted>())
    let newExecutorEvents = executorEventsAfter.length - executorEventsBefore.length
    Test.assertEqual(1, newExecutorEvents)

    // Verify counter was incremented by exactly 1
    let counterAfter = getCounterValue()
    Test.assertEqual(counterBefore + 1, counterAfter)
}

/// Test that keeper schedules next executor and keeper after execution
access(all) fun test_KeeperSchedulesNextCycle() {
    // Create and schedule cron handler
    let createResult = Test.executeTransaction(
        Test.Transaction(
            code: Test.readFile("../transactions/CreateCronHandler.cdc"),
            authorizers: [testAccount.address],
            signers: [testAccount],
            arguments: [
                "* * * * *",
                /storage/CounterTransactionHandler as StoragePath,
                /storage/TestCronHandler as StoragePath
            ]
        )
    )
    Test.expect(createResult, Test.beSucceeded())

    let initialTimestamp = getTimestamp()

    // Schedule the cron handler
    let scheduleResult = Test.executeTransaction(
        Test.Transaction(
            code: Test.readFile("../transactions/ScheduleCronHandler.cdc"),
            authorizers: [testAccount.address],
            signers: [testAccount],
            arguments: [
                /storage/TestCronHandler as StoragePath,
                nil as AnyStruct?,
                1 as UInt8,
                1000 as UInt64,
                2500 as UInt64
            ]
        )
    )
    Test.expect(scheduleResult, Test.beSucceeded())

    let eventsAfterSchedule = Test.eventsOfType(Type<FlowTransactionScheduler.Scheduled>())

    // Capture baseline for keeper executed events BEFORE triggering execution
    let keeperExecutedEventsBefore = Test.eventsOfType(Type<FlowCron.CronKeeperExecuted>())

    // Move time to trigger first execution
    let keeperEvent = eventsAfterSchedule[eventsAfterSchedule.length - 1] as! FlowTransactionScheduler.Scheduled
    let timeToAdvance = (keeperEvent.timestamp - initialTimestamp) + 1.0
    Test.moveTime(by: Fix64(timeToAdvance))

    // After keeper executes, should have exactly 2 more scheduled transactions (executor + keeper)
    let eventsAfterExecution = Test.eventsOfType(Type<FlowTransactionScheduler.Scheduled>())
    let newScheduledEvents = eventsAfterExecution.length - eventsAfterSchedule.length
    Test.assertEqual(2, newScheduledEvents)

    // Verify exactly 1 CronKeeperExecuted event was emitted
    let keeperExecutedEventsAfter = Test.eventsOfType(Type<FlowCron.CronKeeperExecuted>())
    let newKeeperEvents = keeperExecutedEventsAfter.length - keeperExecutedEventsBefore.length
    Test.assertEqual(1, newKeeperEvents)
}

// ============================================================================
// EVENT TESTS
// ============================================================================

/// Test that CronExecutorExecuted event is emitted when executor runs
access(all) fun test_ExecutorEmitsEvent() {
    // Create and schedule cron handler
    let createResult = Test.executeTransaction(
        Test.Transaction(
            code: Test.readFile("../transactions/CreateCronHandler.cdc"),
            authorizers: [testAccount.address],
            signers: [testAccount],
            arguments: [
                "* * * * *",
                /storage/CounterTransactionHandler as StoragePath,
                /storage/TestCronHandler as StoragePath
            ]
        )
    )
    Test.expect(createResult, Test.beSucceeded())

    let scheduleResult = Test.executeTransaction(
        Test.Transaction(
            code: Test.readFile("../transactions/ScheduleCronHandler.cdc"),
            authorizers: [testAccount.address],
            signers: [testAccount],
            arguments: [
                /storage/TestCronHandler as StoragePath,
                nil as AnyStruct?,
                1 as UInt8,
                1000 as UInt64,
                2500 as UInt64
            ]
        )
    )
    Test.expect(scheduleResult, Test.beSucceeded())

    let executorEventsBefore = Test.eventsOfType(Type<FlowCron.CronExecutorExecuted>())

    // Trigger execution
    let scheduledEvents = Test.eventsOfType(Type<FlowTransactionScheduler.Scheduled>())
    let executorEvent = scheduledEvents[scheduledEvents.length - 2] as! FlowTransactionScheduler.Scheduled
    let initialTimestamp = getTimestamp()
    let timeToAdvance = (executorEvent.timestamp - initialTimestamp) + 1.0
    Test.moveTime(by: Fix64(timeToAdvance))

    // Verify CronExecutorExecuted event was emitted
    let executorEventsAfter = Test.eventsOfType(Type<FlowCron.CronExecutorExecuted>())
    let newEvents = executorEventsAfter.length - executorEventsBefore.length
    Test.assertEqual(1, newEvents)
}

/// Test that CronKeeperExecuted event contains correct next transaction IDs
access(all) fun test_KeeperEventContainsNextIds() {
    // Create and schedule cron handler
    let createResult = Test.executeTransaction(
        Test.Transaction(
            code: Test.readFile("../transactions/CreateCronHandler.cdc"),
            authorizers: [testAccount.address],
            signers: [testAccount],
            arguments: [
                "* * * * *",
                /storage/CounterTransactionHandler as StoragePath,
                /storage/TestCronHandler as StoragePath
            ]
        )
    )
    Test.expect(createResult, Test.beSucceeded())

    let scheduleResult = Test.executeTransaction(
        Test.Transaction(
            code: Test.readFile("../transactions/ScheduleCronHandler.cdc"),
            authorizers: [testAccount.address],
            signers: [testAccount],
            arguments: [
                /storage/TestCronHandler as StoragePath,
                nil as AnyStruct?,
                1 as UInt8,
                1000 as UInt64,
                2500 as UInt64
            ]
        )
    )
    Test.expect(scheduleResult, Test.beSucceeded())

    // Capture baseline for keeper executed events BEFORE triggering execution
    let keeperExecutedEventsBefore = Test.eventsOfType(Type<FlowCron.CronKeeperExecuted>())

    // Trigger keeper execution
    let scheduledEvents = Test.eventsOfType(Type<FlowTransactionScheduler.Scheduled>())
    let keeperEvent = scheduledEvents[scheduledEvents.length - 1] as! FlowTransactionScheduler.Scheduled
    let initialTimestamp = getTimestamp()
    let timeToAdvance = (keeperEvent.timestamp - initialTimestamp) + 1.0
    Test.moveTime(by: Fix64(timeToAdvance))

    // Verify exactly 1 keeper event was emitted
    let keeperExecutedEventsAfter = Test.eventsOfType(Type<FlowCron.CronKeeperExecuted>())
    let newKeeperEvents = keeperExecutedEventsAfter.length - keeperExecutedEventsBefore.length
    Test.assertEqual(1, newKeeperEvents)

    // Check the new keeper event has next IDs
    let lastKeeperEvent = keeperExecutedEventsAfter[keeperExecutedEventsAfter.length - 1] as! FlowCron.CronKeeperExecuted
    Test.assert(lastKeeperEvent.nextKeeperTxID > 0, message: "Should have next keeper ID")
}

// ============================================================================
// TIMING TESTS
// ============================================================================

/// Test keeper is scheduled 1 second after executor
access(all) fun test_KeeperOffsetOneSecond() {
    // Create and schedule cron handler
    let createResult = Test.executeTransaction(
        Test.Transaction(
            code: Test.readFile("../transactions/CreateCronHandler.cdc"),
            authorizers: [testAccount.address],
            signers: [testAccount],
            arguments: [
                "* * * * *",
                /storage/CounterTransactionHandler as StoragePath,
                /storage/TestCronHandler as StoragePath
            ]
        )
    )
    Test.expect(createResult, Test.beSucceeded())

    let scheduleResult = Test.executeTransaction(
        Test.Transaction(
            code: Test.readFile("../transactions/ScheduleCronHandler.cdc"),
            authorizers: [testAccount.address],
            signers: [testAccount],
            arguments: [
                /storage/TestCronHandler as StoragePath,
                nil as AnyStruct?,
                1 as UInt8,
                1000 as UInt64,
                2500 as UInt64
            ]
        )
    )
    Test.expect(scheduleResult, Test.beSucceeded())

    // Get the two scheduled events
    let scheduledEvents = Test.eventsOfType(Type<FlowTransactionScheduler.Scheduled>())
    let executorEvent = scheduledEvents[scheduledEvents.length - 2] as! FlowTransactionScheduler.Scheduled
    let keeperEvent = scheduledEvents[scheduledEvents.length - 1] as! FlowTransactionScheduler.Scheduled

    // Verify keeper is 1 second after executor
    let timeDiff = keeperEvent.timestamp - executorEvent.timestamp
    Test.assertEqual(1.0, timeDiff)
}

/// Test every-5-minute cron schedules at correct times
access(all) fun test_FiveMinuteCronTiming() {
    // Create cron handler with every 5 minutes
    let createResult = Test.executeTransaction(
        Test.Transaction(
            code: Test.readFile("../transactions/CreateCronHandler.cdc"),
            authorizers: [testAccount.address],
            signers: [testAccount],
            arguments: [
                "*/5 * * * *",
                /storage/CounterTransactionHandler as StoragePath,
                /storage/TestCronHandler as StoragePath
            ]
        )
    )
    Test.expect(createResult, Test.beSucceeded())

    let scheduleResult = Test.executeTransaction(
        Test.Transaction(
            code: Test.readFile("../transactions/ScheduleCronHandler.cdc"),
            authorizers: [testAccount.address],
            signers: [testAccount],
            arguments: [
                /storage/TestCronHandler as StoragePath,
                nil as AnyStruct?,
                1 as UInt8,
                1000 as UInt64,
                2500 as UInt64
            ]
        )
    )
    Test.expect(scheduleResult, Test.beSucceeded())

    // Get the executor scheduled event
    let scheduledEvents = Test.eventsOfType(Type<FlowTransactionScheduler.Scheduled>())
    let executorEvent = scheduledEvents[scheduledEvents.length - 2] as! FlowTransactionScheduler.Scheduled
    let scheduledTime = executorEvent.timestamp

    // Verify scheduled time is on a 5-minute boundary
    let scheduledTimeInt = UInt64(scheduledTime)
    let minutePart = (scheduledTimeInt / 60) % 60

    let validMinutes = [0, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55]
    var isValid = false
    for validMin in validMinutes {
        if minutePart == UInt64(validMin) {
            isValid = true
            break
        }
    }
    Test.assert(isValid, message: "Scheduled time should be on a 5-minute boundary")
}

/// Test minute 15 each hour cron
access(all) fun test_SpecificMinuteEachHour() {
    let createResult = Test.executeTransaction(
        Test.Transaction(
            code: Test.readFile("../transactions/CreateCronHandler.cdc"),
            authorizers: [testAccount.address],
            signers: [testAccount],
            arguments: [
                "15 * * * *",
                /storage/CounterTransactionHandler as StoragePath,
                /storage/TestCronHandler as StoragePath
            ]
        )
    )
    Test.expect(createResult, Test.beSucceeded())

    let scheduleResult = Test.executeTransaction(
        Test.Transaction(
            code: Test.readFile("../transactions/ScheduleCronHandler.cdc"),
            authorizers: [testAccount.address],
            signers: [testAccount],
            arguments: [
                /storage/TestCronHandler as StoragePath,
                nil as AnyStruct?,
                1 as UInt8,
                1000 as UInt64,
                2500 as UInt64
            ]
        )
    )
    Test.expect(scheduleResult, Test.beSucceeded())

    // Verify scheduled time is at minute 15
    let scheduledEvents = Test.eventsOfType(Type<FlowTransactionScheduler.Scheduled>())
    let executorEvent = scheduledEvents[scheduledEvents.length - 2] as! FlowTransactionScheduler.Scheduled
    let scheduledTimeInt = UInt64(executorEvent.timestamp)
    let minutePart = (scheduledTimeInt / 60) % 60

    Test.assertEqual(15, Int(minutePart))
}

// ============================================================================
// SCHEDULE STATUS TESTS
// ============================================================================

/// Test GetCronScheduleStatus returns both executor and keeper IDs
access(all) fun test_ScheduleStatusReturnsIDs() {
    // Create and schedule cron handler
    let createResult = Test.executeTransaction(
        Test.Transaction(
            code: Test.readFile("../transactions/CreateCronHandler.cdc"),
            authorizers: [testAccount.address],
            signers: [testAccount],
            arguments: [
                "* * * * *",
                /storage/CounterTransactionHandler as StoragePath,
                /storage/TestCronHandler as StoragePath
            ]
        )
    )
    Test.expect(createResult, Test.beSucceeded())

    let scheduleResult = Test.executeTransaction(
        Test.Transaction(
            code: Test.readFile("../transactions/ScheduleCronHandler.cdc"),
            authorizers: [testAccount.address],
            signers: [testAccount],
            arguments: [
                /storage/TestCronHandler as StoragePath,
                nil as AnyStruct?,
                1 as UInt8,
                1000 as UInt64,
                2500 as UInt64
            ]
        )
    )
    Test.expect(scheduleResult, Test.beSucceeded())

    // Trigger first execution to establish full state
    let scheduledEvents = Test.eventsOfType(Type<FlowTransactionScheduler.Scheduled>())
    let keeperEvent = scheduledEvents[scheduledEvents.length - 1] as! FlowTransactionScheduler.Scheduled
    let initialTimestamp = getTimestamp()
    let timeToAdvance = (keeperEvent.timestamp - initialTimestamp) + 1.0
    Test.moveTime(by: Fix64(timeToAdvance))

    // Check schedule status
    let statusResult = Test.executeScript(
        Test.readFile("../scripts/GetCronScheduleStatus.cdc"),
        [testAccount.address, /storage/TestCronHandler]
    )
    Test.expect(statusResult, Test.beSucceeded())

    let status = statusResult.returnValue! as! {String: AnyStruct?}
    let executorID = status["nextScheduledExecutorID"] as! UInt64?
    let keeperID = status["nextScheduledKeeperID"] as! UInt64?

    Test.assert(executorID != nil, message: "Executor ID should exist")
    Test.assert(keeperID != nil, message: "Keeper ID should exist")
    // Keeper is scheduled immediately after executor, so its ID = executor ID + 1
    Test.assertEqual(executorID! + 1, keeperID!)
}

// ============================================================================
// CANCELLATION TESTS
// ============================================================================

/// Test that cancellation cancels both executor and keeper
access(all) fun test_CancellationCancelsBothTransactions() {
    // Create and schedule cron handler
    let createResult = Test.executeTransaction(
        Test.Transaction(
            code: Test.readFile("../transactions/CreateCronHandler.cdc"),
            authorizers: [testAccount.address],
            signers: [testAccount],
            arguments: [
                "* * * * *",
                /storage/CounterTransactionHandler as StoragePath,
                /storage/TestCronHandler as StoragePath
            ]
        )
    )
    Test.expect(createResult, Test.beSucceeded())

    let scheduleResult = Test.executeTransaction(
        Test.Transaction(
            code: Test.readFile("../transactions/ScheduleCronHandler.cdc"),
            authorizers: [testAccount.address],
            signers: [testAccount],
            arguments: [
                /storage/TestCronHandler as StoragePath,
                nil as AnyStruct?,
                1 as UInt8,
                1000 as UInt64,
                2500 as UInt64
            ]
        )
    )
    Test.expect(scheduleResult, Test.beSucceeded())

    // Trigger first execution to get both IDs stored
    let scheduledEvents = Test.eventsOfType(Type<FlowTransactionScheduler.Scheduled>())
    let keeperEvent = scheduledEvents[scheduledEvents.length - 1] as! FlowTransactionScheduler.Scheduled
    let initialTimestamp = getTimestamp()
    let timeToAdvance = (keeperEvent.timestamp - initialTimestamp) + 1.0
    Test.moveTime(by: Fix64(timeToAdvance))

    let cancelEventsBefore = Test.eventsOfType(Type<FlowTransactionScheduler.Canceled>())

    // Cancel the cron
    let cancelResult = Test.executeTransaction(
        Test.Transaction(
            code: Test.readFile("../transactions/CancelCronSchedule.cdc"),
            authorizers: [testAccount.address],
            signers: [testAccount],
            arguments: [/storage/TestCronHandler as StoragePath]
        )
    )
    Test.expect(cancelResult, Test.beSucceeded())

    // Verify 2 cancellation events (executor + keeper)
    let cancelEventsAfter = Test.eventsOfType(Type<FlowTransactionScheduler.Canceled>())
    let newCancelEvents = cancelEventsAfter.length - cancelEventsBefore.length
    Test.assertEqual(2, newCancelEvents)
}

/// Test cancellation and rescheduling works correctly
access(all) fun test_CancellationAndRescheduling() {
    // Create cron handler
    let createResult = Test.executeTransaction(
        Test.Transaction(
            code: Test.readFile("../transactions/CreateCronHandler.cdc"),
            authorizers: [testAccount.address],
            signers: [testAccount],
            arguments: [
                "* * * * *",
                /storage/CounterTransactionHandler as StoragePath,
                /storage/TestCronHandler as StoragePath
            ]
        )
    )
    Test.expect(createResult, Test.beSucceeded())

    // First schedule
    let scheduleResult = Test.executeTransaction(
        Test.Transaction(
            code: Test.readFile("../transactions/ScheduleCronHandler.cdc"),
            authorizers: [testAccount.address],
            signers: [testAccount],
            arguments: [
                /storage/TestCronHandler as StoragePath,
                nil as AnyStruct?,
                1 as UInt8,
                1000 as UInt64,
                2500 as UInt64
            ]
        )
    )
    Test.expect(scheduleResult, Test.beSucceeded())

    // Trigger execution
    let scheduledEvents = Test.eventsOfType(Type<FlowTransactionScheduler.Scheduled>())
    let keeperEvent = scheduledEvents[scheduledEvents.length - 1] as! FlowTransactionScheduler.Scheduled
    let initialTimestamp = getTimestamp()
    let timeToAdvance = (keeperEvent.timestamp - initialTimestamp) + 1.0
    Test.moveTime(by: Fix64(timeToAdvance))

    // Cancel
    let cancelResult = Test.executeTransaction(
        Test.Transaction(
            code: Test.readFile("../transactions/CancelCronSchedule.cdc"),
            authorizers: [testAccount.address],
            signers: [testAccount],
            arguments: [/storage/TestCronHandler as StoragePath]
        )
    )
    Test.expect(cancelResult, Test.beSucceeded())

    // Capture baseline BEFORE reschedule
    let eventsBeforeReschedule = Test.eventsOfType(Type<FlowTransactionScheduler.Scheduled>())

    // Reschedule - should succeed since cancelled
    let rescheduleResult = Test.executeTransaction(
        Test.Transaction(
            code: Test.readFile("../transactions/ScheduleCronHandler.cdc"),
            authorizers: [testAccount.address],
            signers: [testAccount],
            arguments: [
                /storage/TestCronHandler as StoragePath,
                "new data" as AnyStruct?,
                1 as UInt8,
                1000 as UInt64,
                2500 as UInt64
            ]
        )
    )
    Test.expect(rescheduleResult, Test.beSucceeded())

    // Verify exactly 2 new transactions were scheduled (executor + keeper)
    let eventsAfterReschedule = Test.eventsOfType(Type<FlowTransactionScheduler.Scheduled>())
    let newScheduledEvents = eventsAfterReschedule.length - eventsBeforeReschedule.length
    Test.assertEqual(2, newScheduledEvents)
}

// ============================================================================
// REJECTION TESTS
// ============================================================================

/// Test that duplicate keeper scheduling is rejected
access(all) fun test_DuplicateKeeperRejected() {
    // Create cron handler
    let createResult = Test.executeTransaction(
        Test.Transaction(
            code: Test.readFile("../transactions/CreateCronHandler.cdc"),
            authorizers: [testAccount.address],
            signers: [testAccount],
            arguments: [
                "* * * * *",
                /storage/CounterTransactionHandler as StoragePath,
                /storage/TestCronHandler as StoragePath
            ]
        )
    )
    Test.expect(createResult, Test.beSucceeded())

    // First schedule
    let scheduleResult1 = Test.executeTransaction(
        Test.Transaction(
            code: Test.readFile("../transactions/ScheduleCronHandler.cdc"),
            authorizers: [testAccount.address],
            signers: [testAccount],
            arguments: [
                /storage/TestCronHandler as StoragePath,
                "initial data" as AnyStruct?,
                1 as UInt8,
                1000 as UInt64,
                2500 as UInt64
            ]
        )
    )
    Test.expect(scheduleResult1, Test.beSucceeded())

    let rejectionEventsBefore = Test.eventsOfType(Type<FlowCron.CronScheduleRejected>())

    // Try to schedule again while already scheduled
    let scheduleResult2 = Test.executeTransaction(
        Test.Transaction(
            code: Test.readFile("../transactions/ScheduleCronHandler.cdc"),
            authorizers: [testAccount.address],
            signers: [testAccount],
            arguments: [
                /storage/TestCronHandler as StoragePath,
                "different data" as AnyStruct?,
                2 as UInt8,
                2000 as UInt64,
                2500 as UInt64
            ]
        )
    )
    Test.expect(scheduleResult2, Test.beSucceeded())

    // Trigger execution of duplicate by moving time to the duplicate keeper's timestamp
    let scheduledEvents = Test.eventsOfType(Type<FlowTransactionScheduler.Scheduled>())
    let lastEvent = scheduledEvents[scheduledEvents.length - 1] as! FlowTransactionScheduler.Scheduled
    let currentTime = getTimestamp()
    let timeToAdvance = (lastEvent.timestamp - currentTime) + 1.0
    Test.moveTime(by: Fix64(timeToAdvance))

    // Verify exactly 1 rejection event was emitted for the duplicate keeper
    let rejectionEventsAfter = Test.eventsOfType(Type<FlowCron.CronScheduleRejected>())
    let newRejectionEvents = rejectionEventsAfter.length - rejectionEventsBefore.length
    Test.assertEqual(1, newRejectionEvents)
}

// ============================================================================
// CRON INFO VIEW TESTS
// ============================================================================

/// Test CronInfo view returns correct data
access(all) fun test_CronInfoView() {
    // Create cron handler
    let createResult = Test.executeTransaction(
        Test.Transaction(
            code: Test.readFile("../transactions/CreateCronHandler.cdc"),
            authorizers: [testAccount.address],
            signers: [testAccount],
            arguments: [
                "*/10 * * * *",
                /storage/CounterTransactionHandler as StoragePath,
                /storage/TestCronHandler as StoragePath
            ]
        )
    )
    Test.expect(createResult, Test.beSucceeded())

    // Before scheduling
    let cronInfoBefore = getCronInfo(/storage/TestCronHandler)
    Test.assert(cronInfoBefore != nil, message: "CronInfo should not be nil")

    if let info = cronInfoBefore {
        Test.assertEqual("*/10 * * * *", info.cronExpression)
        Test.assert(info.nextScheduledKeeperID == nil, message: "Should have no keeper ID before scheduling")
        Test.assert(info.nextScheduledExecutorID == nil, message: "Should have no executor ID before scheduling")
        Test.assert(info.wrappedHandlerType != nil, message: "Should have wrapped handler type")
    }

    // Schedule
    let scheduleResult = Test.executeTransaction(
        Test.Transaction(
            code: Test.readFile("../transactions/ScheduleCronHandler.cdc"),
            authorizers: [testAccount.address],
            signers: [testAccount],
            arguments: [
                /storage/TestCronHandler as StoragePath,
                nil as AnyStruct?,
                1 as UInt8,
                1000 as UInt64,
                2500 as UInt64
            ]
        )
    )
    Test.expect(scheduleResult, Test.beSucceeded())

    // Trigger first execution
    let scheduledEvents = Test.eventsOfType(Type<FlowTransactionScheduler.Scheduled>())
    let keeperEvent = scheduledEvents[scheduledEvents.length - 1] as! FlowTransactionScheduler.Scheduled
    let initialTimestamp = getTimestamp()
    let timeToAdvance = (keeperEvent.timestamp - initialTimestamp) + 1.0
    Test.moveTime(by: Fix64(timeToAdvance))

    // After execution
    let cronInfoAfter = getCronInfo(/storage/TestCronHandler)
    Test.assert(cronInfoAfter != nil, message: "CronInfo should not be nil after execution")

    if let info = cronInfoAfter {
        Test.assert(info.nextScheduledKeeperID != nil, message: "Should have keeper ID after execution")
        Test.assert(info.nextScheduledExecutorID != nil, message: "Should have executor ID after execution")
    }
}

// ============================================================================
// CONTINUOUS EXECUTION TESTS
// ============================================================================

/// Test continuous execution over multiple cycles
access(all) fun test_ContinuousExecution() {
    // Verify counter starts at 0 (reset by beforeEach)
    Test.assertEqual(0, getCounterValue())

    // Create cron handler with every-minute execution
    let createResult = Test.executeTransaction(
        Test.Transaction(
            code: Test.readFile("../transactions/CreateCronHandler.cdc"),
            authorizers: [testAccount.address],
            signers: [testAccount],
            arguments: [
                "* * * * *",
                /storage/CounterTransactionHandler as StoragePath,
                /storage/TestCronHandler as StoragePath
            ]
        )
    )
    Test.expect(createResult, Test.beSucceeded())

    let scheduleResult = Test.executeTransaction(
        Test.Transaction(
            code: Test.readFile("../transactions/ScheduleCronHandler.cdc"),
            authorizers: [testAccount.address],
            signers: [testAccount],
            arguments: [
                /storage/TestCronHandler as StoragePath,
                nil as AnyStruct?,
                1 as UInt8,
                1000 as UInt64,
                2500 as UInt64
            ]
        )
    )
    Test.expect(scheduleResult, Test.beSucceeded())

    // Get initial keeper timestamp
    let initialEvents = Test.eventsOfType(Type<FlowTransactionScheduler.Scheduled>())
    let firstKeeperEvent = initialEvents[initialEvents.length - 1] as! FlowTransactionScheduler.Scheduled
    let firstKeeperTime = firstKeeperEvent.timestamp

    // Capture baseline AFTER scheduling but BEFORE any time advancement
    // This ensures we don't count events from previous tests
    let executorEventsBefore = Test.eventsOfType(Type<FlowCron.CronExecutorExecuted>())
    let counterBefore = getCounterValue()

    // Advance to trigger first cycle (executor + keeper)
    let startTime = getTimestamp()
    Test.moveTime(by: Fix64((firstKeeperTime - startTime) + 1.0))

    // Advance 1 minute + 2 seconds to trigger second cycle
    Test.moveTime(by: 62.0)

    // Advance 1 minute + 2 seconds to trigger third cycle
    Test.moveTime(by: 62.0)

    // Verify we had exactly 3 executor executions since our baseline
    let executorEventsAfter = Test.eventsOfType(Type<FlowCron.CronExecutorExecuted>())
    let newExecutorEvents = executorEventsAfter.length - executorEventsBefore.length
    Test.assertEqual(3, newExecutorEvents)

    // Counter should have incremented by 3
    Test.assertEqual(counterBefore + 3, getCounterValue())
}

/// Test executed transactions change status
access(all) fun test_ExecutedTransactionsChangeStatus() {
    // Create and schedule cron handler
    let createResult = Test.executeTransaction(
        Test.Transaction(
            code: Test.readFile("../transactions/CreateCronHandler.cdc"),
            authorizers: [testAccount.address],
            signers: [testAccount],
            arguments: [
                "* * * * *",
                /storage/CounterTransactionHandler as StoragePath,
                /storage/TestCronHandler as StoragePath
            ]
        )
    )
    Test.expect(createResult, Test.beSucceeded())

    let scheduleResult = Test.executeTransaction(
        Test.Transaction(
            code: Test.readFile("../transactions/ScheduleCronHandler.cdc"),
            authorizers: [testAccount.address],
            signers: [testAccount],
            arguments: [
                /storage/TestCronHandler as StoragePath,
                nil as AnyStruct?,
                1 as UInt8,
                1000 as UInt64,
                2500 as UInt64
            ]
        )
    )
    Test.expect(scheduleResult, Test.beSucceeded())

    // Get the initial scheduled executor ID
    let scheduledEvents = Test.eventsOfType(Type<FlowTransactionScheduler.Scheduled>())
    let executorEvent = scheduledEvents[scheduledEvents.length - 2] as! FlowTransactionScheduler.Scheduled
    let firstTxID = executorEvent.id

    // Check status before execution
    let txDataCode = "import FlowTransactionScheduler from \"FlowTransactionScheduler\"\n\n"
        .concat("access(all) fun main(txID: UInt64): {String: AnyStruct}? {\n")
        .concat("    if let txData = FlowTransactionScheduler.getTransactionData(id: txID) {\n")
        .concat("        return {\n")
        .concat("            \"id\": txData.id,\n")
        .concat("            \"status\": txData.status.rawValue,\n")
        .concat("            \"scheduledTimestamp\": txData.scheduledTimestamp\n")
        .concat("        }\n")
        .concat("    }\n")
        .concat("    return nil\n")
        .concat("}")

    let txDataBefore = Test.executeScript(txDataCode, [firstTxID])
    Test.expect(txDataBefore, Test.beSucceeded())
    Test.assert(txDataBefore.returnValue != nil, message: "Transaction should exist before execution")

    let beforeData = txDataBefore.returnValue! as! {String: AnyStruct}
    let beforeStatus = beforeData["status"]! as! UInt8
    Test.assertEqual(1, Int(beforeStatus))  // Status.Scheduled = 1

    // Move time to trigger execution
    let initialTimestamp = getTimestamp()
    let timeToAdvance = (executorEvent.timestamp - initialTimestamp) + 1.0
    Test.moveTime(by: Fix64(timeToAdvance))

    // Verify counter incremented
    Test.assertEqual(1, getCounterValue())

    // Verify executed transaction status changed
    let txDataAfter = Test.executeScript(txDataCode, [firstTxID])
    Test.expect(txDataAfter, Test.beSucceeded())
    Test.assert(txDataAfter.returnValue != nil, message: "Transaction should still exist after execution")

    let afterData = txDataAfter.returnValue! as! {String: AnyStruct}
    let afterStatus = afterData["status"]! as! UInt8
    Test.assertEqual(2, Int(afterStatus))  // Status.Executed = 2
}

// ============================================================================
// VALIDATION TESTS
// ============================================================================

/// Test that empty cron expression fails
access(all) fun test_EmptyCronExpressionFails() {
    let createResult = Test.executeTransaction(
        Test.Transaction(
            code: Test.readFile("../transactions/CreateCronHandler.cdc"),
            authorizers: [testAccount.address],
            signers: [testAccount],
            arguments: [
                "",  // Empty cron expression
                /storage/CounterTransactionHandler as StoragePath,
                /storage/TestCronHandler as StoragePath
            ]
        )
    )
    Test.expect(createResult, Test.beFailed())
}

/// Test that invalid cron expression fails
access(all) fun test_InvalidCronExpressionFails() {
    let createResult = Test.executeTransaction(
        Test.Transaction(
            code: Test.readFile("../transactions/CreateCronHandler.cdc"),
            authorizers: [testAccount.address],
            signers: [testAccount],
            arguments: [
                "invalid cron expression",
                /storage/CounterTransactionHandler as StoragePath,
                /storage/TestCronHandler as StoragePath
            ]
        )
    )
    Test.expect(createResult, Test.beFailed())
}

/// Test that execution effort below minimum (10) fails
access(all) fun test_ExecutionEffortBelowMinimumFails() {
    // Create valid cron handler first
    let createResult = Test.executeTransaction(
        Test.Transaction(
            code: Test.readFile("../transactions/CreateCronHandler.cdc"),
            authorizers: [testAccount.address],
            signers: [testAccount],
            arguments: [
                "* * * * *",
                /storage/CounterTransactionHandler as StoragePath,
                /storage/TestCronHandler as StoragePath
            ]
        )
    )
    Test.expect(createResult, Test.beSucceeded())

    // Try to schedule with execution effort below minimum
    let scheduleResult = Test.executeTransaction(
        Test.Transaction(
            code: Test.readFile("../transactions/ScheduleCronHandler.cdc"),
            authorizers: [testAccount.address],
            signers: [testAccount],
            arguments: [
                /storage/TestCronHandler as StoragePath,
                nil as AnyStruct?,
                1 as UInt8,
                5 as UInt64  // Below minimum of 10
            ]
        )
    )
    Test.expect(scheduleResult, Test.beFailed())
}

/// Test that execution effort above maximum (9999) fails
access(all) fun test_ExecutionEffortAboveMaximumFails() {
    // Create valid cron handler first
    let createResult = Test.executeTransaction(
        Test.Transaction(
            code: Test.readFile("../transactions/CreateCronHandler.cdc"),
            authorizers: [testAccount.address],
            signers: [testAccount],
            arguments: [
                "* * * * *",
                /storage/CounterTransactionHandler as StoragePath,
                /storage/TestCronHandler as StoragePath
            ]
        )
    )
    Test.expect(createResult, Test.beSucceeded())

    // Try to schedule with execution effort above maximum
    let scheduleResult = Test.executeTransaction(
        Test.Transaction(
            code: Test.readFile("../transactions/ScheduleCronHandler.cdc"),
            authorizers: [testAccount.address],
            signers: [testAccount],
            arguments: [
                /storage/TestCronHandler as StoragePath,
                nil as AnyStruct?,
                1 as UInt8,
                10000 as UInt64  // Above maximum of 9999
            ]
        )
    )
    Test.expect(scheduleResult, Test.beFailed())
}

// ============================================================================
// METADATA VIEWS TESTS
// ============================================================================

/// Test that getViews returns correct view types
access(all) fun test_GetViewsReturnsCorrectTypes() {
    // Create cron handler
    let createResult = Test.executeTransaction(
        Test.Transaction(
            code: Test.readFile("../transactions/CreateCronHandler.cdc"),
            authorizers: [testAccount.address],
            signers: [testAccount],
            arguments: [
                "* * * * *",
                /storage/CounterTransactionHandler as StoragePath,
                /storage/TestCronHandler as StoragePath
            ]
        )
    )
    Test.expect(createResult, Test.beSucceeded())

    // Get views via script using getAuthAccount for storage access
    let getViewsCode = "import FlowCron from \"FlowCron\"\n"
        .concat("import MetadataViews from \"MetadataViews\"\n\n")
        .concat("access(all) fun main(address: Address, path: StoragePath): [Type] {\n")
        .concat("    let account = getAuthAccount<auth(BorrowValue) &Account>(address)\n")
        .concat("    if let handler = account.storage.borrow<&FlowCron.CronHandler>(from: path) {\n")
        .concat("        return handler.getViews()\n")
        .concat("    }\n")
        .concat("    return []\n")
        .concat("}")

    let result = Test.executeScript(getViewsCode, [testAccount.address, /storage/TestCronHandler])
    Test.expect(result, Test.beSucceeded())

    let views = result.returnValue! as! [Type]
    // CronHandler returns 2 views: Display and CronInfo
    // CounterTransactionHandler adds 2 more views: StoragePath and PublicPath
    // Total: 4 views
    Test.assertEqual(4, views.length)
    Test.assert(views.contains(Type<MetadataViews.Display>()), message: "Should contain Display view")
    Test.assert(views.contains(Type<FlowCron.CronInfo>()), message: "Should contain CronInfo view")
    Test.assert(views.contains(Type<StoragePath>()), message: "Should contain StoragePath view from wrapped handler")
    Test.assert(views.contains(Type<PublicPath>()), message: "Should contain PublicPath view from wrapped handler")
}

/// Test that Display view is correctly enriched with cron info
access(all) fun test_DisplayViewMergesWithWrappedHandler() {
    // Create cron handler
    let createResult = Test.executeTransaction(
        Test.Transaction(
            code: Test.readFile("../transactions/CreateCronHandler.cdc"),
            authorizers: [testAccount.address],
            signers: [testAccount],
            arguments: [
                "*/5 * * * *",
                /storage/CounterTransactionHandler as StoragePath,
                /storage/TestCronHandler as StoragePath
            ]
        )
    )
    Test.expect(createResult, Test.beSucceeded())

    // Get Display view via script using getAuthAccount for storage access
    let getDisplayCode = "import FlowCron from \"FlowCron\"\n"
        .concat("import MetadataViews from \"MetadataViews\"\n\n")
        .concat("access(all) fun main(address: Address, path: StoragePath): MetadataViews.Display? {\n")
        .concat("    let account = getAuthAccount<auth(BorrowValue) &Account>(address)\n")
        .concat("    if let handler = account.storage.borrow<&FlowCron.CronHandler>(from: path) {\n")
        .concat("        return handler.resolveView(Type<MetadataViews.Display>()) as? MetadataViews.Display\n")
        .concat("    }\n")
        .concat("    return nil\n")
        .concat("}")

    let result = Test.executeScript(getDisplayCode, [testAccount.address, /storage/TestCronHandler])
    Test.expect(result, Test.beSucceeded())

    let display = result.returnValue as? MetadataViews.Display
    Test.assert(display != nil, message: "Display view should not be nil")

    if let d = display {
        // Display should contain cron expression in description
        Test.assert(d.description.utf8.length > 0, message: "Description should not be empty")
    }
}

// ============================================================================
// GETTER FUNCTION TESTS
// ============================================================================

/// Test that all getter functions return correct values
access(all) fun test_GetterFunctionsReturnCorrectValues() {
    // Create cron handler
    let createResult = Test.executeTransaction(
        Test.Transaction(
            code: Test.readFile("../transactions/CreateCronHandler.cdc"),
            authorizers: [testAccount.address],
            signers: [testAccount],
            arguments: [
                "*/15 * * * *",
                /storage/CounterTransactionHandler as StoragePath,
                /storage/TestCronHandler as StoragePath
            ]
        )
    )
    Test.expect(createResult, Test.beSucceeded())

    // Test getCronExpression
    let getCronExprCode = "import FlowCron from \"FlowCron\"\n\n"
        .concat("access(all) fun main(address: Address, path: StoragePath): String {\n")
        .concat("    let account = getAuthAccount<auth(BorrowValue) &Account>(address)\n")
        .concat("    let handler = account.storage.borrow<&FlowCron.CronHandler>(from: path)!\n")
        .concat("    return handler.getCronExpression()\n")
        .concat("}")

    let cronExprResult = Test.executeScript(getCronExprCode, [testAccount.address, /storage/TestCronHandler])
    Test.expect(cronExprResult, Test.beSucceeded())
    Test.assertEqual("*/15 * * * *", cronExprResult.returnValue! as! String)

    // Test getCronSpec - just verify it returns a non-nil spec
    let getCronSpecCode = "import FlowCron from \"FlowCron\"\n"
        .concat("import FlowCronUtils from \"FlowCronUtils\"\n\n")
        .concat("access(all) fun main(address: Address, path: StoragePath): FlowCronUtils.CronSpec {\n")
        .concat("    let account = getAuthAccount<auth(BorrowValue) &Account>(address)\n")
        .concat("    let handler = account.storage.borrow<&FlowCron.CronHandler>(from: path)!\n")
        .concat("    return handler.getCronSpec()\n")
        .concat("}")

    let cronSpecResult = Test.executeScript(getCronSpecCode, [testAccount.address, /storage/TestCronHandler])
    Test.expect(cronSpecResult, Test.beSucceeded())

    // Before scheduling: IDs should be nil
    let getIDsCode = "import FlowCron from \"FlowCron\"\n\n"
        .concat("access(all) fun main(address: Address, path: StoragePath): {String: UInt64?} {\n")
        .concat("    let account = getAuthAccount<auth(BorrowValue) &Account>(address)\n")
        .concat("    let handler = account.storage.borrow<&FlowCron.CronHandler>(from: path)!\n")
        .concat("    return {\n")
        .concat("        \"executorID\": handler.getNextScheduledExecutorID(),\n")
        .concat("        \"keeperID\": handler.getNextScheduledKeeperID()\n")
        .concat("    }\n")
        .concat("}")

    let idsBeforeResult = Test.executeScript(getIDsCode, [testAccount.address, /storage/TestCronHandler])
    Test.expect(idsBeforeResult, Test.beSucceeded())
    let idsBefore = idsBeforeResult.returnValue! as! {String: UInt64?}
    Test.assert(idsBefore["executorID"]! == nil, message: "Executor ID should be nil before scheduling")
    Test.assert(idsBefore["keeperID"]! == nil, message: "Keeper ID should be nil before scheduling")

    // Schedule
    let scheduleResult = Test.executeTransaction(
        Test.Transaction(
            code: Test.readFile("../transactions/ScheduleCronHandler.cdc"),
            authorizers: [testAccount.address],
            signers: [testAccount],
            arguments: [
                /storage/TestCronHandler as StoragePath,
                nil as AnyStruct?,
                1 as UInt8,
                1000 as UInt64,
                2500 as UInt64
            ]
        )
    )
    Test.expect(scheduleResult, Test.beSucceeded())

    // Trigger keeper execution to populate IDs
    let scheduledEvents = Test.eventsOfType(Type<FlowTransactionScheduler.Scheduled>())
    let keeperEvent = scheduledEvents[scheduledEvents.length - 1] as! FlowTransactionScheduler.Scheduled
    let initialTimestamp = getTimestamp()
    let timeToAdvance = (keeperEvent.timestamp - initialTimestamp) + 1.0
    Test.moveTime(by: Fix64(timeToAdvance))

    // After scheduling and keeper execution: IDs should be set
    let idsAfterResult = Test.executeScript(getIDsCode, [testAccount.address, /storage/TestCronHandler])
    Test.expect(idsAfterResult, Test.beSucceeded())
    let idsAfter = idsAfterResult.returnValue! as! {String: UInt64?}
    Test.assert(idsAfter["executorID"]! != nil, message: "Executor ID should be set after keeper execution")
    Test.assert(idsAfter["keeperID"]! != nil, message: "Keeper ID should be set after keeper execution")
}

/// Test that resolveView returns nil for unknown view types
access(all) fun test_ResolveViewReturnsNilForUnknownType() {
    // Create cron handler
    let createResult = Test.executeTransaction(
        Test.Transaction(
            code: Test.readFile("../transactions/CreateCronHandler.cdc"),
            authorizers: [testAccount.address],
            signers: [testAccount],
            arguments: [
                "* * * * *",
                /storage/CounterTransactionHandler as StoragePath,
                /storage/TestCronHandler as StoragePath
            ]
        )
    )
    Test.expect(createResult, Test.beSucceeded())

    // Try to resolve an unknown view type (Int is not a supported view)
    let resolveUnknownCode = "import FlowCron from \"FlowCron\"\n\n"
        .concat("access(all) fun main(address: Address, path: StoragePath): AnyStruct? {\n")
        .concat("    let account = getAuthAccount<auth(BorrowValue) &Account>(address)\n")
        .concat("    let handler = account.storage.borrow<&FlowCron.CronHandler>(from: path)!\n")
        .concat("    return handler.resolveView(Type<Int>())\n")
        .concat("}")

    let result = Test.executeScript(resolveUnknownCode, [testAccount.address, /storage/TestCronHandler])
    Test.expect(result, Test.beSucceeded())
    Test.assert(result.returnValue == nil, message: "Unknown view type should return nil")
}

// ============================================================================
// HELPER FUNCTIONS
// ============================================================================

/// Helper: Get CronInfo
access(all) fun getCronInfo(_ storagePath: StoragePath): FlowCron.CronInfo? {
    let result = Test.executeScript(
        Test.readFile("../scripts/GetCronInfo.cdc"),
        [testAccount.address, storagePath]
    )
    Test.expect(result, Test.beSucceeded())
    return result.returnValue as! FlowCron.CronInfo?
}

/// Helper: Get counter value
access(all) fun getCounterValue(): Int {
    let result = Test.executeScript(
        Test.readFile("mocks/scripts/GetCounter.cdc"),
        []
    )
    Test.expect(result, Test.beSucceeded())
    return result.returnValue! as! Int
}

/// Helper: Get current timestamp
access(all) fun getTimestamp(): UFix64 {
    let code = "access(all) fun main(): UFix64 { return getCurrentBlock().timestamp }"
    let result = Test.executeScript(code, [])
    Test.expect(result, Test.beSucceeded())
    return result.returnValue! as! UFix64
}
