# Integration Audit — Confirmed Direction

**Date:** 2026-07-28  
**Source:** iPhone vs Apple TV Integration Audit

## Decision

**Hybrid: keep AirPlay-by-design now; harden the dual path; stage native TV later.**

| Path | Stance |
|------|--------|
| **Path A — Multipeer** (`EclipseShareProtocol` → `EclipseAppleTV`) | Treat as **complete**. No protocol catch-up work. Library images/videos, playback remote, display mode, content transition, account/albums, multi-TV sync stay as they are. |
| **Path B — AirPlay** (`ExternalDisplayManager` → external display) | Treat camera, web, PDF, logo, black, and ambient audio as **intentionally phone-rendered**. Do not block shipping on native tvOS ports. |
| **Near-term work** | Dual-path UX/QA hardening (see `IntegrationAudit-QAMatrix.md`). |
| **Later work** | Phased native `EclipseAppleTV` support if product wants Multipeer delivery for Path B features (see `IntegrationAudit-NativeTVScope.md`). |

## Why this direction

1. Protocol copies are identical; every `Kind` is handled correctly on both sides.
2. Path B has **no** TV-side stubs — native support would be greenfield (new kinds, envelopes, renderers).
3. AirPlay already delivers Path B to Apple TV (and other receivers) without companion changes.
4. Shipping risk is confusion when **both** paths are active (library on Multipeer TV app vs overlays on AirPlay), not missing Multipeer handlers.

## Out of scope for this confirmation

- Changing Apple TV Caches / `UserDefaults` album storage (locked by project rule).
- Implementing native TV Path B features in this pass (sketch only).
- Editing the Cursor plan file.
