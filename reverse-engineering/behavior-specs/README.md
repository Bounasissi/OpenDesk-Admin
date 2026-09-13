# Behavior Spec Corpus — Index

Clean-room behavioral specifications of ARD operations. Each spec describes **inputs, states, and observable results only** — never implementation. Implementation agents receive these specs plus public protocol docs; they never receive Apple disassembly.

Format per `docs/CLEAN-ROOM-POLICY.md`.

| Spec | Operation | Priority milestone |
|---|---|---|
| [execute-command.yaml](execute-command.yaml) | Remote UNIX command execution | 3 |
| [copy-files.yaml](copy-files.yaml) | File push/pull | 3 |
| [install-package.yaml](install-package.yaml) | PKG deployment | 3 |
| [power-management.yaml](power-management.yaml) | Wake/sleep/restart/shutdown/logout | 3 |
| [inventory-collect.yaml](inventory-collect.yaml) | Hardware/software/network inventory | 3 |
| [remote-control.yaml](remote-control.yaml) | Observe/control session | 3 |
| [discovery.yaml](discovery.yaml) | Device discovery | 3 |
| [task-lifecycle.yaml](../state-machines/task-lifecycle.md) | Universal task state machine | 3 |

## Experiment fixture convention

Each experiment lives in `fixtures/experiments/<experiment-id>/` with captured artifacts:

```
network.pcapng · unified_log.logexport · fs_usage.txt · process_tree.txt
launchd_dump.txt · sqlite_mutations.sql · ard_task_state.json · notes.md
```

Vary per corpus: 1 KB / 1 GB file · folder · symlink · permissions · ACL · xattr · offline machine · interrupted transfer · slow connection · disk full · destination collision · permission denied.
