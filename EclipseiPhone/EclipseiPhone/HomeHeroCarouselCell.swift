//
//  HomeHeroCarouselCell.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Paging Home hero: brand / feature cards with a page control.
final class HomeHeroCarouselCell: UICollectionViewCell, UIScrollViewDelegate {

    static let reuseIdentifier = "HomeHeroCarouselCell"

    /// Preferred card height for the Home hero band.
    static let cardHeight: CGFloat = 168

    private let scrollView = UIScrollView()
    private let pageControl = UIPageControl()
    private var pageViews: [UIView] = []
    private var configuredWidth: CGFloat = 0
    private var isAdjustingOffset = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = contentView.bounds.width
        guard width > 0, abs(width - configuredWidth) > 0.5 else { return }
        configuredWidth = width
        layoutPages(width: width)
    }

    /// Rebuilds pages from `HomeHeroSlide.all`.
    func reload() {
        configuredWidth = 0
        layoutPages(width: contentView.bounds.width)
    }

    // MARK: - Private

    private func setup() {
        backgroundColor = .clear
        contentView.backgroundColor = .clear

        scrollView.isPagingEnabled = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.delegate = self
        scrollView.clipsToBounds = true
        scrollView.layer.cornerRadius = 20
        scrollView.layer.cornerCurve = .continuous
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(scrollView)

        pageControl.numberOfPages = HomeHeroSlide.all.count
        pageControl.currentPage = 0
        pageControl.currentPageIndicatorTintColor = .systemBlue
        pageControl.pageIndicatorTintColor = UIColor.tertiaryLabel
        pageControl.isUserInteractionEnabled = false
        pageControl.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(pageControl)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: contentView.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            scrollView.heightAnchor.constraint(equalToConstant: Self.cardHeight),

            pageControl.topAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: 8),
            pageControl.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            pageControl.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
        isAccessibilityElement = true
        accessibilityTraits = .updatesFrequently
        accessibilityLabel = "Eclipse"
        accessibilityHint = "Swipe horizontally for more"
    }

    /// Content order: [last clone, …slides…, first clone] so paging can wrap.
    private func layoutPages(width: CGFloat) {
        guard width > 0 else { return }
        let slides = HomeHeroSlide.all
        guard !slides.isEmpty else { return }

        pageViews.forEach { $0.removeFromSuperview() }
        let looped = [slides.last!] + slides + [slides.first!]
        pageViews = looped.enumerated().map { index, slide in
            let page = makePage(for: slide)
            page.frame = CGRect(
                x: CGFloat(index) * width,
                y: 0,
                width: width,
                height: Self.cardHeight
            )
            scrollView.addSubview(page)
            return page
        }
        scrollView.contentSize = CGSize(
            width: width * CGFloat(looped.count),
            height: Self.cardHeight
        )

        let logical = min(max(0, pageControl.currentPage), slides.count - 1)
        pageControl.currentPage = logical
        isAdjustingOffset = true
        scrollView.setContentOffset(
            CGPoint(x: CGFloat(logical + 1) * width, y: 0),
            animated: false
        )
        isAdjustingOffset = false
        updateAccessibility()
    }

    private func makePage(for slide: HomeHeroSlide) -> UIView {
        let page = UIView()
        page.clipsToBounds = true
        page.backgroundColor = slide.palette.fallbackColor
        addBackground(for: slide, to: page)
        addTopCenteredCopy(for: slide, to: page)
        return page
    }

    private func addBackground(for slide: HomeHeroSlide, to page: UIView) {
        if let name = slide.imageName, let image = UIImage(named: name) {
            let imageView = UIImageView(image: image)
            imageView.contentMode = .scaleAspectFill
            imageView.translatesAutoresizingMaskIntoConstraints = false
            page.addSubview(imageView)
            pinEdges(imageView, to: page)
            return
        }
        let gradient = GradientView()
        gradient.colors = slide.palette.gradientColors
        gradient.locations = [0, 1]
        gradient.translatesAutoresizingMaskIntoConstraints = false
        page.addSubview(gradient)
        pinEdges(gradient, to: page)
    }

    /// Icon + title + subtitle, centered as a column under the top of the card.
    private func addTopCenteredCopy(for slide: HomeHeroSlide, to page: UIView) {
        let hasImage = slide.imageName.flatMap { UIImage(named: $0) } != nil
        if hasImage { addImageScrim(to: page) }

        let title = makeHeroLabel(
            text: slide.title,
            font: .systemFont(ofSize: 28, weight: .bold),
            color: .white
        )
        let subtitle = makeHeroLabel(
            text: slide.subtitle,
            font: .systemFont(ofSize: 15, weight: .regular),
            color: UIColor.white.withAlphaComponent(0.78)
        )
        subtitle.numberOfLines = 2

        var arranged: [UIView] = []
        if hasImage {
            let logo = UIImageView(image: UIImage(named: "EclipseLogo"))
            logo.contentMode = .scaleAspectFit
            logo.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                logo.widthAnchor.constraint(equalToConstant: 28),
                logo.heightAnchor.constraint(equalToConstant: 28)
            ])
            arranged.append(logo)
        } else if let symbol = slide.systemImage {
            let icon = UIImageView(image: UIImage(
                systemName: symbol,
                withConfiguration: UIImage.SymbolConfiguration(
                    pointSize: 36, weight: .medium
                )
            ))
            icon.tintColor = .white
            arranged.append(icon)
        }
        arranged.append(contentsOf: [title, subtitle])

        let stack = UIStackView(arrangedSubviews: arranged)
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 8
        stack.setCustomSpacing(4, after: title)
        stack.translatesAutoresizingMaskIntoConstraints = false
        page.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: page.topAnchor, constant: 24),
            stack.leadingAnchor.constraint(equalTo: page.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: page.trailingAnchor, constant: -20)
        ])
    }

    private func addImageScrim(to page: UIView) {
        let scrim = GradientView()
        scrim.colors = [
            UIColor.black.withAlphaComponent(0.55),
            UIColor.clear
        ]
        scrim.locations = [0, 0.65]
        scrim.translatesAutoresizingMaskIntoConstraints = false
        page.addSubview(scrim)
        pinEdges(scrim, to: page)
    }

    private func makeHeroLabel(text: String, font: UIFont, color: UIColor) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = font
        label.textColor = color
        label.textAlignment = .center
        return label
    }

    private func pinEdges(_ view: UIView, to page: UIView) {
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: page.topAnchor),
            view.leadingAnchor.constraint(equalTo: page.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: page.trailingAnchor),
            view.bottomAnchor.constraint(equalTo: page.bottomAnchor)
        ])
    }

    private func logicalPage(forContentIndex index: Int) -> Int {
        let count = HomeHeroSlide.all.count
        guard count > 0 else { return 0 }
        if index <= 0 { return count - 1 }
        if index >= count + 1 { return 0 }
        return index - 1
    }

    private func normalizeLoopOffsetIfNeeded() {
        let width = scrollView.bounds.width
        let count = HomeHeroSlide.all.count
        guard width > 0, count > 0 else { return }
        let page = Int(round(scrollView.contentOffset.x / width))
        if page == 0 {
            isAdjustingOffset = true
            scrollView.setContentOffset(
                CGPoint(x: CGFloat(count) * width, y: 0),
                animated: false
            )
            isAdjustingOffset = false
        } else if page == count + 1 {
            isAdjustingOffset = true
            scrollView.setContentOffset(
                CGPoint(x: width, y: 0),
                animated: false
            )
            isAdjustingOffset = false
        }
    }

    private func updateAccessibility() {
        let slides = HomeHeroSlide.all
        guard slides.indices.contains(pageControl.currentPage) else { return }
        let slide = slides[pageControl.currentPage]
        accessibilityLabel = "\(slide.title). \(slide.subtitle)"
        accessibilityValue = "Page \(pageControl.currentPage + 1) of \(slides.count)"
    }

    // MARK: - UIScrollViewDelegate

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard !isAdjustingOffset else { return }
        let width = scrollView.bounds.width
        guard width > 0 else { return }
        let contentIndex = Int(round(scrollView.contentOffset.x / width))
        let logical = logicalPage(forContentIndex: contentIndex)
        if pageControl.currentPage != logical {
            pageControl.currentPage = logical
            updateAccessibility()
        }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        normalizeLoopOffsetIfNeeded()
    }

    func scrollViewDidEndDragging(
        _ scrollView: UIScrollView,
        willDecelerate decelerate: Bool
    ) {
        if !decelerate {
            normalizeLoopOffsetIfNeeded()
        }
    }
}
