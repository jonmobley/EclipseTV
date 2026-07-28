# Integration Audit — Dual-Path QA Matrix

Validate Multipeer (EclipseTV app), AirPlay (phone-owned external window), and both together. Status pill expectations come from [`HomeHeaderBar.swift`](../EclipseiPhone/EclipseiPhone/HomeHeaderBar.swift).

## Legend

| Symbol | Meaning |
|--------|---------|
| MC | Multipeer link to EclipseAppleTV |
| AP | AirPlay / wired external display via `ExternalDisplayManager` |
| Both | MC connected **and** AP presenting |

---

## A. Connection status pill

| # | Setup | Action | Expected pill | Notes |
|---|--------|--------|---------------|-------|
| A1 | No MC, no AP | Launch home | `Ready` (gray) | Tap opens Settings |
| A2 | MC connecting | Pairing / browsing | `Connecting…` (gray) | |
| A3 | MC only | Paired, no AirPlay | `EclipseTV` (green) | Library remote works |
| A4 | AP only | AirPlay on, MC paused/off | `AirPlay` (blue) | Path B tools work |
| A5 | Both | MC + AP | `EclipseTV · AirPlay` (green) | Both surfaces live |

---

## B. Multipeer only (EclipseTV app, no AirPlay)

| # | Feature | Steps | Expected on TV app |
|---|---------|-------|--------------------|
| B1 | Send image | Add photo → wait transfer | Appears in grid; can go live |
| B2 | Send video | Add video → transfer | Plays; loop/mute settings apply |
| B3 | Play request | Tap library item | Item fullscreen on TV |
| B4 | Playback remote | Play/pause/seek/skip from phone | TV player follows; status updates on phone |
| B5 | Reorder / delete / move | Arrange mode mutations | Manifest updates; TV grid matches |
| B6 | Restore purged | Re-send unavailable item | `restore_item` then resource; item returns |
| B7 | Display mode | Settings → Landscape / Vertical | TV switches `Media/Landscape` vs `Vertical` bucket |
| B8 | Content transition | Cut vs Crossfade | TV switches with chosen style |
| B9 | Join account | Enter join code on phone | TV receives `set_account`; albums sync into Caches |
| B10 | Multi-TV sync | Enable “Keep all Apple TVs in sync”; 2 TVs | Mutations + replay reach both peers |
| B11 | Path B without AP | Open Camera / Website / PDF / Logo / Black with no AP | Phone UI OK; **TV app unchanged** (no protocol for these) |

---

## C. AirPlay only (no EclipseTV Multipeer)

| # | Feature | Steps | Expected on external display |
|---|---------|-------|------------------------------|
| C1 | Library still | Present image/video via AP | Fullscreen on AP window (not EclipseTV app) |
| C2 | Camera live | Home → Camera | Live camera on AP |
| C3 | Camera park Logo | Park / logo chip | AP shows logo; phone camera session stays |
| C4 | Camera close dest | Settings → Camera/Logo/Black; close camera | AP shows configured destination |
| C5 | Web | Website tile or bookmark | WKWebView on AP; scroll/zoom/media sync |
| C6 | Web popup / OAuth | Trigger popup flow | Phone handles popup; session cookies shared |
| C7 | PDF | Open saved PDF | PDFKit on AP; page/scroll/zoom sync |
| C8 | Logo tile | Home → Logo | Still logo on AP |
| C9 | Black | Header Black control | Solid black on AP; control shows live state |
| C10 | Joined album | Join → play item | Streamed on AP (`presentJoined`); phone may not store full file |
| C11 | Ambient audio | Play music while AP shows still/web/PDF | Audio on **phone**; optional Now Playing badge on AP overlay |
| C12 | Display orientation | Landscape vs Vertical + rotation | AP layout/rotation follows `ExternalOutputSettings` |
| C13 | Web text size | Small/Medium/Large | Shared CSS viewport on phone + AP |
| C14 | Background / switcher | Background app briefly during AP | External window survives transient disconnect (coalesce) |

---

## D. Both paths active (highest risk)

| # | Scenario | Steps | Expected |
|---|----------|-------|----------|
| D1 | Library on MC, tool on AP | MC playing video on EclipseTV; start Camera with AP | Pill: `EclipseTV · AirPlay`. AP shows camera. **TV app keeps prior library item** (camera not sent over MC). |
| D2 | Play library while AP overlay | AP showing web; tap library play on MC | MC TV switches library item. AP web overlay behavior: either stays until cleared or yields per current `ExternalDisplayManager` rules — record actual; flag if confusing. |
| D3 | Black while MC live | MC live item + Black on AP | AP black; TV app still shows its live item |
| D4 | Content transition | Change Cut/Crossfade with Both | MC TV applies via `set_content_transition`; AP uses phone `PresentationViewController+Transition` |
| D5 | Display mode Both | Switch Landscape/Vertical | MC bucket switches; AP aspect updates |
| D6 | End AP, keep MC | Stop AirPlay | Pill → `EclipseTV`; TV app library unchanged |
| D7 | End MC, keep AP | Forget/disconnect TV | Pill → `AirPlay`; Path B still works |
| D8 | Join code Both | Set account with MC + browse Join on phone | TV downloads albums; phone Join can also `presentJoined` on AP — two independent viewers of same account |

---

## E. Negative / edge

| # | Case | Expected |
|---|------|----------|
| E1 | MC transfer fail | `IMAGE_ERROR` / `VIDEO_ERROR`; phone surfaces failure; TV rejects bad file |
| E2 | Second peer while TV connected | TV rejects second companion (single-companion model) |
| E3 | AP to non-Apple-TV receiver | Path B still works (no EclipseAppleTV required) |
| E4 | Storage pressure on TV | Missing Caches media dropped; re-send/re-sync recovers (by design) |
| E5 | Shows (local albums) | Organizing only; presenting a member still uses MC and/or AP per item path |

---

## Suggested pass order

1. A (pill) → B (MC baseline) → C (AP baseline) → D (both) → E (edges).
2. Log any D2/D3 UX confusion as product polish candidates (copy, toasts, or auto-yield rules) — not as Multipeer protocol bugs.
