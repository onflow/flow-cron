# FlowCron Emulator Testing Guide

This guide provides step-by-step commands to test the FlowCron implementation on the **Flow Emulator** using the Counter contract.

## Test Objective

Schedule a recurring transaction that executes **every minute** and increments a counter by 1. We'll verify:
- Counter increments correctly (by 1 each minute)
- Double-buffer pattern maintains 2 scheduled transactions (next + future)
- Automatic rescheduling works after each execution
- All transactions execute sequentially without rejections

## Prerequisites

Before starting, ensure you have:
- Flow CLI installed (`flow version`)
- Flow emulator ready to start

## Important: Emulator Block Time

**Critical:** The emulator MUST be started with the `--block-time 1s` flag for scheduled transactions to execute properly:

```bash
flow emulator start --block-time 1s
```

Without this flag, the emulator's Transaction Scheduler will not execute scheduled transactions.

## Step-by-Step Testing

### Step 1: Start Emulator

Start the emulator with 1-second block time:

```bash
flow emulator start --block-time 1s
```

**Keep this terminal open** - it will show logs of all transactions executing.

**Expected output:**
```
INFO[0000] ⚙️   Using service account 0xf8d6e0586b0a20c7
INFO[0000] 📜  Flow contracts FlowServiceAccount, FlowToken, FungibleToken, ...
INFO[0000] 🌱  Starting emulator server on port 3569
```

### Step 2: Deploy Contracts

In a **new terminal**, deploy all required contracts:

```bash
flow project deploy --network=emulator
```

**Expected output:**
```
Deploying 4 contracts for accounts: emulator-account

FlowCronUtils -> 0xf8d6e0586b0a20c7
FlowCron -> 0xf8d6e0586b0a20c7
Counter -> 0xf8d6e0586b0a20c7
CounterTransactionHandler -> 0xf8d6e0586b0a20c7

✅ All contracts deployed successfully
```

### Step 3: Initialize Counter Handler

Create and store the CounterTransactionHandler resource:

```bash
flow transactions send cadence/tests/mocks/transactions/InitCounterTransactionHandler.cdc \
  --network=emulator \
  --signer=emulator-account
```

**Expected output:**
```
Transaction ID: <some-hash>
Status: ✅ SEALED
```

### Step 4: Verify Initial Counter Value

Check that the counter starts at 0:

```bash
flow scripts execute cadence/tests/mocks/scripts/GetCounter.cdc \
  --network=emulator
```

**Expected output:**
```
Result: 0
```

### Step 5: Create CronHandler

Wrap the CounterTransactionHandler with a CronHandler that runs **every minute** (`* * * * *`):

```bash
flow transactions send cadence/transactions/CreateCronHandler.cdc \
  "* * * * *" \
  /storage/CounterTransactionHandler \
  /storage/CounterCronHandler \
  --network=emulator \
  --signer=emulator-account
```

**Expected output:**
```
Transaction ID: <some-hash>
Status: ✅ SEALED
```

### Step 6: Verify CronHandler Creation

Check that the CronHandler was created:

```bash
flow scripts execute cadence/scripts/GetCronInfo.cdc \
  0xf8d6e0586b0a20c7 \
  /storage/CounterCronHandler \
  --network=emulator
```

**Expected output (example):**
```json
{
  "cronExpression": "* * * * *",
  "nextExecution": 1699999999,
  "futureExecution": 1700000059,
  "wrappedHandlerType": "A.f8d6e0586b0a20c7.CounterTransactionHandler.Handler",
  "wrappedHandlerUUID": 123
}
```

### Step 7: Schedule the Initial Cron Execution

Start the cron job by scheduling the first execution:

```bash
flow transactions send cadence/transactions/ScheduleCronHandler.cdc \
  /storage/CounterCronHandler \
  nil \
  2 \
  500 \
  --network=emulator \
  --signer=emulator-account
```

**Arguments explained:**
- `/storage/CounterCronHandler` - Where the CronHandler is stored
- `nil` - No wrapped data needed for Counter
- `2` - Priority: Low (0=High, 1=Medium, 2=Low)
- `500` - Execution effort (confirmed working value)

**Expected output:**
```
Transaction ID: <some-hash>
Status: ✅ SEALED

Events:
  - A.f8d6e0586b0a20c7.FlowTransactionScheduler.Scheduled
```

### Step 8: Check Emulator Logs

In the emulator terminal, you should see logs showing the transaction was scheduled:

```
INFO[...] 📝  Transaction scheduled ID=1
```

### Step 9: Wait for First Execution

Wait approximately **60-90 seconds** for the first execution. Watch the emulator logs for:

```
INFO[...] 🔷  Executing scheduled transaction ID=1
LOG [2025-01-03 14:00:00.000 UTC] "Transaction executed (id: 1) newCount: 1"
```

Then check the counter:

```bash
flow scripts execute cadence/tests/mocks/scripts/GetCounter.cdc \
  --network=emulator
```

**Expected output:**
```
Result: 1
```

✅ **The counter incremented to 1!**

### Step 10: Verify Double-Buffer Pattern

After the first execution, check that both next and future are scheduled:

```bash
flow scripts execute cadence/scripts/GetCronScheduleStatus.cdc \
  0xf8d6e0586b0a20c7 \
  /storage/CounterCronHandler \
  --network=emulator
```

**Expected output:**
```json
{
  "cronExpression": "* * * * *",
  "nextTransactionID": 2,
  "futureTransactionID": 3,
  "nextTxStatus": 1,
  "nextTxTimestamp": "...",
  "futureTxStatus": 1,
  "futureTxTimestamp": "..."
}
```

**Key observations:**
- `nextTransactionID` and `futureTransactionID` are both present
- Both have status `1` (Scheduled)
- This confirms the double-buffer pattern is active!

### Step 11: Monitor Continuous Execution

Watch the emulator logs and check the counter every 60-90 seconds:

**Check counter:**
```bash
flow scripts execute cadence/tests/mocks/scripts/GetCounter.cdc \
  --network=emulator
```

**Check schedule:**
```bash
flow scripts execute cadence/scripts/GetCronScheduleStatus.cdc \
  0xf8d6e0586b0a20c7 \
  /storage/CounterCronHandler \
  --network=emulator
```

**Expected behavior over time:**

| Time | Counter | Next TX ID | Future TX ID | Emulator Log |
|------|---------|------------|--------------|--------------|
| Initial | 0 | 1 | null | Scheduled ID=1 |
| After 1 min | 1 | 2 | 3 | Executed ID=1, Scheduled ID=2,3 |
| After 2 min | 2 | 3 | 4 | Executed ID=2, Scheduled ID=4 |
| After 3 min | 3 | 4 | 5 | Executed ID=3, Scheduled ID=5 |
| After 4 min | 4 | 5 | 6 | Executed ID=4, Scheduled ID=6 |

**What to verify:**
1. ✅ Counter increments by exactly 1 each minute
2. ✅ Both next and future transactions are always scheduled (after first execution)
3. ✅ Transaction IDs increment sequentially (1, 2, 3, 4...)
4. ✅ No `CronScheduleRejected` events in the logs
5. ✅ All executions show in emulator logs with "newCount" incrementing

### Step 12: Verify No Rejections

After 3-4 minutes of execution, check for any rejection events. In the emulator logs, look for:

**Good (no rejections):**
```
LOG [timestamp] "Transaction executed (id: 1) newCount: 1"
LOG [timestamp] "Transaction executed (id: 2) newCount: 2"
LOG [timestamp] "Transaction executed (id: 3) newCount: 3"
```

**Bad (rejections present):**
```
EVENT A.f8d6e0586b0a20c7.FlowCron.CronScheduleRejected
```

If you see rejections, this indicates the race condition bug has returned. All executions should succeed.

### Step 13: Check Transaction Details

Verify a specific scheduled transaction:

```bash
flow scripts execute cadence/scripts/GetTransactionData.cdc \
  2 \
  --network=emulator
```

Replace `2` with any transaction ID from the schedule status.

**Expected output:**
```json
{
  "id": 2,
  "status": 1,
  "scheduledTimestamp": "..."
}
```

Status codes:
- `1` = Scheduled
- `2` = Executed
- `3` = Cancelled

### Step 14: Stop the Cron Job

When you're satisfied with testing (after 3-5 minutes), cancel all scheduled transactions:

```bash
flow transactions send cadence/transactions/CancelCronSchedule.cdc \
  /storage/CounterCronHandler \
  --network=emulator \
  --signer=emulator-account
```

**Expected output:**
```
Transaction ID: <some-hash>
Status: ✅ SEALED

Events:
  - A.f8d6e0586b0a20c7.FlowTransactionScheduler.Canceled (x2)
```

### Step 15: Verify Cancellation

Confirm all scheduled transactions were cancelled:

```bash
flow scripts execute cadence/scripts/GetCronScheduleStatus.cdc \
  0xf8d6e0586b0a20c7 \
  /storage/CounterCronHandler \
  --network=emulator
```

**Expected output:**
```json
{
  "cronExpression": "* * * * *"
}
```

The transaction ID fields should be missing or null, indicating no active scheduled transactions.

**Check final counter value:**
```bash
flow scripts execute cadence/tests/mocks/scripts/GetCounter.cdc \
  --network=emulator
```

The counter should remain at its last value (e.g., `4` if it ran for 4 minutes).

### Step 16: Verify Cancellation Removed Transactions

Try to get data for the cancelled transactions - they should return `nil`:

```bash
flow scripts execute cadence/scripts/GetTransactionData.cdc \
  5 \
  --network=emulator
```

**Expected output:**
```
Result: nil
```

This confirms the transactions were fully cancelled and removed from the scheduler.

## Advanced Testing

### Test: Restart After Cancellation

After cancelling, you can restart the cron job:

```bash
flow transactions send cadence/transactions/ScheduleCronHandler.cdc \
  /storage/CounterCronHandler \
  nil \
  2 \
  500 \
  --network=emulator \
  --signer=emulator-account
```

**Verify:** The counter should continue incrementing from its current value.

### Test: Multiple Concurrent Cron Jobs

Create additional CronHandlers with different handlers:

**Note:** This requires creating additional TransactionHandler implementations. The Counter example only supports one concurrent cron.
