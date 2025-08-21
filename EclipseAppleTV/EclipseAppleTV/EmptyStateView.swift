import UIKit

protocol EmptyStateViewDelegate: AnyObject {
    func emptyStateViewDidTapOpenApp(_ view: EmptyStateView)
}

class EmptyStateView: UIView {
    
    // MARK: - Delegate
    
    weak var delegate: EmptyStateViewDelegate?
    
    // MARK: - UI Elements
    
    private let containerView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let contentStackView: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.spacing = 50  // Large spacing between QR code and text
        stackView.alignment = .center
        stackView.distribution = .fill  // More flexible distribution
        stackView.translatesAutoresizingMaskIntoConstraints = false
        return stackView
    }()
    
    private let textStackView: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.spacing = 32
        stackView.alignment = .center
        stackView.distribution = .fill  // More flexible distribution
        stackView.translatesAutoresizingMaskIntoConstraints = false
        return stackView
    }()
    
    private let headerLabel: UILabel = {
        let label = UILabel()
        label.text = "Add images and videos"
        label.font = UIFont.systemFont(ofSize: 72, weight: .bold)
        label.textColor = .white
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let bodyLabel: UILabel = {
        let label = UILabel()
        label.text = "Download the Eclipse iPhone app to send images and videos to this device."
        label.font = UIFont.systemFont(ofSize: 42, weight: .regular)
        label.textColor = .lightGray
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let qrCodeImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.image = UIImage(named: "eclipse-qrcode")
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    private let openAppButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Open App", for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 38, weight: .medium)
        button.backgroundColor = UIColor.white.withAlphaComponent(0.15)
        button.layer.cornerRadius = 12
        button.layer.borderWidth = 2
        button.layer.borderColor = UIColor.white.withAlphaComponent(0.3).cgColor
        button.translatesAutoresizingMaskIntoConstraints = false
        
        // Add hover effect for Apple TV
        button.layer.shadowColor = UIColor.white.cgColor
        button.layer.shadowOffset = CGSize.zero
        button.layer.shadowRadius = 0
        button.layer.shadowOpacity = 0
        
        return button
    }()
    
    // MARK: - Initialization
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }
    
    // MARK: - UI Setup
    
    private func setupUI() {
        backgroundColor = .clear
        
        // Add container view
        addSubview(containerView)
        
        // Add main content stack view to container
        containerView.addSubview(contentStackView)
        
        // First add QR code to the main stack
        contentStackView.addArrangedSubview(qrCodeImageView)
        
        // Then add the text stack view below the QR code
        contentStackView.addArrangedSubview(textStackView)
        
        // Add labels to text stack view
        textStackView.addArrangedSubview(headerLabel)
        textStackView.addArrangedSubview(bodyLabel)
        
        // Add the Open App button to the main content stack
        contentStackView.addArrangedSubview(openAppButton)
        
        // Setup constraints with priorities to avoid conflicts with Apple TV focus system
        let containerCenterYConstraint = containerView.centerYAnchor.constraint(equalTo: centerYAnchor, constant: 50)
        containerCenterYConstraint.priority = UILayoutPriority(999)
        
        let containerLeadingConstraint = containerView.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 95)
        containerLeadingConstraint.priority = UILayoutPriority(999)
        
        let containerTrailingConstraint = containerView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -95)
        containerTrailingConstraint.priority = UILayoutPriority(750) // Lower priority to allow flexibility
        
        let contentStackCenterXConstraint = contentStackView.centerXAnchor.constraint(equalTo: containerView.centerXAnchor)
        contentStackCenterXConstraint.priority = UILayoutPriority(999)
        
        let contentStackCenterYConstraint = contentStackView.centerYAnchor.constraint(equalTo: containerView.centerYAnchor)
        contentStackCenterYConstraint.priority = UILayoutPriority(999)
        
        let contentStackLeadingConstraint = contentStackView.leadingAnchor.constraint(greaterThanOrEqualTo: containerView.leadingAnchor, constant: 20)
        contentStackLeadingConstraint.priority = UILayoutPriority(750)
        
        let contentStackTrailingConstraint = contentStackView.trailingAnchor.constraint(lessThanOrEqualTo: containerView.trailingAnchor, constant: -20)
        contentStackTrailingConstraint.priority = UILayoutPriority(750)
        
        // Add minimum width constraint for content stack to prevent zero-width issues
        // Use very low priority to avoid conflicts with Apple TV focus container constraints
        let contentStackMinWidthConstraint = contentStackView.widthAnchor.constraint(greaterThanOrEqualToConstant: 200)
        contentStackMinWidthConstraint.priority = UILayoutPriority(1) // Lowest possible priority
        
        let qrCodeWidthConstraint = qrCodeImageView.widthAnchor.constraint(equalToConstant: 400)
        qrCodeWidthConstraint.priority = UILayoutPriority(999)
        
        let qrCodeHeightConstraint = qrCodeImageView.heightAnchor.constraint(equalToConstant: 400)
        qrCodeHeightConstraint.priority = UILayoutPriority(999)
        
        let textStackWidthConstraint = textStackView.widthAnchor.constraint(equalTo: contentStackView.widthAnchor)
        textStackWidthConstraint.priority = UILayoutPriority(750)
        
        let bodyLabelWidthConstraint = bodyLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 900)
        bodyLabelWidthConstraint.priority = UILayoutPriority(750)
        
        let buttonWidthConstraint = openAppButton.widthAnchor.constraint(equalToConstant: 300)
        buttonWidthConstraint.priority = UILayoutPriority(999)
        
        let buttonHeightConstraint = openAppButton.heightAnchor.constraint(equalToConstant: 80)
        buttonHeightConstraint.priority = UILayoutPriority(999)
        
        NSLayoutConstraint.activate([
            // Position the container in the middle of the screen, but offset upward slightly
            // to account for the Eclipse title at the top
            containerCenterYConstraint,
            containerLeadingConstraint,
            containerTrailingConstraint,
            
            // Center the content stack view in the container
            contentStackCenterXConstraint,
            contentStackCenterYConstraint,
            contentStackLeadingConstraint,
            contentStackTrailingConstraint,
            contentStackMinWidthConstraint,
            
            // Set the QR code size
            qrCodeWidthConstraint,
            qrCodeHeightConstraint,
            
            // Make the text stack view full width
            textStackWidthConstraint,
            
            // Set maximum width for body label to control text wrapping
            bodyLabelWidthConstraint,
            
            // Open App button constraints
            buttonWidthConstraint,
            buttonHeightConstraint
        ])
        
        // Setup button action
        openAppButton.addTarget(self, action: #selector(openAppButtonTapped), for: .primaryActionTriggered)
    }
    
    // MARK: - Public Methods
    
    func show(in parentView: UIView) {
        // Set up frame
        translatesAutoresizingMaskIntoConstraints = false
        
        // Add to parent view
        parentView.addSubview(self)
        
        // Set constraints to fill parent view
        NSLayoutConstraint.activate([
            topAnchor.constraint(equalTo: parentView.topAnchor),
            leadingAnchor.constraint(equalTo: parentView.leadingAnchor),
            trailingAnchor.constraint(equalTo: parentView.trailingAnchor),
            bottomAnchor.constraint(equalTo: parentView.bottomAnchor)
        ])
        
        // Animate appearance
        alpha = 0
        UIView.animate(withDuration: 0.3) {
            self.alpha = 1
        }
    }
    
    func hide() {
        UIView.animate(withDuration: 0.3, animations: {
            self.alpha = 0
        }) { _ in
            self.removeFromSuperview()
        }
    }
    
    // MARK: - Actions
    
    @objc private func openAppButtonTapped() {
        delegate?.emptyStateViewDidTapOpenApp(self)
    }
    
    // MARK: - Focus Management
    
    override var preferredFocusEnvironments: [UIFocusEnvironment] {
        return [openAppButton]
    }
    
    override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
        super.didUpdateFocus(in: context, with: coordinator)
        
        coordinator.addCoordinatedAnimations({
            if context.nextFocusedView == self.openAppButton {
                // Add glow effect when focused
                self.openAppButton.layer.shadowOpacity = 0.8
                self.openAppButton.layer.shadowRadius = 20
                self.openAppButton.transform = CGAffineTransform(scaleX: 1.05, y: 1.05)
            } else if context.previouslyFocusedView == self.openAppButton {
                // Remove glow effect when focus leaves
                self.openAppButton.layer.shadowOpacity = 0
                self.openAppButton.layer.shadowRadius = 0
                self.openAppButton.transform = CGAffineTransform.identity
            }
        }, completion: nil)
    }
} 