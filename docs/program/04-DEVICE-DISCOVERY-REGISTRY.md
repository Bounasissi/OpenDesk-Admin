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

---

## Amendment A1 — Three-Conversation Addendum (2026-09-13, Addendum §5, §6, §17)

### A1.1 Discovery breadth is not satisfied by Bonjour alone

Conversation 1 reported `_rfb._tcp` browsing only. That does not satisfy Plan 04. §2 already requires the full set; make the concrete probes explicit:

```text
manual hostname — required
IPv4 — required
IPv6 — required
Bonjour/mDNS — required
CIDR scan — required
RFB probe (5900) — required
SSH probe (22) — required
ARD/reporting probe (3283) — required
OpenDesk Agent probe — required (project-defined port)
```

The conversation-derived implementation covers only Bonjour. CIDR scan, capability probes, and dedupe are VERIFIED-MISSING on the canonical branch → implementation tasks in this plan (reference design: scaffold `Discovery.swift`, branch `OG-Output-Plan-0913`).

### A1.2 Identity reconciliation signals (concretize §2.4)

Reconcile device identity across: DHCP address changes, multiple NICs, hostname changes, Bonjour name changes, IPv4/IPv6 coexistence. Stable-signal confidence order: hardware MAC → machine UUID (agent) → SSH host key → hostname → subnet correlation.

### A1.3 Smart groups are unconditional (tighten §2.6)

Replace "Smart-group predicate engine follows once device properties exist" with: Smart Groups are a v1 requirement (Program Charter §3.1). Implement predicate-based groups over fields including:

```text
OS version, architecture, online state, installed software,
agent state, network, inventory values, capability flags
```

**Persist group definitions (the predicate), not only resolved membership.** Resolved membership is derived and cacheable; definitions are source of truth.

### A1.4 Shared-filesystem multi-admin is an experiment, not production architecture (Addendum §17)

The implementation history proposes pointing multiple admins at one shared SQLite file. Treat as an experiment only. Validate before any multi-admin claim: locking semantics, concurrent writers, network-filesystem behavior, sync-provider conflicts, corruption recovery, schema migrations, backup, conflict resolution. If unsafe (expected on SMB/AFP/NFS + sync services), the production design is `local SQLite + authenticated coordination/API service`. **Single-admin local SQLite remains the preferred v1 default.** Record outcome as an ADR before Plan 05 builds on it.
