//
//  LiveOverlayStackTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//
//  Overlay stacking and toggle rules, the template editor draft, and the
//  program-frame math used to place overlays.
//

import CoreGraphics
import Foundation
import Testing
@testable import EclipseiPhone

struct LiveOverlayStackTests {

    // MARK: - Toggle

    @Test func tapPutsOnTapAgainTakesOff() {
        var stack = LiveOverlayStack()
        let card = LiveOverlayID.template(UUID())
        #expect(stack.toggle(card) == true)
        #expect(stack.contains(card))
        #expect(stack.toggle(card) == false)
        #expect(stack.isEmpty)
    }

    @Test func severalOverlaysStack() {
        var stack = LiveOverlayStack()
        let a = LiveOverlayID.template(UUID())
        let b = LiveOverlayID.media("photo-1")
        stack.toggle(a)
        stack.toggle(b)
        #expect(stack.contains(a) && stack.contains(b))
        stack.remove(a)
        #expect(!stack.contains(a) && stack.contains(b))
        stack.removeAll()
        #expect(stack.isEmpty)
    }

    // MARK: - Draw Order

    @Test func drawOrderFollowsStackOrderNotActivation() {
        var stack = LiveOverlayStack()
        let top = LiveOverlayID.template(UUID())
        let bottom = LiveOverlayID.media("clip")
        stack.toggle(top)
        stack.toggle(bottom)
        let orders: [LiveOverlayID: Int] = [top: 5, bottom: 1]
        #expect(stack.drawOrder { orders[$0] } == [bottom, top])
    }

    @Test func drawOrderSkipsDeletedAndBreaksTiesStably() {
        var stack = LiveOverlayStack()
        let a = LiveOverlayID.media("a")
        let b = LiveOverlayID.media("b")
        let gone = LiveOverlayID.template(UUID())
        [b, gone, a].forEach { stack.toggle($0) }
        let order = stack.drawOrder { $0 == gone ? nil : 0 }
        #expect(order == [a, b])
    }

    @Test func pruneDropsOverlaysWhoseSourceIsGone() {
        var stack = LiveOverlayStack()
        let keep = LiveOverlayID.media("keep")
        let gone = LiveOverlayID.media("gone")
        stack.toggle(keep)
        stack.toggle(gone)
        stack.prune { $0 == keep }
        #expect(stack.liveIds == [keep])
    }

    // MARK: - Editor Draft

    @Test func newDraftNeedsFirstFieldBeforeAdd() {
        var draft = TemplateCardDraft(newCardOf: .lowerThird)
        #expect(!draft.canCommit)
        draft.fields["name"] = "Jane"
        #expect(draft.canCommit)
        #expect(draft.config.autoRemoveAfterSeconds == nil)
    }

    @Test func cornerChoiceDocksAndCenterPlaces() {
        var draft = TemplateCardDraft(newCardOf: .lowerThird)
        draft.setPosition(.corner(.topLeading))
        #expect(draft.config.corner == .topLeading)
        #expect(draft.config.placement == nil)
        draft.setPosition(.center)
        #expect(draft.position == .center)
        #expect(draft.config.placement?.centerX == 0.5)
    }

    @Test func qrStartsCenteredLikeTheMac() {
        let draft = TemplateCardDraft(newCardOf: .qrCode)
        #expect(draft.position == .center)
    }

    @Test func announcementAutoRemoveIsClamped() {
        var draft = TemplateCardDraft(newCardOf: .announcement)
        draft.autoRemoveEnabled = true
        draft.autoRemoveSeconds = 1
        #expect(draft.config.autoRemoveAfterSeconds == 3)
        var lower = TemplateCardDraft(newCardOf: .lowerThird)
        lower.autoRemoveEnabled = true
        #expect(lower.config.autoRemoveAfterSeconds == nil)
    }

    @Test func editingKeepsTheMacAIFlag() throws {
        var config = OverlayCardTemplate.descriptor(for: .wifi).sampleConfig
        config.madeByAI = true
        let draft = TemplateCardDraft(editing: ShowTemplateCard(showId: UUID(), config: config))
        #expect(draft.config.madeByAI == true)
    }

    @Test func lookChangesPaletteButNotTemplate() {
        var draft = TemplateCardDraft(newCardOf: .scoreboardVersus)
        draft.applyLook(.corporate)
        #expect(draft.look == .corporate)
        #expect(draft.config.template == .scoreboardVersus)
    }

    // MARK: - Program Frame

    @Test func programFrameLetterboxesToAspect() {
        let wide = LiveOverlayLayerView.programFrame(in: CGSize(width: 400, height: 400), aspect: 16.0 / 9.0)
        #expect(wide.width == 400)
        #expect(abs(wide.height - 225) < 0.001)
        #expect(abs(wide.minY - 87.5) < 0.001)
        let whole = LiveOverlayLayerView.programFrame(in: CGSize(width: 300, height: 100), aspect: nil)
        #expect(whole == CGRect(x: 0, y: 0, width: 300, height: 100))
    }

    @Test func mediaOverlayEntryClamps() {
        let entry = MediaOverlayEntry(
            itemId: "x", isVideo: false, centerX: 2, centerY: -1, scale: 5, stackOrder: 0
        ).clamped()
        #expect(entry.centerX == 1 && entry.centerY == 0)
        #expect(entry.scale == MediaOverlayEntry.scaleRange.upperBound)
    }
}
