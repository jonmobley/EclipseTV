// HomeHeaderBar.swift
import UIKit

/// Top header for the home (library) screen.
///
/// In its normal state it shows a connection-status indicator on the leading side
/// (a colored dot plus "Connected"/"Disconnected"), a center dropdown button showing
/// the active Apple TV library name (with a chevron) that lets the user switch
/// libraries or open Settings, and, on the trailing side, an ellipsis ("…") menu
/// button (which offers "Arrange") next to a blue circular "+" button that opens the
/// media picker.
///
/// While arranging, it switches to an editing layout: a "Cancel" button (leading),
/// an "Arrange" title (center), and a "Done" button (trailing) that saves the layout.
final class HomeHeaderBar: UIView {

    /// The connection state reflected by the status pill and the "…" menu contents.
    /// `.paused` means the user chose to use Eclipse without an Apple TV; auto-connect
    /// is suspended until they reconnect.
    enum ConnectionDisplayState {
        case connected
        case disconnected
        case paused
    }

    /// A single Apple TV row shown in the library dropdown.
    struct LibraryMenuItem {
        let name: String
        let subtitle: String?
        let isActive: Bool
    }

    // MARK: - Subviews

    private let libraryButton = UIButton(type: .system)
    private let statusDot = UIView()
    private let statusLabel = UILabel()
    /// Transparent overlay over the status dot + label so the pill is tappable to
    /// (re)connect when disconnected or paused.
    private let statusButton = UIButton(type: .system)
    private let presentingIcon = UIImageView()
    private let menuButton = UIButton(type: .system)
    private let addButton = UIButton(type: .system)

    private let titleLabel = UILabel()
    private let cancelButton = UIButton(type: .system)
    private let doneButton = UIButton(type: .system)

    /// Invoked when the "+" button is tapped.
    var onAddTapped: (() -> Void)?
    /// Invoked when "Arrange" is chosen from the ellipsis menu.
    var onArrangeTapped: (() -> Void)?
    /// Invoked when "Set Up Album" is chosen from the ellipsis menu.
    var onSetUpAlbum: (() -> Void)?
    /// Invoked when "Done" is tapped while arranging (save the layout).
    var onArrangeDone: (() -> Void)?
    /// Invoked when "Cancel" is tapped while arranging (discard changes).
    var onArrangeCancel: (() -> Void)?
    /// Invoked with the device name when a library is chosen from the dropdown.
    var onSelectLibrary: ((String) -> Void)?
    /// Invoked when "Albums" is chosen from the dropdown (browse account albums).
    var onBrowseAlbums: (() -> Void)?
    /// Invoked when "Settings" is chosen from the dropdown.
    var onOpenSettings: (() -> Void)?
    /// Invoked when the user asks to connect — via the status pill tap or the
    /// "Connect to Apple TV" / "Connect Now" item in the "…" menu.
    var onConnect: (() -> Void)?
    /// Invoked when the user chooses "Stop Trying to Connect" from the "…" menu.
    var onStopConnecting: (() -> Void)?

    private var isArranging = false
    private var connectionState: ConnectionDisplayState = .disconnected

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
        setConnectionState(.disconnected)
        setArranging(false)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    private func setupViews() {
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: "chevron.down",
                               withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .bold))
        config.imagePlacement = .trailing
        config.imagePadding = 4
        config.baseForegroundColor = .label
        config.contentInsets = .zero
        libraryButton.configuration = config
        libraryButton.showsMenuAsPrimaryAction = true
        libraryButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(libraryButton)
        setLibraryTitle(nil)

        statusDot.layer.cornerRadius = 5
        statusDot.translatesAutoresizingMaskIntoConstraints = false
        addSubview(statusDot)

        statusLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(statusLabel)

        statusButton.translatesAutoresizingMaskIntoConstraints = false
        statusButton.addTarget(self, action: #selector(statusTapped), for: .touchUpInside)
        addSubview(statusButton)

        presentingIcon.image = UIImage(systemName: "airplayvideo")
        presentingIcon.tintColor = .systemBlue
        presentingIcon.contentMode = .scaleAspectFit
        presentingIcon.isHidden = true
        presentingIcon.translatesAutoresizingMaskIntoConstraints = false
        addSubview(presentingIcon)

        let menuConfig = UIImage.SymbolConfiguration(pointSize: 20, weight: .bold)
        menuButton.setImage(UIImage(systemName: "ellipsis", withConfiguration: menuConfig), for: .normal)
        menuButton.tintColor = .label
        menuButton.translatesAutoresizingMaskIntoConstraints = false
        menuButton.showsMenuAsPrimaryAction = true
        menuButton.menu = makeOptionsMenu()
        addSubview(menuButton)

        let plusConfig = UIImage.SymbolConfiguration(pointSize: 20, weight: .bold)
        addButton.setImage(UIImage(systemName: "plus", withConfiguration: plusConfig), for: .normal)
        addButton.tintColor = .white
        addButton.backgroundColor = .systemBlue
        addButton.layer.cornerRadius = 18
        addButton.clipsToBounds = true
        addButton.translatesAutoresizingMaskIntoConstraints = false
        addButton.addTarget(self, action: #selector(addTapped), for: .touchUpInside)
        addSubview(addButton)

        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.text = "Arrange"
        titleLabel.textColor = .label
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        cancelButton.setTitle("Cancel", for: .normal)
        cancelButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .regular)
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        addSubview(cancelButton)

        doneButton.setTitle("Done", for: .normal)
        doneButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        doneButton.translatesAutoresizingMaskIntoConstraints = false
        doneButton.addTarget(self, action: #selector(doneTapped), for: .touchUpInside)
        addSubview(doneButton)

        NSLayoutConstraint.activate([
            libraryButton.centerXAnchor.constraint(equalTo: centerXAnchor),
            libraryButton.centerYAnchor.constraint(equalTo: centerYAnchor),

            statusDot.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            statusDot.centerYAnchor.constraint(equalTo: centerYAnchor),
            statusDot.widthAnchor.constraint(equalToConstant: 10),
            statusDot.heightAnchor.constraint(equalToConstant: 10),

            statusLabel.leadingAnchor.constraint(equalTo: statusDot.trailingAnchor, constant: 8),
            statusLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            statusButton.leadingAnchor.constraint(equalTo: statusDot.leadingAnchor, constant: -8),
            statusButton.trailingAnchor.constraint(equalTo: statusLabel.trailingAnchor, constant: 8),
            statusButton.topAnchor.constraint(equalTo: topAnchor),
            statusButton.bottomAnchor.constraint(equalTo: bottomAnchor),

            presentingIcon.leadingAnchor.constraint(equalTo: statusLabel.trailingAnchor, constant: 8),
            presentingIcon.centerYAnchor.constraint(equalTo: centerYAnchor),
            presentingIcon.widthAnchor.constraint(equalToConstant: 22),
            presentingIcon.heightAnchor.constraint(equalToConstant: 18),

            addButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            addButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            addButton.widthAnchor.constraint(equalToConstant: 36),
            addButton.heightAnchor.constraint(equalToConstant: 36),

            menuButton.trailingAnchor.constraint(equalTo: addButton.leadingAnchor, constant: -12),
            menuButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            menuButton.widthAnchor.constraint(equalToConstant: 36),
            menuButton.heightAnchor.constraint(equalToConstant: 36),

            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: libraryButton.leadingAnchor, constant: -8),

            cancelButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            cancelButton.centerYAnchor.constraint(equalTo: centerYAnchor),

            doneButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            doneButton.centerYAnchor.constraint(equalTo: centerYAnchor),

            titleLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    /// Builds the "…" menu for the current connection state. When connected it offers
    /// the TV actions (Arrange / Set Up Album); otherwise it offers connection controls
    /// so the user can connect on demand or stop auto-connect attempts.
    private func makeOptionsMenu() -> UIMenu {
        switch connectionState {
        case .connected:
            let arrange = UIAction(title: "Arrange",
                                   image: UIImage(systemName: "arrow.up.arrow.down")) { [weak self] _ in
                self?.onArrangeTapped?()
            }
            let setUpAlbum = UIAction(title: "Set Up Album…",
                                      image: UIImage(systemName: "rectangle.stack.badge.plus")) { [weak self] _ in
                self?.onSetUpAlbum?()
            }
            return UIMenu(title: "", children: [arrange, setUpAlbum])

        case .disconnected:
            let connectNow = UIAction(title: "Connect Now",
                                      image: UIImage(systemName: "wifi")) { [weak self] _ in
                self?.onConnect?()
            }
            let stop = UIAction(title: "Stop Trying to Connect",
                                image: UIImage(systemName: "pause.circle")) { [weak self] _ in
                self?.onStopConnecting?()
            }
            return UIMenu(title: "", children: [connectNow, stop])

        case .paused:
            let connect = UIAction(title: "Connect to Apple TV",
                                   image: UIImage(systemName: "wifi")) { [weak self] _ in
                self?.onConnect?()
            }
            return UIMenu(title: "", children: [connect])
        }
    }

    // MARK: - Library Dropdown

    /// Sets the dropdown's title to the active library name, or "EclipseTV" when none.
    func setLibraryTitle(_ name: String?) {
        let title = (name?.isEmpty == false) ? name! : "EclipseTV"
        libraryButton.configuration?.attributedTitle = AttributedString(
            title, attributes: AttributeContainer([.font: UIFont.systemFont(ofSize: 17, weight: .bold)]))
    }

    /// Rebuilds the dropdown from the given Apple TVs plus a trailing Settings action.
    func setLibraryMenu(items: [LibraryMenuItem]) {
        var tvActions: [UIAction] = []
        for item in items {
            let action = UIAction(title: item.name,
                                  subtitle: item.subtitle,
                                  image: UIImage(systemName: "appletv"),
                                  state: item.isActive ? .on : .off) { [weak self] _ in
                self?.onSelectLibrary?(item.name)
            }
            tvActions.append(action)
        }

        let albums = UIAction(title: "Albums",
                              image: UIImage(systemName: "rectangle.stack")) { [weak self] _ in
            self?.onBrowseAlbums?()
        }
        let settings = UIAction(title: "Settings",
                                image: UIImage(systemName: "gearshape")) { [weak self] _ in
            self?.onOpenSettings?()
        }
        let bottomSection = UIMenu(title: "", options: .displayInline, children: [albums, settings])

        var children: [UIMenuElement] = []
        if !tvActions.isEmpty {
            children.append(UIMenu(title: "Apple TVs", options: .displayInline, children: tvActions))
        }
        children.append(bottomSection)
        libraryButton.menu = UIMenu(title: "", children: children)
    }

    // MARK: - Actions

    @objc private func addTapped() {
        onAddTapped?()
    }

    @objc private func cancelTapped() {
        onArrangeCancel?()
    }

    @objc private func statusTapped() {
        // Tapping the pill only does something useful while not connected.
        guard connectionState != .connected else { return }
        onConnect?()
    }

    @objc private func doneTapped() {
        onArrangeDone?()
    }

    // MARK: - State

    /// Reflects the connection state in the dot, label, and trailing controls. Sending
    /// media requires a live connection, so the "+" button is only enabled while
    /// connected; the "…" menu stays enabled in every state because it now hosts the
    /// connect / stop-connecting controls.
    func setConnectionState(_ state: ConnectionDisplayState) {
        connectionState = state
        switch state {
        case .connected:
            statusDot.backgroundColor = .systemGreen
            statusLabel.text = "Connected"
            statusLabel.textColor = .systemGreen
        case .disconnected:
            statusDot.backgroundColor = .systemGray
            statusLabel.text = "Disconnected"
            statusLabel.textColor = .secondaryLabel
        case .paused:
            statusDot.backgroundColor = .systemOrange
            statusLabel.text = "Offline"
            statusLabel.textColor = .secondaryLabel
        }
        setAddEnabled(state == .connected)
        menuButton.isEnabled = true
        menuButton.alpha = 1.0
        menuButton.menu = makeOptionsMenu()
    }

    /// Shows or hides the AirPlay "presenting on TV" indicator next to the status label.
    /// Reflects whether an external display (AirPlay-mirrored Apple TV) is connected.
    func setPresenting(_ presenting: Bool) {
        presentingIcon.isHidden = !presenting || isArranging
    }

    /// Enables or disables the "+" button independently (e.g. dimmed during a transfer).
    func setAddEnabled(_ enabled: Bool) {
        addButton.isEnabled = enabled
        addButton.alpha = enabled ? 1.0 : 0.4
    }

    /// Toggles between the normal layout and the arranging (Cancel / Done) layout.
    func setArranging(_ arranging: Bool) {
        isArranging = arranging
        libraryButton.isHidden = arranging
        statusDot.isHidden = arranging
        statusLabel.isHidden = arranging
        statusButton.isHidden = arranging
        presentingIcon.isHidden = arranging || !ExternalDisplayManager.shared.isConnected
        menuButton.isHidden = arranging
        addButton.isHidden = arranging
        titleLabel.isHidden = !arranging
        cancelButton.isHidden = !arranging
        doneButton.isHidden = !arranging
    }

    /// The "+" button, exposed so callers can anchor popovers (iPad action sheets) to it.
    var addAnchor: UIView { addButton }
}
