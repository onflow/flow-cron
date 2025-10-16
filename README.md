# FlowCron - Cron Job Scheduling on Flow

FlowCron enables autonomous, recurring transaction execution without external triggers, allowing smart contracts to "wake up" and execute logic at predefined times using cron expressions.

## Overview

FlowCron leverages Flow's native transaction scheduling capabilities (FLIP-330) to implement recurring executions. Unlike traditional cron systems that require external schedulers, FlowCron operates entirely onchain, ensuring decentralization and reliability.

### Key Features

- **Standard Cron Syntax**: Uses familiar 5-field cron expressions (minute, hour, day-of-month, month, day-of-week)
- **Self-Perpetuating**: Jobs automatically reschedule themselves after each execution
- **Double-Buffer Pattern**: Maintains two scheduled transactions (next + future) for continuous operation
- **Fault Tolerant**: Wrapped handler failures don't stop the cron schedule
- **Flexible Priority**: Supports High, Medium, and Low priority executions
- **View Resolver Integration**: Full support for querying job states and metadata
- **Distributed Design**: Each user controls their own CronHandler resources

## Quick Start

### 1. Create a Transaction Handler

First, create a handler that implements the `TransactionHandler` interface:

```cadence
import "FlowTransactionScheduler"

access(all) resource MyTaskHandler: FlowTransactionScheduler.TransactionHandler {
    access(FlowTransactionScheduler.Execute)
    fun executeTransaction(id: UInt64, data: AnyStruct?) {
        // Your recurring logic here
        log("Cron job executed!")
    }
}
```

### 2. Wrap with CronHandler

Wrap your handler with FlowCron to add scheduling:

```cadence
import "FlowCron"

// Store your task handler
account.storage.save(<-create MyTaskHandler(), to: /storage/MyTaskHandler)

// Create capability to your handler
let handlerCap = account.capabilities.storage.issue<
    auth(FlowTransactionScheduler.Execute) &{FlowTransactionScheduler.TransactionHandler}
>(/storage/MyTaskHandler)

// Create cron handler (runs every day at midnight)
let cronHandler <- FlowCron.createCronHandler(
    cronExpression: "0 0 * * *",
    wrappedHandlerCap: handlerCap
)

// Store it
account.storage.save(<-cronHandler, to: /storage/MyCronHandler)
```

### 3. Schedule Initial Execution

Use the provided `ScheduleCronHandler` transaction to start:

```bash
flow transactions send cadence/transactions/ScheduleCronHandler.cdc \
    --arg Path:/storage/MyCronHandler \
    --arg 'Optional(String):null' \
    --arg UInt8:2 \
    --arg UInt64:100
```

### 4. Monitor & Control

Query status:

```bash
flow scripts execute cadence/scripts/GetCronInfo.cdc \
    --arg Address:0x... \
    --arg Path:/storage/MyCronHandler
```

Cancel when needed:

```bash
flow transactions send cadence/transactions/CancelCronSchedule.cdc \
    --arg Path:/storage/MyCronHandler
```

## Architecture

### Core Components

#### CronHandler Resource

The main resource that wraps any `TransactionHandler` with cron functionality:

```cadence
access(all) resource CronHandler: FlowTransactionScheduler.TransactionHandler, ViewResolver.Resolver
{
    // Cron configuration
    access(all) let cronExpression: String
    access(all) let cronSpec: FlowCronUtils.CronSpec

    // Wrapped handler
    access(self) let wrappedHandlerCap: Capability<auth(FlowTransactionScheduler.Execute) &{FlowTransactionScheduler.TransactionHandler}>

    // Scheduling state (internal)
    access(self) var nextScheduledTransactionID: UInt64?
    access(self) var futureScheduledTransactionID: UInt64?
    access(self) var hasActiveSchedule: Bool

    // TransactionHandler interface
    access(FlowTransactionScheduler.Execute) fun executeTransaction(id: UInt64, data: AnyStruct?)

    // Public getter methods (all view - read-only)
    access(all) view fun getCronExpression(): String
    access(all) view fun getCronSpec(): FlowCronUtils.CronSpec
    access(all) view fun getNextScheduledTransactionID(): UInt64?
    access(all) view fun getFutureScheduledTransactionID(): UInt64?

    // ViewResolver methods
    access(all) view fun getViews(): [Type]  // view: required by ViewResolver interface
    access(all) fun resolveView(_ view: Type): AnyStruct?  // Not view: may delegate to wrapped handler
}
```

#### CronContext Struct

Execution context passed with each scheduled transaction:

```cadence
access(all) struct CronContext {
    access(all) let schedulerManagerCap: Capability<auth(FlowTransactionSchedulerUtils.Owner) &{FlowTransactionSchedulerUtils.Manager}>
    access(all) let feeProviderCap: Capability<auth(FungibleToken.Withdraw) &FlowToken.Vault>
    access(all) let priority: FlowTransactionScheduler.Priority
    access(all) let executionEffort: UInt64
    access(all) let wrappedData: AnyStruct?
}
```

#### CronInfo View

Metadata view for querying cron handler information:

```cadence
access(all) struct CronInfo {
    access(all) let cronExpression: String
    access(all) let cronSpec: FlowCronUtils.CronSpec
    access(all) let nextExecution: UInt64?
    access(all) let futureExecution: UInt64?
    access(all) let wrappedHandlerType: String?
    access(all) let wrappedHandlerUUID: UInt64?
}
```

### Design Principles

#### 1. Double-Buffer Pattern

FlowCron uses a **double-buffer scheduling pattern** to maintain continuous execution:

```
Time ────────────────────────────────────>
         │
         ├── Next (T2)     ← Executes soon
         │
         └── Future (T3)   ← Backup/continuity
```

**How it works:**

1. **Initial Schedule**: You schedule a single transaction (T1) at **any time you choose**
   - Can be the next cron time, or any custom timestamp
   - Gives you flexibility to start cron jobs at specific moments (e.g., "start tomorrow at 9 AM")
2. **T1 Executes**:
   - **First**: Schedules BOTH Next (T2) and Future (T3) based on cron spec **from current time**
   - **Then**: Runs your wrapped handler logic
   - Double-buffer is now active BEFORE handler executes (safety guarantee)
3. **T2 Executes**:
   - **First**: Shifts Future (T3) → Next, schedules new Future (T4) based on cron spec
   - **Then**: Runs your wrapped handler logic
   - Maintains the double-buffer even if handler fails
4. **Continues indefinitely** - each execution ensures two transactions are always scheduled, following the cron spec

**Benefits:**

- **Flexible Start**: Choose exactly when your cron job begins (next cron time, specific date, or custom timestamp)
- **Reliability**: If one transaction fails to execute, the other ensures continuity
- **No Gaps**: System always has a scheduled execution after the first run
- **Smooth Operation**: Seamless transition between executions
- **Automatic Recovery**: Even if scheduling temporarily fails (low funds), the existing buffered transaction keeps it running

#### 2. Atomic Rescheduling

- Rescheduling happens **before** wrapped handler execution
- If wrapped handler fails, cron continues on schedule
- State sync ensures accuracy even after cancellations

#### 3. State Management with `syncSchedule()`

The `syncSchedule()` function maintains consistency:

- Clears stale transaction IDs (executed/cancelled/missing)
- Updates `hasActiveSchedule` flag to control external scheduling
- Ensures internal state matches scheduler reality

#### 4. Distributed Ownership

Each user owns their `CronHandler` resources:

```
┌─────────────────────────────────────┐
│         User Account                │
│                                     │
│  /storage/MyCronHandler1            │
│    └─> CronHandler                  │
│          └─> wraps MyTaskHandler1   │
│                                     │
│  /storage/MyCronHandler2            │
│    └─> CronHandler                  │
│          └─> wraps MyTaskHandler2   │
└─────────────────────────────────────┘
```

**Benefits:**

- No central bottleneck or single point of failure
- Users pay their own scheduling fees
- Scales horizontally across all accounts
- Permissionless as anyone can create cron jobs

### How It Works: Execution Flow

#### Initial Scheduling

**Step 1: You start the cron job**

- Schedule a single execution at any time you choose
- Can be the next cron time, tomorrow at 9 AM, or any future moment
- This gives you full control over when the cron job begins

**Step 2: First execution (T1)**

1. ⚠️ **Schedules future executions FIRST**
   - Calculates next two times from cron expression: T2 and T3
   - Schedules both transactions
   - Double-buffer is now active
2. **Runs your task logic**
   - Executes your wrapped handler
   - Even if this fails, cron continues (already scheduled!)

**Result**: Two future executions are queued, cron job is self-sustaining

#### Recurring Execution

**Step 3: Subsequent executions (T2, T3, T4...)**

1. ⚠️ **Maintains schedule FIRST**
   - Checks which transactions are still pending
   - Shifts the future execution to become the next one
   - Schedules a new future execution based on cron expression
   - Double-buffer is always maintained
2. **Runs your task logic**
   - Executes your wrapped handler
   - Even if this fails, cron continues

**Result**: Job runs indefinitely, always keeping two executions scheduled ahead

#### Protection Against Double-Scheduling

**If someone tries to schedule again while active:**

- System detects the cron job is already running
- Rejects the new scheduling attempt
- Prevents conflicting contexts or duplicate executions
- Emits a rejection event for monitoring

**Result**: Data consistency is protected - one cron schedule per handler

## Cron Expression Engine

### Syntax

Standard 5-field format:

```
┌───────────── minute (0-59)
│ ┌───────────── hour (0-23)
│ │ ┌───────────── day of month (1-31)
│ │ │ ┌───────────── month (1-12)
│ │ │ │ ┌───────────── day of week (0-6, 0=Sunday)
│ │ │ │ │
* * * * *
```

### Operators

- `*` - Any value (wildcard)
- `,` - List separator: `1,3,5` means 1, 3, and 5
- `-` - Range: `1-5` means 1, 2, 3, 4, 5
- `/` - Step: `*/5` means every 5, `10-30/5` means 10, 15, 20, 25, 30

### Common Patterns

| Pattern | Description |
|---------|-------------|
| `* * * * *` | Every minute |
| `*/5 * * * *` | Every 5 minutes |
| `0 * * * *` | Every hour (on the hour) |
| `0 0 * * *` | Daily at midnight |
| `0 12 * * *` | Daily at noon |
| `0 0 * * 0` | Weekly on Sunday at midnight |
| `0 0 1 * *` | Monthly on the 1st at midnight |
| `0 9-17 * * 1-5` | Hourly during business hours (9am-5pm, Mon-Fri) |
| `*/15 9-17 * * 1-5` | Every 15 min during business hours |
| `0 0,12 * * *` | Twice daily (midnight and noon) |

### Bitmask Implementation

FlowCronUtils uses **bitmasks** for ultra-efficient scheduling:

```cadence
access(all) struct CronSpec {
    access(all) let minMask: UInt64   // bits 0-59 for minutes
    access(all) let hourMask: UInt32  // bits 0-23 for hours
    access(all) let domMask: UInt32   // bits 1-31 for day-of-month
    access(all) let monthMask: UInt16 // bits 1-12 for months
    access(all) let dowMask: UInt8    // bits 0-6 for day-of-week
    access(all) let domIsStar: Bool   // day-of-month was "*"
    access(all) let dowIsStar: Bool   // day-of-week was "*"
}
```

**Example: `0 9,17 * * 1-5` (9 AM and 5 PM on weekdays)**

```
minMask:   0x0000000000000001  (bit 0 set = minute 0)
hourMask:  0x00020200          (bits 9,17 set = hours 9,17)
domMask:   0xFFFFFFFE          (all days)
monthMask: 0x1FFE              (all months)
dowMask:   0x3E                (bits 1-5 set = Mon-Fri)
```

**Benefits:**
- **Space**: ~15 bytes vs hundreds for arrays
- **Speed**: O(1) bit check vs O(n) array scan
- **Gas**: Bitwise operations are cheapest on EVM/Cadence
