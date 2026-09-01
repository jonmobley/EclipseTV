//
//  CloudKitSyncEngine+Delegate.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import CloudKit
import Foundation

// MARK: - CKSyncEngineDelegate

extension CloudKitSyncEngine: CKSyncEngineDelegate {

    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        switch event {
        case .stateUpdate(let update):
            persistEngineState(update.stateSerialization)

        case .accountChange(let change):
            await handleAccountChange(change)

        case .fetchedDatabaseChanges(let changes):
            for deletion in changes.deletions where deletion.zoneID == CloudKitSchema.zoneID {
                // Local content is the user's — never delete it because the server
                // dropped the zone. Recreate and push everything back up.
                logger.warning("Library zone deleted remotely; recreating")
                recoverFromZoneLoss()
            }

        case .fetchedRecordZoneChanges(let changes):
            await applyFetchedModifications(changes.modifications.map(\.record))
            isApplyingRemote = true
            for deletion in changes.deletions {
                EclipseSyncController.shared.applyRemoteDeletion(
                    recordName: deletion.recordID.recordName
                )
            }
            isApplyingRemote = false

        case .sentRecordZoneChanges(let sent):
            await handleSent(sent)

        case .sentDatabaseChanges:
            break

        default:
            break
        }
    }

    func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext,
        syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let scope = context.options.scope
        let changes = syncEngine.state.pendingRecordZoneChanges.filter { scope.contains($0) }
        var mutableRecordMap: [CKRecord.ID: CKRecord] = [:]
        for change in changes {
            if case .saveRecord(let recordID) = change,
               let record = makeRecordToSave(recordID) {
                mutableRecordMap[recordID] = record
            } else if case .saveRecord(let recordID) = change {
                syncEngine.state.remove(pendingRecordZoneChanges: [.saveRecord(recordID)])
            }
        }
        let recordMap = mutableRecordMap
        return await CKSyncEngine.RecordZoneChangeBatch(
            pendingChanges: changes
        ) { recordID in
            recordMap[recordID]
        }
    }

    private func handleSent(_ sent: CKSyncEngine.Event.SentRecordZoneChanges) async {
        for saved in sent.savedRecords {
            noteSavedRecord(saved)
        }
        var didRecoverZone = false
        for failed in sent.failedRecordSaves {
            let code = failed.error.code
            switch CloudKitSaveFailurePolicy.action(
                for: code,
                description: failed.error.localizedDescription
            ) {
            case .holdForQuota:
                holdForQuota(failed.record.recordID)
            case .mergeAndRequeue:
                mergeConflictAndRequeueExpanded(record: failed.record, error: failed.error)
            case .recreateZone:
                if !didRecoverZone {
                    didRecoverZone = true
                    recoverFromZoneLoss()
                }
            case .dropPendingChange:
                engine?.state.remove(pendingRecordZoneChanges: [
                    .saveRecord(failed.record.recordID)
                ])
                logger.error(
                    "Dropped pending save for \(failed.record.recordID.recordName, privacy: .public): \(failed.error.localizedDescription)"
                )
            case .stripShareParentAndRetry:
                retryWithoutShareParent(failed.record)
            case .retryHandledByEngine:
                logger.notice(
                    "Save retry deferred to CKSyncEngine for \(failed.record.recordID.recordName, privacy: .public): \(failed.error.localizedDescription)"
                )
            case .logOnly:
                logger.error(
                    "Save failed \(failed.record.recordID.recordName, privacy: .public): \(failed.error.localizedDescription)"
                )
            }
        }
        for id in sent.deletedRecordIDs {
            forgetLastKnown(id)
            CaptureStore.shared.purge(id: id.recordName)
            ImportedMediaStore.shared.purge(id: id.recordName)
        }
    }

    private func handleAccountChange(_ change: CKSyncEngine.Event.AccountChange) async {
        switch change.changeType {
        case .signOut, .switchAccounts:
            engine = nil
            lastKnownRecords.removeAll()
            await account.refresh()
        case .signIn:
            await bootstrapEngineIfPossiblePublic()
        @unknown default:
            await account.refresh()
        }
    }
}
