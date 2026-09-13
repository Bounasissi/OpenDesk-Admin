# TASK_MODEL — OpenDesk

**Authority:** Decision-precedence level 4. Binding contract for Plan 08 and every operation that becomes a task.

---

## 1. Canonical State Machine

```text
CREATED
  ↓
QUEUED
  ↓
WAITING_FOR_TARGET
  ↓
DISPATCHED
  ↓
RUNNING
  ├── SUCCESS
  ├── FAILED
  ├── CANCELLED
  └── RETRY_WAIT → DISPATCHED
```

Terminal states (`SUCCESS`, `FAILED`, `CANCELLED`) are immutable. Transitions append `task_events` with correlation ID.

---

## 2. Task Object Fields

```text
TaskID
type
target selector
resolved targets
parameters
execution policy
schedule
created at
deadline
state
results
retry policy
idempotency key
correlation ID
```

---

## 3. Target Resolution

Supported selectors:

```text
device IDs
static group
smart group
predicate
```

Resolved targets are **snapshotted at dispatch** unless task semantics explicitly require dynamic resolution (the requirement is recorded per task type). The Plan 15 composer's "review impact" must show the same resolution the engine will dispatch.

---

## 4. Scheduler Modes

```text
run now
run once
RRULE recurrence
run when device returns online
run when predicate becomes true
```

---

## 5. Retry Classification

| Failure class | Retry policy |
|---|---|
| retryable transport | capped exponential backoff + jitter |
| retryable offline | wait-for-online schedule |
| authentication | normally not retryable |
| authorization | not retryable |
| invalid request | not retryable |
| remote execution failure | configurable per task type |

---

## 6. Idempotency Semantics (per type, from Plan 08)

| Task type | Idempotency semantics |
|---|---|
| install package | checksum + staged verify; re-entry safe (verify-before-install) |
| copy files | destination policy + checksum; re-entry safe |
| collect inventory | safe to repeat; deduped snapshots |
| agent operations | version/capability guarded; re-entry safe |
| power | **not idempotent** — requires explicit confirmation + single-dispatch guard |

---

## 7. Concurrency Controls

- Global limit + per-host limit.
- Protects against accidental mass execution of expensive operations.
- Cancellation is cooperative and reaches every adapter (RFB, SSH, agent).

---

## 8. Durability Requirement (exit gate of Plan 08)

Closing and reopening OpenDesk cannot lose scheduled or running task history. Every state transition is persisted before side effects that depend on it.

---

## 9. Per-Target Results (exit gate of Plan 07, honored here)

One operation targeting one Mac or a group returns **independent, structured per-device results** — no aggregate-only outcomes.
