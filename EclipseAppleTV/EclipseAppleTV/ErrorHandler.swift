import UIKit
import os.log

/// Centralized error handling and user notification system
@MainActor
class ErrorHandler: ObservableObject {
    static let shared = ErrorHandler()
    
    // MARK: - Properties
    @Published var currentError: MediaError?
    @Published var errorHistory: [ErrorEvent] = []
    @Published var isShowingError = false
    
    private let logger = Logger(subsystem: "com.eclipsetv.app", category: "ErrorHandler")
    private weak var presentingViewController: UIViewController?
    
    struct ErrorEvent {
        let error: MediaError
        let timestamp: Date
        let context: String
        let stackTrace: String?
        
        var timeAgo: String {
            let formatter = RelativeDateTimeFormatter()
            return formatter.localizedString(for: timestamp, relativeTo: Date())
        }
    }
    
    private init() {}
    
    // MARK: - Public Methods
    
    func setPresentingViewController(_ viewController: UIViewController) {
        self.presentingViewController = viewController
    }
    
    func handle(_ error: MediaError, context: String = "", file: String = #file, function: String = #function, line: Int = #line) {
        let contextInfo = context.isEmpty ? "\(function)" : context
        let location = "\(URL(fileURLWithPath: file).lastPathComponent):\(line)"
        
        // Create error event
        let event = ErrorEvent(
            error: error,
            timestamp: Date(),
            context: contextInfo,
            stackTrace: location
        )
        
        // Add to history
        errorHistory.append(event)
        
        // Keep only last 50 errors
        if errorHistory.count > 50 {
            errorHistory.removeFirst(errorHistory.count - 50)
        }
        
        // Log the error
        logError(error: error, context: contextInfo, location: location)
        
        // Show to user based on severity
        showErrorToUser(error)
    }
    
    func handleResult<T>(_ result: Result<T, MediaError>, context: String = "", file: String = #file, function: String = #function, line: Int = #line) -> T? {
        switch result {
        case .success(let value):
            return value
        case .failure(let error):
            handle(error, context: context, file: file, function: function, line: line)
            return nil
        }
    }
    
    func clearErrorHistory() {
        errorHistory.removeAll()
        logger.info("Error history cleared")
    }
    
    func getErrorSummary() -> String {
        let total = errorHistory.count
        let recent = errorHistory.filter { $0.timestamp.timeIntervalSinceNow > -3600 }.count // Last hour
        let critical = errorHistory.filter { $0.error.severity == .critical || $0.error.severity == .severe }.count
        
        return "Total: \(total), Recent: \(recent), Critical: \(critical)"
    }
    
    // MARK: - Private Methods
    
    private func logError(error: MediaError, context: String, location: String) {
        let message = """
        🚨 MediaError [\(error.severity)] in \(context)
        📍 Location: \(location)
        💬 Message: \(error.localizedDescription)
        🔧 Recovery: \(error.recoverySuggestion ?? "None")
        📂 Category: \(error.category.displayName)
        """
        
        switch error.severity {
        case .info:
            logger.info("\(message)")
        case .warning:
            logger.warning("\(message)")
        case .error:
            logger.error("\(message)")
        case .critical, .severe:
            logger.fault("\(message)")
        }
    }
    
    private func showErrorToUser(_ error: MediaError) {
        switch error.severity {
        case .info:
            // Don't show info-level errors to users
            break
        case .warning:
            showToast(for: error)
        case .error, .critical:
            showAlert(for: error)
        case .severe:
            showCriticalAlert(for: error)
        }
    }
    
    private func showToast(for error: MediaError) {
        // Use existing ToastView or create a simple one
        guard let presentingVC = presentingViewController else { return }
        
        let message = error.localizedDescription ?? "Unknown error"
        
        // Create simple toast view
        let toastView = UIView()
        toastView.backgroundColor = error.severity.color.withAlphaComponent(0.9)
        toastView.layer.cornerRadius = 8
        
        let label = UILabel()
        label.text = message
        label.textColor = .white
        label.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        label.numberOfLines = 0
        label.textAlignment = .center
        
        toastView.addSubview(label)
        label.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: toastView.topAnchor, constant: 12),
            label.leadingAnchor.constraint(equalTo: toastView.leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: toastView.trailingAnchor, constant: -16),
            label.bottomAnchor.constraint(equalTo: toastView.bottomAnchor, constant: -12)
        ])
        
        presentingVC.view.addSubview(toastView)
        toastView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            toastView.topAnchor.constraint(equalTo: presentingVC.view.safeAreaLayoutGuide.topAnchor, constant: 20),
            toastView.trailingAnchor.constraint(equalTo: presentingVC.view.trailingAnchor, constant: -60),
            toastView.widthAnchor.constraint(lessThanOrEqualTo: presentingVC.view.widthAnchor, multiplier: 0.4)
        ])
        
        // Animate in and out
        toastView.alpha = 0
        UIView.animate(withDuration: 0.3) {
            toastView.alpha = 1
        } completion: { _ in
            UIView.animate(withDuration: 0.3, delay: 3.0) {
                toastView.alpha = 0
            } completion: { _ in
                toastView.removeFromSuperview()
            }
        }
    }
    
    private func showAlert(for error: MediaError) {
        guard let presentingVC = presentingViewController else { return }
        
        let alert = UIAlertController(
            title: error.category.displayName + " Error",
            message: error.localizedDescription,
            preferredStyle: .alert
        )
        
        // Add recovery suggestion if available
        if let suggestion = error.recoverySuggestion {
            alert.message = (alert.message ?? "") + "\n\n" + suggestion
        }
        
        // Add retry option if applicable
        if error.shouldRetry {
            alert.addAction(UIAlertAction(title: "Retry", style: .default) { _ in
                // Post notification for retry
                NotificationCenter.default.post(
                    name: Notification.Name("RetryLastOperation"),
                    object: error
                )
            })
        }
        
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        
        presentingVC.present(alert, animated: true)
    }
    
    private func showCriticalAlert(for error: MediaError) {
        guard let presentingVC = presentingViewController else { return }
        
        let alert = UIAlertController(
            title: "Critical Error",
            message: error.localizedDescription,
            preferredStyle: .alert
        )
        
        if let suggestion = error.recoverySuggestion {
            alert.message = (alert.message ?? "") + "\n\n" + suggestion
        }
        
        // For critical errors, offer more options
        if error.shouldRetry {
            alert.addAction(UIAlertAction(title: "Retry", style: .default) { _ in
                NotificationCenter.default.post(
                    name: Notification.Name("RetryLastOperation"),
                    object: error
                )
            })
        }
        
        alert.addAction(UIAlertAction(title: "Report Issue", style: .default) { _ in
            // Could open support or generate error report
            self.generateErrorReport()
        })
        
        alert.addAction(UIAlertAction(title: "OK", style: .cancel))
        
        presentingVC.present(alert, animated: true)
    }
    
    private func generateErrorReport() {
        let report = """
        EclipseTV Error Report
        Generated: \(Date())
        
        \(getErrorSummary())
        
        Recent Errors:
        \(errorHistory.suffix(5).map { "• \($0.error.localizedDescription ?? "Unknown") at \($0.timestamp)" }.joined(separator: "\n"))
        """
        
        logger.info("Error report generated:\n\(report)")
        
        // Could save to files or send to analytics
    }
}

// MARK: - Convenience Extensions
extension ErrorHandler {
    /// Quick method to handle file operations
    func handleFileOperation<T>(_ operation: () throws -> T, context: String = "") -> T? {
        do {
            return try operation()
        } catch let error as MediaError {
            handle(error, context: context)
            return nil
        } catch {
            handle(.unknown(underlyingError: error), context: context)
            return nil
        }
    }
    
    /// Quick method to handle async operations
    func handleAsyncOperation<T>(_ operation: () async throws -> T, context: String = "") async -> T? {
        do {
            return try await operation()
        } catch let error as MediaError {
            await handle(error, context: context)
            return nil
        } catch {
            await handle(.unknown(underlyingError: error), context: context)
            return nil
        }
    }
} 