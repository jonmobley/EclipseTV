//
//  SingleInstancePresentation.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

extension UIViewController {

    /// Whether a controller of `type` is already on screen from here: on this
    /// controller's own navigation stack, or anywhere in the chain of modals presented
    /// above it.
    ///
    /// UIKit updates `viewControllers` and `presentedViewController` synchronously
    /// inside `pushViewController` and `present`, so this already reads `true` for the
    /// second of two taps that land while the first transition is still animating.
    /// That is the point: it lets an opener bail before it duplicates the work that
    /// goes with opening a screen, instead of relying on UIKit to drop the second
    /// present with a console warning.
    ///
    /// - Parameter type: Screen to look for, e.g. `WebRemoteViewController.self`.
    func isAlreadyOpen<T: UIViewController>(_ type: T.Type) -> Bool {
        openController(ofType: type) != nil
    }

    /// The already-visible controller of `type`, if any (nav stack, then modal chain).
    ///
    /// - Parameter type: Screen to look for, e.g. `WebRemoteViewController.self`.
    func openController<T: UIViewController>(ofType type: T.Type) -> T? {
        if let found = navigationController?.viewControllers.reversed().compactMap({ $0 as? T }).first {
            return found
        }
        var presented = presentedViewController
        while let host = presented {
            if let found = host.findController(ofType: type) { return found }
            presented = host.presentedViewController
        }
        return nil
    }

    /// Whether `self` is a `type`, or a container holding one.
    private func findController<T: UIViewController>(ofType type: T.Type) -> T? {
        if let match = self as? T { return match }
        for child in children {
            if let found = child.findController(ofType: type) { return found }
        }
        return nil
    }
}
