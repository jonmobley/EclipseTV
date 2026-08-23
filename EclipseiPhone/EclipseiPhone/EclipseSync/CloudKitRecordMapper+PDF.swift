//
//  CloudKitRecordMapper+PDF.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import CloudKit
import Foundation

// MARK: - PDFDoc

extension CloudKitRecordMapper {

    /// Builds a PDFDoc record, attaching the file as a `CKAsset` when it is on disk.
    ///
    /// - Parameters:
    ///   - assetURL: Local `.pdf` to upload. Pass nil only when the file is missing;
    ///     the record then carries metadata alone and the asset is filled in later.
    ///   - showId: A Show that contains this PDF. Stored as a field always; used
    ///     as CloudKit `parent` only when `attachAsShareChild` is true. A PDF may
    ///     be in several Shows, but CloudKit allows one parent, so the caller picks.
    ///   - attachAsShareChild: Set `parent` so the PDF rides with that Show's
    ///     `CKShare`. Must be false unless the Show is a share root.
    static func makePDFRecord(
        from doc: SavedPDF,
        existing: CKRecord? = nil,
        assetURL: URL? = nil,
        showId: UUID? = nil,
        modifiedAt: Date = Date(),
        attachAsShareChild: Bool = false
    ) -> CKRecord {
        let record = existing ?? CKRecord(
            recordType: CloudKitSchema.RecordType.pdfDoc,
            recordID: CloudKitSchema.pdfRecordID(for: doc.id)
        )
        record[CloudKitSchema.PDFKey.title] = doc.title as CKRecordValue
        record[CloudKitSchema.PDFKey.createdAt] = doc.createdAt as CKRecordValue
        record[CloudKitSchema.PDFKey.modifiedAt] = modifiedAt as CKRecordValue
        applyShowLink(
            to: record,
            showId: showId,
            showIdKey: CloudKitSchema.PDFKey.showId,
            attachAsShareChild: attachAsShareChild
        )
        if let assetURL {
            record[CloudKitSchema.PDFKey.asset] = CKAsset(fileURL: assetURL)
        }
        return record
    }

    /// Saved PDF from a PDFDoc record (the file itself is handled by the caller).
    static func savedPDF(from record: CKRecord) -> SavedPDF? {
        guard record.recordType == CloudKitSchema.RecordType.pdfDoc,
              let uuid = UUID(uuidString: record.recordID.recordName),
              let title = record[CloudKitSchema.PDFKey.title] as? String
        else { return nil }
        let createdAt = (record[CloudKitSchema.PDFKey.createdAt] as? Date) ?? Date()
        return SavedPDF(
            id: uuid,
            title: UserDisplayName.clamp(title),
            createdAt: createdAt
        )
    }

    /// Local temp URL CloudKit staged the PDF bytes at, if the record carries them.
    static func pdfAssetURL(from record: CKRecord) -> URL? {
        (record[CloudKitSchema.PDFKey.asset] as? CKAsset)?.fileURL
    }
}
