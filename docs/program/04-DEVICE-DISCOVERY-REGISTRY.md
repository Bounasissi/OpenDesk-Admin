# Plan 04 — Device Discovery and Registry

> Binding instruction document. Read `/AGENTS.md`, `docs/architecture/SYSTEM_ARCHITECTURE.md`, and `docs/architecture/DATA_MODEL.md` first.
> Execute in an isolated worktree/branch per `AGENTS.md` §4.

- **Plan ID:** 04
- **Prerequisites:** 03
- **Blocks:** 05–13

---

## 1. Goal

Reliably find, identify, persist, and classify candidate machines.

---

## 2. Required Capabilities

### 2.1 Manual targets

Support: `hostname`, `IPv4`, `IPv6`.

### 2.2 Bonjour/mDNS

Discover useful remote-management services when advertised.

### 2.3 Network scan

Bounded CIDR scanning with:

```text
concurrency limit
timeout
cancellation
deduplication
IPv4/IPv6 correctness
rate control
```

Probe capabilities rather than guessing them. Useful capability probes:

```text
RFB : 5900
ARD/reporting : 3283
SSH : 22
OpenDesk Agent : project-defined port/service
```

### 2.4 Identity reconciliation

A machine may have multiple IP addresses, multiple interfaces, changing DHCP address, and Bonjour hostname changes. Do not create a new device merely because its IP changed. Implement a confidence-based reconciliation strategy using stable signals when available.

### 2.5 Device lifecycle

Support states:

```text
unknown
online
degraded
offline
retired
```

### 2.6 Groups

Support static lists immediately. Smart-group predicate engine follows once device properties exist (see `docs/architecture/DATA_MODEL.md`).

---

## 3. Agent Sequence

1. Implement manual target ingestion with validation (hostname syntax, IPv4/IPv6 parse, CIDR parse).
2. Implement mDNS browser with service filtering.
3. Implement bounded CIDR scanner (bounded concurrency, per-probe timeout, cancellation tokens, rate limiting, dedup by identity key).
4. Implement capability prober (TCP banner/probe for 5900/22/3283, agent service probe; record observed capabilities into `device_capabilities`).
5. Implement identity reconciliation (confidence scoring across MAC/IP/hostname/service fingerprints; merge policy).
6. Implement lifecycle state machine and persistence.
7. Implement static groups UI + persistence.

---

## 4. Tests Required

Acceptance tests must cover:

```text
duplicate discovery
host disappearance
IP changes
timeouts
invalid CIDR
IPv6
cancellation
500+ candidate addresses
database restart persistence
```

Use in-process fakes for network layers in unit tests; a scripted local integration lane exercises real loopback sockets.

---

## 5. Exit Gate

An administrator can discover, manually add, persist, remove, and group devices.

---

## 6. Status Update

On completion update `docs/status/PROGRAM_STATUS.md` and `program-state.json` (next: `05-IDENTITY-SECRETS-SECURITY`).
