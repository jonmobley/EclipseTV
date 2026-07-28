//
//  WebRemoteViewController+Chrome.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Safari-like Nav Chrome

extension WebRemoteViewController: UITextFieldDelegate {

    /// Builds Back · pill URL (reload inside) · bookmarks ⋯.
    func setupBrowserChrome() {
        backButton = UIBarButtonItem(
            image: UIImage(systemName: "chevron.backward"),
            style: .plain,
            target: self,
            action: #selector(goBackTapped)
        )
        navigationItem.leftBarButtonItem = backButton

        urlField.delegate = self
        if page.isFreeBrowse, isBlankBrowserURL(page.url) {
            urlField.text = nil
        } else {
            urlField.text = displayHost(for: page.url)
        }
        urlBarContainer.addSubview(urlField)
        urlBarContainer.addSubview(reloadButton)
        reloadButton.addTarget(self, action: #selector(reloadTapped), for: .touchUpInside)

        NSLayoutConstraint.activate([
            urlField.leadingAnchor.constraint(
                equalTo: urlBarContainer.leadingAnchor, constant: 12),
            urlField.trailingAnchor.constraint(
                equalTo: reloadButton.leadingAnchor, constant: -2),
            urlField.topAnchor.constraint(equalTo: urlBarContainer.topAnchor),
            urlField.bottomAnchor.constraint(equalTo: urlBarContainer.bottomAnchor),

            reloadButton.trailingAnchor.constraint(
                equalTo: urlBarContainer.trailingAnchor, constant: -4),
            reloadButton.centerYAnchor.constraint(equalTo: urlBarContainer.centerYAnchor),
            reloadButton.widthAnchor.constraint(equalToConstant: 40),
            reloadButton.heightAnchor.constraint(equalToConstant: 40)
        ])
        navigationItem.titleView = urlBarContainer

        // Give the bar room for a taller Safari-style pill.
        let appearance = UINavigationBarAppearance()
        appearance.configureWithDefaultBackground()
        navigationItem.standardAppearance = appearance
        navigationItem.scrollEdgeAppearance = appearance

        bookmarksButton = UIBarButtonItem(
            image: UIImage(systemName: "ellipsis"),
            menu: makeBookmarksMenu()
        )
        navigationItem.rightBarButtonItem = bookmarksButton
    }

    /// Sizes the URL pill between Back and ⋯.
    func layoutURLBarWidth() {
        guard let navBar = navigationController?.navigationBar else { return }
        let reserved: CGFloat = 120
        let width = max(navBar.bounds.width - reserved, 160)
        let height: CGFloat = 44
        urlBarContainer.frame = CGRect(x: 0, y: 0, width: width, height: height)
        urlBarContainer.layer.cornerRadius = height / 2
    }

    /// Syncs URL display and Back affordance with `webView`.
    func updateBrowserChrome() {
        guard let web = webView else { return }
        if !urlField.isFirstResponder {
            if let url = web.url, !isBlankBrowserURL(url) {
                urlField.text = displayHost(for: url)
            } else if !page.isFreeBrowse {
                urlField.text = displayHost(for: page.url)
            } else {
                urlField.text = nil
            }
        }
    }

    /// Rebuilds the ⋯ menu (Close + other bookmarks).
    func refreshBookmarksMenu() {
        bookmarksButton?.menu = makeBookmarksMenu()
    }

    /// Loads an HTTPS URL in the phone web view (AirPlay follows via delegate).
    func loadBrowserURL(_ url: URL) {
        webView?.load(URLRequest(url: url))
    }

    /// Compact host label like Safari when the field is not being edited.
    func displayHost(for url: URL) -> String {
        if let host = url.host, !host.isEmpty {
            return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        }
        return url.absoluteString
    }

    // MARK: - Bookmarks Menu

    private func makeBookmarksMenu() -> UIMenu {
        var children: [UIMenuElement] = [
            UIAction(
                title: "Close",
                subtitle: "TV keeps showing this page",
                image: UIImage(systemName: "xmark")
            ) { [weak self] _ in
                // Dismisses the phone browser only; AirPlay web stays live.
                self?.closeTapped()
            }
        ]

        let others = WebPageStore.shared.pages.filter { $0.id != page.id }
        if others.isEmpty {
            children.append(UIAction(
                title: "No other websites",
                attributes: .disabled
            ) { _ in })
        } else {
            children.append(contentsOf: others.map { bookmark in
                UIAction(title: bookmark.title, subtitle: bookmark.url.host) { [weak self] _ in
                    self?.loadBrowserURL(bookmark.url)
                }
            })
        }
        return UIMenu(children: children)
    }

    // MARK: - UITextFieldDelegate

    func textFieldDidBeginEditing(_ textField: UITextField) {
        textField.textAlignment = .left
        if let url = webView?.url, !isBlankBrowserURL(url) {
            textField.text = url.absoluteString
        } else if !page.isFreeBrowse {
            textField.text = page.url.absoluteString
        } else {
            textField.text = nil
        }
        textField.selectAll(nil)
    }

    func textFieldDidEndEditing(_ textField: UITextField) {
        textField.textAlignment = .center
        if let url = webView?.url {
            textField.text = displayHost(for: url)
        }
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        let raw = textField.text ?? ""
        do {
            let url = try WebPageStore.normalizedHTTPSURL(from: raw)
            textField.text = displayHost(for: url)
            loadBrowserURL(url)
        } catch {
            let alert = UIAlertController(
                title: "Invalid Address",
                message: error.localizedDescription,
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
            if let url = webView?.url {
                textField.text = displayHost(for: url)
            }
        }
        return true
    }
}
