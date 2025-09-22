# FlowCron - Cron Job Scheduling on Flow

FlowCron enables autonomous, recurring transaction execution without external triggers, allowing smart contracts to "wake up" and execute logic at predefined times using cron expressions.

## Overview

FlowCron leverages Flow's native transaction scheduling capabilities (FLIP-330) to implement recurring executions. Unlike traditional cron systems that require external schedulers, FlowCron operates entirely onchain, ensuring decentralization and reliability.

### Key Features

- **Standard Cron Syntax**: Uses familiar 5-field cron expressions (minute, hour, day-of-month, month, day-of-week)
- **Self-Perpetuating**: Jobs automatically reschedule themselves after each execution
- **Fault Tolerant**: Double-buffering pattern ensures continuity even if wrapped handler fails
- **Flexible Priority**: Support for High, Medium, and Low priority executions
- **Cost Efficient**: Optimized bitmask operations minimize computation and storage
- **View Resolver Integration**: Full support for querying job states and their wrapped handler metadata
- **Distributed Design**: Each user controls their own CronHandler resources

## Architecture

### Core Design Principles

1. **Distributed Ownership**: Each CronHandler is an independent resource owned by users
2. **No Central State**: Leverages Manager's existing tracking instead of maintaining separate state
3. **Double-Buffer Pattern**: Two transactions are always scheduled (next and future) to ensure continuity
4. **Atomic Rescheduling**: New executions are scheduled before wrapped handler execution
5. **Failure Isolation**: Wrapped handler failures don't stop the cron schedule

## Core Components

### CronHandler Resource

A lightweight wrapper that adds cron functionality to any TransactionHandler:

```cadence
access(all) resource CronHandler: FlowTransactionScheduler.TransactionHandler, ViewResolver.Resolver {
    access(all) let cronExpression: String
    access(all) let cronSpec: FlowCronUtils.CronSpec
    access(self) let wrappedHandlerCap: Capability<auth(FlowTransactionScheduler.Execute) &{FlowTransactionScheduler.TransactionHandler}>
}
```

**Key Features:**

- Wraps any existing TransactionHandler
- Stores cron expression and parsed spec
- Implements automatic rescheduling logic
- Provides metadata through ViewResolver interface

### CronContext Struct

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

### CronHandlerInfo View

Metadata view for querying cron handler information:

```cadence
access(all) struct CronHandlerInfo {
    access(all) let cronExpression: String
    access(all) let cronSpec: FlowCronUtils.CronSpec
    access(all) let nextExecution: UInt64?
    access(all) let wrappedHandlerType: String?
    access(all) let wrappedHandlerUUID: UInt64?
}
```

## How It Works

### Scheduling Flow

1. **Create CronHandler**: Wrap your existing TransactionHandler with a cron expression
2. **Store in Account**: Save the CronHandler resource in your storage
3. **Schedule with Manager**: Use `scheduleCronHandler` helper to schedule initial executions
4. **Automatic Rescheduling**: Each execution schedules the next one before running wrapped handler
5. **Continuous Operation**: Runs indefinitely until manually cancelled

### Execution Sequence

```
Time ----------->
     |
     +-- Create & Schedule CronHandler
     |   +-- Parse cron expression
     |   +-- Schedule transaction at T1 (next)
     |   +-- Schedule transaction at T2 (future)
     |   +-- Return transaction IDs
     |
     +-- T1 arrives: Execute
     |   +-- Validate capabilities
     |   +-- Calculate T3 (new future)
     |   +-- Check balance & withdraw fees
     |   +-- Schedule transaction at T3
     |   +-- Execute wrapped handler (may fail)
     |
     +-- T2 arrives: Execute
     |   +-- Validate capabilities
     |   +-- Calculate T4 (new future)
     |   +-- Check balance & withdraw fees
     |   +-- Schedule transaction at T4
     |   +-- Execute wrapped handler (may fail)
     |
     +-- ... continues until cancelled
```

## Cron Expression Engine

FlowCronUtils provides a highly optimized cron expression parser and scheduler using bitmask operations for efficiency.

### Cron Expression Format

Standard 5-field format:
```
+----------+----------+----------+----------+----------+
| minute   | hour     | day of   | month    | day of   |
|          |          | month    |          | week     |
| (0-59)   | (0-23)   | (1-31)   | (1-12)   | (0-6)    |
|          |          |          |          | (0=Sun)  |
+----------+----------+----------+----------+----------+
|    *     |    *     |    *     |    *     |    *     |
+----------+----------+----------+----------+----------+
```

### Supported Operators

- `*` - Wildcard (any value)
- `,` - List separator (e.g., `1,3,5`)
- `-` - Range (e.g., `1-5`)
- `/` - Step values (e.g., `*/5`, `1-30/5`)

### Bitmask Implementation

FlowCronUtils uses bitmasks for ultra-efficient storage and computation:

```cadence
access(all) struct CronSpec {
    access(all) let minMask: UInt64   // bits 0-59 for minutes
    access(all) let hourMask: UInt32  // bits 0-23 for hours
    access(all) let domMask: UInt32   // bits 1-31 for days
    access(all) let monthMask: UInt16 // bits 1-12 for months
    access(all) let dowMask: UInt8    // bits 0-6 for weekdays
}
```

#### Why Bitmasks?

1. **Space Efficiency**: Entire cron spec fits in ~15 bytes vs hundreds for arrays
2. **O(1) Checking**: Bit operations are constant time
3. **Cache Friendly**: All data fits in a single cache line
4. **Gas Efficient**: Bitwise operations are the cheapest computations

#### Example: "0 9,17 * * 1-5" (9 AM and 5 PM on weekdays)

```
minMask:   0x0000000000000001  (bit 0 = minute 0)
hourMask:  0x00020200          (bits 9,17 = hours 9,17)  
domMask:   0xFFFFFFFE          (all days)
monthMask: 0x1FFE              (all months)
dowMask:   0x3E                (bits 1-5 = Mon-Fri)
```

### Common Cron Patterns

- `* * * * *` - Every minute (use with caution)
- `0 * * * *` - Every hour
- `0 0 * * *` - Daily at midnight
- `0 0 * * 0` - Weekly on Sunday
- `0 0 1 * *` - Monthly on the 1st
- `*/15 * * * *` - Every 15 minutes
- `0 9-17 * * 1-5` - Hourly during business hours
- `0 0,12 * * *` - Twice daily at midnight and noon

## License

This project is licensed under the MIT License.
