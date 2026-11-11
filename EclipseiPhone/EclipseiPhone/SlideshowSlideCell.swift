//
//  SlideshowSlideCell.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// One slide in the slideshow editor: thumbnail, an editable name, its position,
/// and the slide's own Fit / Fill.
///
/// The name edits in place (no alert). The Fit / Fill control is a labelled pill
/// that opens a two-item menu, and it is hidden when the slide is already shaped
/// like the screen, where Fit and Fill look the same.
final class SlideshowSlideCell: UITableViewCell, UITextFieldDelegate {

    static let reuseId = "SlideshowSlideCell"
    static let thumbnailSide: CGFloat = 72

    /// Called with the new name (nil or blank clears it) when editing ends.
    var onRename: ((String?) -> Void)?
    /// Called when the user picks Fit or Fill.
    var onSelectFit: ((MediaFitMode) -> Void)?

    private let thumbnailView = UIImageView()
    private let nameField = UITextField()
    private let positionLabel = UILabel()
    private let fitButton = UIButton(configuration: .gray())

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        setUpViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        onRename = nil
        onSelectFit = nil
        thumbnailView.image = nil
    }

    /// Fills the row.
    /// - Parameters:
    ///   - name: The slide's title, or nil to show the "Slide N" placeholder.
    ///   - fitMode: The slide's Fit / Fill, or nil to hide the control.
    ///   - hasCustomFraming: Shows "Custom" instead of Fit / Fill.
    func configure(
        thumbnail: UIImage?,
        name: String?,
        position: Int,
        fitMode: MediaFitMode?,
        hasCustomFraming: Bool
    ) {
        thumbnailView.image = thumbnail
        let placeholder = "Slide \(position)"
        nameField.placeholder = placeholder
        if !nameField.isFirstResponder {
            nameField.text = name
        }
        nameField.accessibilityLabel = "Name of slide \(position)"
        positionLabel.text = name == nil ? nil : placeholder
        positionLabel.isHidden = name == nil

        guard let fitMode else {
            fitButton.isHidden = true
            return
        }
        fitButton.isHidden = false
        let title = hasCustomFraming ? "Custom" : fitMode.rawValue
        fitButton.configuration?.title = title
        fitButton.accessibilityLabel = "Screen Fit, \(title)"
        fitButton.menu = UIMenu(title: "Screen Fit", children: MediaFitMode.allCases.map { mode in
            UIAction(
                title: mode.rawValue,
                subtitle: mode == .fit ? "Whole image, with bars" : "Fills the screen, crops edges",
                state: !hasCustomFraming && mode == fitMode ? .on : .off
            ) { [weak self] _ in
                self?.onSelectFit?(mode)
            }
        })
    }

    // MARK: - UITextFieldDelegate

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }

    func textFieldDidEndEditing(_ textField: UITextField) {
        onRename?(textField.text)
    }

    // MARK: - Layout

    private func setUpViews() {
        thumbnailView.contentMode = .scaleAspectFill
        thumbnailView.clipsToBounds = true
        thumbnailView.layer.cornerRadius = 8
        thumbnailView.backgroundColor = .secondarySystemFill
        thumbnailView.translatesAutoresizingMaskIntoConstraints = false

        nameField.font = .preferredFont(forTextStyle: .body)
        nameField.adjustsFontForContentSizeCategory = true
        nameField.returnKeyType = .done
        nameField.autocapitalizationType = .sentences
        nameField.clearButtonMode = .whileEditing
        nameField.delegate = self
        UserDisplayName.configureTextField(nameField)

        positionLabel.font = .preferredFont(forTextStyle: .footnote)
        positionLabel.adjustsFontForContentSizeCategory = true
        positionLabel.textColor = .secondaryLabel

        let text = UIStackView(arrangedSubviews: [nameField, positionLabel])
        text.axis = .vertical
        text.spacing = 2
        text.translatesAutoresizingMaskIntoConstraints = false

        fitButton.configuration?.cornerStyle = .capsule
        fitButton.configuration?.buttonSize = .small
        fitButton.configuration?.image = UIImage(systemName: "chevron.up.chevron.down")
        fitButton.configuration?.imagePlacement = .trailing
        fitButton.configuration?.imagePadding = 4
        fitButton.configuration?.preferredSymbolConfigurationForImage =
            UIImage.SymbolConfiguration(pointSize: 10, weight: .semibold)
        fitButton.showsMenuAsPrimaryAction = true
        fitButton.setContentHuggingPriority(.required, for: .horizontal)
        fitButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        fitButton.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(thumbnailView)
        contentView.addSubview(text)
        contentView.addSubview(fitButton)

        let side = Self.thumbnailSide
        let margins = contentView.layoutMarginsGuide
        NSLayoutConstraint.activate([
            thumbnailView.leadingAnchor.constraint(equalTo: margins.leadingAnchor),
            thumbnailView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            thumbnailView.widthAnchor.constraint(equalToConstant: side),
            thumbnailView.heightAnchor.constraint(equalToConstant: side),
            thumbnailView.topAnchor.constraint(
                greaterThanOrEqualTo: contentView.topAnchor, constant: 8
            ),
            contentView.bottomAnchor.constraint(
                greaterThanOrEqualTo: thumbnailView.bottomAnchor, constant: 8
            ),

            text.leadingAnchor.constraint(equalTo: thumbnailView.trailingAnchor, constant: 12),
            text.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            text.topAnchor.constraint(greaterThanOrEqualTo: margins.topAnchor),

            fitButton.leadingAnchor.constraint(
                greaterThanOrEqualTo: text.trailingAnchor, constant: 8
            ),
            fitButton.trailingAnchor.constraint(equalTo: margins.trailingAnchor),
            fitButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
        ])
        // Keep the name field from shrinking to nothing when there is no Fit button.
        let textTrailing = text.trailingAnchor.constraint(equalTo: margins.trailingAnchor)
        textTrailing.priority = .defaultLow
        textTrailing.isActive = true
    }
}
