//
//  ScrollSafeMenuButton.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Pull-down button for grid tiles (⋯ and full-tile Add) that opens its menu on a clean
/// tap, never on touch-down and never from a touch that lands while the grid is moving.
///
/// UIKit opens `showsMenuAsPrimaryAction` menus on touch-down, so a scroll that started on a
/// tile's ⋯ popped its menu. Touches go to a plain `MenuTouchArea` instead of the button:
/// scroll views never take a touch away from a `UIControl`, so a drag that starts on ⋯
/// would otherwise not scroll.
final class ScrollSafeMenuButton: UIButton {

    private let touchArea = MenuTouchArea()
    /// True only while `presentMenu` asks UIKit for the menu.
    private var isOpeningFromTap = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        touchArea.frame = bounds
        touchArea.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        touchArea.onTap = { [weak self] in self?.presentMenu() }
        touchArea.onPress = { [weak self] in self?.isHighlighted = $0 }
        addSubview(touchArea)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        super.hitTest(point, with: event) == nil ? nil : touchArea
    }

    // MARK: - Menu

    override func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        configurationForMenuAtLocation location: CGPoint
    ) -> UIContextMenuConfiguration? {
        // A long press asks too; only `presentMenu` may open it.
        guard isOpeningFromTap else { return nil }
        return super.contextMenuInteraction(interaction, configurationForMenuAtLocation: location)
    }

    override func accessibilityActivate() -> Bool {
        guard menu != nil else { return false }
        presentMenu()
        return true
    }

    private func presentMenu() {
        guard menu != nil, !isOpeningFromTap else { return }
        isOpeningFromTap = true
        showsMenuAsPrimaryAction = true
        performPrimaryAction()
        showsMenuAsPrimaryAction = false
        isOpeningFromTap = false
    }
}

/// Takes `ScrollSafeMenuButton`'s touches. Not a `UIControl`, so grids scroll from it.
private final class MenuTouchArea: UIView, UIGestureRecognizerDelegate {

    var onTap: (() -> Void)?
    var onPress: ((Bool) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped))
        tap.delegate = self
        addGestureRecognizer(tap)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func tapped() {
        onTap?()
    }

    /// A touch that stops a moving grid is not a tap on ⋯.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        !isInsideMovingScrollView
    }

    /// Any enclosing scroll view (grid, Home pager) still being dragged or gliding.
    private var isInsideMovingScrollView: Bool {
        var view = superview
        while let current = view {
            if let scrollView = current as? UIScrollView,
               scrollView.isDragging || scrollView.isDecelerating {
                return true
            }
            view = current.superview
        }
        return false
    }

    // Kept here (not passed up) so the button never tracks and the tile never selects.
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        onPress?(true)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {}

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        onPress?(false)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        onPress?(false)
    }
}
