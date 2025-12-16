# FlowCron TESTNET Testing Guide

This guide provides step-by-step commands to fully test the FlowCron implementation on **Flow TESTNET** using the Counter contract.

## Test Objective

Schedule a recurring transaction that executes **every minute** and increments a counter by 1. We'll verify:

- Counter increments correctly (by 1 each minute)
- Keeper/Executor architecture works correctly
- Automatic rescheduling works after each keeper execution
- All transactions execute without rejections

## Prerequisites

Before starting, ensure you have:

- Flow CLI installed (`flow version`)
- TESTNET account with FLOW tokens (use faucet: https://testnet-faucet.onflow.org/)
- Account configured in flow.json

## Step-by-Step Testing

### Step 1: Setup TESTNET Account

Ensure your TESTNET account is configured in `flow.json` and has sufficient FLOW tokens. You'll need tokens for:

- Contract deployment fees
- Transaction execution fees for the cron job

Get TESTNET tokens from: https://testnet-faucet.onflow.org/

### Step 2: Deploy Contracts

Deploy all required contracts to TESTNET:

```bash
flow project deploy --network=testnet
```

**Expected output:**

```text
Deploying 4 contracts for accounts: testnet-account

FlowCronUtils -> 0x...
FlowCron -> 0x...
Counter -> 0x...
CounterTransactionHandler -> 0x...

✅ All contracts deployed successfully
```

### Step 3: Initialize Counter Handler

Create and store the CounterTransactionHandler resource:

```bash
flow transactions send cadence/tests/mocks/transactions/InitCounterTransactionHandler.cdc \
  --network=testnet \
  --signer=testnet-account
```

Replace `testnet-account` with your account name from flow.json.

**Expected output:**

```text
Transaction ID: <some-hash>
Status: ✅ SEALED
```

### Step 4: Verify Initial Counter Value

Check that the counter starts at 0:

```bash
flow scripts execute cadence/tests/mocks/scripts/GetCounter.cdc \
  --network=testnet
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
  --network=testnet \
  --signer=testnet-account
```

**Expected output:**

```text
Transaction ID: <some-hash>
Status: ✅ SEALED
```

### Step 6: Verify CronHandler Creation

Check that the CronHandler was created with correct metadata:

```bash
flow scripts execute cadence/scripts/GetCronInfo.cdc \
  <YOUR_TESTNET_ADDRESS> \
  /storage/CounterCronHandler \
  --network=testnet
```

Replace `<YOUR_TESTNET_ADDRESS>` with your account address (e.g., `0x1234567890abcdef`).

**Expected output (example):**

```json
{
  "cronExpression": "* * * * *",
  "cronSpec": {
    "minMask": "18446744073709551615",
    "hourMask": "16777215",
    "domMask": "4294967294",
    "monthMask": "8190",
    "dowMask": "127",
    "domIsStar": true,
    "dowIsStar": true
  },
  "nextScheduledKeeperID": null,
  "nextScheduledExecutorID": null,
  "wrappedHandlerType": "A.0000000000000007.CounterTransactionHandler.Handler",
  "wrappedHandlerUUID": 123
}
```

**Key observations:**

- `cronExpression` is `* * * * *` (every minute)
- `nextScheduledKeeperID` and `nextScheduledExecutorID` are `null` (no active schedule yet)

### Step 7: Schedule the Initial Cron Execution

Start the cron job by scheduling the first execution (both executor and keeper):

```bash
flow transactions send cadence/transactions/ScheduleCronHandler.cdc \
  /storage/CounterCronHandler \
  nil \
  2 \
  500 \
  --network=testnet \
  --signer=testnet-account
```

**Arguments explained:**

- `/storage/CounterCronHandler` - Where the CronHandler is stored
- `nil` - No wrapped data needed for Counter
- `2` - Priority: Low (0=High, 1=Medium, 2=Low)
- `500` - Execution effort (confirmed working value)

**Expected output:**

```text
Transaction ID: <some-hash>
Status: ✅ SEALED

Events:
  - A.<address>.FlowTransactionScheduler.Scheduled (x2)
```

Note: Two transactions are scheduled (executor + keeper for first tick).

### Step 8: Verify Schedule Status

Check that the keeper transaction is scheduled:

```bash
flow scripts execute cadence/scripts/GetCronScheduleStatus.cdc \
  <YOUR_TESTNET_ADDRESS> \
  /storage/CounterCronHandler \
  --network=testnet
```

**Expected output:**

```json
{
  "cronExpression": "* * * * *",
  "nextScheduledExecutorID": 0,
  "nextScheduledKeeperID": 1,
  "executorTxStatus": 1,
  "executorTxTimestamp": "1699999999.00000000",
  "keeperTxStatus": 1,
  "keeperTxTimestamp": "1699999999.00000000"
}
```

**Key observations:**

- `nextScheduledExecutorID` shows the executor transaction ID (runs user code)
- `nextScheduledKeeperID` shows the keeper transaction ID (schedules next cycle)
- Both have `status` = `1` (Scheduled)

### Step 9: Wait for First Execution

Wait approximately **60-90 seconds** for the first execution. The scheduler will:

1. Execute the Executor transaction (runs your user code - increments counter)
2. Execute the Keeper transaction (schedules next executor + keeper)

Then check the counter:

```bash
flow scripts execute cadence/tests/mocks/scripts/GetCounter.cdc \
  --network=testnet
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
  <YOUR_TESTNET_ADDRESS> \
  /storage/CounterCronHandler \
  --network=testnet
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

Run this monitoring loop to watch the cron job in action. Execute these commands every 60-90 seconds:

**Check counter value:**

```bash
flow scripts execute cadence/tests/mocks/scripts/GetCounter.cdc \
  --network=testnet
```

**Check schedule status:**

```bash
flow scripts execute cadence/scripts/GetCronScheduleStatus.cdc \
  <YOUR_TESTNET_ADDRESS> \
  /storage/CounterCronHandler \
  --network=testnet
```

**Check CronInfo:**

```bash
flow scripts execute cadence/scripts/GetCronInfo.cdc \
  <YOUR_TESTNET_ADDRESS> \
  /storage/CounterCronHandler \
  --network=testnet
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
4. ✅ No `CronScheduleRejected` events

### Step 12: Stop the Cron Job

When you're satisfied with the testing, cancel the scheduled transactions:

```bash
flow transactions send cadence/transactions/CancelCronSchedule.cdc \
  /storage/CounterCronHandler \
  --network=testnet \
  --signer=testnet-account
```

**Expected output:**

```text
Transaction ID: <some-hash>
Status: ✅ SEALED

Events:
  - A.<address>.FlowTransactionScheduler.Canceled (x2)

Logs:
  - "Cancelled 2 transaction(s)"
```

This cancels both the executor and keeper transactions, completely stopping the cron job.

### Step 13: Verify Cancellation

Confirm the transactions were cancelled:

```bash
flow scripts execute cadence/scripts/GetCronScheduleStatus.cdc \
  <YOUR_TESTNET_ADDRESS> \
  /storage/CounterCronHandler \
  --network=testnet
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
  --network=testnet
```

The counter should remain at its last value (e.g., `4` if it ran for 4 minutes).

## Advanced Testing Scenarios

### Test 1: Restart After Cancellation

After cancelling, you can restart the cron job:

```bash
flow transactions send cadence/transactions/ScheduleCronHandler.cdc \
  /storage/CounterCronHandler \
  nil \
  2 \
  500 \
  --network=testnet \
  --signer=testnet-account
```

**Verify:** The cron job should resume incrementing from the current counter value.

### Test 2: Different Cron Expressions

Create additional CronHandlers with different schedules:

**Every 5 minutes:**

```bash
flow transactions send cadence/transactions/CreateCronHandler.cdc \
  "*/5 * * * *" \
  /storage/CounterTransactionHandler \
  /storage/CounterCronHandler5Min \
  --network=testnet \
  --signer=testnet-account
```

**Every hour (on the hour):**

```bash
flow transactions send cadence/transactions/CreateCronHandler.cdc \
  "0 * * * *" \
  /storage/CounterTransactionHandler \
  /storage/CounterCronHandlerHourly \
  --network=testnet \
  --signer=testnet-account
```

### Test 3: Event Monitoring

Watch for FlowCron events on TESTNET using Flowdiver (https://testnet.flowdiver.io/).

Search for your account address and look for these events:

- `CronKeeperExecuted` - Keeper successfully scheduled next cycle
- `CronExecutorExecuted` - Executor successfully ran user code
- `CronScheduleRejected` - Duplicate/unauthorized keeper was blocked
- `CronScheduleFailed` - If insufficient funds
- `CronEstimationFailed` - If fee estimation fails (e.g., High priority slot full)

Events include details like:

- `txID` - The executed transaction ID
- `nextExecutorTxID` - Next scheduled executor
- `nextKeeperTxID` - Next scheduled keeper
- `cronExpression` - The cron pattern
- `handlerUUID` - Handler identifier
