# FlowCron - Cron Job Scheduling on Flow

FlowCron enables autonomous, recurring transaction execution without external triggers, allowing smart contracts to "wake up" and execute logic at predefined times using cron expressions.

## Overview

FlowCron leverages Flow's native transaction scheduling capabilities (FLIP-330) to implement recurring executions. Unlike traditional cron systems that require external schedulers, FlowCron operates entirely onchain, ensuring decentralization and reliability.

### Key Features

- **Standard Cron Syntax**: Uses familiar 5-field cron expressions (minute, hour, day-of-month, month, day-of-week)
- **Self-Perpetuating**: Jobs automatically reschedule themselves after each execution
- **Keeper/Executor Architecture**: Separates scheduling logic from user code for fault isolation
- **Fault Tolerant**: Executor failures don't stop the keeper from scheduling next cycle
- **Flexible Priority**: Supports High, Medium, and Low priority executions
- **View Resolver Integration**: Full support for querying job states and metadata
- **Distributed Design**: Each user controls their own CronHandler resources

## Contract Addresses

| Contract | Testnet | Mainnet |
|----------|---------|---------|
| FlowCron | `0x5cbfdec870ee216d` | TBD |
| FlowCronUtils | `0x5cbfdec870ee216d` | TBD |

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
import "FlowTransactionScheduler"
import "FlowTransactionSchedulerUtils"
import "FlowToken"
import "FungibleToken"

// Store your task handler
account.storage.save(<-create MyTaskHandler(), to: /storage/MyTaskHandler)

// Create capability to your handler
let handlerCap = account.capabilities.storage.issue<
    auth(FlowTransactionScheduler.Execute) &{FlowTransactionScheduler.TransactionHandler}
>(/storage/MyTaskHandler)

// Create capabilities for fee payment and scheduling (stored securely in resource)
let feeProviderCap = account.capabilities.storage.issue<
    auth(FungibleToken.Withdraw) &FlowToken.Vault
>(/storage/flowTokenVault)

// Ensure manager exists
if account.storage.borrow<&{FlowTransactionSchedulerUtils.Manager}>(
    from: FlowTransactionSchedulerUtils.managerStoragePath
) == nil {
    account.storage.save(
        <-FlowTransactionSchedulerUtils.createManager(),
        to: FlowTransactionSchedulerUtils.managerStoragePath
    )
}
let schedulerManagerCap = account.capabilities.storage.issue<
    auth(FlowTransactionSchedulerUtils.Owner) &{FlowTransactionSchedulerUtils.Manager}
>(FlowTransactionSchedulerUtils.managerStoragePath)

// Create cron handler (runs every day at midnight)
// Capabilities are stored securely in the resource, not passed in transaction data
let cronHandler <- FlowCron.createCronHandler(
    cronExpression: "0 0 * * *",
    wrappedHandlerCap: handlerCap,
    feeProviderCap: feeProviderCap,
    schedulerManagerCap: schedulerManagerCap
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
    --arg UInt64:100 \
    --arg UInt64:2500
```

**Parameters:**

- `cronHandlerStoragePath`: Path to your CronHandler
- `wrappedData`: Optional data passed to your handler
- `executorPriority`: Priority for executor (0=High, 1=Medium, 2=Low)
- `executorExecutionEffort`: Execution effort for user code (100-9999)
- `keeperExecutionEffort`: Execution effort for keeper scheduling (recommended: 2500)

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
    access(self) let cronExpression: String
    access(self) let cronSpec: FlowCronUtils.CronSpec

    // Wrapped handler
    access(self) let wrappedHandlerCap: Capability<auth(FlowTransactionScheduler.Execute) &{FlowTransactionScheduler.TransactionHandler}>

    // Capabilities needed for rescheduling
    access(self) let feeProviderCap: Capability<auth(FungibleToken.Withdraw) &FlowToken.Vault>
    access(self) let schedulerManagerCap: Capability<auth(FlowTransactionSchedulerUtils.Owner) &{FlowTransactionSchedulerUtils.Manager}>

    // Scheduling state (internal)
    access(self) var nextScheduledKeeperID: UInt64?
    access(self) var nextScheduledExecutorID: UInt64?

    // TransactionHandler interface
    access(FlowTransactionScheduler.Execute) fun executeTransaction(id: UInt64, data: AnyStruct?)

    // Public getter methods (all view - read-only)
    access(all) view fun getCronExpression(): String
    access(all) view fun getCronSpec(): FlowCronUtils.CronSpec
    access(all) view fun getNextScheduledKeeperID(): UInt64?
    access(all) view fun getNextScheduledExecutorID(): UInt64?

    // ViewResolver methods
    access(all) view fun getViews(): [Type]
    access(all) fun resolveView(_ view: Type): AnyStruct?
}
```

#### ExecutionMode Enum

Determines whether a scheduled transaction runs as keeper or executor:

```cadence
access(all) enum ExecutionMode: UInt8 {
    access(all) case Keeper   // Pure scheduling logic
    access(all) case Executor // User code execution
}
```

#### CronContext Struct

Execution context passed with each scheduled transaction. This allows scheduling the same CronHandler with different configurations without recreating the resource:

```cadence
access(all) struct CronContext {
    access(contract) let executionMode: ExecutionMode
    access(contract) let executorPriority: FlowTransactionScheduler.Priority
    access(contract) let executorExecutionEffort: UInt64
    access(contract) let keeperExecutionEffort: UInt64
    access(contract) let wrappedData: AnyStruct?
}
```

- `executionMode`: Whether this is a Keeper or Executor transaction
- `executorPriority`: Priority for executor transactions (High, Medium, Low)
- `executorExecutionEffort`: Computational effort for user code execution
- `keeperExecutionEffort`: Computational effort for keeper scheduling operations
- `wrappedData`: Optional data passed to your handler

#### CronInfo View

Metadata view for querying cron handler information:

```cadence
access(all) struct CronInfo {
    access(all) let cronExpression: String
    access(all) let cronSpec: FlowCronUtils.CronSpec
    access(all) let nextScheduledKeeperID: UInt64?
    access(all) let nextScheduledExecutorID: UInt64?
    access(all) let wrappedHandlerType: String?
    access(all) let wrappedHandlerUUID: UInt64?
}
```

### Design Principles

#### 1. Keeper/Executor Architecture

FlowCron uses a **dual-mode architecture** that separates scheduling from execution:

```
Time ────────────────────────────────────>
     T1                    T2                    T3
     │                     │                     │
     ├── Executor ────────►├── Executor ────────►├── Executor
     │   (user code)       │   (user code)       │   (user code)
     │                     │                     │
     └── Keeper ──────────►└── Keeper ──────────►└── Keeper
         (schedules T2)        (schedules T3)        (schedules T4)
         (+1s offset)          (+1s offset)          (+1s offset)
```

**Two transaction types per cycle:**

1. **Executor**: Runs at exact cron tick, executes your wrapped handler
2. **Keeper**: Runs 1 second later, schedules next cycle (both executor + keeper)

**Why this design?**

- **Fault Isolation**: If executor panics (user code error), keeper still runs and schedules next cycle
- **No Silent Death**: Keeper uses force-unwrap - if scheduling fails, it panics loudly (better than silent stop)
- **Strict Priority**: Executor uses exactly the priority you specify - if High priority slot is full, that tick is skipped (use Medium for guaranteed scheduling)

#### 2. Bootstrap Process

**Initial scheduling** (user triggers once):

1. User schedules BOTH executor AND keeper for the first cron tick
2. Executor runs user code at T1
3. Keeper schedules next executor (T2) + next keeper (T2+1s)
4. Cycle continues forever

```
User Bootstrap          T1                      T2
     │                  │                       │
     ├─ Schedule ──────►├── Executor ──────────►├── Executor
     │  Executor(T1)    │   runs user code      │   runs user code
     │                  │                       │
     └─ Schedule ──────►└── Keeper ────────────►└── Keeper
        Keeper(T1)          schedules T2            schedules T3
```

#### 3. Protection Against Duplicate Scheduling

FlowCron tracks `nextScheduledKeeperID` to prevent duplicates:

- If a keeper with different ID tries to execute, it's rejected
- Emits `CronScheduleRejected` event for monitoring
- Only the scheduled keeper can continue the chain

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
- Permissionless - anyone can create cron jobs

### Events

FlowCron emits detailed events for monitoring:

| Event | When Emitted |
|-------|--------------|
| `CronKeeperExecuted` | Keeper successfully scheduled next cycle |
| `CronExecutorExecuted` | Executor successfully ran user code |
| `CronScheduleRejected` | Duplicate/unauthorized keeper was blocked |
| `CronScheduleFailed` | Scheduling failed (insufficient funds) |
| `CronEstimationFailed` | Fee estimation failed (e.g., High priority slot full) |

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
