//
//  VideoImportDetailView.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Format line, plus an optional caution, shown under the import thumbnail picker.
///
/// Both halves collapse when empty so the sheet keeps its layout for the common case of
/// a clip with nothing worth saying about it.
final class VideoImportDetailView: UIStackView {

    private let formatLabel: UILabel = {
        let label = UILabel()
        label.textColor = .lightGray
        label.font = .monospacedDigitSystemFont(ofSize: 14, weight: .regular)
        label.textAlignment = .center
        return label
    }()

    private let noticeLabel: UILabel = {
        let label = UILabel()
        label.textColor = .systemOrange
        label.font = .systemFont(ofSize: 13)
        label.textAlignment = .center
        label.numberOfLines = 0
        return label
    }()

    init() {
        super.init(frame: .zero)
        axis = .vertical
        alignment = .fill
        spacing = 6
        addArrangedSubview(formatLabel)
        addArrangedSubview(noticeLabel)
        configure(format: nil, notice: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Shows the format line and caution, hiding whichever has nothing to say.
    func configure(format: String?, notice: String?) {
        formatLabel.text = format
        formatLabel.isHidden = (format ?? "").isEmpty
        noticeLabel.text = notice
        noticeLabel.isHidden = (notice ?? "").isEmpty
        isHidden = formatLabel.isHidden && noticeLabel.isHidden
    }
}
