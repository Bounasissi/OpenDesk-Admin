# POST_V1_ROADMAP — OpenDesk Post-v1 Objectives

> Source requirement: Addendum §28. These objectives are retained so they do not disappear, but **most must not delay v1** (Charter §6 scope discipline).
> Promotion of any item into the v1 critical path requires an ADR tied to a v1 capability.

## Capability Objectives

| Objective | Category | Notes |
|---|---|---|
| Natural-language task creation | UX | LLM-assisted task composer |
| AI-assisted remediation | UX | suggest fixes from findings/incidents |
| Tailscale-native connectivity | Transport | beyond the ssh -L tunnel policy (Plan 07 A1.1) |
| WebRTC / QUIC high-performance transport | Transport | alternative to Plan 14 RFB-native path |
| Configuration drift | Inventory | desired-state comparison engine |
| Desired-state policies | Fleet | declarative policy → enforcement |
| Live telemetry | Observability | streaming fleet metrics |
| REST/network API where justified | Automation | beyond local Unix-socket API |
| Webhooks | Automation | event push on task/incident completion |
| GitOps task definitions | Automation | versioned task-as-code |
| Agent-to-agent execution | Orchestration | chained agent workflows |
| Automatic remediation / retry | Tasks | policy-driven self-healing |
| Health monitoring | Inventory | proactive fleet health scoring |
| Rollback-aware installations | Distribution | transactional package deployment |
| Fleet compliance scoring | Security | per-device posture score |
| Package deployment history | Inventory | per-device install ledger |
| Remote log investigation | Diagnostics | fleet log search |
| Built-in terminal | UX | per-device shell session |
| Remote process manager | Administration | process list/kill via agent |
| launchd / service manager | Administration | service control surface |
| Software-update orchestration | Administration | macOS update scheduling |
| Homebrew fleet management | Administration | package fleet sync |
| Docker management | Administration | deferred explicitly (Charter §6) |
| Apple Shortcuts expansion | Automation | beyond the six v1 intents |
| DashHound integration | Governance | DashHound object mapping (Agent/Roster/Eval/Run) for governed agent operations |
| Remote audio | Streaming | Plan 14 extension |
| HDR | Streaming | Plan 14 extension |
| Virtual-display sessions | Streaming | headless/virtual observe |
| One-to-many screen broadcast | Streaming | presenter → fleet |
| Lock / curtain mode | Control | privacy screen during control |

## Sequencing Guidance

1. First post-v1 wave: Tailscale-native connectivity, drift/desired-state, webhooks, remote log investigation (highest operator value, lowest protocol risk).
2. Streaming extensions (audio/HDR/broadcast) ride on Plan 14 infrastructure.
3. AI-assisted surfaces (NL task creation, remediation) require the governed-ops integration (DashHound mapping) to avoid ungoverned agent actions.
4. Never reprioritize an item above a v1 exit gate without an ADR per Charter §6.
