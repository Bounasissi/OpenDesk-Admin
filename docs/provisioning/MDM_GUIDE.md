# MDM / Provisioning Guide — OpenDesk (Plan 13)

> Production provisioning supersedes the manual bootstrap
> (`scripts/setup-client.sh` — developer/manual bootstrap only).
> Automate what the platform legally permits; **never bypass TCC/user consent**.

## Configuration payloads (per vendor, where public MDM capabilities permit)

| Vendor | Delivery | Notes |
|---|---|---|
| Generic Apple MDM | `.mobileconfig` custom payload | agent installation via managed PKG install; managed preferences via `ConfigurationProfiles` (shipped server links it — B6 observation) |
| Jamf Pro | Package + policy + custom payload | agent `.pkg` via Jamf packages; enrollment token via managed `defaults write` |
| Kandji | Custom app library item + parameters | same payload contract |
| Mosyle | Custom app + managed preferences | same payload contract |
| Intune (macOS) | Shell script + LOB app | `setup-client.sh` boundary; no TCC bypass |

## Automated (where permitted)

```text
agent installation (managed .pkg)
configuration (managed preferences)
certificate deployment
background service registration (LaunchDaemon plist + SMAppService)
Remote Management activation (per Apple's documented flow)
```

## System-consent boundary (Plan 13 §4)

macOS requires user/administrator consent for: Screen Recording, Accessibility,
notifications, Local Network access. OpenDesk **detects and instructs**
(Plan 15 §5); it never claims a permission was granted until the OS reports it.

## Enrollment diagnostics (Plan 13 §5 — one command)

`opendesk-agent status` reports: agent installed, daemon state, user agent
state, enrolled identity, database reachability, Screen Recording state,
Accessibility state, network reachability. Implemented in
`Sources/OpenDeskAgent/main.swift` (verified live).
