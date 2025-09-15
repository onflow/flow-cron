# FlowCron - Cron Job Scheduling on Flow

FlowCron is a smart contract system that brings the power of cron job scheduling to the Flow blockchain. It enables autonomous, recurring transaction execution without external triggers, allowing smart contracts to "wake up" and execute logic at predefined times using familiar cron expressions.

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Core Components](#core-components)
- [How It Works](#how-it-works)
- [Usage Guide](#usage-guide)
- [FlowCronUtils - The Cron Expression Engine](#flowcronutils---the-cron-expression-engine)
- [Transaction Reference](#transaction-reference)
- [Script Reference](#script-reference)
- [Best Practices](#best-practices)
- [Examples](#examples)

## Overview

FlowCron leverages Flow's native transaction scheduling capabilities (FLIP-330) to implement recurring executions. Unlike traditional cron systems that require external schedulers, FlowCron operates entirely on-chain, ensuring decentralization and reliability.

### Key Features

- **Standard Cron Syntax**: Uses familiar 5-field cron expressions (minute, hour, day-of-month, month, day-of-week)
- **Self-Perpetuating**: Jobs automatically reschedule themselves after each execution
- **Fault Tolerant**: Double-buffering pattern ensures continuity even if an execution fails
- **Flexible Priority**: Support for High, Medium, and Low priority executions
- **Cost Efficient**: Optimized bitmask operations minimize computation and storage
- **View Resolver Integration**: Full support for querying job states and custom handler data

## Architecture

### System Overview

```
+----------------------------------------------------------+
|                    User Account                          |
+----------------------------------------------------------+
|                                                          |
|  +-----------------+    +---------------------------+    |
|  |  CronHandler    |--->|      CronJob #1           |    |
|  |                 |    |  - cronSpec               |    |
|  |  - jobs         |    |  - wrappedHandlerCap      |    |
|  |  - nextJobId    |    |  - executionCount         |    |
|  |                 |    +---------------------------+    |
|  |                 |                                     |
|  |                 |    +---------------------------+    |
|  |                 |--->|      CronJob #2           |    |
|  |                 |    +---------------------------+    |
|  +-----------------+                                     |
|           |                                              |
|           v                                              |
|  +---------------------------------------------------+   |
|  |     TransactionSchedulerUtils.Manager             |   |
|  |  - Manages scheduled transactions                 |   |
|  +---------------------------------------------------+   |
|                                                          |
|  +---------------------------------------------------+   |
|  |         Custom Handler (User's)                   |   |
|  |  - Implements TransactionHandler                  |   |
|  |  - Contains actual job logic                      |   |
|  +---------------------------------------------------+   |
+----------------------------------------------------------+
```

### Core Design Principles

1. **Resource Ownership**: Each account owns its CronHandler resource, ensuring complete control over scheduled jobs
2. **Double-Buffer Pattern**: Two transactions are always scheduled (next and future) to ensure continuity
3. **Atomic Rescheduling**: New executions are scheduled before current execution completes

## Core Components

### CronHandler Resource

The main resource that manages all cron jobs for an account:

```cadence
access(all) resource CronHandler: FlowTransactionScheduler.TransactionHandler, ViewResolver.Resolver {
    access(self) var jobs: @{UInt64: CronJob}
    access(contract) var nextJobId: UInt64
    access(self) var transactionToJob: {UInt64: UInt64}
}
```

**Key Responsibilities:**

- Creates and manages CronJob resources
- Implements the TransactionHandler interface for execution
- Maintains transaction-to-job mappings
- Handles cleanup of completed jobs

### CronJob Resource

Individual cron job containing scheduling information and execution state:

```cadence
access(all) resource CronJob: ViewResolver.Resolver {
    access(all) let id: UInt64
    access(all) let cronSpec: FlowCronUtils.CronSpec
    access(contract) let wrappedHandlerCap: Capability<...>
    access(all) var executionCount: UInt64
    access(all) var lastExecution: UFix64?
    access(all) var nextExecution: UFix64?
    access(all) var futureExecution: UFix64?
}
```

### CronJobContext Struct

Immutable context passed with each execution containing all necessary information for rescheduling:

```cadence
access(all) struct CronJobContext {
    access(all) let jobId: UInt64
    access(all) let cronSpec: FlowCronUtils.CronSpec
    access(all) let cronHandlerCap: Capability<...>
    access(all) let schedulerManagerCap: Capability<...>
    access(all) let feeProviderCap: Capability<...>
    access(all) let data: AnyStruct?
    access(all) let priority: FlowTransactionScheduler.Priority
    access(all) let executionEffort: UInt64
}
```

## How It Works

### Job Scheduling Flow

1. **User Creates Handler**: Implements TransactionHandler interface with custom logic
2. **Schedule Job**: Calls `scheduleJob` with cron expression and handler capability
3. **Initial Scheduling**: System schedules two transactions (next and future execution)
4. **Execution**: When timestamp arrives, `executeTransaction` is called
5. **Rescheduling**: Before executing user code, system schedules the next future execution
6. **User Logic**: Wrapped handler executes with provided data
7. **Repeat**: Process continues indefinitely until cancelled

### Execution Sequence

```
Time ----------->
     |
     +-- Schedule Job
     |   +-- Create CronJob resource
     |   +-- Schedule transaction at T1 (next)
     |   +-- Schedule transaction at T2 (future)
     |
     +-- T1 arrives: Execute
     |   +-- Schedule transaction at T3 (new future)
     |   +-- Update state (T1->last, T2->next, T3->future)
     |   +-- Execute user handler
     |
     +-- T2 arrives: Execute
     |   +-- Schedule transaction at T4 (new future)
     |   +-- Update state (T2->last, T3->next, T4->future)
     |   +-- Execute user handler
     |
     +-- ... continues
```

## Usage Guide

### 1. Create Your Custom Handler

First, you need a transaction handler to be executed recurringly, so create a new one implementing the TransactionHandler interface or use third party ones:

```cadence
import "FlowTransactionScheduler"

access(all) contract MyHandler {
    access(all) resource Handler: FlowTransactionScheduler.TransactionHandler {
        access(FlowTransactionScheduler.Execute) 
        fun executeTransaction(id: UInt64, data: AnyStruct?) {
            // Your custom logic here
            log("Executing scheduled task with data: ".concat(data.toString()))
        }
    }
    
    access(all) fun createHandler(): @Handler {
        return <-create Handler()
    }
}
```

### 2. Setup and Save Handler

```cadence
import "MyHandler"

transaction {
    prepare(signer: auth(SaveValue) &Account) {
        let handler <- MyHandler.createHandler()
        signer.storage.save(<-handler, to: /storage/myHandler)
    }
}
```

### 3. Schedule a Cron Job

```cadence
import "FlowCron"
import "FlowCronUtils"
import "FlowTransactionScheduler"
import "FlowTransactionSchedulerUtils"
import "FlowToken"
import "FungibleToken"

transaction(
    cronSpec: FlowCronUtils.CronSpec,
    wrappedHandlerStoragePath: StoragePath,
    data: AnyStruct?,
    priority: FlowTransactionScheduler.Priority,
    executionEffort: UInt64
) {
    prepare(signer: auth(...) &Account) { 
        // Schedule the job (see ScheduleCronJob.cdc for full implementation)
    }
}
```

## FlowCronUtils - The Cron Expression Engine

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

### Usage Patterns

#### Option 1: Parse On-Chain

```cadence
// In a script
import "FlowCronUtils"

access(all) fun main(expression: String): FlowCronUtils.CronSpec? {
    return FlowCronUtils.parse(expression: expression)
}
```

Then use the result in your transaction:

```cadence
let cronSpec = FlowCronUtils.parse(expression: "0 9 * * 1-5")
    ?? panic("Invalid expression")
```

#### Option 2: Pre-compute Off-Chain

```javascript
// JavaScript example for computing bitmasks
function parseCronExpression(expression) {
    const parts = expression.split(' ');
    
    return {
        minMask: parseField(parts[0], 0, 59),
        hourMask: parseField(parts[1], 0, 23),
        domMask: parseField(parts[2], 1, 31),
        monthMask: parseField(parts[3], 1, 12),
        dowMask: parseField(parts[4], 0, 6),
        domIsStar: parts[2] === '*',
        dowIsStar: parts[4] === '*'
    };
}

function parseField(field, min, max) {
    if (field === '*') {
        return (1n << BigInt(max - min + 1)) - 1n << BigInt(min);
    }
    
    let mask = 0n;
    const parts = field.split(',');
    
    for (const part of parts) {
        if (part.includes('-')) {
            const [start, end] = part.split('-').map(Number);
            for (let i = start; i <= end; i++) {
                mask |= 1n << BigInt(i);
            }
        } else if (part.includes('/')) {
            // Handle step values
            const [range, step] = part.split('/');
            const [start, end] = range === '*' 
                ? [min, max] 
                : range.split('-').map(Number);
            
            for (let i = start; i <= end; i += Number(step)) {
                mask |= 1n << BigInt(i);
            }
        } else {
            mask |= 1n << BigInt(part);
        }
    }
    
    return mask;
}

// Example usage
const spec = parseCronExpression("0 9 * * 1-5");
// Use spec values in your transaction
```

## License

This project is licensed under the MIT License.
