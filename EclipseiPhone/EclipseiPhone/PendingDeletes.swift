//
//  PendingDeletes.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Deletes that wait out their Undo toast before they really happen.
///
/// A Show or Library item deleted with Undo on offer is only hidden at first.
/// Nothing is removed from disk, iCloud or the Apple TV until the toast has had
/// its time, so Undo just shows it again: no file is gone and no deletion
/// marker ever leaves this phone. The real delete runs when the timer ends or
/// the app goes to the background, whichever comes first. If the app is killed
/// before then, the delete simply never happened.
///
/// Main actor only.
@MainActor
final class PendingDeletes {

    // MARK: - Types

    /// What a pending delete is for; also the key that Undo cancels.
    enum Key: Hashable {
        case show(UUID)
        case libraryItem(String)
        /// A countdown or Live Poll card (its Show token), deleted outright.
        case showCard(String)
    }

    // MARK: - Properties

    static let shared = PendingDeletes()

    /// Posted when something is hidden, put back, or finally deleted.
    static let didChangeNotification = Notification.Name("PendingDeletes.didChange")

    /// How long a delete waits. A little longer than the Undo toast so the
    /// button never outlives the chance to use it.
    static let delay: TimeInterval = PresentationToastTiming.undoDuration + 0.5

    private var commits: [Key: () -> Void] = [:]
    private var tokens: [Key: UUID] = [:]

    // MARK: - Initialization

    init(notificationCenter: NotificationCenter = .default) {
        notificationCenter.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.commitAll() }
        }
    }

    // MARK: - Public Interface

    /// Library ids hidden while their delete waits (media ids and PDF uuids).
    var hiddenLibraryIds: Set<String> {
        Set(commits.keys.compactMap {
            if case .libraryItem(let id) = $0 { return id }
            return nil
        })
    }

    /// Show-card tokens hidden while their delete waits.
    var hiddenShowCardTokens: Set<String> {
        Set(commits.keys.compactMap {
            if case .showCard(let token) = $0 { return token }
            return nil
        })
    }

    /// Whether `key` is waiting to be deleted.
    func isPending(_ key: Key) -> Bool {
        commits[key] != nil
    }

    /// Starts the wait. A second schedule for the same key deletes the first now.
    /// - Parameters:
    ///   - key: What is being deleted.
    ///   - delay: Seconds to wait; `nil` uses `PendingDeletes.delay`.
    ///   - commit: Performs the real delete.
    func schedule(_ key: Key, delay: TimeInterval? = nil, commit: @escaping () -> Void) {
        if commits[key] != nil { self.commit(key) }
        let token = UUID()
        commits[key] = commit
        tokens[key] = token
        postChange()
        DispatchQueue.main.asyncAfter(deadline: .now() + (delay ?? Self.delay)) { [weak self] in
            guard let self, self.tokens[key] == token else { return }
            self.commit(key)
        }
    }

    /// Undo: forgets the delete without running it.
    /// - Returns: false when it already ran (time ran out or the app went to the background).
    @discardableResult
    func cancel(_ key: Key) -> Bool {
        guard commits.removeValue(forKey: key) != nil else { return false }
        tokens[key] = nil
        postChange()
        return true
    }

    /// Runs one delete now.
    func commit(_ key: Key) {
        guard let action = commits.removeValue(forKey: key) else { return }
        tokens[key] = nil
        action()
        postChange()
    }

    /// Runs every waiting delete now (app going to the background).
    func commitAll() {
        for key in Array(commits.keys) {
            commit(key)
        }
    }

    // MARK: - Private Helpers

    private func postChange() {
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }
}
