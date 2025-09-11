Each section describes a test case.  

The goal: given the **CronSpec bitmasks** and a starting `from` timestamp, the function `nextTick(spec, from)` must return the `expected` timestamp (strictly greater than `from`).  
Time basis is Flow chain time (UTC-like, no DST). Minute resolution; the implementation rounds `from` up to the next minute boundary internally.

## every-minute_basic_wildcard
- cron: `* * * * *`
- CronSpec:
  - minMask (hex): `0xfffffffffffffff`
  - minMask (list): `[0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59]`
  - hourMask (hex): `0xffffff`
  - hourMask (list): `[0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23]`
  - domMask (hex): `0xfffffffe`
  - domMask (list): `[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31]`
  - monthMask (hex): `0x1ffe`
  - monthMask (list): `[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]`
  - dowMask (hex): `0x7f`
  - dowMask (list): `[0, 1, 2, 3, 4, 5, 6]`
  - domIsStar: `true`
  - dowIsStar: `true`
- from: `2025-01-01T12:07:05Z`
- expected: `2025-01-01T12:08:00Z`

## top-of-hour_min0_all-hours
- cron: `0 * * * *`
- CronSpec:
  - minMask (hex): `0x1`
  - minMask (list): `[0]`
  - hourMask (hex): `0xffffff`
  - hourMask (list): `[0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23]`
  - domMask (hex): `0xfffffffe`
  - domMask (list): `[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31]`
  - monthMask (hex): `0x1ffe`
  - monthMask (list): `[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]`
  - dowMask (hex): `0x7f`
  - dowMask (list): `[0, 1, 2, 3, 4, 5, 6]`
  - domIsStar: `true`
  - dowIsStar: `true`
- from: `2025-01-01T12:07:00Z`
- expected: `2025-01-01T13:00:00Z`

## midnight-daily_min0_hour0
- cron: `0 0 * * *`
- CronSpec:
  - minMask (hex): `0x1`
  - minMask (list): `[0]`
  - hourMask (hex): `0x1`
  - hourMask (list): `[0]`
  - domMask (hex): `0xfffffffe`
  - domMask (list): `[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31]`
  - monthMask (hex): `0x1ffe`
  - monthMask (list): `[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]`
  - dowMask (hex): `0x7f`
  - dowMask (list): `[0, 1, 2, 3, 4, 5, 6]`
  - domIsStar: `true`
  - dowIsStar: `true`
- from: `2025-01-01T12:00:00Z`
- expected: `2025-01-02T00:00:00Z`

## every-5-minutes_step_5
- cron: `*/5 * * * *`
- CronSpec:
  - minMask (hex): `0x84210842108421`
  - minMask (list): `[0, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55]`
  - hourMask (hex): `0xffffff`
  - hourMask (list): `[0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23]`
  - domMask (hex): `0xfffffffe`
  - domMask (list): `[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31]`
  - monthMask (hex): `0x1ffe`
  - monthMask (list): `[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]`
  - dowMask (hex): `0x7f`
  - dowMask (list): `[0, 1, 2, 3, 4, 5, 6]`
  - domIsStar: `true`
  - dowIsStar: `true`
- from: `2025-01-01T12:07:00Z`
- expected: `2025-01-01T12:10:00Z`

## minute-step-range_15_25_35_45
- cron: `15-45/10 * * * *`
- CronSpec:
  - minMask (hex): `0x200802008000`
  - minMask (list): `[15, 25, 35, 45]`
  - hourMask (hex): `0xffffff`
  - hourMask (list): `[0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23]`
  - domMask (hex): `0xfffffffe`
  - domMask (list): `[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31]`
  - monthMask (hex): `0x1ffe`
  - monthMask (list): `[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]`
  - dowMask (hex): `0x7f`
  - dowMask (list): `[0, 1, 2, 3, 4, 5, 6]`
  - domIsStar: `true`
  - dowIsStar: `true`
- from: `2025-01-01T12:33:00Z`
- expected: `2025-01-01T12:35:00Z`

## every-3-hours_on-the-hour
- cron: `0 */3 * * *`
- CronSpec:
  - minMask (hex): `0x1`
  - minMask (list): `[0]`
  - hourMask (hex): `0x249249`
  - hourMask (list): `[0, 3, 6, 9, 12, 15, 18, 21]`
  - domMask (hex): `0xfffffffe`
  - domMask (list): `[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31]`
  - monthMask (hex): `0x1ffe`
  - monthMask (list): `[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]`
  - dowMask (hex): `0x7f`
  - dowMask (list): `[0, 1, 2, 3, 4, 5, 6]`
  - domIsStar: `true`
  - dowIsStar: `true`
- from: `2025-01-01T05:00:01Z`
- expected: `2025-01-01T06:00:00Z`

## two-daily-times_09_and_17
- cron: `0 9,17 * * *`
- CronSpec:
  - minMask (hex): `0x1`
  - minMask (list): `[0]`
  - hourMask (hex): `0x20200`
  - hourMask (list): `[9, 17]`
  - domMask (hex): `0xfffffffe`
  - domMask (list): `[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31]`
  - monthMask (hex): `0x1ffe`
  - monthMask (list): `[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]`
  - dowMask (hex): `0x7f`
  - dowMask (list): `[0, 1, 2, 3, 4, 5, 6]`
  - domIsStar: `true`
  - dowIsStar: `true`
- from: `2025-01-01T10:00:00Z`
- expected: `2025-01-01T17:00:00Z`

## hour-range_08_to_10
- cron: `0 8-10 * * *`
- CronSpec:
  - minMask (hex): `0x1`
  - minMask (list): `[0]`
  - hourMask (hex): `0x700`
  - hourMask (list): `[8, 9, 10]`
  - domMask (hex): `0xfffffffe`
  - domMask (list): `[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31]`
  - monthMask (hex): `0x1ffe`
  - monthMask (list): `[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]`
  - dowMask (hex): `0x7f`
  - dowMask (list): `[0, 1, 2, 3, 4, 5, 6]`
  - domIsStar: `true`
  - dowIsStar: `true`
- from: `2025-01-01T10:00:01Z`
- expected: `2025-01-02T08:00:00Z`

## mixed-hour_single_and_range
- cron: `0 6,14-16 * * *`
- CronSpec:
  - minMask (hex): `0x1`
  - minMask (list): `[0]`
  - hourMask (hex): `0x1c040`
  - hourMask (list): `[6, 14, 15, 16]`
  - domMask (hex): `0xfffffffe`
  - domMask (list): `[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31]`
  - monthMask (hex): `0x1ffe`
  - monthMask (list): `[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]`
  - dowMask (hex): `0x7f`
  - dowMask (list): `[0, 1, 2, 3, 4, 5, 6]`
  - domIsStar: `true`
  - dowIsStar: `true`
- from: `2025-01-01T13:00:00Z`
- expected: `2025-01-01T14:00:00Z`

## dom31_only_month_clipping
- cron: `0 0 31 * *`
- CronSpec:
  - minMask (hex): `0x1`
  - minMask (list): `[0]`
  - hourMask (hex): `0x1`
  - hourMask (list): `[0]`
  - domMask (hex): `0x80000000`
  - domMask (list): `[31]`
  - monthMask (hex): `0x1ffe`
  - monthMask (list): `[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]`
  - dowMask (hex): `0x7f`
  - dowMask (list): `[0, 1, 2, 3, 4, 5, 6]`
  - domIsStar: `false`
  - dowIsStar: `true`
- from: `2025-04-01T00:00:00Z`
- expected: `2025-05-31T00:00:00Z`

## dom30_in_30day_months_variantA
- cron: `0 0 30 4,6,9,11 *`
- CronSpec:
  - minMask (hex): `0x1`
  - minMask (list): `[0]`
  - hourMask (hex): `0x1`
  - hourMask (list): `[0]`
  - domMask (hex): `0x40000000`
  - domMask (list): `[30]`
  - monthMask (hex): `0xa50`  *(bits 4,6,9,11)*
  - monthMask (list): `[4, 6, 9, 11]`
  - dowMask (hex): `0x7f`
  - dowMask (list): `[0, 1, 2, 3, 4, 5, 6]`
  - domIsStar: `false`
  - dowIsStar: `true`
- from: `2025-04-29T00:00:00Z`
- expected: `2025-04-30T00:00:00Z`

## dom30_in_30day_months_variantB
- cron: `0 0 30 4,6,9,11 *`
- CronSpec:
  - minMask (hex): `0x1`
  - minMask (list): `[0]`
  - hourMask (hex): `0x1`
  - hourMask (list): `[0]`
  - domMask (hex): `0x40000000`
  - domMask (list): `[30]`
  - monthMask (hex): `0xa50`
  - monthMask (list): `[4, 6, 9, 11]`
  - dowMask (hex): `0x7f`
  - dowMask (list): `[0, 1, 2, 3, 4, 5, 6]`
  - domIsStar: `false`
  - dowIsStar: `true`
- from: `2025-04-30T00:00:01Z`
- expected: `2025-06-30T00:00:00Z`

## leap_feb29_midnight_next_leap_year
- cron: `0 0 29 2 *`
- CronSpec:
  - minMask (hex): `0x1`
  - minMask (list): `[0]`
  - hourMask (hex): `0x1`
  - hourMask (list): `[0]`
  - domMask (hex): `0x20000000`
  - domMask (list): `[29]`
  - monthMask (hex): `0x4`
  - monthMask (list): `[2]`
  - dowMask (hex): `0x7f`
  - dowMask (list): `[0, 1, 2, 3, 4, 5, 6]`
  - domIsStar: `false`
  - dowIsStar: `true`
- from: `2025-01-01T00:00:00Z`
- expected: `2028-02-29T00:00:00Z`

## feb28_variant1_nonleap_to_leap
- cron: `0 0 28 2 *`
- CronSpec:
  - minMask (hex): `0x1`
  - minMask (list): `[0]`
  - hourMask (hex): `0x1`
  - hourMask (list): `[0]`
  - domMask (hex): `0x10000000`
  - domMask (list): `[28]`
  - monthMask (hex): `0x4`
  - monthMask (list): `[2]`
  - dowMask (hex): `0x7f`
  - dowMask (list): `[0, 1, 2, 3, 4, 5, 6]`
  - domIsStar: `false`
  - dowIsStar: `true`
- from: `2024-02-27T23:59:00Z`
- expected: `2024-02-28T00:00:00Z`

## feb28_variant2_leap_boundary
- cron: `0 0 28 2 *`
- CronSpec:
  - minMask (hex): `0x1`
  - minMask (list): `[0]`
  - hourMask (hex): `0x1`
  - hourMask (list): `[0]`
  - domMask (hex): `0x10000000`
  - domMask (list): `[28]`
  - monthMask (hex): `0x4`
  - monthMask (list): `[2]`
  - dowMask (hex): `0x7f`
  - dowMask (list): `[0, 1, 2, 3, 4, 5, 6]`
  - domIsStar: `false`
  - dowIsStar: `true`
- from: `2023-02-28T23:59:00Z`
- expected: `2024-02-28T00:00:00Z`

## dom13_or_friday_9am_caseA
- cron: `0 9 13 * 5`
- CronSpec:
  - minMask (hex): `0x1`
  - minMask (list): `[0]`
  - hourMask (hex): `0x200`
  - hourMask (list): `[9]`
  - domMask (hex): `0x2000`
  - domMask (list): `[13]`
  - monthMask (hex): `0x1ffe`
  - monthMask (list): `[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]`
  - dowMask (hex): `0x20`
  - dowMask (list): `[5]`
  - domIsStar: `false`
  - dowIsStar: `false`
- from: `2025-06-12T08:00:00Z`
- expected: `2025-06-13T09:00:00Z`

## dom13_or_friday_9am_caseB
- cron: `0 9 13 * 5`
- CronSpec:
  - minMask (hex): `0x1`
  - minMask (list): `[0]`
  - hourMask (hex): `0x200`
  - hourMask (list): `[9]`
  - domMask (hex): `0x2000`
  - domMask (list): `[13]`
  - monthMask (hex): `0x1ffe`
  - monthMask (list): `[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]`
  - dowMask (hex): `0x20`
  - dowMask (list): `[5]`
  - domIsStar: `false`
  - dowIsStar: `false`
- from: `2025-09-12T10:00:00Z`
- expected: `2025-09-13T09:00:00Z`

## mondays_only_dow_only
- cron: `0 0 * * 1`
- CronSpec:
  - minMask (hex): `0x1`
  - minMask (list): `[0]`
  - hourMask (hex): `0x1`
  - hourMask (list): `[0]`
  - domMask (hex): `0xfffffffe`
  - domMask (list): `[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31]`
  - monthMask (hex): `0x1ffe`
  - monthMask (list): `[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]`
  - dowMask (hex): `0x2`
  - dowMask (list): `[1]`
  - domIsStar: `true`
  - dowIsStar: `false`
- from: `2025-01-07T10:00:00Z`
- expected: `2025-01-13T00:00:00Z`

## first_of_month_only_dom_only
- cron: `0 0 1 * *`
- CronSpec:
  - minMask (hex): `0x1`
  - minMask (list): `[0]`
  - hourMask (hex): `0x1`
  - hourMask (list): `[0]`
  - domMask (hex): `0x2`
  - domMask (list): `[1]`
  - monthMask (hex): `0x1ffe`
  - monthMask (list): `[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]`
  - dowMask (hex): `0x7f`
  - dowMask (list): `[0, 1, 2, 3, 4, 5, 6]`
  - domIsStar: `false`
  - dowIsStar: `true`
- from: `2025-01-15T00:00:00Z`
- expected: `2025-02-01T00:00:00Z`

## dom31_or_monday_union_caseA
- cron: `0 0 31 * 1`
- CronSpec:
  - minMask (hex): `0x1`
  - minMask (list): `[0]`
  - hourMask (hex): `0x1`
  - hourMask (list): `[0]`
  - domMask (hex): `0x80000000`
  - domMask (list): `[31]`
  - monthMask (hex): `0x1ffe`
  - monthMask (list): `[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]`
  - dowMask (hex): `0x2`
  - dowMask (list): `[1]`
  - domIsStar: `false`
  - dowIsStar: `false`
- from: `2025-04-27T23:59:00Z`
- expected: `2025-04-28T00:00:00Z`

## dom31_or_monday_union_caseB
- cron: `0 0 31 * 1`
- CronSpec:
  - minMask (hex): `0x1`
  - minMask (list): `[0]`
  - hourMask (hex): `0x1`
  - hourMask (list): `[0]`
  - domMask (hex): `0x80000000`
  - domMask (list): `[31]`
  - monthMask (hex): `0x1ffe`
  - monthMask (list): `[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]`
  - dowMask (hex): `0x2`
  - dowMask (list): `[1]`
  - domIsStar: `false`
  - dowIsStar: `false`
- from: `2025-05-30T23:59:00Z`
- expected: `2025-05-31T00:00:00Z`

## minute_carry_30_and_00
- cron: `*/30 * * * *`
- CronSpec:
  - minMask (hex): `0x40000001`
  - minMask (list): `[0, 30]`
  - hourMask (hex): `0xffffff`
  - hourMask (list): `[0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23]`
  - domMask (hex): `0xfffffffe`
  - domMask (list): `[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31]`
  - monthMask (hex): `0x1ffe`
  - monthMask (list): `[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]`
  - dowMask (hex): `0x7f`
  - dowMask (list): `[0, 1, 2, 3, 4, 5, 6]`
  - domIsStar: `true`
  - dowIsStar: `true`
- from: `2025-01-01T12:59:00Z`
- expected: `2025-01-01T13:00:00Z`

## hour_carry_23_15_same_day
- cron: `15 23 * * *`
- CronSpec:
  - minMask (hex): `0x8000`
  - minMask (list): `[15]`
  - hourMask (hex): `0x800000`
  - hourMask (list): `[23]`
  - domMask (hex): `0xfffffffe`
  - domMask (list): `[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31]`
  - monthMask (hex): `0x1ffe`
  - monthMask (list): `[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]`
  - dowMask (hex): `0x7f`
  - dowMask (list): `[0, 1, 2, 3, 4, 5, 6]`
  - domIsStar: `true`
  - dowIsStar: `true`
- from: `2025-01-01T23:14:00Z`
- expected: `2025-01-01T23:15:00Z`

## hour_carry_23_15_next_day
- cron: `15 23 * * *`
- CronSpec:
  - minMask (hex): `0x8000`
  - minMask (list): `[15]`
  - hourMask (hex): `0x800000`
  - hourMask (list): `[23]`
  - domMask (hex): `0xfffffffe`
  - domMask (list): `[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31]`
  - monthMask (hex): `0x1ffe`
  - monthMask (list): `[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]`
  - dowMask (hex): `0x7f`
  - dowMask (list): `[0, 1, 2, 3, 4, 5, 6]`
  - domIsStar: `true`
  - dowIsStar: `true`
- from: `2025-01-01T23:15:00Z`
- expected: `2025-01-02T23:15:00Z`

## day_carry_end_of_month_to_next
- cron: `0 0 * * *`
- CronSpec:
  - minMask (hex): `0x1`
  - minMask (list): `[0]`
  - hourMask (hex): `0x1`
  - hourMask (list): `[0]`
  - domMask (hex): `0xfffffffe`
  - domMask (list): `[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31]`
  - monthMask (hex): `0x1ffe`
  - monthMask (list): `[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]`
  - dowMask (hex): `0x7f`
  - dowMask (list): `[0, 1, 2, 3, 4, 5, 6]`
  - domIsStar: `true`
  - dowIsStar: `true`
- from: `2025-01-31T23:59:00Z`
- expected: `2025-02-01T00:00:00Z`

## month_carry_dec31_to_jan1
- cron: `0 0 1 * *`
- CronSpec:
  - minMask (hex): `0x1`
  - minMask (list): `[0]`
  - hourMask (hex): `0x1`
  - hourMask (list): `[0]`
  - domMask (hex): `0x2`
  - domMask (list): `[1]`
  - monthMask (hex): `0x1ffe`
  - monthMask (list): `[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]`
  - dowMask (hex): `0x7f`
  - dowMask (list): `[0, 1, 2, 3, 4, 5, 6]`
  - domIsStar: `false`
  - dowIsStar: `true`
- from: `2024-12-31T12:00:00Z`
- expected: `2025-01-01T00:00:00Z`

## months_noon_jan_jun_dec
- cron: `0 12 * 1,6,12 *`
- CronSpec:
  - minMask (hex): `0x1`
  - minMask (list): `[0]`
  - hourMask (hex): `0x1000`
  - hourMask (list): `[12]`
  - domMask (hex): `0xfffffffe`
  - domMask (list): `[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31]`
  - monthMask (hex): `0x1042`  *(bits 1,6,12)*
  - monthMask (list): `[1, 6, 12]`
  - dowMask (hex): `0x7f`
  - dowMask (list): `[0, 1, 2, 3, 4, 5, 6]`
  - domIsStar: `true`
  - dowIsStar: `true`
- from: `2025-01-01T12:00:00Z`
- expected: `2025-01-02T12:00:00Z`

## single_day_in_feb_feb15_next_year
- cron: `0 0 15 2 *`
- CronSpec:
  - minMask (hex): `0x1`
  - minMask (list): `[0]`
  - hourMask (hex): `0x1`
  - hourMask (list): `[0]`
  - domMask (hex): `0x8000`
  - domMask (list): `[15]`
  - monthMask (hex): `0x4`
  - monthMask (list): `[2]`
  - dowMask (hex): `0x7f`
  - dowMask (list): `[0, 1, 2, 3, 4, 5, 6]`
  - domIsStar: `false`
  - dowIsStar: `true`
- from: `2025-02-16T00:00:00Z`
- expected: `2026-02-15T00:00:00Z`

## sundays_midnight_dow0
- cron: `0 0 * * 0`
- CronSpec:
  - minMask (hex): `0x1`
  - minMask (list): `[0]`
  - hourMask (hex): `0x1`
  - hourMask (list): `[0]`
  - domMask (hex): `0xfffffffe`
  - domMask (list): `[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31]`
  - monthMask (hex): `0x1ffe`
  - monthMask (list): `[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]`
  - dowMask (hex): `0x1`
  - dowMask (list): `[0]`
  - domIsStar: `true`
  - dowIsStar: `false`
- from: `2025-01-03T10:00:00Z`
- expected: `2025-01-05T00:00:00Z`

## minute_steps_across_hour_boundary
- cron: `*/20 9-10 * * *`
- CronSpec:
  - minMask (hex): `0x1001001001`
  - minMask (list): `[0, 20, 40]`
  - hourMask (hex): `0x600`
  - hourMask (list): `[9, 10]`
  - domMask (hex): `0xfffffffe`
  - domMask (list): `[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31]`
  - monthMask (hex): `0x1ffe`
  - monthMask (list): `[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]`
  - dowMask (hex): `0x7f`
  - dowMask (list): `[0, 1, 2, 3, 4, 5, 6]`
  - domIsStar: `true`
  - dowIsStar: `true`
- from: `2025-01-01T10:40:00Z`
- expected: `2025-01-02T09:00:00Z`

## every_6_hours_0_6_12_18
- cron: `0 0,6,12,18 * * *`
- CronSpec:
  - minMask (hex): `0x1`
  - minMask (list): `[0]`
  - hourMask (hex): `0x44041`
  - hourMask (list): `[0, 6, 12, 18]`
  - domMask (hex): `0xfffffffe`
  - domMask (list): `[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31]`
  - monthMask (hex): `0x1ffe`
  - monthMask (list): `[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]`
  - dowMask (hex): `0x7f`
  - dowMask (list): `[0, 1, 2, 3, 4, 5, 6]`
  - domIsStar: `true`
  - dowIsStar: `true`
- from: `2025-01-01T18:00:00Z`
- expected: `2025-01-02T00:00:00Z`

## weekdays_midnight_dow1_5
- cron: `0 0 * * 1-5`
- CronSpec:
  - minMask (hex): `0x1`
  - minMask (list): `[0]`
  - hourMask (hex): `0x1`
  - hourMask (list): `[0]`
  - domMask (hex): `0xfffffffe`
  - domMask (list): `[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31]`
  - monthMask (hex): `0x1ffe`
  - monthMask (list): `[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]`
  - dowMask (hex): `0x3e`
  - dowMask (list): `[1, 2, 3, 4, 5]`
  - domIsStar: `true`
  - dowIsStar: `false`
- from: `2025-01-03T00:00:00Z`
- expected: `2025-01-06T00:00:00Z`