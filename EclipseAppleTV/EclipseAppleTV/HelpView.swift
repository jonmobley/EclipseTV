// HelpView.swift
import UIKit

protocol HelpViewDelegate: AnyObject {
    func didTapCloseButton()
}

class HelpView: UIView {
    
    weak var delegate: HelpViewDelegate?
    
    private let titleLabel: UILabel = {
        let label = UILabel()
        label.text = "EclipseTV Help"
        label.textColor = .white
        label.font = UIFont.preferredFont(forTextStyle: .title1)
        label.textAlignment = .center
        return label
    }()
    
    private let helpTextLabel: UILabel = {
        let label = UILabel()
        label.text = """
        • Press Menu button to access options
        
        • Swipe Left/Right to navigate between images
        
        • Swipe Up to view image grid
        
        • Swipe Down to exit grid view
        
        • Press Play/Pause to toggle grid view
        
        
        This app displays the built-in sample images.
        Images are shown fullscreen while maintaining aspect ratio.
        """
        label.textColor = UIColor(white: 0.9, alpha: 1.0) // Lighter, more readable text
        label.font = UIFont.preferredFont(forTextStyle: .body)
        label.textAlignment = .left
        label.numberOfLines = 0
        return label
    }()
    
    private let closeButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Close", for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.titleLabel?.font = UIFont.preferredFont(forTextStyle: .headline)
        return button
    }()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }
    
    private func setupView() {
        backgroundColor = UIColor.black.withAlphaComponent(0.8)
        isHidden = true
        
        addSubview(titleLabel)
        addSubview(helpTextLabel)
        addSubview(closeButton)
        
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        helpTextLabel.translatesAutoresizingMaskIntoConstraints = false
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 60),
            titleLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 40),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -40),
            
            helpTextLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 40),
            helpTextLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 100),
            helpTextLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -100),
            
            closeButton.topAnchor.constraint(equalTo: helpTextLabel.bottomAnchor, constant: 60),
            closeButton.centerXAnchor.constraint(equalTo: centerXAnchor),
            closeButton.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -60)
        ])
        
        closeButton.addTarget(self, action: #selector(closeButtonTapped), for: .primaryActionTriggered)
    }
    
    @objc private func closeButtonTapped() {
        delegate?.didTapCloseButton()
    }
}
