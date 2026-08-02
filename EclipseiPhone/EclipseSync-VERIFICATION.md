# Eclipse Sync — Multi-Device Verification

Phase 1 leaves Apple TV out of CloudKit (`EclipseSyncTVPolicy.appleTVParticipates == false`).

## Where CloudKit fits (product map)

| Plane | Primary? | Carries |
|-------|----------|---------|
| **Multipeer → Eclipse Apple TV** | Yes for TV media | Imported library files + control |
| **CloudKit Eclipse Sync** | Yes for multi-iPhone Shows | Shows, membership, captures, Share |
| **HTTPS remote albums** | Optional side channel | Read-only hosted albums (not Shows) |

Do not send captures over Multipeer. Do not expect CloudKit to populate the Apple TV library.

### Phase-1 code gates (kept green)

- New captures upload to CloudKit (`.pendingUpload`); still never Multipeer to Apple TV.
- Orphan recovery / pending flush skip capture provenance.
- Shared-DB apply sets `EclipseSyncController.isApplyingRemote` and private reconcile honors it (no Share → private fork).
- Bootstrap does not stamp Show `modifiedAt` to “now” (LWW-safe).
- Asset download tries private DB, then shared DB (Share recipients).
- Slideshow slides that are captures use AirPlay/local only.

## Manual checklist

1. **Fresh install rebuilds the library**
   - On device A: create two Shows, add captures (when camera→CaptureStore ships), wait for sync.
   - On device B (same Apple ID): install / launch Eclipse.
   - Expect: both Shows appear immediately; media tiles show until tapped (download on demand).

2. **Offline edits reconcile**
   - Airplane mode on device A: rename a Show, reorder membership.
   - Online again: device B shows the rename and unioned membership (no lost adds).

3. **Quota pause**
   - Fill iCloud storage, capture or edit until save fails.
   - Expect: orange banner with quota copy; after freeing space, pending saves resume.

4. **No iCloud account**
   - Sign out of iCloud on the phone.
   - Expect: banner explaining Settings sign-in; local Shows still work; Share Show alerts.

5. **Share Show**
   - Long-press a Show → Share Show… → invite a second Apple ID.
   - Recipient accepts the link; Show appears via the shared-database engine.

6. **Captures never reach Apple TV**
   - Connect a TV; confirm Multipeer uploads do not include capture library ids.
   - Tapping a capture uses phone AirPlay / offline live, never `sendPlayRequest`.

7. **TV manifest cannot drop captures**
   - With captures in a Show, connect a TV that sends a fresh manifest omitting them.
   - Expect: captures remain in `TVLibraryStore.items` and Show membership.
