//
//  PrompterViewControllerTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import Testing
import UIKit
@testable import EclipseiPhone

@MainActor
struct PrompterViewControllerTests {

    private func makeController(script: String) throws -> PrompterController {
        let store = PrompterControllerTests.FakeStore()
        let showId = UUID()
        store.scripts[showId] = script
        let suite = "PrompterVC.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let controller = PrompterController(
            scriptStore: store,
            settings: PrompterLocalSettings(defaults: defaults),
            frames: PrompterControllerTests.FakeFrames()
        )
        controller.bind(scriptId: showId)
        return controller
    }

    @Test func keyCommandsCoverSpaceEscapeAndReset() throws {
        let controller = try makeController(script: "Hello")
        let vc = PrompterViewController(scriptId: controller.boundScriptId!, controller: controller)
        let inputs = Set(vc.keyCommands?.map(\.input) ?? [])
        #expect(inputs.contains(" "))
        #expect(inputs.contains(UIKeyCommand.inputEscape))
        #expect(inputs.contains("r"))
        #expect(inputs.contains(UIKeyCommand.inputDownArrow))
    }

    @Test func emptyScriptShowsTheEmptyStateAndDisablesPlay() throws {
        let controller = try makeController(script: "")
        let vc = PrompterViewController(scriptId: controller.boundScriptId!, controller: controller)
        vc.loadViewIfNeeded()
        #expect(!vc.emptyLabel.isHidden)
        #expect(vc.emptyLabel.text == PrompterViewController.emptyStateText)
        #expect(!vc.playButton.isEnabled)
    }

    @Test func liveButtonHiddenWithoutActionsAndTogglesWithThem() throws {
        let controller = try makeController(script: "Hello")
        let vc = PrompterViewController(scriptId: controller.boundScriptId!, controller: controller)
        vc.loadViewIfNeeded()
        #expect(vc.liveButton.isHidden)
        var wentLive = false
        vc.liveActions = .init(
            goLive: { wentLive = true; controller.prepareLive(showId: controller.boundScriptId!, scriptId: controller.boundScriptId!); return true },
            stopLive: { controller.endLive() }
        )
        vc.refreshFromController()
        #expect(!vc.liveButton.isHidden)
        #expect(vc.liveButton.accessibilityLabel == "Go Live")
        vc.liveTapped()
        #expect(wentLive)
        #expect(vc.liveButton.accessibilityLabel == "Stop Live")
        vc.liveTapped()
        #expect(vc.liveButton.accessibilityLabel == "Go Live")
    }

    @Test func speedTextReadsNaturally() {
        #expect(PrompterViewController.speedText(1) == "1×")
        #expect(PrompterViewController.speedText(1.5) == "1.5×")
        #expect(PrompterViewController.speedText(0.25) == "0.25×")
        #expect(PrompterViewController.speedText(2.75) == "2.75×")
    }
}
