# Eclipse Sync — Multi-Device Verification

Phase 1 leaves Apple TV out of CloudKit (`EclipseSyncTVPolicy.appleTVParticipates == false`).

## Where CloudKit fits (product map)

| Plane | Primary? | Carries |
|-------|----------|---------|
| **Multipeer → Eclipse Apple TV** | Yes for TV media | Imported library files + control |
| **CloudKit Eclipse Sync** | Yes for multi-iPhone Shows | Shows, membership, captures, websites, slideshows, imports, PDFs, tool libraries, Share |
| **HTTPS remote albums** | Optional side channel | Read-only hosted albums (not Shows) |

Do not send captures over Multipeer. Do not expect CloudKit to populate the Apple TV library.

### Code gates (kept green)

- New captures upload to CloudKit (`.pendingUpload`); still never Multipeer to Apple TV.
- Imported media syncs as `MediaItem` with `provenance=imported` and stays Multipeer-sendable.
- Orphan recovery / pending flush skip capture provenance.
- Shared-DB apply sets `EclipseSyncController.isApplyingRemote` and private reconcile honors it (no Share → private fork).
- Bootstrap does not stamp Show `modifiedAt` to “now” (LWW-safe).
- Asset download tries private DB, then shared DB (Share recipients); imports land under `LocalMedia/`.
- Slideshow slides that are captures use AirPlay/local only.
- Show `deletedItemIds` / `deletedSurfaceIds` prevent union merge from resurrecting removals.
- Unresolved membership renders a Syncing placeholder (not silently dropped).

## Manual checklist

1. **Fresh install rebuilds the library**
   - On device A: create two Shows, add captures, websites, a slideshow, and imported photos; wait for sync.
   - On device B (same Apple ID): install / launch Eclipse.
   - Expect: both Shows appear; websites and slideshows resolve; media tiles may show Syncing / unavailable until tapped (download on demand).

2. **Offline edits reconcile**
   - Airplane mode on device A: rename a Show, reorder membership, remove one item.
   - Online again: device B shows the rename and unioned membership; the removed item stays gone (tombstone).

3. **Quota pause**
   - Fill iCloud storage, capture or edit until save fails.
   - Expect: orange banner with quota copy; after freeing space, pending saves resume.

4. **No iCloud account**
   - Sign out of iCloud on the phone.
   - Expect: banner explaining Settings sign-in; local Shows still work; Share Show alerts.

5. **Share Show**
   - Long-press a Show → Share Show… → invite a second Apple ID.
   - Recipient accepts the link; Show appears via the shared-database engine with websites / slideshows / media children.

6. **Captures never reach Apple TV**
   - Connect a TV; confirm Multipeer uploads do not include capture library ids.
   - Tapping a capture uses phone AirPlay / offline live, never `sendPlayRequest`.

7. **Imports still reach Apple TV**
   - Add a Photos import to a Show; with EclipseTV linked, confirm it still Multipeer-uploads.
   - On device B, the same import appears via CloudKit (placeholder then download).

8. **TV manifest cannot drop captures**
   - With captures in a Show, connect a TV that sends a fresh manifest omitting them.
   - Expect: captures remain in `TVLibraryStore.items` and Show membership.

9. **Tool libraries roam**
   - On device A: set a custom Background and Screensaver; import a camera frame and a cutaway still.
   - On device B: expect the same custom Background / Screensaver / frames / cutaways (account-global).

10. **Prompter script follows the Show (Mac ⇄ iPad)**
    - On the Mac, type a script in the Prompt window for Show A; within a minute the iPad's Prompter tile for Show A shows its first line, and the operator view shows the text. And back: edit on the iPad, the Mac's Prompt window updates.
    - Code gate: Prompter records are unparented; `enqueueShareChildren` never lists them.

11. **Clear propagates**
    - Empty the script on one device; the other goes blank (not stale).

12. **Concurrent edit**
    - Airplane mode on both; edit the script on each; reconnect. The later edit wins on both devices, with no mixed text.

13. **Typing while a remote edit lands**
    - An iPad edit arrives while the Mac editor has focus: the Mac text does not jump; once the cursor leaves, the newer of the two is shown.

14. **Show switch on the Mac**
    - Switching Shows swaps scripts; the Media Library tab keeps the last Show's script.

15. **Migration**
    - A Mac updated from the single-script build shows its old script in the Show that was open, once.

16. **Shared Show stays private**
    - Owner's script never appears on a participant's device; a participant can keep their own script for that Show.

17. **Delete Show**
    - Delete on either device: the other drops the script; CloudKit Console shows no orphan `prompter-<id>` record.

18. **Older builds ignore the record**
    - An older build on a third device keeps syncing Shows unaffected by the Prompter record.
