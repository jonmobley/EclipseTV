# Eclipse Sync — Multi-Device Verification

Phase 1 leaves Apple TV out of CloudKit (`EclipseSyncTVPolicy.appleTVParticipates == false`).

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
