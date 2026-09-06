//
//  WebVideoShellHTML.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation

/// Bare-bones local HTML that hosts a YouTube / Vimeo embed edge-to-edge.
///
/// Loaded via `loadHTMLString(_:baseURL:)` with the provider origin as `baseURL`
/// so the IFrame API's postMessage origin checks succeed (WKWebView's default
/// `null` origin rejects the player API).
enum WebVideoShellHTML {

    /// Full document for `link`. Returns nil for direct files (those use AVPlayer).
    static func document(for link: WebVideoLink) -> String? {
        switch link {
        case .youTube(let id, let startAt):
            return youTubeDocument(videoId: id, startAt: startAt)
        case .vimeo:
            guard let embedURL = link.embedURL else { return nil }
            return vimeoDocument(embedSrc: embedURL.absoluteString)
        case .directFile:
            return nil
        }
    }

    // MARK: - YouTube

    /// YouTube IFrame API shell. Player posts state on `eclipseWebVideo`.
    ///
    /// `YT.Player` creates its own fullscreen iframe. The document itself must
    /// load with `baseURL` `https://www.youtube.com` so `postMessage` is accepted.
    private static func youTubeDocument(videoId: String, startAt: TimeInterval) -> String {
        let start = max(0, Int(startAt))
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
        <style>
          html, body { margin: 0; padding: 0; background: #000; overflow: hidden;
            width: 100%; height: 100%; }
          #player { position: absolute; inset: 0; width: 100%; height: 100%;
            border: 0; }
        </style>
        </head>
        <body>
        <div id="player"></div>
        <script>
        var tag = document.createElement('script');
        tag.src = 'https://www.youtube.com/iframe_api';
        document.head.appendChild(tag);

        var player = null;

        function post(action) {
          try {
            if (!window.webkit || !webkit.messageHandlers
                || !webkit.messageHandlers.eclipseWebVideo) { return; }
            var payload = {
              action: action,
              currentTime: 0,
              duration: 0,
              paused: true,
              muted: false
            };
            if (player) {
              try { payload.currentTime = player.getCurrentTime() || 0; } catch (e) {}
              try { payload.duration = player.getDuration() || 0; } catch (e) {}
              try {
                var state = player.getPlayerState();
                payload.paused = state !== 1 && state !== 3;
              } catch (e) {}
              try { payload.muted = !!player.isMuted(); } catch (e) {}
            }
            webkit.messageHandlers.eclipseWebVideo.postMessage(payload);
          } catch (e) {}
        }

        function onYouTubeIframeAPIReady() {
          player = new YT.Player('player', {
            width: '100%',
            height: '100%',
            videoId: '\(videoId)',
            playerVars: {
              autoplay: 1,
              playsinline: 1,
              rel: 0,
              modestbranding: 1,
              controls: 0,
              enablejsapi: 1,
              start: \(start)
            },
            events: {
              onReady: function() {
                post('ready');
                setInterval(function() {
                  if (!player) { return; }
                  try {
                    if (player.getPlayerState() === 1) { post('timeupdate'); }
                  } catch (err) {}
                }, 500);
              },
              onStateChange: function(e) {
                var map = { '-1': 'unstarted', 0: 'ended', 1: 'play',
                  2: 'pause', 3: 'buffering', 5: 'cued' };
                post(map[String(e.data)] || 'state');
              }
            }
          });
        }
        window.onYouTubeIframeAPIReady = onYouTubeIframeAPIReady;

        window.__eclipseWebVideo = {
          play: function() { try { player && player.playVideo(); } catch (e) {} },
          pause: function() { try { player && player.pauseVideo(); } catch (e) {} },
          seek: function(t) {
            try { player && player.seekTo(t, true); } catch (e) {}
          },
          mute: function(m) {
            try {
              if (!player) { return; }
              if (m) { player.mute(); } else { player.unMute(); }
            } catch (e) {}
          }
        };
        </script>
        </body>
        </html>
        """
    }

    // MARK: - Vimeo

    /// Vimeo Player.js shell. Same message shape as the YouTube path.
    private static func vimeoDocument(embedSrc: String) -> String {
        """
        <!DOCTYPE html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
        <style>
          html, body { margin: 0; padding: 0; background: #000; overflow: hidden;
            width: 100%; height: 100%; }
          iframe { position: absolute; inset: 0; width: 100%; height: 100%;
            border: 0; }
        </style>
        </head>
        <body>
        <iframe id="player"
          src="\(embedSrc)"
          allow="autoplay; encrypted-media; picture-in-picture; fullscreen"
          allowfullscreen></iframe>
        <script src="https://player.vimeo.com/api/player.js"></script>
        <script>
        var iframe = document.getElementById('player');
        var player = new Vimeo.Player(iframe);

        function post(action) {
          Promise.all([
            player.getCurrentTime().catch(function() { return 0; }),
            player.getDuration().catch(function() { return 0; }),
            player.getPaused().catch(function() { return true; }),
            player.getMuted().catch(function() { return false; })
          ]).then(function(vals) {
            try {
              if (!window.webkit || !webkit.messageHandlers
                  || !webkit.messageHandlers.eclipseWebVideo) { return; }
              webkit.messageHandlers.eclipseWebVideo.postMessage({
                action: action,
                currentTime: vals[0] || 0,
                duration: vals[1] || 0,
                paused: !!vals[2],
                muted: !!vals[3]
              });
            } catch (e) {}
          });
        }

        player.on('play', function() { post('play'); });
        player.on('pause', function() { post('pause'); });
        player.on('ended', function() { post('ended'); });
        player.on('timeupdate', function() { post('timeupdate'); });
        player.ready().then(function() { post('ready'); });

        window.__eclipseWebVideo = {
          play: function() { player.play().catch(function() {}); },
          pause: function() { player.pause().catch(function() {}); },
          seek: function(t) { player.setCurrentTime(t).catch(function() {}); },
          mute: function(m) { player.setMuted(!!m).catch(function() {}); }
        };
        </script>
        </body>
        </html>
        """
    }
}
