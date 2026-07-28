# Integration Audit — Native TV Scope (Phased)

Staged plan if product later wants Path B features on `EclipseAppleTV` over Multipeer instead of (or in addition to) AirPlay. **Not implementing in this pass** — sketch only.

Keep [`EclipseShareProtocol.swift`](../EclipseiPhone/EclipseiPhone/EclipseShareProtocol.swift) duplicated verbatim on both targets (existing rule).

## Priority order

| Phase | Feature | Why first / later |
|-------|---------|-------------------|
| **1** | Logo + Black idle | Small payloads; reuses existing image display path; clears “blank/branded idle” without WKWebView |
| **2** | PDF | Finite document; page/zoom commands map cleanly; PDFKit on tvOS |
| **3** | Web | Large surface (nav, popups, media sync); `WKWebView` on tvOS is constrained vs iPhone remote |
| **4** | Camera | High bandwidth / latency; streaming frames over MC is a different product than AirPlay |
| **5** | Ambient audio | Lowest need on TV — today phone-local by design; only if users want room audio from the Apple TV |

---

## Phase 1 — Logo / Black

### Protocol sketch

```text
Kind (new):
  set_idle_mode = "set_idle_mode"

Envelope fields:
  eclipseMsg: "set_idle_mode"
  mode: "logo" | "black" | "clear"   // clear → return to library live/grid
  // optional for logo:
  // resource send: eclmode_<mode>_idle_logo.<ext>  OR reuse last logo resource id
```

### TV work

- Handle `set_idle_mode` in `ConnectionManager` → `ImageViewController` idle layer.
- Store logo under existing Caches media rules (or a fixed `Caches/Media/.../idle_logo` name) — **do not** migrate storage strategy.
- Black = solid UIView / empty player; no new file.

### iPhone work

- When user taps Logo/Black **and** MC is connected (policy TBD: MC-first vs AP-first vs dual), send `set_idle_mode` in addition to or instead of AP present.

---

## Phase 2 — PDF

### Protocol sketch

```text
Kind (new):
  present_pdf = "present_pdf"       // start / replace document
  pdf_command = "pdf_command"       // page / scroll / zoom
  dismiss_overlay = "dismiss_overlay"  // shared with web/camera later

present_pdf envelope:
  eclipseMsg, documentId, pageCount?, title?
  + MC sendResource: eclpdf_<documentId>.pdf

pdf_command envelope:
  eclipseMsg, documentId
  action: "set_page" | "set_offset" | "set_zoom"
  page: Int?
  offsetX/offsetY: Double?
  zoom: Double?
```

### TV work

- PDFKit (or equivalent) fullscreen viewer; ignore library play while overlay active.
- Mirror commands from phone `PDFRemoteViewController` semantics.

### iPhone work

- Parallel path: keep AP for receivers without EclipseTV; when MC connected, optionally drive TV app.

---

## Phase 3 — Web

### Protocol sketch

```text
Kind (new):
  present_web = "present_web"
  web_command = "web_command"

present_web:
  eclipseMsg, url, pageId?

web_command:
  action: "load" | "scroll" | "zoom" | "media_play" | "media_pause" | "media_seek"
  url?, offsetX/Y?, zoom?, mediaTime?
```

### Hard constraints

- OAuth/popups stay on phone (current `WebPopupViewController` model); TV is display-only or limited navigate.
- HTML5 media sync already exists phone→AP (`EclipseWebMediaSync`); reuse message shapes for MC.
- Evaluate tvOS `WKWebView` limits before committing.

---

## Phase 4 — Camera

### Options (pick one before build)

1. **Low-res JPEG frame stream** over unreliable MC — high CPU/bandwidth; simplest conceptually.
2. **Stay AirPlay-only** — recommended default; native stream rarely worth it vs AP.

If streaming:

```text
Kind:
  present_camera = "present_camera"
  camera_frame = "camera_frame"  // or raw MC unreliable data path
  camera_command = "camera_command"  // park_logo | resume | end
```

Logo-park can reuse Phase 1 idle logo on TV.

---

## Phase 5 — Ambient audio

```text
Kind:
  audio_command = "audio_command"
  // action: play | pause | seek | set_track
  // + sendResource for track files, or stream URL if policy allows
```

Prefer **deferring** unless product requires TV speaker output independent of the phone.

---

## Shared overlay rules (Phases 1–4)

| Rule | Detail |
|------|--------|
| Priority | Idle < library live < PDF/Web/Camera overlay (match phone `OverlaySource` mental model) |
| Dismiss | `dismiss_overlay` returns to previous library current item |
| Manifest | Overlays **never** enter `library_manifest` (same as home Tools row today) |
| Dual path | Document MC-vs-AP preference in Settings when both available |
| Storage | Media files remain under Caches; metadata light; no Application Support migration |

---

## Suggested milestone gates

1. Phase 1 shipping + QA rows B/D updated for idle on TV app.
2. Phase 2 PDF open + page sync round-trip.
3. Phase 3 web load + scroll only (media sync optional follow-up).
4. Explicit go/no-go on Phase 4 after bandwidth prototype.
5. Phase 5 only with clear user request for TV-side audio.
