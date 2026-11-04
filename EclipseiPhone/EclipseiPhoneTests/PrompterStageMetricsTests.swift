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

    @Test func outputFontScalesWithTheShorterSideAndFloors() {
        let hd = PrompterStageMetrics.outputFontSize(in: CGSize(width: 1920, height: 1080))
        #expect(abs(hd - 1080 * 0.068) < 0.001)
        let vertical = PrompterStageMetrics.outputFontSize(in: CGSize(width: 1080, height: 1920))
        #expect(vertical == hd)
        #expect(PrompterStageMetrics.outputFontSize(in: CGSize(width: 320, height: 200)) == 40)
    }

    @Test func operatorDefaultsDifferByDevice() {
        #expect(PrompterStageMetrics.defaultOperatorFontSize(isPad: true) == 56)
        #expect(PrompterStageMetrics.defaultOperatorFontSize(isPad: false) == 32)
        #expect(PrompterStageMetrics.clampedOperatorFontSize(5) == 20)
        #expect(PrompterStageMetrics.clampedOperatorFontSize(500) == 120)
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
