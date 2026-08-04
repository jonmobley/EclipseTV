//
//  SalvagingListDecoder.swift
//  EclipseiPhone
//
//  Shared recovery path for stores that persist a list as one JSON blob.
//

import Foundation
import OSLog

/// Decodes a persisted `Codable` list without letting one bad payload destroy it.
///
/// The stores here keep their user-visible lists as a single JSON blob in `UserDefaults`
/// and rewrite that blob on every mutation. A plain `catch { list = [] }` therefore turns
/// a recoverable decode failure — one malformed entry, a field written by a newer build —
/// into permanent loss: the list loads empty and the next `persist()` writes that
/// emptiness over the only copy the user has.
///
/// `decodeList` degrades in three steps instead:
/// 1. Decode the whole payload (the normal path).
/// 2. Salvage element-wise, keeping every entry that still decodes on its own.
/// 3. Copy the raw bytes to a backup key and start empty, so the data survives on disk
///    even though this build cannot read it.
enum SalvagingListDecoder {

    // MARK: - API

    /// Where bytes this build cannot read are parked, keyed off the store's items key.
    static func backupKey(for itemsKey: String) -> String {
        itemsKey + ".unreadableBackup"
    }

    /// A salvaging load: whatever could be read, plus whether anything was lost.
    struct Outcome<Element> {
        let elements: [Element]
        /// True when the payload was unreadable and its bytes were backed up instead.
        let didFailToLoad: Bool
    }

    /// Loads `[Element]` from `itemsKey`, salvaging or backing up a bad payload.
    static func decodeList<Element: Decodable>(
        _ type: Element.Type,
        forKey itemsKey: String,
        from defaults: UserDefaults,
        logger: Logger
    ) -> Outcome<Element> {
        guard let data = defaults.data(forKey: itemsKey) else {
            return Outcome(elements: [], didFailToLoad: false)
        }
        let decoder = JSONDecoder()
        if let decoded = try? decoder.decode([Element].self, from: data) {
            return Outcome(elements: decoded, didFailToLoad: false)
        }

        let label = String(describing: Element.self)
        if let salvaged = try? decoder.decode([Salvaged<Element>].self, from: data) {
            let recovered = salvaged.compactMap(\.element)
            logger.error(
                "Recovered \(recovered.count) of \(salvaged.count) \(label, privacy: .public)"
            )
            if recovered.count != salvaged.count {
                defaults.set(data, forKey: backupKey(for: itemsKey))
            }
            return Outcome(elements: recovered, didFailToLoad: false)
        }

        logger.error("\(label, privacy: .public) payload unreadable; keeping a backup copy")
        defaults.set(data, forKey: backupKey(for: itemsKey))
        return Outcome(elements: [], didFailToLoad: true)
    }

    // MARK: - Private

    /// Decodes one element without failing its whole container.
    private struct Salvaged<Element: Decodable>: Decodable {
        let element: Element?

        init(from decoder: Decoder) throws {
            element = try? Element(from: decoder)
        }
    }
}
