# Legal & Engineering Policy

## 1. Clean-Room Commitment

OpenDesk-Admin is built by **functional specification only**, derived from publicly available documentation (App Store description, Apple support articles, public discussion). This repository contains and will never contain:

1. Apple source code, object code, or binaries.
2. Disassembled, decompiled, or "deobfuscated" output of any Apple product, including Apple Remote Desktop.
3. Apple artwork, icons, UI assets, or strings copied from Apple software.
4. Redistribution instructions for Apple software outside its license terms.

## 2. Why the original prompt's "deobfuscation" step is excluded

The initial goal included decompiling/deobfuscating Apple's Remote Desktop binary. That step is excluded because:

- Apple's software EULA and DMCA §1201 prohibit reverse engineering of macOS system software components; distributing derived artifacts would taint the entire project and expose every contributor to legal risk.
- It is also **unnecessary**: the functional surface of ARD (screen control, tasks, inventory, distribution) is achievable with open standards (RFB/VNC per RFC 6143, SSH, `installer`, `system_profiler`) that Apple itself supports.
- Clean-room functional reimplementation is the established, legally sound pattern (compare: open VNC clients, open SMB/NFS implementations).

## 3. Trademark

"Apple Remote Desktop" and "macOS" are trademarks of Apple Inc. This project is not affiliated with, endorsed by, or derived from Apple Inc. The name "OpenDesk-Admin" does not incorporate Apple trademarks.

## 4. User Responsibilities

- Users must hold administrator credentials and authorization for any machine they administer with this tool.
- Screen observation/control of machines you do not own or administer may violate local law (e.g., computer fraud statutes, wiretap laws). The tool does not bypass authentication of any kind.
