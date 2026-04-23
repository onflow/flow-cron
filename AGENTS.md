# AGENTS.md

This file provides guidance to AI coding agents (Claude Code, Codex, Cursor, Copilot, Windsurf, Gemini CLI, and others) when working in this repository. It is loaded into agent context automatically — keep it concise.

## Overview

FlowCron is a Cadence-only smart-contract project that adds cron-like recurring execution on top of Flow's native transaction scheduler (`FlowTransactionScheduler` / `FlowTransactionSchedulerUtils`). The `FlowCron` contract wraps any `TransactionHandler` in a `CronHandler` resource that self-reschedules using a 5-field cron expression, while `FlowCronUtils` parses expressions into bitmask `CronSpec` structs and computes the next tick. Contracts are deployed to testnet (`0x5cbfdec870ee216d`) and mainnet (`0x6dec6e64a13b881e`) per `flow.json`.

## Build and Test Commands

This repo has no Makefile, `package.json`, or CI workflow. All tooling is the Flow CLI.

- `flow test cadence/tests/*_test.cdc` — run the Cadence Test framework suite (3 test files: `FlowCron_test.cdc`, `FlowCronUtils_Mask_test.cdc`, `FlowCronUtils_String_test.cdc`).
- `flow emulator start --block-time 1s` — start the emulator. The `--block-time 1s` flag is **required**; without it the scheduler will not execute scheduled transactions (see `GUIDE_EMULATOR.md` step 1).
- `flow project deploy --network=emulator` — deploys `FlowCronUtils`, `FlowCron`, `Counter`, `CounterTransactionHandler` (order defined in `flow.json` `deployments.emulator`).
- `flow project deploy --network=testnet` — deploys the same 4 contracts to `testnet-account`.
- `flow project deploy --network=mainnet` — deploys only `FlowCronUtils` and `FlowCron` (no mocks), signed via Google KMS key per `flow.json`.

End-to-end manual test flows for emulator and testnet are in `GUIDE_EMULATOR.md` and `GUIDE_TESTNET.md`.

## Architecture

```
cadence/
├── contracts/
│   ├── FlowCron.cdc           # CronHandler resource, CronContext, CronInfo view, ExecutionMode enum
│   └── FlowCronUtils.cdc      # Cron expression parser, CronSpec bitmasks, nextTick()
├── transactions/
│   ├── ScheduleCronHandler.cdc   # Bootstrap: schedules executor + keeper for first tick
│   ├── CreateCronHandler.cdc     # Wraps a TransactionHandler with a CronHandler
│   ├── CancelCronSchedule.cdc    # Cancels both scheduled executor and keeper txs
│   ├── cli/                      # FlowScheduleCancel, FlowScheduleSetup
│   └── manager/                  # CancelTransaction, SetupManager
├── scripts/
│   ├── GetCronInfo.cdc                # Reads CronInfo via ViewResolver.resolveView
│   ├── GetCronScheduleStatus.cdc
│   ├── GetNextExecutionTime.cdc
│   ├── GetParsedCronExpression.cdc
│   ├── GetTransactionData.cdc
│   ├── cli/                           # FlowScheduleGet, FlowScheduleList (+ IncludeHandlerData variants)
│   └── manager/                       # GetManagerHandlers, GetManagerTransactions, GetTransactionStatus, etc.
└── tests/
    ├── FlowCron_test.cdc, FlowCronUtils_Mask_test.cdc, FlowCronUtils_String_test.cdc
    └── mocks/                   # Counter contract + CounterTransactionHandler + init/create txs
```

**Keeper/Executor model** (see `FlowCron.cdc` doc comment and `CronContext.executionMode`): each cron tick schedules two transactions — an Executor (runs user code at the tick) and a Keeper (runs `keeperOffset = 1s` later, schedules the next tick's pair). Keeper uses the contract-fixed `keeperPriority` (Medium); Executor uses the caller-supplied priority. `ScheduleCronHandler.cdc` bootstraps the chain by scheduling both for the first tick.

**Dependency order:** `FlowCron` imports `FlowCronUtils`, so `FlowCronUtils` must deploy first (reflected in `flow.json` `deployments` arrays).

## Conventions and Gotchas

- **Testing alias is `0x0000000000000007`**, not the service account. `flow.json` sets `contracts.FlowCron.aliases.testing` / `FlowCronUtils.aliases.testing` / `Counter` / `CounterTransactionHandler` all to `0000000000000007`. Tests using `Test.serviceAccount()` deploy against this alias.
- **`FlowTransactionSchedulerUtils` has no emulator alias** in `flow.json` dependencies (only `testnet` and `mainnet`). On emulator it must be pulled/aliased manually before any transaction that imports it will resolve.
- **`ScheduleCronHandler.cdc` argument order is fixed** and positional: `(StoragePath, AnyStruct?, UInt8 priority, UInt64 executorEffort, UInt64 keeperEffort)`. Priority enum: `0=High`, `1=Medium`, `2=Low`. High priority can be rejected if the slot is full — the tick is then skipped (emits `CronEstimationFailed`). Use Medium (`1`) for guaranteed scheduling.
- **Capabilities live inside the `CronHandler` resource**, not in transaction data. When creating a CronHandler (see README Quick Start and `CreateCronHandler.cdc`), issue capabilities for the wrapped handler, `FlowToken.Vault` (with `FungibleToken.Withdraw` auth), and the `FlowTransactionSchedulerUtils.Manager` (with `Owner` auth) before calling `FlowCron.createCronHandler`.
- **Cancel refunds the fee vault.** `CancelCronSchedule.cdc` only cancels txs whose status is `FlowTransactionScheduler.Status.Scheduled` and deposits the refund back to `/storage/flowTokenVault`.
- **Never edit `cadence/tests/mocks/**`** as if it were production code — those contracts (`Counter`, `CounterTransactionHandler`) exist only for tests and the emulator/testnet end-to-end guides.
- **Do not commit key files.** `.gitignore` excludes `*.pkey` and `.env`; the mainnet account uses Google KMS (`flow.json` `accounts.mainnet-account.key.type = "google-kms"`), no local key.

## Files Not to Modify

- `*.pkey` — git-ignored account keys.
- `.audit-extract.json`, `SEO_AUDIT_REPORT.md` — tooling artifacts outside the contract surface.
