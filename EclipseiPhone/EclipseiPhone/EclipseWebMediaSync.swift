//
//  EclipseWebMediaSync.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import WebKit

/// Bridges HTML5 media events from the phone WebView to the AirPlay WebView.
enum EclipseWebMediaSync {

    static let messageName = "eclipseMedia"

    /// Play / pause / seek / rate payload posted by the injected reporter.
    struct Event: Codable, Equatable {
        var action: String
        var index: Int
        var currentTime: Double
        var paused: Bool
        var muted: Bool
        var playbackRate: Double
        var src: String
        var tag: String

        init?(messageBody: Any) {
            guard let dict = messageBody as? [String: Any] else { return nil }
            action = (dict["action"] as? String) ?? ""
            guard !action.isEmpty else { return nil }
            index = dict["index"] as? Int ?? -1
            currentTime = dict["currentTime"] as? Double ?? 0
            paused = dict["paused"] as? Bool ?? true
            muted = dict["muted"] as? Bool ?? false
            playbackRate = dict["playbackRate"] as? Double ?? 1
            src = dict["src"] as? String ?? ""
            tag = dict["tag"] as? String ?? "VIDEO"
        }
    }

    /// Injected into the phone browser to report media play state to native.
    static let reporterJavaScript = """
    (function() {
      if (window.__eclipseMediaInstalled) { return; }
      window.__eclipseMediaInstalled = true;
      var handlerName = '\(messageName)';

      function list() {
        return Array.prototype.slice.call(document.querySelectorAll('video,audio'));
      }

      function mediaIndex(el) {
        return list().indexOf(el);
      }

      function post(el, action) {
        try {
          if (!window.webkit || !webkit.messageHandlers
              || !webkit.messageHandlers[handlerName]) { return; }
          webkit.messageHandlers[handlerName].postMessage({
            action: action,
            index: mediaIndex(el),
            currentTime: el.currentTime || 0,
            paused: !!el.paused,
            muted: !!el.muted,
            playbackRate: el.playbackRate || 1,
            src: el.currentSrc || el.src || '',
            tag: el.tagName || 'VIDEO'
          });
        } catch (e) {}
      }

      function wire(el) {
        if (!el || el.__eclipseWired) { return; }
        el.__eclipseWired = true;
        ['play', 'pause', 'seeked', 'volumechange', 'ratechange', 'ended']
          .forEach(function(evt) {
            el.addEventListener(evt, function() { post(el, evt); }, true);
          });
        var last = 0;
        el.addEventListener('timeupdate', function() {
          var now = Date.now();
          if (now - last < 750) { return; }
          last = now;
          if (!el.paused) { post(el, 'timeupdate'); }
        }, true);
      }

      function scan() { list().forEach(wire); }

      var origPlay = HTMLMediaElement.prototype.play;
      HTMLMediaElement.prototype.play = function() {
        wire(this);
        var result = origPlay.apply(this, arguments);
        post(this, 'play');
        return result;
      };
      var origPause = HTMLMediaElement.prototype.pause;
      HTMLMediaElement.prototype.pause = function() {
        wire(this);
        origPause.apply(this, arguments);
        post(this, 'pause');
      };

      scan();
      try {
        new MutationObserver(scan).observe(document.documentElement, {
          childList: true, subtree: true
        });
      } catch (e) {}
    })();
    """

    /// JS that applies a phone media event onto the AirPlay page.
    static func applyJavaScript(jsonPayload: String) -> String {
        """
        (function(msg) {
          if (!msg || !msg.action) { return 'bad'; }
          var nodes = Array.prototype.slice.call(
            document.querySelectorAll('video,audio')
          );
          var el = null;
          if (typeof msg.index === 'number' && msg.index >= 0
              && msg.index < nodes.length) {
            el = nodes[msg.index];
          }
          if (!el && msg.src) {
            el = nodes.find(function(n) {
              var s = n.currentSrc || n.src || '';
              return s && msg.src && (s === msg.src || s.indexOf(msg.src) !== -1
                || msg.src.indexOf(s) !== -1);
            }) || null;
          }
          if (!el && nodes.length === 1) { el = nodes[0]; }
          if (!el && nodes.length > 0
              && (msg.action === 'play' || msg.action === 'timeupdate')) {
            el = nodes[0];
          }
          if (!el) {
            if (msg.action === 'play') {
              var btn = document.querySelector(
                'button[aria-label*="Play"], button[aria-label*="play"],'
                + ' .ytp-large-play-button, .play-button, [data-testid*="play"]'
              );
              if (btn) { try { btn.click(); return 'click'; } catch (e) {} }
            }
            return 'none';
          }
          try {
            if (typeof msg.currentTime === 'number'
                && isFinite(msg.currentTime)
                && Math.abs((el.currentTime || 0) - msg.currentTime) > 0.45) {
              el.currentTime = msg.currentTime;
            }
          } catch (e) {}
          try { el.muted = !!msg.muted; } catch (e) {}
          try {
            if (msg.playbackRate) { el.playbackRate = msg.playbackRate; }
          } catch (e) {}
          if (msg.action === 'play'
              || (msg.action === 'timeupdate' && !msg.paused)
              || (msg.action === 'seeked' && !msg.paused)) {
            try {
              var p = el.play();
              if (p && p.catch) { p.catch(function() {}); }
            } catch (e) {}
          } else if (msg.action === 'pause' || msg.action === 'ended') {
            try { el.pause(); } catch (e) {}
          }
          return 'ok';
        })(\(jsonPayload));
        """
    }
}

/// Avoids a retain cycle between `WKUserContentController` and its handler.
final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var delegate: WKScriptMessageHandler?

    init(delegate: WKScriptMessageHandler) {
        self.delegate = delegate
        super.init()
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        delegate?.userContentController(userContentController, didReceive: message)
    }
}
