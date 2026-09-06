//
//  ExternalDisplaySceneAccessory.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import ObjectiveC
import UIKit

/// Registers noninteractive external-display content for iOS 27+.
///
/// Beginning in iOS 27 the system no longer auto-connects
/// `windowExternalDisplayNonInteractive` scenes. Apps must register a scene
/// accessory on a presented main-interface view controller. This helper uses the
/// Objective-C runtime so the project still builds against the iOS 26 SDK; once
/// Xcode 27 ships, the same selectors resolve to Apple's `UISceneAccessory` API.
@MainActor
enum ExternalDisplaySceneAccessory {

    /// Opaque handle returned by `registerSceneAccessory:`.
    private(set) static var registration: AnyObject?

    /// Whether the system can currently present the registered accessory.
    ///
    /// True only after a successful iOS 27+ registration and while a display is
    /// available. On iOS 18–26 this stays false; connection still flows through
    /// the legacy scene-role path in `AppDelegate`.
    static var isDisplayAvailable: Bool {
        guard let registration else { return false }
        if let value = registration.value(forKey: "isAvailable") as? Bool {
            return value
        }
        if let value = registration.value(forKey: "available") as? Bool {
            return value
        }
        return false
    }

    /// Registers the external-display accessory on `viewController` when supported.
    ///
    /// Safe to call repeatedly; only the first successful registration is kept.
    /// - Parameter viewController: A VC that stays presented in the main interface
    ///   (typically `iPhoneMainViewController`).
    static func register(on viewController: UIViewController) {
        guard registration == nil else { return }
        guard #available(iOS 27.0, *) else { return }
        registration = registerUsingRuntime(on: viewController)
    }

    // MARK: - Runtime bridge (iOS 27 SDK types not required to compile)

    @available(iOS 27.0, *)
    private static func registerUsingRuntime(
        on viewController: UIViewController
    ) -> AnyObject? {
        guard let accessoryClass = NSClassFromString("UISceneAccessory") as? NSObject.Type
        else { return nil }

        let configuration = UISceneConfiguration(
            name: "External Display",
            sessionRole: .windowExternalDisplayNonInteractive
        )
        configuration.delegateClass = ExternalSceneDelegate.self

        guard let accessory = makeAccessory(
            accessoryClass: accessoryClass,
            configuration: configuration
        ) else { return nil }

        let registerSel = NSSelectorFromString("registerSceneAccessory:")
        guard viewController.responds(to: registerSel) else { return nil }

        typealias RegisterIMP = @convention(c) (
            AnyObject, Selector, AnyObject
        ) -> Unmanaged<AnyObject>?
        let imp = unsafeBitCast(
            viewController.method(for: registerSel),
            to: RegisterIMP.self
        )
        return imp(viewController, registerSel, accessory)?.takeUnretainedValue()
    }

    @available(iOS 27.0, *)
    private static func makeAccessory(
        accessoryClass: NSObject.Type,
        configuration: UISceneConfiguration
    ) -> AnyObject? {
        let withUserInfo = NSSelectorFromString(
            "externalNonInteractiveSceneAccessoryWithSceneConfiguration:userInfo:"
        )
        if accessoryClass.responds(to: withUserInfo),
           let method = class_getClassMethod(accessoryClass, withUserInfo) {
            typealias FactoryIMP = @convention(c) (
                AnyClass, Selector, AnyObject, AnyObject?
            ) -> Unmanaged<AnyObject>?
            let imp = unsafeBitCast(
                method_getImplementation(method),
                to: FactoryIMP.self
            )
            return imp(
                accessoryClass, withUserInfo, configuration, nil
            )?.takeUnretainedValue()
        }

        let withConfig = NSSelectorFromString(
            "externalNonInteractiveWithSceneConfiguration:"
        )
        if accessoryClass.responds(to: withConfig),
           let method = class_getClassMethod(accessoryClass, withConfig) {
            typealias FactoryIMP = @convention(c) (
                AnyClass, Selector, AnyObject
            ) -> Unmanaged<AnyObject>?
            let imp = unsafeBitCast(
                method_getImplementation(method),
                to: FactoryIMP.self
            )
            return imp(
                accessoryClass, withConfig, configuration
            )?.takeUnretainedValue()
        }

        let withConfigUserInfo = NSSelectorFromString(
            "externalNonInteractiveWithSceneConfiguration:userInfo:"
        )
        if accessoryClass.responds(to: withConfigUserInfo),
           let method = class_getClassMethod(accessoryClass, withConfigUserInfo) {
            typealias FactoryIMP = @convention(c) (
                AnyClass, Selector, AnyObject, AnyObject?
            ) -> Unmanaged<AnyObject>?
            let imp = unsafeBitCast(
                method_getImplementation(method),
                to: FactoryIMP.self
            )
            return imp(
                accessoryClass, withConfigUserInfo, configuration, nil
            )?.takeUnretainedValue()
        }

        return nil
    }
}
