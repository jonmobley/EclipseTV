# Eclipse - Apple TV & iPhone Media System

A dual-platform media system: the iPhone curates **Shows** and drives the big screen (AirPlay and/or the Eclipse Apple TV app). The phone is the operator; the TV is the audience canvas.

![Eclipse Logo](EclipseAppleTV/Images/eclipse-qrcode.png)

## 🌟 Overview

Eclipse is a companion pair:

- **📱 Eclipse iPhone** — Curate Shows, go live on AirPlay, optionally link the Eclipse Apple TV app, ambient music, live camera
- **🍎 Eclipse Apple TV** — Fullscreen library display + Multipeer receive/control; optional read-only hosted cloud albums

### Sync planes (one clear story)

| Plane | What it syncs | Path | Notes |
|-------|---------------|------|--------|
| **1. Multipeer (primary for TV)** | Imported photos/videos → TV library; play/delete/reorder/playback | Local network, encrypted | Captures never fan out to Apple TV |
| **2. CloudKit Eclipse Sync** | Shows, membership, captures across **iPhones** (same Apple ID / Share) | iCloud | Apple TV does **not** participate (Phase 1) |
| **3. HTTPS remote albums** | Read-only hosted albums via 6-digit code | `aircamtv.com` | Separate from Shows; optional on TV + phone browser |

**Primary user loop:** Open a Show → tap media/tools → present on AirPlay (always) and/or push/control the Eclipse TV library when linked.

## 🚀 Key Features

### 📺 Apple TV App
- **Fullscreen Media Display**: Optimized viewing with perfect aspect ratio handling
- **Grid Interface**: Beautiful 16:9 thumbnail grid with smooth navigation; cloud albums appear as extra sections
- **Move Mode**: Intuitive drag-and-drop reorganization of the local library
- **Wireless Reception**: Seamless media receiving from the iPhone over the local network
- **Remote Albums**: Read-only cloud albums synced via a 6-digit account code, with realtime update push
- **Smart Caching**: Intelligent thumbnail and video caching for smooth performance
- **Apple TV Remote Optimized**: Controls designed for the Siri Remote

### 📱 iPhone App
- **Shows**: Named presentation collections (media, screensaver/logo/camera tools, websites, PDFs, slideshows)
- **AirPlay Presentation**: App-owned external canvas while the phone stays interactive
- **EclipseTV Link**: Encrypted Multipeer send + library mirror/control; multi-TV optional keep-in-sync
- **Live Camera**: Phone camera as a live AirPlay source; in-app captures stay on the phone
- **Ambient Music**: Local playlists that yield (pause) to audible video/web media
- **Eclipse Sync (CloudKit)**: Multi-iPhone Shows/captures; Share Show (TV out of CloudKit)
- **Remote Albums**: Browse hosted albums by account code; push code to the TV when linked

## 🎬 Supported Formats

### Images
- **JPEG** (.jpg, .jpeg) - Standard photo format
- **PNG** (.png) - High-quality images with transparency  
- **HEIC** (.heic) - Modern Apple photo format

### Videos
- **MP4** (.mp4) - Standard video format
- **MOV** (.mov) - Apple video format
- **Automatic optimization** for Apple TV compatibility

## 📋 Requirements

### Apple TV App
- **tvOS 17.0+**
- **Apple TV HD or Apple TV 4K**
- **Xcode 15.0+** (for development)

### iPhone App
- **iOS 16.0+** 
- **iPhone or iPad** with Wi-Fi connectivity
- **Xcode 15.0+** (for development)

## 🛠 Installation & Setup

### 1. Clone the Repository
```bash
git clone [your-repository-url]
cd EclipseTV
```

### 2. Apple TV Setup
```bash
cd EclipseAppleTV
open EclipseAppleTV.xcodeproj
```
- Select Apple TV target device or simulator
- Build and run the application
- Grant local network permissions when prompted

### 3. iPhone Setup  
```bash
cd EclipseiPhone
open EclipseiPhone.xcodeproj
```
- Select iPhone target device or simulator
- Build and run the application
- Grant photo library and local network permissions

## 🎮 Usage Guide

### Getting Started
1. **Open Eclipse on iPhone** — create or open a Show
2. **Connect AirPlay** to an Apple TV (or wired display) for the presentation canvas
3. **Optional:** Launch Eclipse on Apple TV and link with the pairing code for Multipeer library sync/control
4. **Add media** with `+` inside a Show; tap a tile to go live
5. **Optional:** Share Shows via iCloud (Eclipse Sync), or browse hosted remote albums by account code

### Apple TV Controls
| Control | Action |
|---------|--------|
| **Play/Pause** | Toggle between grid and fullscreen |
| **Menu Button** | In fullscreen: return to grid. In grid: open the options menu (albums, help) |
| **Swipe Left/Right** | Navigate between items in fullscreen |
| **Long Press** | Enter move mode to reorder the local library (grid view) |

Cloud album items are read-only (no move/delete on the TV). The options menu also handles account-code entry, album refresh/removal, and help.

### iPhone Interface
- **Connection pill**: Shows connected / searching / offline status for the active Apple TV
- **Library switcher**: Switch between Apple TVs you've connected to
- **Arrange mode**: Drag to reorder the TV library
- **Progress overlay**: Shows transfer progress while sending media
- **AirPlay icon**: Appears when an external display is connected

## 🏗 Architecture

### Design Patterns
- **Single source of truth**: `MediaDataSource` owns the media list, current index, and persistence
- **Protocol-oriented programming** for modularity
- **Delegate patterns** for communication
- **Async/await** for modern concurrency

### Key Components

#### Apple TV App
```
MediaDataSource.swift        # Single source of truth for the media list + persistence

Models/
├── MediaItem.swift          # Core data model (path-based identity)
├── AppState.swift           # Per-file video settings (mute/loop) storage
└── MediaError.swift         # Error handling

ViewModels/
└── MediaLibraryViewModel.swift  # Sample-media loading + video settings access

Services/
├── MediaService.swift      # Bundled sample-media loading
└── ConnectionManager.swift # Network connectivity (encryption required)

Views/
├── ImageViewController.swift    # Main controller (split across extensions)
├── ImageThumbnailCell.swift    # Grid cell implementation  
├── VideoThumbnailCache.swift   # Memory + disk thumbnail cache
├── ToastView.swift             # User notifications
├── HelpView.swift              # Built-in help system
└── EmptyStateView.swift        # Empty state interface
```

#### iPhone App
```
├── iPhoneMainViewController.swift     # Root shell (split across extensions)
├── iPhoneConnectionManager.swift      # Multipeer browser/session + control commands
├── TVLibraryStore.swift               # Read-only mirror of the TV library (per TV)
├── LocalMediaStore.swift              # Full-res copies of sent media (for AirPlay)
├── KnownTVRegistry.swift              # Apple TVs this phone has connected to
├── LibraryGridViewController.swift    # Home grid: live hero, tap-to-play, context menus
├── HomeHeaderBar.swift                # Connection pill, library switcher, arrange, +
├── AlbumsViewController.swift         # Read-only cloud album browser (HTTPS)
├── ExternalDisplayManager.swift       # AirPlay external screen detection + window
├── PresentationViewController.swift   # Fullscreen renderer on the external display
└── MediaValidator.swift               # File validation + image downscaling
```

### Networking / sync
- **Multipeer (TV library)**: service type `eclipse-share`, required encryption; `EclipseShareEnvelope` for play/delete/move/reorder/video-settings/playback/account
- **CloudKit (iPhone Shows)**: `CKSyncEngine` via `EclipseSyncController`; Apple TV excluded (`EclipseSyncTVPolicy`)
- **HTTPS remote albums**: manifest + media from `aircamtv.com`; TV may use Supabase Realtime for album refresh
- These three planes are independent — do not treat CloudKit as a substitute for Multipeer TV media

## 🔧 Development

### Code Style
- **Swift 5.5+** with modern concurrency
- **Comprehensive error handling** with user-friendly messages
- **Performance monitoring** and memory management
- **Extensive logging** with os.log framework

### Key Features Implementation
- **Modular Design**: Clean separation with extensions
- **Memory Management**: Automatic cleanup and pressure handling
- **Performance Optimization**: Async loading and intelligent caching
- **Focus Management**: Apple TV remote navigation optimization

## 🐛 Troubleshooting

### Connection Issues
- Ensure both devices are on the same Wi-Fi network
- Check local network permissions in iOS Settings
- Restart both apps if connection fails
- Verify Bonjour services aren't blocked

### Media Transfer Problems  
- Supported formats: JPEG, PNG, HEIC (images), MP4, MOV (videos)
- Check available storage space on Apple TV
- Large files may take longer to transfer
- Cancel and retry if transfer stalls

### Performance Issues
- Clear cached thumbnails if experiencing slowdowns
- Restart app for memory cleanup  
- Check network bandwidth for video playback

## 📄 License

Copyright © 2026 Moxie LLC. All rights reserved.

This software and its source code are the confidential and proprietary property of
Moxie LLC. Unauthorized copying, modification, or distribution is strictly prohibited.
See [LICENSE](LICENSE) for full terms.

## 🙏 Credits

**Eclipse** - Advanced media viewing and wireless connectivity for Apple TV
- **Architecture**: `MediaDataSource`-centered single source of truth (UIKit, not full MVVM)
- **Frameworks**: UIKit, AVKit, MultipeerConnectivity, Combine
- **Platform**: tvOS 17.0+ / iOS 16.0+

---

For detailed component documentation, see the individual README files in each app directory:
- [Apple TV App Documentation](EclipseAppleTV/EclipseAppleTV/README.md)
- [iPhone App Documentation](EclipseiPhone/README.md)

---

Copyright © 2026 Moxie LLC. All rights reserved.
