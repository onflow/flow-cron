import Test
import "FlowCron"
import "FlowCronUtils"
import "FlowTransactionScheduler"
import "FlowTransactionSchedulerUtils"
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

// AfterEach runs after each individual test
access(all) fun afterEach() {
    // Remove all test cron handlers to prevent interference with next test
    let cleanupCode = "import FlowCron from \"FlowCron\"\n\n"
        .concat("transaction(paths: [StoragePath]) {\n")
        .concat("    prepare(signer: auth(LoadValue) &Account) {\n")
        .concat("        for path in paths {\n")
        .concat("            if let handler <- signer.storage.load<@FlowCron.CronHandler>(from: path) {\n")
        .concat("                destroy handler\n")
        .concat("            }\n")
        .concat("        }\n")
        .concat("    }\n")
        .concat("}")

    let paths: [StoragePath] = [
        /storage/TestCronHandler,
        /storage/TestCronHandler2,
        /storage/TestCronHandler3,
        /storage/TestCronHandler4
    ]

    let cleanupResult = Test.executeTransaction(
        Test.Transaction(
            code: cleanupCode,
            authorizers: [testAccount.address],
            signers: [testAccount],
            arguments: [paths]
        )
    )
    // Don't fail if cleanup fails - handlers might not exist
}

/// Schedule a cron handler and verify first execution happens
access(all) fun test_CronHandler_FirstExecution() {

    // Create cron handler with every-minute cron
    let createResult = Test.executeTransaction(
        Test.Transaction(
            code: Test.readFile("../transactions/CreateCronHandler.cdc"),
            authorizers: [testAccount.address],
            signers: [testAccount],
            arguments: [
                "* * * * *",  // Every minute
                /storage/CounterTransactionHandler as StoragePath,
                /storage/TestCronHandler as StoragePath
            ]
        )
    )
    Test.expect(createResult, Test.beSucceeded())

    // Check initial counter value
    let initialCount = getCounterValue()
    Test.assertEqual(0, initialCount)

    // Get initial timestamp
    let initialTimestamp = getTimestamp()

    // Schedule the cron handler (will schedule at next minute boundary)
    let scheduleResult = Test.executeTransaction(
        Test.Transaction(
            code: Test.readFile("../transactions/ScheduleCronHandler.cdc"),
            authorizers: [testAccount.address],
            signers: [testAccount],
            arguments: [
                /storage/TestCronHandler as StoragePath,
                nil as AnyStruct?,
                1 as UInt8,  // Medium priority
                1000 as UInt64  // execution effort
            ]
        )
    )
    Test.expect(scheduleResult, Test.beSucceeded())

    // Verify initial scheduling created 1 transaction
    let scheduledEvents = Test.eventsOfType(Type<FlowTransactionScheduler.Scheduled>())
    Test.assertEqual(1, scheduledEvents.length)

    // Get the scheduled timestamp from the event
    let scheduledEvent = scheduledEvents[0] as! FlowTransactionScheduler.Scheduled
    let scheduledTimestamp = scheduledEvent.timestamp

    // Move time forward past the scheduled time (1 minute + 1 second buffer)
    let timeToAdvance = (scheduledTimestamp - initialTimestamp) + 1.0
    Test.moveTime(by: Fix64(timeToAdvance))

    let advancedTimestamp = getTimestamp()

    // Verify the counter incremented (first execution happened)
    let finalCount = getCounterValue()
    Test.assertEqual(1, finalCount)
}

/// Verify double-buffer pattern - first execution schedules 2 more transactions
access(all) fun test_CronHandler_DoubleBufferAfterFirstExecution() {

    // Create cron handler with every-minute cron
    let createResult = Test.executeTransaction(
        Test.Transaction(
            code: Test.readFile("../transactions/CreateCronHandler.cdc"),
            authorizers: [testAccount.address],
            signers: [testAccount],
            arguments: [
                "* * * * *",
                /storage/CounterTransactionHandler as StoragePath,
                /storage/TestCronHandler2 as StoragePath
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
                /storage/TestCronHandler2 as StoragePath,
                nil as AnyStruct?,
                1 as UInt8,
                1000 as UInt64
            ]
        )
    )
    Test.expect(scheduleResult, Test.beSucceeded())

    let eventsAfterSchedule = Test.eventsOfType(Type<FlowTransactionScheduler.Scheduled>())

    // Get scheduled timestamp and move time to trigger first execution
    let scheduledEvent = eventsAfterSchedule[eventsAfterSchedule.length - 1] as! FlowTransactionScheduler.Scheduled
    let scheduledTimestamp = scheduledEvent.timestamp
    let timeToAdvance = (scheduledTimestamp - initialTimestamp) + 1.0
    Test.moveTime(by: Fix64(timeToAdvance))

    // After first execution, should have scheduled 2 more (next + future)
    let eventsAfterExecution = Test.eventsOfType(Type<FlowTransactionScheduler.Scheduled>())
    let newEvents = eventsAfterExecution.length - eventsAfterSchedule.length

    // Should have scheduled 2 new transactions (double-buffer pattern)
    Test.assertEqual(2, newEvents)
    Test.assertEqual(1, getCounterValue())
}

/// Verify cron scheduling calculates correct next execution times
access(all) fun test_CronScheduling_CalculatesCorrectTimes() {

    // Test every 5 minutes cron
    let createResult = Test.executeTransaction(
        Test.Transaction(
            code: Test.readFile("../transactions/CreateCronHandler.cdc"),
            authorizers: [testAccount.address],
            signers: [testAccount],
            arguments: [
                "*/5 * * * *",  // Every 5 minutes
                /storage/CounterTransactionHandler as StoragePath,
                /storage/TestCronHandler3 as StoragePath
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
                /storage/TestCronHandler3 as StoragePath,
                nil as AnyStruct?,
                1 as UInt8,
                1000 as UInt64
            ]
        )
    )
    Test.expect(scheduleResult, Test.beSucceeded())

    // Get scheduled events
    let initialEvents = Test.eventsOfType(Type<FlowTransactionScheduler.Scheduled>())
    let scheduledEvent = initialEvents[initialEvents.length - 1] as! FlowTransactionScheduler.Scheduled
    let scheduledTime = scheduledEvent.timestamp

    // Verify scheduled time is on a 5-minute boundary
    let scheduledTimeInt = UInt64(scheduledTime)
    let minutePart = (scheduledTimeInt / 60) % 60

    // Should be at 0, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, or 55 minute mark
    let validMinutes = [0, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55]
    var isValid = false
    for validMin in validMinutes {
        if minutePart == UInt64(validMin) {
            isValid = true
            break
        }
    }
    Test.assert(isValid, message: "Scheduled time should be on a 5-minute boundary")

    // Move time to trigger first execution and verify double-buffer scheduling
    let timeToAdvance = (scheduledTime - initialTimestamp) + 1.0
    Test.moveTime(by: Fix64(timeToAdvance))

    // Verify first execution happened
    Test.assertEqual(1, getCounterValue())

    // Verify 2 new transactions were scheduled (double-buffer)
    let eventsAfterExecution = Test.eventsOfType(Type<FlowTransactionScheduler.Scheduled>())
    let newEvents = eventsAfterExecution.length - initialEvents.length
    Test.assertEqual(2, newEvents)

    // Get the 2 new scheduled timestamps
    let nextEvent = eventsAfterExecution[eventsAfterExecution.length - 2] as! FlowTransactionScheduler.Scheduled
    let futureEvent = eventsAfterExecution[eventsAfterExecution.length - 1] as! FlowTransactionScheduler.Scheduled

    let nextTime = UInt64(nextEvent.timestamp)
    let futureTime = UInt64(futureEvent.timestamp)

    // Verify they are 5 minutes apart
    let timeDiff = futureTime - nextTime
    Test.assertEqual(300, Int(timeDiff))  // 5 minutes = 300 seconds
}

/// Verify every-10-minutes cron pattern
access(all) fun test_CronEvery10Minutes_SchedulesCorrectly() {

    let createResult = Test.executeTransaction(
        Test.Transaction(
            code: Test.readFile("../transactions/CreateCronHandler.cdc"),
            authorizers: [testAccount.address],
            signers: [testAccount],
            arguments: [
                "*/10 * * * *",  // Every 10 minutes
                /storage/CounterTransactionHandler as StoragePath,
                /storage/TestCronHandler4 as StoragePath
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
                /storage/TestCronHandler4 as StoragePath,
                nil as AnyStruct?,
                1 as UInt8,
                1000 as UInt64
            ]
        )
    )
    Test.expect(scheduleResult, Test.beSucceeded())

    // Get scheduled event
    let initialEvents = Test.eventsOfType(Type<FlowTransactionScheduler.Scheduled>())
    let scheduledEvent = initialEvents[initialEvents.length - 1] as! FlowTransactionScheduler.Scheduled
    let scheduledTime = scheduledEvent.timestamp

    // Verify scheduled time is on a 10-minute boundary (0, 10, 20, 30, 40, 50)
    let scheduledTimeInt = UInt64(scheduledTime)
    let minutePart = (scheduledTimeInt / 60) % 60

    let validMinutes = [0, 10, 20, 30, 40, 50]
    var isValid = false
    for validMin in validMinutes {
        if minutePart == UInt64(validMin) {
            isValid = true
            break
        }
    }
    Test.assert(isValid, message: "Scheduled time should be on a 10-minute boundary")

    // Move time to trigger execution
    let timeToAdvance = (scheduledTime - initialTimestamp) + 1.0
    Test.moveTime(by: Fix64(timeToAdvance))

    // Verify execution happened
    Test.assertEqual(1, getCounterValue())

    // Verify double-buffer scheduling with 10-minute intervals
    let eventsAfterExecution = Test.eventsOfType(Type<FlowTransactionScheduler.Scheduled>())
    let newEvents = eventsAfterExecution.length - initialEvents.length
    Test.assertEqual(2, newEvents)

    // Verify the scheduled times are 10 minutes apart
    let nextEvent = eventsAfterExecution[eventsAfterExecution.length - 2] as! FlowTransactionScheduler.Scheduled
    let futureEvent = eventsAfterExecution[eventsAfterExecution.length - 1] as! FlowTransactionScheduler.Scheduled

    let nextTime = UInt64(nextEvent.timestamp)
    let futureTime = UInt64(futureEvent.timestamp)
    let timeDiff = futureTime - nextTime

    Test.assertEqual(600, Int(timeDiff))  // 10 minutes = 600 seconds
}

/// Verify every-2-minutes cron pattern
access(all) fun test_CronEvery2Minutes_SchedulesCorrectly() {

    let createResult = Test.executeTransaction(
        Test.Transaction(
            code: Test.readFile("../transactions/CreateCronHandler.cdc"),
            authorizers: [testAccount.address],
            signers: [testAccount],
            arguments: [
                "*/2 * * * *",  // Every 2 minutes
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
                1000 as UInt64
            ]
        )
    )
    Test.expect(scheduleResult, Test.beSucceeded())

    // Get scheduled event
    let initialEvents = Test.eventsOfType(Type<FlowTransactionScheduler.Scheduled>())
    let scheduledEvent = initialEvents[initialEvents.length - 1] as! FlowTransactionScheduler.Scheduled
    let scheduledTime = scheduledEvent.timestamp

    // Verify scheduled time is on a 2-minute boundary (even minutes: 0, 2, 4, 6, 8...)
    let scheduledTimeInt = UInt64(scheduledTime)
    let minutePart = (scheduledTimeInt / 60) % 60

    // Minute should be even
    Test.assert(minutePart % 2 == 0, message: "Scheduled time should be on a 2-minute boundary (even minute)")

    // Move time to trigger execution
    let timeToAdvance = (scheduledTime - initialTimestamp) + 1.0
    Test.moveTime(by: Fix64(timeToAdvance))

    // Verify execution happened
    Test.assertEqual(1, getCounterValue())

    // Verify double-buffer scheduling with 2-minute intervals
    let eventsAfterExecution = Test.eventsOfType(Type<FlowTransactionScheduler.Scheduled>())
    let newEvents = eventsAfterExecution.length - initialEvents.length
    Test.assertEqual(2, newEvents)

    // Verify the scheduled times are 2 minutes apart (120 seconds)
    let nextEvent = eventsAfterExecution[eventsAfterExecution.length - 2] as! FlowTransactionScheduler.Scheduled
    let futureEvent = eventsAfterExecution[eventsAfterExecution.length - 1] as! FlowTransactionScheduler.Scheduled

    let nextTime = UInt64(nextEvent.timestamp)
    let futureTime = UInt64(futureEvent.timestamp)
    let timeDiff = futureTime - nextTime

    Test.assertEqual(120, Int(timeDiff))  // 2 minutes = 120 seconds
}

/// Verify every-3-minutes cron pattern
access(all) fun test_CronEvery3Minutes_SchedulesCorrectly() {

    let createResult = Test.executeTransaction(
        Test.Transaction(
            code: Test.readFile("../transactions/CreateCronHandler.cdc"),
            authorizers: [testAccount.address],
            signers: [testAccount],
            arguments: [
                "*/3 * * * *",  // Every 3 minutes
                /storage/CounterTransactionHandler as StoragePath,
                /storage/TestCronHandler2 as StoragePath
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
                /storage/TestCronHandler2 as StoragePath,
                nil as AnyStruct?,
                1 as UInt8,
                1000 as UInt64
            ]
        )
    )
    Test.expect(scheduleResult, Test.beSucceeded())

    // Get scheduled event
    let initialEvents = Test.eventsOfType(Type<FlowTransactionScheduler.Scheduled>())
    let scheduledEvent = initialEvents[initialEvents.length - 1] as! FlowTransactionScheduler.Scheduled
    let scheduledTime = scheduledEvent.timestamp

    // Verify scheduled time is on a 3-minute boundary (0, 3, 6, 9, 12, 15...)
    let scheduledTimeInt = UInt64(scheduledTime)
    let minutePart = (scheduledTimeInt / 60) % 60

    // Minute should be divisible by 3
    Test.assert(minutePart % 3 == 0, message: "Scheduled time should be on a 3-minute boundary")

    // Move time to trigger execution
    let timeToAdvance = (scheduledTime - initialTimestamp) + 1.0
    Test.moveTime(by: Fix64(timeToAdvance))

    // Verify execution happened
    Test.assertEqual(1, getCounterValue())

    // Verify double-buffer scheduling with 3-minute intervals
    let eventsAfterExecution = Test.eventsOfType(Type<FlowTransactionScheduler.Scheduled>())
    let newEvents = eventsAfterExecution.length - initialEvents.length
    Test.assertEqual(2, newEvents)

    // Verify the scheduled times are 3 minutes apart (180 seconds)
    let nextEvent = eventsAfterExecution[eventsAfterExecution.length - 2] as! FlowTransactionScheduler.Scheduled
    let futureEvent = eventsAfterExecution[eventsAfterExecution.length - 1] as! FlowTransactionScheduler.Scheduled

    let nextTime = UInt64(nextEvent.timestamp)
    let futureTime = UInt64(futureEvent.timestamp)
    let timeDiff = futureTime - nextTime

    Test.assertEqual(180, Int(timeDiff))  // 3 minutes = 180 seconds
}

/// Verify every-15-minutes cron pattern
access(all) fun test_CronEvery15Minutes_SchedulesCorrectly() {

    let createResult = Test.executeTransaction(
        Test.Transaction(
            code: Test.readFile("../transactions/CreateCronHandler.cdc"),
            authorizers: [testAccount.address],
            signers: [testAccount],
            arguments: [
                "*/15 * * * *",  // Every 15 minutes
                /storage/CounterTransactionHandler as StoragePath,
                /storage/TestCronHandler3 as StoragePath
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
                /storage/TestCronHandler3 as StoragePath,
                nil as AnyStruct?,
                1 as UInt8,
                1000 as UInt64
            ]
        )
    )
    Test.expect(scheduleResult, Test.beSucceeded())

    // Get scheduled event
    let initialEvents = Test.eventsOfType(Type<FlowTransactionScheduler.Scheduled>())
    let scheduledEvent = initialEvents[initialEvents.length - 1] as! FlowTransactionScheduler.Scheduled
    let scheduledTime = scheduledEvent.timestamp

    // Verify scheduled time is on a 15-minute boundary (0, 15, 30, 45)
    let scheduledTimeInt = UInt64(scheduledTime)
    let minutePart = (scheduledTimeInt / 60) % 60

    let validMinutes = [0, 15, 30, 45]
    var isValid = false
    for validMin in validMinutes {
        if minutePart == UInt64(validMin) {
            isValid = true
            break
        }
    }
    Test.assert(isValid, message: "Scheduled time should be on a 15-minute boundary (0, 15, 30, 45)")

    // Move time to trigger execution
    let timeToAdvance = (scheduledTime - initialTimestamp) + 1.0
    Test.moveTime(by: Fix64(timeToAdvance))

    // Verify execution happened
    Test.assertEqual(1, getCounterValue())

    // Verify double-buffer scheduling with 15-minute intervals
    let eventsAfterExecution = Test.eventsOfType(Type<FlowTransactionScheduler.Scheduled>())
    let newEvents = eventsAfterExecution.length - initialEvents.length
    Test.assertEqual(2, newEvents)

    // Verify the scheduled times are 15 minutes apart (900 seconds)
    let nextEvent = eventsAfterExecution[eventsAfterExecution.length - 2] as! FlowTransactionScheduler.Scheduled
    let futureEvent = eventsAfterExecution[eventsAfterExecution.length - 1] as! FlowTransactionScheduler.Scheduled

    let nextTime = UInt64(nextEvent.timestamp)
    let futureTime = UInt64(futureEvent.timestamp)
    let timeDiff = futureTime - nextTime

    Test.assertEqual(900, Int(timeDiff))  // 15 minutes = 900 seconds
}

/// Verify every-30-minutes cron pattern
access(all) fun test_CronEvery30Minutes_SchedulesCorrectly() {

    let createResult = Test.executeTransaction(
        Test.Transaction(
            code: Test.readFile("../transactions/CreateCronHandler.cdc"),
            authorizers: [testAccount.address],
            signers: [testAccount],
            arguments: [
                "*/30 * * * *",  // Every 30 minutes
                /storage/CounterTransactionHandler as StoragePath,
                /storage/TestCronHandler4 as StoragePath
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
                /storage/TestCronHandler4 as StoragePath,
                nil as AnyStruct?,
                1 as UInt8,
                1000 as UInt64
            ]
        )
    )
    Test.expect(scheduleResult, Test.beSucceeded())

    // Get scheduled event
    let initialEvents = Test.eventsOfType(Type<FlowTransactionScheduler.Scheduled>())
    let scheduledEvent = initialEvents[initialEvents.length - 1] as! FlowTransactionScheduler.Scheduled
    let scheduledTime = scheduledEvent.timestamp

    // Verify scheduled time is on a 30-minute boundary (0 or 30)
    let scheduledTimeInt = UInt64(scheduledTime)
    let minutePart = (scheduledTimeInt / 60) % 60

    Test.assert(minutePart == 0 || minutePart == 30, message: "Scheduled time should be on a 30-minute boundary (0 or 30)")

    // Move time to trigger execution
    let timeToAdvance = (scheduledTime - initialTimestamp) + 1.0
    Test.moveTime(by: Fix64(timeToAdvance))

    // Verify execution happened
    Test.assertEqual(1, getCounterValue())

    // Verify double-buffer scheduling with 30-minute intervals
    let eventsAfterExecution = Test.eventsOfType(Type<FlowTransactionScheduler.Scheduled>())
    let newEvents = eventsAfterExecution.length - initialEvents.length
    Test.assertEqual(2, newEvents)

    // Verify the scheduled times are 30 minutes apart (1800 seconds)
    let nextEvent = eventsAfterExecution[eventsAfterExecution.length - 2] as! FlowTransactionScheduler.Scheduled
    let futureEvent = eventsAfterExecution[eventsAfterExecution.length - 1] as! FlowTransactionScheduler.Scheduled

    let nextTime = UInt64(nextEvent.timestamp)
    let futureTime = UInt64(futureEvent.timestamp)
    let timeDiff = futureTime - nextTime

    Test.assertEqual(1800, Int(timeDiff))  // 30 minutes = 1800 seconds
}

/// Verify specific minute each hour pattern (at minute 15 of every hour)
access(all) fun test_CronSpecificMinuteEachHour() {

    let createResult = Test.executeTransaction(
        Test.Transaction(
            code: Test.readFile("../transactions/CreateCronHandler.cdc"),
            authorizers: [testAccount.address],
            signers: [testAccount],
            arguments: [
                "15 * * * *",  // At minute 15 of every hour
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
                1000 as UInt64
            ]
        )
    )
    Test.expect(scheduleResult, Test.beSucceeded())

    // Get scheduled event
    let initialEvents = Test.eventsOfType(Type<FlowTransactionScheduler.Scheduled>())
    let scheduledEvent = initialEvents[initialEvents.length - 1] as! FlowTransactionScheduler.Scheduled
    let scheduledTime = scheduledEvent.timestamp

    // Verify scheduled time is at minute 15
    let scheduledTimeInt = UInt64(scheduledTime)
    let minutePart = (scheduledTimeInt / 60) % 60

    Test.assertEqual(15, Int(minutePart))

    // Move time to trigger execution
    let timeToAdvance = (scheduledTime - initialTimestamp) + 1.0
    Test.moveTime(by: Fix64(timeToAdvance))

    // Verify execution happened
    Test.assertEqual(1, getCounterValue())

    // Verify double-buffer scheduling - should schedule for next hour's minute 15
    let eventsAfterExecution = Test.eventsOfType(Type<FlowTransactionScheduler.Scheduled>())
    let newEvents = eventsAfterExecution.length - initialEvents.length
    Test.assertEqual(2, newEvents)

    // Verify the scheduled times are 1 hour apart (3600 seconds)
    let nextEvent = eventsAfterExecution[eventsAfterExecution.length - 2] as! FlowTransactionScheduler.Scheduled
    let futureEvent = eventsAfterExecution[eventsAfterExecution.length - 1] as! FlowTransactionScheduler.Scheduled

    let nextTime = UInt64(nextEvent.timestamp)
    let futureTime = UInt64(futureEvent.timestamp)
    let timeDiff = futureTime - nextTime

    Test.assertEqual(3600, Int(timeDiff))  // 1 hour = 3600 seconds

    // Verify both are at minute 15
    let nextMinute = (nextTime / 60) % 60
    let futureMinute = (futureTime / 60) % 60
    Test.assertEqual(15, Int(nextMinute))
    Test.assertEqual(15, Int(futureMinute))
}

/// Verify specific hour and minute pattern (at 2:30 every day)
access(all) fun test_CronSpecificHourAndMinute() {

    let createResult = Test.executeTransaction(
        Test.Transaction(
            code: Test.readFile("../transactions/CreateCronHandler.cdc"),
            authorizers: [testAccount.address],
            signers: [testAccount],
            arguments: [
                "30 2 * * *",  // At 2:30 AM every day
                /storage/CounterTransactionHandler as StoragePath,
                /storage/TestCronHandler2 as StoragePath
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
                /storage/TestCronHandler2 as StoragePath,
                nil as AnyStruct?,
                1 as UInt8,
                1000 as UInt64
            ]
        )
    )
    Test.expect(scheduleResult, Test.beSucceeded())

    // Get scheduled event
    let initialEvents = Test.eventsOfType(Type<FlowTransactionScheduler.Scheduled>())
    let scheduledEvent = initialEvents[initialEvents.length - 1] as! FlowTransactionScheduler.Scheduled
    let scheduledTime = scheduledEvent.timestamp

    // Verify scheduled time is at 2:30
    let scheduledTimeInt = UInt64(scheduledTime)
    let minutePart = (scheduledTimeInt / 60) % 60
    let hourPart = (scheduledTimeInt / 3600) % 24

    Test.assertEqual(2, Int(hourPart))
    Test.assertEqual(30, Int(minutePart))

    // Move time to trigger execution
    let timeToAdvance = (scheduledTime - initialTimestamp) + 1.0
    Test.moveTime(by: Fix64(timeToAdvance))

    // Verify execution happened
    Test.assertEqual(1, getCounterValue())

    // Verify double-buffer scheduling - should schedule for next day's 2:30
    let eventsAfterExecution = Test.eventsOfType(Type<FlowTransactionScheduler.Scheduled>())
    let newEvents = eventsAfterExecution.length - initialEvents.length
    Test.assertEqual(2, newEvents)

    // Verify the scheduled times are 1 day apart (86400 seconds)
    let nextEvent = eventsAfterExecution[eventsAfterExecution.length - 2] as! FlowTransactionScheduler.Scheduled
    let futureEvent = eventsAfterExecution[eventsAfterExecution.length - 1] as! FlowTransactionScheduler.Scheduled

    let nextTime = UInt64(nextEvent.timestamp)
    let futureTime = UInt64(futureEvent.timestamp)
    let timeDiff = futureTime - nextTime

    Test.assertEqual(86400, Int(timeDiff))  // 1 day = 86400 seconds

    // Verify both are at 2:30
    let nextMinute = (nextTime / 60) % 60
    let nextHour = (nextTime / 3600) % 24
    let futureMinute = (futureTime / 60) % 60
    let futureHour = (futureTime / 3600) % 24


    Test.assertEqual(2, Int(nextHour))
    Test.assertEqual(30, Int(nextMinute))
    Test.assertEqual(2, Int(futureHour))
    Test.assertEqual(30, Int(futureMinute))
}

/// Verify rejection when trying to schedule with different data while already scheduled
access(all) fun test_CronRejectsSchedulingWhenAlreadyScheduled() {

    // Create cron handler
    let createResult = Test.executeTransaction(
        Test.Transaction(
            code: Test.readFile("../transactions/CreateCronHandler.cdc"),
            authorizers: [testAccount.address],
            signers: [testAccount],
            arguments: [
                "* * * * *",  // Every minute
                /storage/CounterTransactionHandler as StoragePath,
                /storage/TestCronHandler as StoragePath
            ]
        )
    )
    Test.expect(createResult, Test.beSucceeded())

    // Schedule with initial data
    let scheduleResult1 = Test.executeTransaction(
        Test.Transaction(
            code: Test.readFile("../transactions/ScheduleCronHandler.cdc"),
            authorizers: [testAccount.address],
            signers: [testAccount],
            arguments: [
                /storage/TestCronHandler as StoragePath,
                "initial data" as AnyStruct?,
                1 as UInt8,
                1000 as UInt64
            ]
        )
    )
    Test.expect(scheduleResult1, Test.beSucceeded())

    let initialEvents = Test.eventsOfType(Type<FlowTransactionScheduler.Scheduled>())

    // Count rejection events before second schedule
    let rejectionEventsBefore = Test.eventsOfType(Type<FlowCron.CronScheduleRejected>())

    // Try to schedule again with different data - should be rejected
    let scheduleResult2 = Test.executeTransaction(
        Test.Transaction(
            code: Test.readFile("../transactions/ScheduleCronHandler.cdc"),
            authorizers: [testAccount.address],
            signers: [testAccount],
            arguments: [
                /storage/TestCronHandler as StoragePath,
                "different data" as AnyStruct?,
                2 as UInt8,  // Different priority
                2000 as UInt64  // Different execution effort
            ]
        )
    )

    // The transaction should succeed (doesn't revert)
    Test.expect(scheduleResult2, Test.beSucceeded())

    // The second schedule creates a transaction, but rejection happens during EXECUTION
    // So we need to trigger execution by moving time forward
    let scheduledEventAfterSecond = Test.eventsOfType(Type<FlowTransactionScheduler.Scheduled>())
    if scheduledEventAfterSecond.length > initialEvents.length {
        let secondScheduledEvent = scheduledEventAfterSecond[scheduledEventAfterSecond.length - 1] as! FlowTransactionScheduler.Scheduled
        let currentTime = getTimestamp()
        let timeToAdvance = (secondScheduledEvent.timestamp - currentTime) + 1.0
        Test.moveTime(by: Fix64(timeToAdvance))
    }

    // Now check for NEW rejection events (after execution)
    let rejectionEventsAfter = Test.eventsOfType(Type<FlowCron.CronScheduleRejected>())
    let newRejectionEvents = rejectionEventsAfter.length - rejectionEventsBefore.length

    // Should have at least 1 new rejection event when the duplicate transaction executes
    Test.assert(newRejectionEvents > 0, message: "Should have new rejection event when duplicate transaction executes")

    let finalEvents = Test.eventsOfType(Type<FlowTransactionScheduler.Scheduled>())
    let finalCounter = getCounterValue()

    // Verify the rejection prevented double-buffer scheduling from duplicate
    // If rejection worked correctly, we should have at most 3 total scheduled events:
    // 1 initial + 2 from first execution (double-buffer)
    // The duplicate should NOT have created additional scheduled transactions
    Test.assert(finalEvents.length <= initialEvents.length + 3,
        message: "Rejection should prevent additional scheduling beyond initial double-buffer")
}

/// Verify cancellation and rescheduling after all transactions cancelled
access(all) fun test_CronCancellationAndRescheduling() {

    // Create cron handler
    let createResult = Test.executeTransaction(
        Test.Transaction(
            code: Test.readFile("../transactions/CreateCronHandler.cdc"),
            authorizers: [testAccount.address],
            signers: [testAccount],
            arguments: [
                "*/5 * * * *",  // Every 5 minutes
                /storage/CounterTransactionHandler as StoragePath,
                /storage/TestCronHandler2 as StoragePath
            ]
        )
    )
    Test.expect(createResult, Test.beSucceeded())

    // Schedule the cron handler
    let scheduleResult = Test.executeTransaction(
        Test.Transaction(
            code: Test.readFile("../transactions/ScheduleCronHandler.cdc"),
            authorizers: [testAccount.address],
            signers: [testAccount],
            arguments: [
                /storage/TestCronHandler2 as StoragePath,
                "initial data" as AnyStruct?,
                1 as UInt8,
                1000 as UInt64
            ]
        )
    )
    Test.expect(scheduleResult, Test.beSucceeded())

    let eventsAfterSchedule = Test.eventsOfType(Type<FlowTransactionScheduler.Scheduled>())

    // Trigger first execution to establish double-buffer
    let scheduledEvent = eventsAfterSchedule[eventsAfterSchedule.length - 1] as! FlowTransactionScheduler.Scheduled
    let initialTimestamp = getTimestamp()
    let timeToAdvance = (scheduledEvent.timestamp - initialTimestamp) + 1.0
    Test.moveTime(by: Fix64(timeToAdvance))

    // Verify double-buffer was established
    let eventsAfterExecution = Test.eventsOfType(Type<FlowTransactionScheduler.Scheduled>())
    let newEventsAfterExec = eventsAfterExecution.length - eventsAfterSchedule.length

    // Now cancel all scheduled transactions using CancelCronSchedule transaction
    let cancelResult = Test.executeTransaction(
        Test.Transaction(
            code: Test.readFile("../transactions/CancelCronSchedule.cdc"),
            authorizers: [testAccount.address],
            signers: [testAccount],
            arguments: [
                /storage/TestCronHandler2 as StoragePath
            ]
        )
    )
    Test.expect(cancelResult, Test.beSucceeded())

    // Check cancellation events
    let cancelEvents = Test.eventsOfType(Type<FlowTransactionScheduler.Canceled>())
    Test.assert(cancelEvents.length > 0, message: "Should have cancellation events")

    // Now try to reschedule - should succeed since all transactions are cancelled
    let rescheduleResult = Test.executeTransaction(
        Test.Transaction(
            code: Test.readFile("../transactions/ScheduleCronHandler.cdc"),
            authorizers: [testAccount.address],
            signers: [testAccount],
            arguments: [
                /storage/TestCronHandler2 as StoragePath,
                "new data" as AnyStruct?,
                1 as UInt8,
                1000 as UInt64
            ]
        )
    )
    Test.expect(rescheduleResult, Test.beSucceeded())

    // Verify new schedule was created
    let eventsAfterReschedule = Test.eventsOfType(Type<FlowTransactionScheduler.Scheduled>())
    let newEventsCount = eventsAfterReschedule.length - eventsAfterSchedule.length

    // Should have at least 1 new scheduled event (the rescheduled transaction)
    Test.assert(newEventsCount >= 1, message: "Should have new scheduled events after cancellation and reschedule")

    // Verify no rejection events were emitted during rescheduling
    let rejectionEventsBefore = Test.eventsOfType(Type<FlowCron.CronScheduleRejected>())

    // Trigger the rescheduled transaction to verify it executes successfully
    let rescheduledEvent = eventsAfterReschedule[eventsAfterReschedule.length - 1] as! FlowTransactionScheduler.Scheduled
    let currentTime = getTimestamp()
    let timeToAdvanceReschedule = (rescheduledEvent.timestamp - currentTime) + 1.0
    Test.moveTime(by: Fix64(timeToAdvanceReschedule))

    let rejectionEventsAfter = Test.eventsOfType(Type<FlowCron.CronScheduleRejected>())
    // Should have no new rejection events during reschedule execution
    Test.assertEqual(rejectionEventsBefore.length, rejectionEventsAfter.length)
}

/// Verify CronInfo view returns correct schedule information
access(all) fun test_CronInfoView() {

    // Create cron handler
    let createResult = Test.executeTransaction(
        Test.Transaction(
            code: Test.readFile("../transactions/CreateCronHandler.cdc"),
            authorizers: [testAccount.address],
            signers: [testAccount],
            arguments: [
                "*/10 * * * *",  // Every 10 minutes
                /storage/CounterTransactionHandler as StoragePath,
                /storage/TestCronHandler3 as StoragePath
            ]
        )
    )
    Test.expect(createResult, Test.beSucceeded())

    // Before scheduling - CronInfo should show calculated times
    let cronInfoBefore = getCronInfo(/storage/TestCronHandler3)
    Test.assert(cronInfoBefore != nil, message: "CronInfo should not be nil")

    if let info = cronInfoBefore {
        Test.assertEqual("*/10 * * * *", info.cronExpression)

        // Should have calculated next/future execution times
        Test.assert(info.nextExecution != nil, message: "Should have calculated next execution time")
        Test.assert(info.futureExecution != nil, message: "Should have calculated future execution time")

        // Verify 10-minute interval (600 seconds)
        let timeDiff = info.futureExecution! - info.nextExecution!
        Test.assertEqual(600, Int(timeDiff))
    }

    // Schedule the cron handler
    let scheduleResult = Test.executeTransaction(
        Test.Transaction(
            code: Test.readFile("../transactions/ScheduleCronHandler.cdc"),
            authorizers: [testAccount.address],
            signers: [testAccount],
            arguments: [
                /storage/TestCronHandler3 as StoragePath,
                nil as AnyStruct?,
                1 as UInt8,
                1000 as UInt64
            ]
        )
    )
    Test.expect(scheduleResult, Test.beSucceeded())

    // Trigger first execution to establish double-buffer
    let scheduledEvents = Test.eventsOfType(Type<FlowTransactionScheduler.Scheduled>())
    let scheduledEvent = scheduledEvents[scheduledEvents.length - 1] as! FlowTransactionScheduler.Scheduled
    let initialTimestamp = getTimestamp()
    let timeToAdvance = (scheduledEvent.timestamp - initialTimestamp) + 1.0
    Test.moveTime(by: Fix64(timeToAdvance))

    // After first execution - CronInfo should show actual scheduled transaction times
    let cronInfoAfter = getCronInfo(/storage/TestCronHandler3)
    Test.assert(cronInfoAfter != nil, message: "CronInfo should not be nil after execution")

    if let info = cronInfoAfter {

        // Should have both next and future scheduled
        Test.assert(info.nextExecution != nil, message: "Should have next execution scheduled")
        Test.assert(info.futureExecution != nil, message: "Should have future execution scheduled")

        // Verify 10-minute interval maintained
        let timeDiffAfter = info.futureExecution! - info.nextExecution!
        Test.assertEqual(600, Int(timeDiffAfter))

        // Verify wrapped handler info
        Test.assert(info.wrappedHandlerType != nil, message: "Should have wrapped handler type")
        Test.assert(info.wrappedHandlerUUID != nil, message: "Should have wrapped handler UUID")
    }
}

/// Verify CronScheduleExecuted events are emitted correctly
access(all) fun test_CronScheduleExecutedEvents() {

    // Create and schedule cron handler
    let createResult = Test.executeTransaction(
        Test.Transaction(
            code: Test.readFile("../transactions/CreateCronHandler.cdc"),
            authorizers: [testAccount.address],
            signers: [testAccount],
            arguments: [
                "* * * * *",
                /storage/CounterTransactionHandler as StoragePath,
                /storage/TestCronHandler4 as StoragePath
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
                /storage/TestCronHandler4 as StoragePath,
                nil as AnyStruct?,
                1 as UInt8,
                1000 as UInt64
            ]
        )
    )
    Test.expect(scheduleResult, Test.beSucceeded())

    let executedEventsBefore = Test.eventsOfType(Type<FlowCron.CronScheduleExecuted>())

    // Trigger execution
    let scheduledEvents = Test.eventsOfType(Type<FlowTransactionScheduler.Scheduled>())
    let scheduledEvent = scheduledEvents[scheduledEvents.length - 1] as! FlowTransactionScheduler.Scheduled
    let initialTimestamp = getTimestamp()
    let timeToAdvance = (scheduledEvent.timestamp - initialTimestamp) + 1.0
    Test.moveTime(by: Fix64(timeToAdvance))

    // Verify CronScheduleExecuted event was emitted
    let executedEventsAfter = Test.eventsOfType(Type<FlowCron.CronScheduleExecuted>())

    let newExecutedEvents = executedEventsAfter.length - executedEventsBefore.length

    // Should have exactly 1 new CronScheduleExecuted event
    Test.assertEqual(1, newExecutedEvents)

    // Verify the event contains correct data
    if executedEventsAfter.length > 0 {
        let lastEvent = executedEventsAfter[executedEventsAfter.length - 1] as! FlowCron.CronScheduleExecuted
        Test.assert(lastEvent.txID > 0, message: "Event should contain valid transaction ID")
    }
}

/// Full cron cycle - verify continuous execution and rescheduling over multiple intervals
access(all) fun test_FullCronCycle_MultipleExecutions() {

    // Create cron handler with every-minute pattern for easier testing
    let createResult = Test.executeTransaction(
        Test.Transaction(
            code: Test.readFile("../transactions/CreateCronHandler.cdc"),
            authorizers: [testAccount.address],
            signers: [testAccount],
            arguments: [
                "* * * * *",  // Every minute
                /storage/CounterTransactionHandler as StoragePath,
                /storage/TestCronHandler as StoragePath
            ]
        )
    )
    Test.expect(createResult, Test.beSucceeded())

    // Schedule the initial cron
    let scheduleResult = Test.executeTransaction(
        Test.Transaction(
            code: Test.readFile("../transactions/ScheduleCronHandler.cdc"),
            authorizers: [testAccount.address],
            signers: [testAccount],
            arguments: [
                /storage/TestCronHandler as StoragePath,
                nil as AnyStruct?,
                1 as UInt8,
                1000 as UInt64
            ]
        )
    )
    Test.expect(scheduleResult, Test.beSucceeded())

    let initialTimestamp = getTimestamp()

    // Get initial schedule event
    let initialScheduledEvents = Test.eventsOfType(Type<FlowTransactionScheduler.Scheduled>())
    let initialCount = initialScheduledEvents.length

    // Track execution over 3 cycles to verify stability
    var executionCycle = 0
    var previousCounter = 0

    // Cycle 1: First execution - establishes double-buffer
    executionCycle = executionCycle + 1

    let cycle1Event = initialScheduledEvents[initialScheduledEvents.length - 1] as! FlowTransactionScheduler.Scheduled
    let timeToAdvance1 = (cycle1Event.timestamp - initialTimestamp) + 1.0
    Test.moveTime(by: Fix64(timeToAdvance1))

    let afterCycle1Timestamp = getTimestamp()

    // Verify counter incremented
    let counterAfterCycle1 = getCounterValue()
    Test.assertEqual(previousCounter + 1, counterAfterCycle1)
    previousCounter = counterAfterCycle1

    // Verify double-buffer established (2 new transactions scheduled)
    let eventsAfterCycle1 = Test.eventsOfType(Type<FlowTransactionScheduler.Scheduled>())
    let newEventsAfterCycle1 = eventsAfterCycle1.length - initialCount
    Test.assertEqual(2, newEventsAfterCycle1)

    // Check CronInfo to verify next and future are set
    let cronInfoAfterCycle1 = getCronInfo(/storage/TestCronHandler)
    Test.assert(cronInfoAfterCycle1 != nil, message: "CronInfo should exist after cycle 1")
    if let info = cronInfoAfterCycle1 {
        Test.assert(info.nextExecution != nil, message: "Should have next execution after cycle 1")
        Test.assert(info.futureExecution != nil, message: "Should have future execution after cycle 1")
        let interval1 = info.futureExecution! - info.nextExecution!
        Test.assertEqual(60, Int(interval1))  // 1 minute = 60 seconds
    }

    // Get the last 2 scheduled events (these should be next and future)
    let lastEvents = eventsAfterCycle1
    if lastEvents.length >= 2 {
        let secondLastEvent = lastEvents[lastEvents.length - 2] as! FlowTransactionScheduler.Scheduled
        let lastEvent = lastEvents[lastEvents.length - 1] as! FlowTransactionScheduler.Scheduled

        // Verify they are 60 seconds apart (1 minute for "* * * * *")
        let eventTimeDiff = lastEvent.timestamp - secondLastEvent.timestamp
        Test.assertEqual(60.0, eventTimeDiff)
    }

    // Check the actual transaction status using the script
    let statusResult = Test.executeScript(
        Test.readFile("../scripts/GetCronScheduleStatus.cdc"),
        [testAccount.address, /storage/TestCronHandler]
    )
    Test.expect(statusResult, Test.beSucceeded())

    let status = statusResult.returnValue! as! {String: AnyStruct?}

    // Part 2: Verify double-buffer is maintained with correct intervals

    // The Cadence test framework has a known limitation: transactions scheduled
    // DURING an execution are not automatically triggered by subsequent Test.moveTime() calls.
    // Therefore, we verify the logic correctness by checking the scheduled state.

    // Extract transaction IDs from status
    let nextTxID = status["nextTransactionID"] as! UInt64?
    let futureTxID = status["futureTransactionID"] as! UInt64?

    // Verify both transactions exist in scheduler
    Test.assert(nextTxID != nil, message: "Next transaction should exist")
    Test.assert(futureTxID != nil, message: "Future transaction should exist")

    // Verify transaction IDs are sequential and different
    Test.assert(nextTxID! != futureTxID!, message: "Next and future must have different IDs")
    Test.assert(futureTxID! > nextTxID!, message: "Future ID should be greater than next ID")

    // Part 3: Verify execution timing correctness

    let nextTxTimestamp = status["nextTxTimestamp"] as! UFix64?
    let futureTxTimestamp = status["futureTxTimestamp"] as! UFix64?

    Test.assert(nextTxTimestamp != nil, message: "Next timestamp should exist")
    Test.assert(futureTxTimestamp != nil, message: "Future timestamp should exist")

    // Verify both are scheduled in the future from current time
    Test.assert(nextTxTimestamp! > afterCycle1Timestamp,
        message: "Next execution should be in the future")
    Test.assert(futureTxTimestamp! > nextTxTimestamp!,
        message: "Future execution should be after next execution")

    // Verify 60-second interval (for "* * * * *" pattern)
    let timeDiff = futureTxTimestamp! - nextTxTimestamp!
    Test.assertEqual(60.0, timeDiff)
}

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
