# FlowCron TESTNET Testing Guide

This guide provides step-by-step commands to fully test the FlowCron implementation on **Flow TESTNET** using the Counter contract.

## Test Objective

Schedule a recurring transaction that executes **every minute** and increments a counter by 1. We'll verify:
- Counter increments correctly (by 1 each minute)
- Double-buffer pattern maintains 2 scheduled transactions (next + future)
- Automatic rescheduling works after each execution
- CronInfo metadata is accurate

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
  --network=testnet \
  --signer=testnet-account
```

Replace `testnet-account` with your account name from flow.json.

**Expected output:**
```
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
  --network=testnet \
  --signer=testnet-account
```

**Expected output:**
```
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
  "nextExecution": 1699999999,
  "futureExecution": 1700000059,
  "wrappedHandlerType": "A.0000000000000007.CounterTransactionHandler.Handler",
  "wrappedHandlerUUID": 123
}
```

**Key observations:**
- `cronExpression` is `* * * * *` (every minute)
- `nextExecution` and `futureExecution` show calculated times (not actual scheduled transactions yet)

### Step 7: Schedule the Initial Cron Execution

Start the cron job by scheduling the first execution:

```bash
flow transactions send cadence/transactions/ScheduleCronHandler.cdc \
  --args-json '[{"type":"Path","value":{"domain":"storage","identifier":"CounterCronHandler"}},{"type":"Optional","value":null},{"type":"UInt8","value":"2"},{"type":"UInt64","value":"500"}]' \
  --network=testnet \
  --signer=testnet-account
```

**Arguments explained:**
- `Path:/storage/CounterCronHandler` - Where the CronHandler is stored
- `Optional(String):null` - No wrapped data needed for Counter
- `UInt8:2` - Priority: Low (0=High, 1=Medium, 2=Low)
- `UInt64:500` - Execution effort estimate (confirmed working value)

**Expected output:**
```
Transaction ID: <some-hash>
Status: ✅ SEALED

Logs:
"Scheduled cron transaction with ID: 0 at time: 1699999999"
```

**Important:** Note the transaction ID in the logs (e.g., `0`). This is the first scheduled transaction.

### Step 8: Verify Schedule Status

Check that the transaction is scheduled:

```bash
flow scripts execute cadence/scripts/GetCronScheduleStatus.cdc \
  <YOUR_TESTNET_ADDRESS> \
  /storage/CounterCronHandler \
  --network=testnet
```

**Expected output:**
```json
{
  "nextTransactionID": 0,
  "futureTransactionID": null,
  "nextTxStatus": 0,
  "nextTxTimestamp": "1699999999.00000000",
  "futureTxStatus": null,
  "futureTxTimestamp": null
}
```

**Key observations:**
- `nextTransactionID` = `0` (the initial scheduled transaction)
- `futureTransactionID` = `null` (double-buffer not active yet - will be filled on first execution)
- `nextTxStatus` = `0` (0 = Scheduled)

### Step 9: Wait for First Execution

The emulator will automatically execute scheduled transactions when their time arrives. On the first execution, FlowCron will:
1. Schedule BOTH next and future executions (double-buffer pattern)
2. Execute the Counter increment

**Wait approximately 1 minute** (or less if the scheduled time is soon), then check the counter:

```bash
flow scripts execute cadence/tests/mocks/scripts/GetCounter.cdc \
  --network=testnet
```

**Expected output:**
```
Result: 1
```

The counter should now be `1`!

### Step 10: Verify Double-Buffer Pattern

After the first execution, check that the double-buffer is now active:

```bash
flow scripts execute cadence/scripts/GetCronScheduleStatus.cdc \
  <YOUR_TESTNET_ADDRESS> \
  /storage/CounterCronHandler \
  --network=testnet
```

**Expected output:**
```json
{
  "nextTransactionID": 1,
  "futureTransactionID": 2,
  "nextTxStatus": 0,
  "nextTxTimestamp": "1700000059.00000000",
  "futureTxStatus": 0,
  "futureTxTimestamp": "1700000119.00000000"
}
```

**Key observations:**
- `nextTransactionID` = `1` (next execution in ~1 minute)
- `futureTransactionID` = `2` (backup execution in ~2 minutes)
- Both have `status = 0` (Scheduled)
- Timestamps are ~60 seconds apart (one minute intervals)

**This confirms the double-buffer pattern is working!**

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

| Time | Counter | Next TX ID | Future TX ID | Notes |
|------|---------|------------|--------------|-------|
| Initial | 0 | 0 | null | First execution scheduled |
| After 1 min | 1 | 1 | 2 | Double-buffer active |
| After 2 min | 2 | 2 | 3 | Next shifts, new future scheduled |
| After 3 min | 3 | 3 | 4 | Pattern continues |
| After 4 min | 4 | 4 | 5 | Indefinite execution |

**What to verify:**
1. Counter increments by exactly 1 each minute
2. Both `nextTransactionID` and `futureTransactionID` are always present (except initially)
3. Transaction IDs increment sequentially
4. Both transactions show `status = 0` (Scheduled)
5. Timestamps are approximately 60 seconds apart

### Step 12: Stop the Cron Job

When you're satisfied with the testing, cancel the scheduled transactions:

```bash
flow transactions send cadence/transactions/CancelCronSchedule.cdc \
  /storage/CounterCronHandler \
  --network=testnet \
  --signer=testnet-account
```

**Expected output:**
```
Transaction ID: <some-hash>
Status: ✅ SEALED

Logs:
"Cancelled 2 of 2 transactions"
```

### Step 13: Verify Cancellation

Confirm all scheduled transactions were cancelled:

```bash
flow scripts execute cadence/scripts/GetCronScheduleStatus.cdc \
  <YOUR_TESTNET_ADDRESS> \
  /storage/CounterCronHandler \
  --network=testnet
```

**Expected output:**
```json
{
  "nextTransactionID": null,
  "futureTransactionID": null,
  "nextTxStatus": null,
  "nextTxTimestamp": null,
  "futureTxStatus": null,
  "futureTxTimestamp": null
}
```

**Check final counter value:**
```bash
flow scripts execute cadence/tests/mocks/scripts/GetCounter.cdc \
  --network=testnet
```

The counter should remain at its last value (e.g., `4` if it ran for 4 minutes).

## Advanced Testing Scenarios

### Test 1: Restart After Cancellation

After cancelling, you can restart the cron job. Repeat Step 7 to schedule again:

```bash
flow transactions send cadence/transactions/ScheduleCronHandler.cdc \
  --args-json '[{"type":"Path","value":{"domain":"storage","identifier":"CounterCronHandler"}},{"type":"Optional","value":null},{"type":"UInt8","value":"2"},{"type":"UInt64","value":"500"}]' \
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
- `CronScheduleExecuted` - Each successful execution
- `CronScheduleFailed` - If insufficient funds
- `CronEstimationFailed` - If fee estimation fails

Events include details like:
- `txID` - The executed transaction ID
- `nextTxID` - Next scheduled transaction
- `futureTxID` - Future scheduled transaction
- `cronExpression` - The cron pattern
- `handlerUUID` - Handler identifier
