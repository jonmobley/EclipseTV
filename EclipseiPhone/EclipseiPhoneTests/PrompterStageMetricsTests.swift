//
//  PrompterStageMetricsTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import Testing
import UIKit
@testable import EclipseiPhone

struct PrompterStageMetricsTests {

    @Test func topInsetLetsTheFirstLineRestOnTheGuide() {
        #expect(PrompterStageMetrics.topInset(viewportHeight: 600, lineHeight: 40) == 280)
        #expect(PrompterStageMetrics.topInset(viewportHeight: 20, lineHeight: 40) == 0)
    }

    @Test func maxOffsetIsNeverNegative() {
        #expect(PrompterStageMetrics.maxOffset(contentHeight: 400, lineHeight: 40) == 360)
        #expect(PrompterStageMetrics.maxOffset(contentHeight: 30, lineHeight: 40) == 0)
    }

    @Test func canvasFontScalesWithTheStageWidth() {
        let full = PrompterStageMetrics.textWidth(forStageWidth: 1920)
        #expect(PrompterStageMetrics.stageFontSize(canvasFontSize: 60, textWidth: full, isVertical: false) == 60)
        let half = PrompterStageMetrics.textWidth(forStageWidth: 960)
        #expect(abs(PrompterStageMetrics.stageFontSize(canvasFontSize: 60, textWidth: half, isVertical: false) - 30) < 0.001)
        let verticalFull = PrompterStageMetrics.textWidth(forStageWidth: 1080)
        #expect(PrompterStageMetrics.stageFontSize(canvasFontSize: 60, textWidth: verticalFull, isVertical: true) == 60)
        #expect(PrompterStageMetrics.textInset(for: CGSize(width: 1000, height: 500)) == 80)
    }

    @Test func canvasDefaultsMatchTheMac() {
        #expect(PrompterStageMetrics.defaultCanvasFontSize == 60)
        #expect(PrompterStageMetrics.clampedCanvasFontSize(5) == 24)
        #expect(PrompterStageMetrics.clampedCanvasFontSize(500) == 160)
        #expect(PrompterStageMetrics.clampedSpeed(0) == 0.25)
        #expect(PrompterStageMetrics.clampedSpeed(9) == 3)
    }

    @Test func lineHeightIsUniformAndWhole() {
        let font = PrompterStageMetrics.font(ofSize: 56)
        let height = PrompterStageMetrics.lineHeight(for: font)
        #expect(height == height.rounded())
        #expect(height > 56)
        let styled = PrompterStageMetrics.attributedScript("a\n\nb", font: font, color: .white)
        let style = styled.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        #expect(style?.minimumLineHeight == height)
        #expect(style?.maximumLineHeight == height)
    }
}
