# Clean-Room Engineering Policy

## Purpose

OpenDesk Admin is a **clean-room implementation**. It reproduces the *observable behavior* and *administrative outcomes* of Apple Remote Desktop (ARD) without copying, translating, or deriving from Apple's proprietary code, assets, or internal implementation.

## What we do

1. **Use public documentation.** Apple's own ARD User Guide, Apple Developer documentation (CoreGraphics, ScreenCaptureKit, Network.framework), RFC 6143 (RFB/VNC), and published port/protocol references define the external product contract.
2. **Observe behavior.** Dynamic analysis on machines we own/operate: UI transitions, filesystem changes, Unified Log events, network connection metadata, task lifecycle. No encryption bypass, no protection circumvention.
3. **Write behavioral specifications.** Every feature is captured as a YAML behavior spec (`reverse-engineering/behavior-specs/`) describing inputs, states, and observable results — never implementation.
4. **Implement independently.** Implementation agents receive only the behavioral spec, public protocol standards, and our own architecture. They never receive Apple disassembly or translated Apple code.

## What we never do

- Bypass App Store / FairPlay protections.
- Circumvent or patch code-signing protections.
- Ship Apple binaries or extract Apple assets (icons, artwork, strings files).
- Copy substantial Apple implementation code (no disassembly → translation → source pipeline).
- Clone Apple's visual design pixel-for-pixel.
- Distribute analysis artifacts that contain Apple proprietary content.

## Information flow (one-way wall)

```
Apple behavior + public docs + standard protocols + interoperability experiments
        ↓
Behavioral specification (reverse-engineering/)
        ↓
Independent OpenDesk implementation (packages/, apps/)
```

The `reverse-engineering/` tree may reference Apple's *observable* behavior. The `packages/` and `apps/` trees must be implementable from the specs alone.

## Static analysis boundary

Static inspection of the ARD bundle (`otool`, `nm`, `strings`, `plutil`, `codesign -d`) on a lawfully owned copy is permitted **for architecture understanding only** — identifying linked frameworks, XPC services, URL schemes, preference domains, and protocol touchpoints. Findings are recorded as *facts about interfaces*, never as reconstructed logic.

## Review gate

Any PR that adds code or docs derived from Apple disassembly output (decompiled functions, translated logic, copied constants beyond public protocol constants) must be rejected. Reviewers check: "Could this have been written from the behavior spec + public docs alone?"
