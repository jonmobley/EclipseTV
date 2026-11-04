//
//  PrompterTextLayoutTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import Testing
@testable import EclipseiPhone

@MainActor
struct PrompterTextLayoutTests {

    private let script = """
    Good evening, everyone, and welcome to the show.

    Tonight we have three segments. First a short film, then a conversation \
    with the director, and finally your questions from the floor.
    Thank you for coming.
    """

    @Test func emptyScriptIsOneLineAtTheStart() {
        let layout = PrompterTextLayout(script: "", font: PrompterStageMetrics.font(ofSize: 32), width: 300)
        #expect(layout.isEmpty)
        #expect(layout.contentHeight == layout.lineHeight)
        #expect(layout.anchor(atTextY: 10) == .start)
        #expect(layout.textY(for: .start) == 0)
        #expect(layout.lines(around: .start).lines == [""])
    }

    @Test func anchorRoundTripsWithinOneLayout() {
        let layout = PrompterTextLayout(script: script, font: PrompterStageMetrics.font(ofSize: 32), width: 360)
        let y = layout.lineHeight * 2.5
        let anchor = layout.anchor(atTextY: y)
        #expect(abs(layout.textY(for: anchor) - y) < 0.5)
        #expect(layout.lineIndex(for: anchor) == 2)
    }

    @Test func anchorLandsOnTheSameWordsInAWiderLargerLayout() throws {
        let narrow = PrompterTextLayout(script: script, font: PrompterStageMetrics.font(ofSize: 32), width: 360)
        let wide = PrompterTextLayout(script: script, font: PrompterStageMetrics.font(ofSize: 73), width: 1600)
        #expect(narrow.lineCount > wide.lineCount)
        let anchor = narrow.anchor(atTextY: narrow.lineHeight * 4.2)
        let wideLines = wide.lines(around: anchor)
        let current = wideLines.lines[wideLines.currentIndex]
        let target = (script as NSString).substring(from: anchor.characterIndex)
        let firstWord = try #require(target.split(separator: " ").first)
        #expect(current.contains(firstWord))
    }

    @Test func linesAroundIncludeNeighboursAndMarkTheCurrent() {
        let layout = PrompterTextLayout(script: "one\ntwo\nthree\nfour", font: PrompterStageMetrics.font(ofSize: 32), width: 400)
        let anchor = layout.anchor(atTextY: layout.lineHeight * 1.5)
        let result = layout.lines(around: anchor)
        #expect(result.lines == ["one", "two", "three"])
        #expect(result.currentIndex == 1)
        let last = layout.anchor(atTextY: layout.lineHeight * 3.5)
        let tail = layout.lines(around: last)
        #expect(tail.lines == ["three", "four"])
        #expect(tail.currentIndex == 1)
    }

    @Test func blankLinesCountAsLines() {
        let layout = PrompterTextLayout(script: "a\n\nb", font: PrompterStageMetrics.font(ofSize: 32), width: 400)
        #expect(layout.lineCount == 3)
        #expect(layout.contentHeight == layout.lineHeight * 3)
    }
}
