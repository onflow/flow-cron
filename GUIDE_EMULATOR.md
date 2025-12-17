# FlowCron Emulator Testing Guide

This guide provides step-by-step commands to test the FlowCron implementation on the **Flow Emulator** using the Counter contract.

## Test Objective

Schedule a recurring transaction that executes **every minute** and increments a counter by 1. We'll verify:

- Counter increments correctly (by 1 each minute)
- Keeper/Executor architecture works correctly
- Automatic rescheduling works after each keeper execution
- All transactions execute without rejections

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

```text
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

```text
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

```text
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

```text
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

```text
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
  "cronSpec": { ... },
  "nextScheduledKeeperID": null,
  "nextScheduledExecutorID": null,
  "wrappedHandlerType": "A.f8d6e0586b0a20c7.CounterTransactionHandler.Handler",
  "wrappedHandlerUUID": 123
}
```

### Step 7: Schedule the Initial Cron Execution

Start the cron job by scheduling the first execution (both executor and keeper):

```bash
flow transactions send cadence/transactions/ScheduleCronHandler.cdc \
  /storage/CounterCronHandler \
  nil \
  2 \
  500 \
  2500 \
  --network=emulator \
  --signer=emulator-account
```

**Arguments explained:**

- `/storage/CounterCronHandler` - Where the CronHandler is stored
- `nil` - No wrapped data needed for Counter
- `2` - Priority: Low (0=High, 1=Medium, 2=Low)
- `500` - Executor execution effort
- `2500` - Keeper execution effort (keeper does more work scheduling next cycle)

**Expected output:**

```text
Transaction ID: <some-hash>
Status: ✅ SEALED

Events:
  - A.f8d6e0586b0a20c7.FlowTransactionScheduler.Scheduled (x2)
```

Note: Two transactions are scheduled (executor + keeper for first tick).

### Step 8: Check Emulator Logs

In the emulator terminal, you should see logs showing transactions were scheduled:

```text
INFO[...] 📝  Transaction scheduled ID=0
INFO[...] 📝  Transaction scheduled ID=1
```

### Step 9: Wait for First Execution

Wait approximately **60-90 seconds** for the first execution. Watch the emulator logs for:

```text
INFO[...] 🔷  Executing scheduled transaction ID=0
LOG [timestamp] "Transaction executed (id: 0) newCount: 1"
INFO[...] 🔷  Executing scheduled transaction ID=1
```

The executor (ID=0) runs your code, the keeper (ID=1) schedules the next cycle.

Then check the counter:

```bash
flow scripts execute cadence/tests/mocks/scripts/GetCounter.cdc \
  --network=emulator
```

**Expected output:**

```text
Result: 1
```

✅ **The counter incremented to 1!**

### Step 10: Verify Keeper/Executor Pattern

After the first execution, check that the keeper scheduled the next cycle:

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
  "nextScheduledExecutorID": 2,
  "nextScheduledKeeperID": 3,
  "executorTxStatus": 1,
  "executorTxTimestamp": "...",
  "keeperTxStatus": 1,
  "keeperTxTimestamp": "..."
}
```

**Key observations:**

- `nextScheduledExecutorID` shows the next executor transaction (runs user code)
- `nextScheduledKeeperID` shows the next keeper transaction (schedules next cycle)
- Status `1` means Scheduled
- The keeper already scheduled the next executor + keeper pair

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

| Time | Counter | Events in Log |
|------|---------|---------------|
| Initial | 0 | Scheduled executor + keeper |
| After 1 min | 1 | `CronExecutorExecuted`, `CronKeeperExecuted` |
| After 2 min | 2 | `CronExecutorExecuted`, `CronKeeperExecuted` |
| After 3 min | 3 | `CronExecutorExecuted`, `CronKeeperExecuted` |

**What to verify:**

1. ✅ Counter increments by exactly 1 each minute
2. ✅ `CronKeeperExecuted` events show `nextExecutorTxID` and `nextKeeperTxID`
3. ✅ `CronExecutorExecuted` events confirm user code ran
4. ✅ No `CronScheduleRejected` events in the logs

### Step 12: Verify No Rejections

After 3-4 minutes of execution, check for any rejection events. In the emulator logs, look for:

**Good (no rejections):**

```text
EVENT CronExecutorExecuted txID=2
EVENT CronKeeperExecuted txID=3 nextExecutorTxID=4 nextKeeperTxID=5
```

**Bad (rejections present):**

```text
EVENT CronScheduleRejected txID=...
```

If you see rejections, this indicates a duplicate keeper tried to execute.

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

When you're satisfied with testing (after 3-5 minutes), cancel the scheduled transactions:

```bash
flow transactions send cadence/transactions/CancelCronSchedule.cdc \
  /storage/CounterCronHandler \
  --network=emulator \
  --signer=emulator-account
```

**Expected output:**

```text
Transaction ID: <some-hash>
Status: ✅ SEALED

Events:
  - A.f8d6e0586b0a20c7.FlowTransactionScheduler.Canceled (x2)

Logs:
  - "Cancelled 2 transaction(s)"
```

This cancels both the executor and keeper transactions, completely stopping the cron job.

### Step 15: Verify Cancellation

Confirm the transactions were cancelled:

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
  "nextScheduledExecutorID": null,
  "nextScheduledKeeperID": null,
  "executorTxStatus": null,
  "executorTxTimestamp": null,
  "keeperTxStatus": null,
  "keeperTxTimestamp": null
}
```

Both `nextScheduledExecutorID` and `nextScheduledKeeperID` are null, indicating the cron job is fully stopped.

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

```text
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
  2500 \
  --network=emulator \
  --signer=emulator-account
```

**Verify:** The counter should continue incrementing from its current value.

### Test: Multiple Concurrent Cron Jobs

Create additional CronHandlers with different handlers:

**Note:** This requires creating additional TransactionHandler implementations. The Counter example only supports one concurrent cron.
