import Test

access(all) fun setup() {
    let err = Test.deployContract(
        name: "FlowCronUtils",
        path: "../contracts/FlowCronUtils.cdc",
        arguments: [],
    )
    Test.expect(err, Test.beNil())
}

/// Test 1: every-minute_basic_wildcard - "* * * * *"
/// from: 2025-01-01T12:07:05Z, expected: 2025-01-01T12:08:00Z
access(all) fun testEveryMinuteBasicWildcard() {
    let script = "import FlowCronUtils from 0x0000000000000007; access(all) fun main(): UInt64? { let spec = FlowCronUtils.parse(expression: \"* * * * *\"); if spec == nil { return nil }; return FlowCronUtils.nextTick(spec: spec!, afterUnix: 1735733225) }"
    let result = Test.executeScript(script, [])
    Test.expect(result, Test.beSucceeded())
    
    let nextTick = result.returnValue as! UInt64?
    Test.expect(nextTick, Test.not(Test.beNil()))
    let expected: UInt64 = 1735733280
    Test.expect(nextTick!, Test.equal(expected))
}

/// Test 2: top-of-hour_min0_all-hours - "0 * * * *"
/// from: 2025-01-01T12:07:00Z, expected: 2025-01-01T13:00:00Z
access(all) fun testTopOfHourMin0AllHours() {
    let script = "import FlowCronUtils from 0x0000000000000007; access(all) fun main(): UInt64? { let spec = FlowCronUtils.parse(expression: \"0 * * * *\"); if spec == nil { return nil }; return FlowCronUtils.nextTick(spec: spec!, afterUnix: 1735733220) }"
    let result = Test.executeScript(script, [])
    Test.expect(result, Test.beSucceeded())
    
    let nextTick = result.returnValue as! UInt64?
    Test.expect(nextTick, Test.not(Test.beNil()))
    let expected: UInt64 = 1735736400
    Test.expect(nextTick!, Test.equal(expected))
}

/// Test 3: midnight-daily_min0_hour0 - "0 0 * * *"
/// from: 2025-01-01T12:00:00Z, expected: 2025-01-02T00:00:00Z
access(all) fun testMidnightDailyMin0Hour0() {
    let script = "import FlowCronUtils from 0x0000000000000007; access(all) fun main(): UInt64? { let spec = FlowCronUtils.parse(expression: \"0 0 * * *\"); if spec == nil { return nil }; return FlowCronUtils.nextTick(spec: spec!, afterUnix: 1735732800) }"
    let result = Test.executeScript(script, [])
    Test.expect(result, Test.beSucceeded())
    
    let nextTick = result.returnValue as! UInt64?
    Test.expect(nextTick, Test.not(Test.beNil()))
    let expected: UInt64 = 1735776000
    Test.expect(nextTick!, Test.equal(expected))
}

/// Test 4: every-5-minutes_step_5 - "*/5 * * * *"
/// from: 2025-01-01T12:07:00Z, expected: 2025-01-01T12:10:00Z
access(all) fun testEvery5MinutesStep5() {
    let script = "import FlowCronUtils from 0x0000000000000007; access(all) fun main(): UInt64? { let spec = FlowCronUtils.parse(expression: \"*/5 * * * *\"); if spec == nil { return nil }; return FlowCronUtils.nextTick(spec: spec!, afterUnix: 1735733220) }"
    let result = Test.executeScript(script, [])
    Test.expect(result, Test.beSucceeded())
    
    let nextTick = result.returnValue as! UInt64?
    Test.expect(nextTick, Test.not(Test.beNil()))
    let expected: UInt64 = 1735733400
    Test.expect(nextTick!, Test.equal(expected))
}

/// Test 5: minute-step-range_15_25_35_45 - "15-45/10 * * * *"
/// from: 2025-01-01T12:33:00Z, expected: 2025-01-01T12:35:00Z
access(all) fun testMinuteStepRange15_25_35_45() {
    let script = "import FlowCronUtils from 0x0000000000000007; access(all) fun main(): UInt64? { let spec = FlowCronUtils.parse(expression: \"15-45/10 * * * *\"); if spec == nil { return nil }; return FlowCronUtils.nextTick(spec: spec!, afterUnix: 1735734780) }"
    let result = Test.executeScript(script, [])
    Test.expect(result, Test.beSucceeded())
    
    let nextTick = result.returnValue as! UInt64?
    Test.expect(nextTick, Test.not(Test.beNil()))
    let expected: UInt64 = 1735734900
    Test.expect(nextTick!, Test.equal(expected))
}

/// Test 6: every-3-hours_on-the-hour - "0 */3 * * *"
/// from: 2025-01-01T05:00:01Z, expected: 2025-01-01T06:00:00Z
access(all) fun testEvery3HoursOnTheHour() {
    let script = "import FlowCronUtils from 0x0000000000000007; access(all) fun main(): UInt64? { let spec = FlowCronUtils.parse(expression: \"0 */3 * * *\"); if spec == nil { return nil }; return FlowCronUtils.nextTick(spec: spec!, afterUnix: 1735707601) }"
    let result = Test.executeScript(script, [])
    Test.expect(result, Test.beSucceeded())
    
    let nextTick = result.returnValue as! UInt64?
    Test.expect(nextTick, Test.not(Test.beNil()))
    let expected: UInt64 = 1735711200
    Test.expect(nextTick!, Test.equal(expected))
}

/// Test 7: two-daily-times_09_and_17 - "0 9,17 * * *"
/// from: 2025-01-01T10:00:00Z, expected: 2025-01-01T17:00:00Z
access(all) fun testTwoDailyTimes09And17() {
    let script = "import FlowCronUtils from 0x0000000000000007; access(all) fun main(): UInt64? { let spec = FlowCronUtils.parse(expression: \"0 9,17 * * *\"); if spec == nil { return nil }; return FlowCronUtils.nextTick(spec: spec!, afterUnix: 1735725600) }"
    let result = Test.executeScript(script, [])
    Test.expect(result, Test.beSucceeded())
    
    let nextTick = result.returnValue as! UInt64?
    Test.expect(nextTick, Test.not(Test.beNil()))
    let expected: UInt64 = 1735750800
    Test.expect(nextTick!, Test.equal(expected))
}

/// Test 8: hour-range_08_to_10 - "0 8-10 * * *"
/// from: 2025-01-01T10:00:01Z, expected: 2025-01-02T08:00:00Z
access(all) fun testHourRange08To10() {
    let script = "import FlowCronUtils from 0x0000000000000007; access(all) fun main(): UInt64? { let spec = FlowCronUtils.parse(expression: \"0 8-10 * * *\"); if spec == nil { return nil }; return FlowCronUtils.nextTick(spec: spec!, afterUnix: 1735725601) }"
    let result = Test.executeScript(script, [])
    Test.expect(result, Test.beSucceeded())
    
    let nextTick = result.returnValue as! UInt64?
    Test.expect(nextTick, Test.not(Test.beNil()))
    let expected: UInt64 = 1735804800
    Test.expect(nextTick!, Test.equal(expected))
}

/// Test 9: mixed-hour_single_and_range - "0 6,14-16 * * *"
/// from: 2025-01-01T13:00:00Z, expected: 2025-01-01T14:00:00Z
access(all) fun testMixedHourSingleAndRange() {
    let script = "import FlowCronUtils from 0x0000000000000007; access(all) fun main(): UInt64? { let spec = FlowCronUtils.parse(expression: \"0 6,14-16 * * *\"); if spec == nil { return nil }; return FlowCronUtils.nextTick(spec: spec!, afterUnix: 1735736400) }"
    let result = Test.executeScript(script, [])
    Test.expect(result, Test.beSucceeded())
    
    let nextTick = result.returnValue as! UInt64?
    Test.expect(nextTick, Test.not(Test.beNil()))
    let expected: UInt64 = 1735740000
    Test.expect(nextTick!, Test.equal(expected))
}

/// Test 10: dom31_only_month_clipping - "0 0 31 * *"
/// from: 2025-04-01T00:00:00Z, expected: 2025-05-31T00:00:00Z
access(all) fun testDom31OnlyMonthClipping() {
    let script = "import FlowCronUtils from 0x0000000000000007; access(all) fun main(): UInt64? { let spec = FlowCronUtils.parse(expression: \"0 0 31 * *\"); if spec == nil { return nil }; return FlowCronUtils.nextTick(spec: spec!, afterUnix: 1743465600) }"
    let result = Test.executeScript(script, [])
    Test.expect(result, Test.beSucceeded())
    
    let nextTick = result.returnValue as! UInt64?
    Test.expect(nextTick, Test.not(Test.beNil()))
    let expected: UInt64 = 1748649600
    Test.expect(nextTick!, Test.equal(expected))
}

/// Test 11: dom30_in_30day_months_variantA - "0 0 30 4,6,9,11 *"
/// from: 2025-04-29T00:00:00Z, expected: 2025-04-30T00:00:00Z
access(all) fun testDom30In30dayMonthsVariantA() {
    let script = "import FlowCronUtils from 0x0000000000000007; access(all) fun main(): UInt64? { let spec = FlowCronUtils.parse(expression: \"0 0 30 4,6,9,11 *\"); if spec == nil { return nil }; return FlowCronUtils.nextTick(spec: spec!, afterUnix: 1745884800) }"
    let result = Test.executeScript(script, [])
    Test.expect(result, Test.beSucceeded())
    
    let nextTick = result.returnValue as! UInt64?
    Test.expect(nextTick, Test.not(Test.beNil()))
    let expected: UInt64 = 1745971200
    Test.expect(nextTick!, Test.equal(expected))
}

/// Test 12: dom30_in_30day_months_variantB - "0 0 30 4,6,9,11 *"
/// from: 2025-04-30T00:00:01Z, expected: 2025-06-30T00:00:00Z
access(all) fun testDom30In30dayMonthsVariantB() {
    let script = "import FlowCronUtils from 0x0000000000000007; access(all) fun main(): UInt64? { let spec = FlowCronUtils.parse(expression: \"0 0 30 4,6,9,11 *\"); if spec == nil { return nil }; return FlowCronUtils.nextTick(spec: spec!, afterUnix: 1745971201) }"
    let result = Test.executeScript(script, [])
    Test.expect(result, Test.beSucceeded())
    
    let nextTick = result.returnValue as! UInt64?
    Test.expect(nextTick, Test.not(Test.beNil()))
    let expected: UInt64 = 1751241600
    Test.expect(nextTick!, Test.equal(expected))
}

/// Test 13: leap_feb29_midnight_next_leap_year - "0 0 29 2 *"
/// from: 2025-01-01T00:00:00Z, expected: 2028-02-29T00:00:00Z
access(all) fun testLeapFeb29MidnightNextLeapYear() {
    let script = "import FlowCronUtils from 0x0000000000000007; access(all) fun main(): UInt64? { let spec = FlowCronUtils.parse(expression: \"0 0 29 2 *\"); if spec == nil { return nil }; return FlowCronUtils.nextTick(spec: spec!, afterUnix: 1735689600) }"
    let result = Test.executeScript(script, [])
    Test.expect(result, Test.beSucceeded())
    
    let nextTick = result.returnValue as! UInt64?
    Test.expect(nextTick, Test.not(Test.beNil()))
    let expected: UInt64 = 1835395200
    Test.expect(nextTick!, Test.equal(expected))
}

/// Test 14: feb28_variant1_nonleap_to_leap - "0 0 28 2 *"
/// from: 2024-02-27T23:59:00Z, expected: 2024-02-28T00:00:00Z
access(all) fun testFeb28Variant1NonleapToLeap() {
    let script = "import FlowCronUtils from 0x0000000000000007; access(all) fun main(): UInt64? { let spec = FlowCronUtils.parse(expression: \"0 0 28 2 *\"); if spec == nil { return nil }; return FlowCronUtils.nextTick(spec: spec!, afterUnix: 1709078340) }"
    let result = Test.executeScript(script, [])
    Test.expect(result, Test.beSucceeded())
    
    let nextTick = result.returnValue as! UInt64?
    Test.expect(nextTick, Test.not(Test.beNil()))
    let expected: UInt64 = 1709078400
    Test.expect(nextTick!, Test.equal(expected))
}

/// Test 15: feb28_variant2_leap_boundary - "0 0 28 2 *"
/// from: 2023-02-28T23:59:00Z, expected: 2024-02-28T00:00:00Z
access(all) fun testFeb28Variant2LeapBoundary() {
    let script = "import FlowCronUtils from 0x0000000000000007; access(all) fun main(): UInt64? { let spec = FlowCronUtils.parse(expression: \"0 0 28 2 *\"); if spec == nil { return nil }; return FlowCronUtils.nextTick(spec: spec!, afterUnix: 1677628740) }"
    let result = Test.executeScript(script, [])
    Test.expect(result, Test.beSucceeded())
    
    let nextTick = result.returnValue as! UInt64?
    Test.expect(nextTick, Test.not(Test.beNil()))
    let expected: UInt64 = 1709078400
    Test.expect(nextTick!, Test.equal(expected))
}

/// Test 16: dom13_or_friday_9am_caseA - "0 9 13 * 5"
/// from: 2025-06-12T08:00:00Z, expected: 2025-06-13T09:00:00Z
access(all) fun testDom13OrFriday9amCaseA() {
    let script = "import FlowCronUtils from 0x0000000000000007; access(all) fun main(): UInt64? { let spec = FlowCronUtils.parse(expression: \"0 9 13 * 5\"); if spec == nil { return nil }; return FlowCronUtils.nextTick(spec: spec!, afterUnix: 1749715200) }"
    let result = Test.executeScript(script, [])
    Test.expect(result, Test.beSucceeded())
    
    let nextTick = result.returnValue as! UInt64?
    Test.expect(nextTick, Test.not(Test.beNil()))
    let expected: UInt64 = 1749805200
    Test.expect(nextTick!, Test.equal(expected))
}

/// Test 17: dom13_or_friday_9am_caseB - "0 9 13 * 5"
/// from: 2025-09-12T10:00:00Z, expected: 2025-09-13T09:00:00Z
access(all) fun testDom13OrFriday9amCaseB() {
    let script = "import FlowCronUtils from 0x0000000000000007; access(all) fun main(): UInt64? { let spec = FlowCronUtils.parse(expression: \"0 9 13 * 5\"); if spec == nil { return nil }; return FlowCronUtils.nextTick(spec: spec!, afterUnix: 1757671200) }"
    let result = Test.executeScript(script, [])
    Test.expect(result, Test.beSucceeded())
    
    let nextTick = result.returnValue as! UInt64?
    Test.expect(nextTick, Test.not(Test.beNil()))
    let expected: UInt64 = 1757754000
    Test.expect(nextTick!, Test.equal(expected))
}

/// Test 18: mondays_only_dow_only - "0 0 * * 1"
/// from: 2025-01-07T10:00:00Z, expected: 2025-01-13T00:00:00Z
access(all) fun testMondaysOnlyDowOnly() {
    let script = "import FlowCronUtils from 0x0000000000000007; access(all) fun main(): UInt64? { let spec = FlowCronUtils.parse(expression: \"0 0 * * 1\"); if spec == nil { return nil }; return FlowCronUtils.nextTick(spec: spec!, afterUnix: 1736244000) }"
    let result = Test.executeScript(script, [])
    Test.expect(result, Test.beSucceeded())
    
    let nextTick = result.returnValue as! UInt64?
    Test.expect(nextTick, Test.not(Test.beNil()))
    let expected: UInt64 = 1736726400
    Test.expect(nextTick!, Test.equal(expected))
}

/// Test 19: first_of_month_only_dom_only - "0 0 1 * *"
/// from: 2025-01-15T00:00:00Z, expected: 2025-02-01T00:00:00Z
access(all) fun testFirstOfMonthOnlyDomOnly() {
    let script = "import FlowCronUtils from 0x0000000000000007; access(all) fun main(): UInt64? { let spec = FlowCronUtils.parse(expression: \"0 0 1 * *\"); if spec == nil { return nil }; return FlowCronUtils.nextTick(spec: spec!, afterUnix: 1736899200) }"
    let result = Test.executeScript(script, [])
    Test.expect(result, Test.beSucceeded())
    
    let nextTick = result.returnValue as! UInt64?
    Test.expect(nextTick, Test.not(Test.beNil()))
    let expected: UInt64 = 1738368000
    Test.expect(nextTick!, Test.equal(expected))
}

/// Test 20: dom31_or_monday_union_caseA - "0 0 31 * 1"
/// from: 2025-04-27T23:59:00Z, expected: 2025-04-28T00:00:00Z
access(all) fun testDom31OrMondayUnionCaseA() {
    let script = "import FlowCronUtils from 0x0000000000000007; access(all) fun main(): UInt64? { let spec = FlowCronUtils.parse(expression: \"0 0 31 * 1\"); if spec == nil { return nil }; return FlowCronUtils.nextTick(spec: spec!, afterUnix: 1745798340) }"
    let result = Test.executeScript(script, [])
    Test.expect(result, Test.beSucceeded())
    
    let nextTick = result.returnValue as! UInt64?
    Test.expect(nextTick, Test.not(Test.beNil()))
    let expected: UInt64 = 1745798400
    Test.expect(nextTick!, Test.equal(expected))
}

/// Test 21: dom31_or_monday_union_caseB - "0 0 31 * 1"
/// from: 2025-05-30T23:59:00Z, expected: 2025-05-31T00:00:00Z
access(all) fun testDom31OrMondayUnionCaseB() {
    let script = "import FlowCronUtils from 0x0000000000000007; access(all) fun main(): UInt64? { let spec = FlowCronUtils.parse(expression: \"0 0 31 * 1\"); if spec == nil { return nil }; return FlowCronUtils.nextTick(spec: spec!, afterUnix: 1748649540) }"
    let result = Test.executeScript(script, [])
    Test.expect(result, Test.beSucceeded())
    
    let nextTick = result.returnValue as! UInt64?
    Test.expect(nextTick, Test.not(Test.beNil()))
    let expected: UInt64 = 1748649600
    Test.expect(nextTick!, Test.equal(expected))
}

/// Test 22: minute_carry_30_and_00 - "*/30 * * * *"
/// from: 2025-01-01T12:59:00Z, expected: 2025-01-01T13:00:00Z
access(all) fun testMinuteCarry30And00() {
    let script = "import FlowCronUtils from 0x0000000000000007; access(all) fun main(): UInt64? { let spec = FlowCronUtils.parse(expression: \"*/30 * * * *\"); if spec == nil { return nil }; return FlowCronUtils.nextTick(spec: spec!, afterUnix: 1735736340) }"
    let result = Test.executeScript(script, [])
    Test.expect(result, Test.beSucceeded())
    
    let nextTick = result.returnValue as! UInt64?
    Test.expect(nextTick, Test.not(Test.beNil()))
    let expected: UInt64 = 1735736400
    Test.expect(nextTick!, Test.equal(expected))
}

/// Test 23: hour_carry_23_15_same_day - "15 23 * * *"
/// from: 2025-01-01T23:14:00Z, expected: 2025-01-01T23:15:00Z
access(all) fun testHourCarry2315SameDay() {
    let script = "import FlowCronUtils from 0x0000000000000007; access(all) fun main(): UInt64? { let spec = FlowCronUtils.parse(expression: \"15 23 * * *\"); if spec == nil { return nil }; return FlowCronUtils.nextTick(spec: spec!, afterUnix: 1735773240) }"
    let result = Test.executeScript(script, [])
    Test.expect(result, Test.beSucceeded())
    
    let nextTick = result.returnValue as! UInt64?
    Test.expect(nextTick, Test.not(Test.beNil()))
    let expected: UInt64 = 1735773300
    Test.expect(nextTick!, Test.equal(expected))
}

/// Test 24: hour_carry_23_15_next_day - "15 23 * * *"
/// from: 2025-01-01T23:15:00Z, expected: 2025-01-02T23:15:00Z
access(all) fun testHourCarry2315NextDay() {
    let script = "import FlowCronUtils from 0x0000000000000007; access(all) fun main(): UInt64? { let spec = FlowCronUtils.parse(expression: \"15 23 * * *\"); if spec == nil { return nil }; return FlowCronUtils.nextTick(spec: spec!, afterUnix: 1735773300) }"
    let result = Test.executeScript(script, [])
    Test.expect(result, Test.beSucceeded())
    
    let nextTick = result.returnValue as! UInt64?
    Test.expect(nextTick, Test.not(Test.beNil()))
    let expected: UInt64 = 1735859700
    Test.expect(nextTick!, Test.equal(expected))
}

/// Test 25: day_carry_end_of_month_to_next - "0 0 * * *"
/// from: 2025-01-31T23:59:00Z, expected: 2025-02-01T00:00:00Z
access(all) fun testDayCarryEndOfMonthToNext() {
    let script = "import FlowCronUtils from 0x0000000000000007; access(all) fun main(): UInt64? { let spec = FlowCronUtils.parse(expression: \"0 0 * * *\"); if spec == nil { return nil }; return FlowCronUtils.nextTick(spec: spec!, afterUnix: 1738367940) }"
    let result = Test.executeScript(script, [])
    Test.expect(result, Test.beSucceeded())
    
    let nextTick = result.returnValue as! UInt64?
    Test.expect(nextTick, Test.not(Test.beNil()))
    let expected: UInt64 = 1738368000
    Test.expect(nextTick!, Test.equal(expected))
}

/// Test 26: month_carry_dec31_to_jan1 - "0 0 1 * *"
/// from: 2024-12-31T12:00:00Z, expected: 2025-01-01T00:00:00Z
access(all) fun testMonthCarryDec31ToJan1() {
    let script = "import FlowCronUtils from 0x0000000000000007; access(all) fun main(): UInt64? { let spec = FlowCronUtils.parse(expression: \"0 0 1 * *\"); if spec == nil { return nil }; return FlowCronUtils.nextTick(spec: spec!, afterUnix: 1735646400) }"
    let result = Test.executeScript(script, [])
    Test.expect(result, Test.beSucceeded())
    
    let nextTick = result.returnValue as! UInt64?
    Test.expect(nextTick, Test.not(Test.beNil()))
    let expected: UInt64 = 1735689600
    Test.expect(nextTick!, Test.equal(expected))
}

/// Test 27: months_noon_jan_jun_dec - "0 12 * 1,6,12 *"
/// from: 2025-01-01T12:00:00Z, expected: 2025-06-01T12:00:00Z
access(all) fun testMonthsNoonJanJunDec() {
    let script = "import FlowCronUtils from 0x0000000000000007; access(all) fun main(): UInt64? { let spec = FlowCronUtils.parse(expression: \"0 12 * 1,6,12 *\"); if spec == nil { return nil }; return FlowCronUtils.nextTick(spec: spec!, afterUnix: 1735732800) }"
    let result = Test.executeScript(script, [])
    Test.expect(result, Test.beSucceeded())
    
    let nextTick = result.returnValue as! UInt64?
    Test.expect(nextTick, Test.not(Test.beNil()))
    let expected: UInt64 = 1735819200
    Test.expect(nextTick!, Test.equal(expected))
}

/// Test 28: single_day_in_feb_feb15_next_year - "0 0 15 2 *"
/// from: 2025-02-16T00:00:00Z, expected: 2026-02-15T00:00:00Z
access(all) fun testSingleDayInFebFeb15NextYear() {
    let script = "import FlowCronUtils from 0x0000000000000007; access(all) fun main(): UInt64? { let spec = FlowCronUtils.parse(expression: \"0 0 15 2 *\"); if spec == nil { return nil }; return FlowCronUtils.nextTick(spec: spec!, afterUnix: 1739664000) }"
    let result = Test.executeScript(script, [])
    Test.expect(result, Test.beSucceeded())
    
    let nextTick = result.returnValue as! UInt64?
    Test.expect(nextTick, Test.not(Test.beNil()))
    let expected: UInt64 = 1771113600
    Test.expect(nextTick!, Test.equal(expected))
}

/// Test 29: sundays_midnight_dow0 - "0 0 * * 0"
/// from: 2025-01-03T10:00:00Z, expected: 2025-01-05T00:00:00Z
access(all) fun testSundaysMidnightDow0() {
    let script = "import FlowCronUtils from 0x0000000000000007; access(all) fun main(): UInt64? { let spec = FlowCronUtils.parse(expression: \"0 0 * * 0\"); if spec == nil { return nil }; return FlowCronUtils.nextTick(spec: spec!, afterUnix: 1735898400) }"
    let result = Test.executeScript(script, [])
    Test.expect(result, Test.beSucceeded())
    
    let nextTick = result.returnValue as! UInt64?
    Test.expect(nextTick, Test.not(Test.beNil()))
    let expected: UInt64 = 1736035200
    Test.expect(nextTick!, Test.equal(expected))
}

/// Test 30: minute_steps_across_hour_boundary - "*/20 9-10 * * *"
/// from: 2025-01-01T10:40:00Z, expected: 2025-01-02T09:00:00Z
access(all) fun testMinuteStepsAcrossHourBoundary() {
    let script = "import FlowCronUtils from 0x0000000000000007; access(all) fun main(): UInt64? { let spec = FlowCronUtils.parse(expression: \"*/20 9-10 * * *\"); if spec == nil { return nil }; return FlowCronUtils.nextTick(spec: spec!, afterUnix: 1735728000) }"
    let result = Test.executeScript(script, [])
    Test.expect(result, Test.beSucceeded())
    
    let nextTick = result.returnValue as! UInt64?
    Test.expect(nextTick, Test.not(Test.beNil()))
    let expected: UInt64 = 1735808400
    Test.expect(nextTick!, Test.equal(expected))
}

/// Test 31: every_6_hours_0_6_12_18 - "0 0,6,12,18 * * *"
/// from: 2025-01-01T18:00:00Z, expected: 2025-01-02T00:00:00Z
access(all) fun testEvery6Hours061218() {
    let script = "import FlowCronUtils from 0x0000000000000007; access(all) fun main(): UInt64? { let spec = FlowCronUtils.parse(expression: \"0 0,6,12,18 * * *\"); if spec == nil { return nil }; return FlowCronUtils.nextTick(spec: spec!, afterUnix: 1735754400) }"
    let result = Test.executeScript(script, [])
    Test.expect(result, Test.beSucceeded())
    
    let nextTick = result.returnValue as! UInt64?
    Test.expect(nextTick, Test.not(Test.beNil()))
    let expected: UInt64 = 1735776000
    Test.expect(nextTick!, Test.equal(expected))
}

/// Test 32: weekdays_midnight_dow1_5 - "0 0 * * 1-5"
/// from: 2025-01-03T00:00:00Z, expected: 2025-01-06T00:00:00Z
access(all) fun testWeekdaysMidnightDow15() {
    let script = "import FlowCronUtils from 0x0000000000000007; access(all) fun main(): UInt64? { let spec = FlowCronUtils.parse(expression: \"0 0 * * 1-5\"); if spec == nil { return nil }; return FlowCronUtils.nextTick(spec: spec!, afterUnix: 1735862400) }"
    let result = Test.executeScript(script, [])
    Test.expect(result, Test.beSucceeded())
    
    let nextTick = result.returnValue as! UInt64?
    Test.expect(nextTick, Test.not(Test.beNil()))
    let expected: UInt64 = 1736121600
    Test.expect(nextTick!, Test.equal(expected))
}