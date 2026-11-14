//
//  PrompterControllerTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import Testing
@testable import EclipseiPhone

@MainActor
struct PrompterControllerTests {

    final class FakeFrames: PrompterFrameSource {
        var onFrame: ((TimeInterval) -> Void)?
        private(set) var isRunning = false
        func start() { isRunning = true }
        func stop() { isRunning = false }
        func step(_ dt: TimeInterval = 1 / 60) { onFrame?(dt) }
    }

    final class FakeStore: PrompterScriptStoring {
        var scripts: [UUID: String] = [:]
        func script(forShowId showId: UUID) -> String { scripts[showId] ?? "" }
        func set(_ text: String, for showId: UUID) {
            scripts[showId] = text
            NotificationCenter.default.post(name: PrompterScriptStore.didChangeNotification, object: showId)
        }
    }

    private let longScript = (1...60).map { "Line number \($0) of the speech." }.joined(separator: "\n")

    private func makeController(
        store: FakeStore? = nil,
        frames: FakeFrames? = nil
    ) throws -> PrompterController {
        let suite = "PrompterController.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return PrompterController(
            scriptStore: store ?? FakeStore(),
            settings: PrompterLocalSettings(defaults: defaults),
            frames: frames ?? FakeFrames()
        )
    }

    @Test func bindLoadsTheScriptFromTheTop() throws {
        let store = FakeStore()
        let showId = UUID()
        store.scripts[showId] = longScript
        let controller = try makeController(store: store)
        controller.bind(scriptId: showId)
        #expect(controller.script == longScript)
        #expect(controller.offset == 0)
        #expect(controller.canPlay)
        #expect(controller.maxOffset > 0)
        #expect(controller.fontSize == 60)
    }

    @Test func playAdvancesAndPauseStopsFrames() throws {
        let store = FakeStore()
        let frames = FakeFrames()
        let showId = UUID()
        store.scripts[showId] = longScript
        let controller = try makeController(store: store, frames: frames)
        controller.bind(scriptId: showId)
        controller.play()
        #expect(controller.isPlaying)
        #expect(frames.isRunning)
        frames.step(0.5)
        #expect(abs(controller.offset - 20) < 0.001)
        controller.pause()
        #expect(!controller.isPlaying)
        #expect(!frames.isRunning)
    }

    @Test func emptyScriptCannotPlay() throws {
        let controller = try makeController()
        controller.bind(scriptId: UUID())
        controller.play()
        #expect(!controller.isPlaying)
    }

    @Test func playbackAutoPausesAtTheEnd() throws {
        let store = FakeStore()
        let frames = FakeFrames()
        let showId = UUID()
        store.scripts[showId] = "one\ntwo\nthree"
        let controller = try makeController(store: store, frames: frames)
        controller.bind(scriptId: showId)
        controller.setSpeed(3)
        controller.play()
        for _ in 0..<600 where controller.isPlaying { frames.step(0.1) }
        #expect(!controller.isPlaying)
        #expect(controller.offset == controller.maxOffset)
        #expect(controller.progress == 1)
    }

    @Test func scrubbingFreezesPlaybackButKeepsItPlaying() throws {
        let store = FakeStore()
        let frames = FakeFrames()
        let showId = UUID()
        store.scripts[showId] = longScript
        let controller = try makeController(store: store, frames: frames)
        controller.bind(scriptId: showId)
        controller.play()
        controller.beginScrub()
        let before = controller.offset
        frames.step(1)
        #expect(controller.offset == before)
        #expect(controller.isPlaying)
        controller.scrub(by: -controller.lineHeight * 3)
        #expect(abs(controller.offset - (before + controller.lineHeight * 3)) < 0.001)
        controller.endScrub(velocity: 0)
        #expect(!controller.isScrubbing)
        for _ in 0..<120 { frames.step() }
        #expect(controller.isPlaying)
    }

    @Test func speedAndFontPersistAndClamp() throws {
        let suite = "PrompterController.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let settings = PrompterLocalSettings(defaults: defaults)
        let controller = PrompterController(scriptStore: FakeStore(), settings: settings, frames: FakeFrames())
        controller.setSpeed(9)
        controller.setFontSize(4)
        #expect(controller.speedMultiplier == 3)
        #expect(controller.fontSize == 24)
        #expect(settings.scrollSpeed == 3)
        #expect(settings.fontSize == 24)
        let again = PrompterController(scriptStore: FakeStore(), settings: settings, frames: FakeFrames())
        #expect(again.speedMultiplier == 3)
        #expect(again.fontSize == 24)
    }

    @Test func fontChangeKeepsTheReadingLine() throws {
        let store = FakeStore()
        let showId = UUID()
        store.scripts[showId] = longScript
        let controller = try makeController(store: store)
        controller.bind(scriptId: showId)
        controller.updateStage(width: 400, viewportHeight: 600)
        controller.nudge(lines: 10)
        let anchor = controller.readingAnchor
        controller.setFontSize(controller.fontSize + 24)
        #expect(controller.readingAnchor.characterIndex == anchor.characterIndex)
    }

    @Test func storeChangeReloadsTheBoundScriptOnly() throws {
        let store = FakeStore()
        let showId = UUID()
        let other = UUID()
        store.scripts[showId] = "First"
        let controller = try makeController(store: store)
        controller.bind(scriptId: showId)
        store.set("Ignored", for: other)
        #expect(controller.script == "First")
        store.set("Second", for: showId)
        #expect(controller.script == "Second")
        store.set("", for: showId)
        #expect(!controller.canPlay)
    }

    @Test func liveKeepsPositionAndPlayState() throws {
        let store = FakeStore()
        let frames = FakeFrames()
        let showId = UUID()
        store.scripts[showId] = longScript
        let controller = try makeController(store: store, frames: frames)
        controller.prepareLive(showId: showId, scriptId: showId)
        #expect(controller.isLive)
        #expect(controller.liveShowId == showId)
        #expect(controller.liveScriptId == showId)
        controller.play()
        frames.step(1)
        let offset = controller.offset
        controller.endLive()
        #expect(!controller.isLive)
        #expect(controller.liveShowId == nil)
        #expect(controller.liveScriptId == nil)
        #expect(controller.isPlaying)
        #expect(controller.offset == offset)
    }

    @Test func offsetNotificationPostsOnlyWhenMoving() throws {
        let store = FakeStore()
        let frames = FakeFrames()
        let showId = UUID()
        store.scripts[showId] = longScript
        let controller = try makeController(store: store, frames: frames)
        controller.bind(scriptId: showId)
        var count = 0
        let token = NotificationCenter.default.addObserver(
            forName: PrompterController.offsetDidChangeNotification, object: controller, queue: nil
        ) { _ in count += 1 }
        defer { NotificationCenter.default.removeObserver(token) }
        frames.step()
        frames.step()
        #expect(count == 0)
        controller.play()
        frames.step()
        #expect(count == 1)
    }

    @Test func liveFollowsTheBoundPrompterWithinItsShow() throws {
        let store = FakeStore()
        let frames = FakeFrames()
        let showId = UUID()
        let extraId = UUID()
        store.scripts[showId] = "First"
        store.scripts[extraId] = "Second"
        let controller = try makeController(store: store, frames: frames)
        controller.prepareLive(showId: showId, scriptId: extraId)
        #expect(controller.liveShowId == showId)
        #expect(controller.liveScriptId == extraId)
        #expect(controller.script == "Second")
        controller.bind(scriptId: showId)
        #expect(controller.liveShowId == showId)
        #expect(controller.liveScriptId == showId)
        #expect(controller.script == "First")
    }
}
