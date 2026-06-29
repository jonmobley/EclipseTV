# Eclipse - Apple TV & iPhone Media System

A dual-platform media system that turns an Apple TV into a fullscreen digital frame and uses the iPhone as a companion remote: send media to the TV, browse and control the TV's library, view read-only cloud albums, and present media on an AirPlay display.

![Eclipse Logo](EclipseAppleTV/Images/eclipse-qrcode.png)

## 🌟 Overview

Eclipse consists of two companion apps that work together to provide a premium media viewing experience:

- **🍎 Eclipse Apple TV**: Fullscreen media display, library management, and read-only cloud albums
- **📱 Eclipse iPhone**: Companion remote that sends media, mirrors and controls the TV library, browses cloud albums, and drives an AirPlay display

The Apple TV draws content from three sources: bundled samples (first launch only), a local library sent and managed from the iPhone, and read-only cloud albums synced from a hosted account code.

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
- **Media Selection**: Easy photo and video selection from your library, with validation and custom video thumbnails
- **Wireless Transfer**: Encrypted peer-to-peer media sharing with real-time progress and cancellation
- **Library Mirroring & Control**: Browse the TV's live library; make items live, delete, reorder, and control video playback
- **Multi-TV Support**: Remembers every Apple TV connected, with per-TV cached libraries and optional keep-all-in-sync
- **Remote Albums**: Browse cloud albums by account code and push the code to the TV
- **AirPlay Presentation**: Present the selected item fullscreen on a mirrored Apple TV while the phone stays interactive
- **Auto-discovery**: Automatic Apple TV detection with offline/pause mode

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
1. **Launch Eclipse on Apple TV** first
2. **Open Eclipse iPhone app** on your iPhone
3. **Wait for automatic connection** (usually 2-5 seconds)
4. **Add media** on the iPhone (the `+` button) to send it to the TV, or **set up remote albums** with an account code
5. **Browse and control** the TV library from the iPhone, and **enjoy fullscreen viewing** with the Siri Remote

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

### Networking
- **iPhone ↔ TV**: MultipeerConnectivity (service type `eclipse-share`, Bonjour discovery, required encryption, auto-reconnection)
- **Control protocol**: JSON `EclipseShareEnvelope` messages for play/delete/move/reorder/video-settings/playback/account
- **Cloud albums**: HTTPS manifest + media fetch from the hosted account (`aircamtv.com`)
- **Realtime updates**: The TV subscribes to Supabase Realtime to re-sync albums when they change on the server

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
