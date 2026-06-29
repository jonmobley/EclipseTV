# Eclipse iPhone

A companion app for the Eclipse Apple TV. It sends photos and videos to the TV, mirrors and controls the TV's live library, browses read-only cloud albums, and can present media on an AirPlay display. Built around a library-centric home screen (header bar + grid), not a one-off "pick and send" flow.

## Features

### 📺 **Library Mirroring & Control**
- **Live library mirror** of the TV's media, cached per Apple TV (works offline)
- **Make items live**, delete, and drag-to-reorder from the phone
- **Video transport controls** (play/pause, scrub, skip) for the live TV video
- **Re-send purged items** that tvOS evicted from the TV's cache

### 📱 **Wireless Media Transfer**
- **Auto-discovery** of nearby Apple TV devices running Eclipse, with offline/pause mode
- **Real-time transfer progress** with visual indicators and cancellation
- **Validation** (resolution/size/duration) and **custom video thumbnails** before sending
- **Encrypted connections** via MultipeerConnectivity

### ☁️ **Remote Albums**
- **Browse cloud albums** by entering a 6-digit account code (HTTPS, read-only)
- **Push the account code to the TV** so it syncs the same albums

### 📡 **AirPlay Presentation**
- **Present the selected item fullscreen** on a mirrored Apple TV while the phone stays interactive
- Uses full-resolution copies kept on the phone (local items) or HTTPS streams (album items)

### 🔄 **Connection & Multi-TV Management**
- **Multiple Apple TVs**: remembers every TV connected, with a library switcher and preferred TV
- **Automatic reconnection** when devices come back in range
- **Connection state monitoring** with visual feedback

### 🎨 **User Experience**
- **Modern iOS design** following Apple's Human Interface Guidelines
- **Responsive animations** and smooth transitions
- **Accessibility support** with VoiceOver compatibility
- **Progress tracking** for ongoing transfers
- **Toast notifications** for status updates

## Supported Media Formats

### **Images**
- **JPEG** (.jpg, .jpeg) - Standard photo format
- **PNG** (.png) - High-quality images with transparency
- **HEIC** (.heic) - Modern Apple photo format

### **Videos**
- **MP4** (.mp4) - Standard video format
- **MOV** (.mov) - Apple video format
- **M4V** (.m4v) - iTunes video format

## Requirements

- **iOS 16.0+**
- **iPhone or iPad** with Wi-Fi connectivity
- **Xcode 15.0+** (for development)
- **Eclipse Apple TV app** running on the same network

## Installation & Setup

### 1. **Development Setup**
```bash
git clone [repository-url]
cd EclipseiPhone
open EclipseiPhone.xcodeproj
```

### 2. **Configuration**
- Ensure your development team is set in Xcode
- Grant photo library access permissions when prompted
- Verify local network permissions are enabled

### 3. **Build & Deploy**
```bash
# For simulator
Build and run on iOS Simulator

# For device
Connect iPhone via USB or wirelessly
Build and run on connected device
```

## Usage Guide

### 🚀 **Getting Started**
1. **Launch** Eclipse on your Apple TV first
2. **Open** the Eclipse iPhone app — it auto-connects and mirrors that TV's library
3. **Browse the grid** of the TV's library; tap an item to make it live on the TV

### 📸 **Sending Media**
1. **Tap the `+` button** in the header to open the photo picker
2. **Choose a photo/video**; preview it (and pick a custom video thumbnail) before sending
3. **Monitor progress** with the transfer overlay
4. **It appears** in the TV library (and the mirrored grid) once the transfer completes

### ☁️ **Remote Albums**
1. **Open "Set Up Albums"** and enter your 6-digit account code
2. **Browse** the read-only albums; the code is also pushed to the TV so it syncs them

### 🔗 **Connection Management**
- **Connection pill** shows connected / searching / offline for the active TV
- **Library switcher** lets you switch between Apple TVs you've connected to
- **Auto-reconnect** when devices are back in range; pause to use the app offline

## Interface Overview

### **Main Screen Elements**
```
┌─────────────────────────────┐
│ [pill] [library ▾] [↕] [+]  │  ← HomeHeaderBar
│  ───────────────────────    │
│   Live item (hero)          │  ← LiveHeaderView
│  ───────────────────────    │
│   TV library grid           │  ← LibraryGridViewController
│   (tap = live, hold = menu) │
└─────────────────────────────┘
```

## Technical Architecture

### **Core Components**
```swift
iPhoneMainViewController        // Root shell (split across extensions)
iPhoneConnectionManager         // Multipeer browser/session + control commands
TVLibraryStore                  // Read-only mirror of the TV library (per TV)
LocalMediaStore                 // Full-res copies of sent media (for AirPlay)
KnownTVRegistry                 // Apple TVs this phone has connected to
LibraryGridViewController       // Home grid: live hero, tap-to-play, context menus
HomeHeaderBar                   // Connection pill, library switcher, arrange, +
AlbumsViewController            // Read-only cloud album browser (HTTPS)
ExternalDisplayManager          // AirPlay external screen detection + window
PresentationViewController      // Fullscreen renderer on the external display
MediaValidator                  // File validation + image downscaling
```

### **Network Layer**
- **TV link**: MultipeerConnectivity (`eclipse-share`, Bonjour, required encryption)
- **Control protocol**: JSON `EclipseShareEnvelope` (play/delete/move/reorder/video/playback/account)
- **Cloud albums**: HTTPS manifest + thumbnails from the hosted account (`aircamtv.com`)

### **Data Flow**
```
Photo Library → pick/preview → validate → Multipeer sendResource → Apple TV
Apple TV → manifest + thumbnails + playback status → TVLibraryStore → grid
Cloud (HTTPS) → AlbumBrowserStore → AlbumsViewController
Grid/Albums → ExternalDisplayManager → PresentationViewController (AirPlay)
```

## Development

### **Project Structure**
```
EclipseiPhone/
├── iPhoneMainViewController.swift    # Root shell (+ Setup/Connection/MediaActions/Album/Library extensions)
├── iPhoneConnectionManager.swift     # Multipeer browser/session + control commands
├── EclipseShareProtocol.swift        # Shared wire protocol (mirrored on the TV target)
├── TVLibraryStore.swift              # Read-only mirror of the TV library (per TV)
├── LocalMediaStore.swift             # Full-res copies of sent media (for AirPlay)
├── KnownTVRegistry.swift             # Apple TVs this phone has connected to
├── LibraryGridViewController.swift   # Home grid (+ Arrange extension)
├── HomeHeaderBar.swift               # Header bar
├── AlbumsViewController.swift        # Cloud album browser
├── AlbumBrowserStore.swift           # Account code + cached album manifest
├── ExternalDisplayManager.swift      # AirPlay external display
├── PresentationViewController.swift  # External-display renderer
├── MediaValidator.swift              # File validation + downscaling
├── AppDelegate.swift                 # App lifecycle
├── SceneDelegate.swift               # Scene management
└── Assets.xcassets/                  # App icons and images
```

### **Key Frameworks**
- **MultipeerConnectivity**: Device discovery and communication
- **Photos/PhotosUI**: Photo library access and selection
- **UIKit**: User interface components
- **Foundation**: Core functionality and data handling

### **Networking Implementation**
```swift
// Service discovery
MCNearbyServiceBrowser(peer: peerID, serviceType: "eclipse-share")

// Secure connections
MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)

// File transfer with progress
session.sendResource(at: fileURL, withName: fileName, toPeer: peer)
```

## Troubleshooting

### **Connection Issues**
- **Both devices on same Wi-Fi**: Verify network connectivity
- **Local network permissions**: Check iOS Settings → Privacy & Security → Local Network
- **Firewall settings**: Ensure Bonjour services aren't blocked
- **App restart**: Close and reopen both apps if connection fails

### **Transfer Problems**
- **Unsupported formats**: Only JPEG, PNG, HEIC, MP4, MOV supported
- **Large files**: Videos may take longer; progress indicator shows status
- **Storage space**: Ensure Apple TV has sufficient storage
- **Network bandwidth**: Slow Wi-Fi may affect transfer speeds

### **Photo Access Issues**
- **Permission denied**: Go to iOS Settings → Privacy & Security → Photos
- **Limited access**: Select "Full Access" for complete photo library
- **iCloud Photos**: Ensure photos are downloaded to device

## Performance Optimization

### **Memory Management**
- Efficient image loading and thumbnail generation
- Automatic cleanup of temporary files
- Progress monitoring without memory leaks

### **Network Efficiency**
- Compressed data transfer where appropriate
- Background task handling for reliability
- Automatic retry mechanisms for failed transfers

### **Battery Optimization**
- Efficient MultipeerConnectivity usage
- Background app refresh optimization
- Smart connection management

## Privacy & Security

### **Data Protection**
- **Encrypted TV link**: All Multipeer data is encrypted in transit
- **Permission-based access**: Requires explicit photo library permission
- **Local copies**: Full-res copies of sent media are kept on the phone to enable AirPlay presentation
- **Cloud albums**: Read-only HTTPS fetch from the hosted account (no credentials stored beyond the account code)

### **Network Security**
- Peer-to-peer encryption via MultipeerConnectivity for the TV link
- HTTPS for read-only cloud album browsing

## Future Enhancements

### **Planned Features**
- [ ] **iPad optimization** with enhanced UI for larger screens
- [ ] **Transfer history** and recently sent items
- [ ] **Live Photos** support

### **Done**
- [x] **Multiple Apple TV** support (library switcher + per-TV cached libraries)
- [x] **AirPlay presentation** on an external display
- [x] **Remote albums** by account code
- [x] **Dark mode** (the app runs in a forced dark appearance)

## License

This project is provided as-is with no warranties. For educational and personal use.

## Credits

**Eclipse iPhone** - iOS companion app for wireless media sharing
- **Platform**: iOS 16.0+
- **Architecture**: MVC with delegate patterns
- **Frameworks**: MultipeerConnectivity, PhotosUI, UIKit
- **Design**: Modern iOS interface with accessibility support

## Support

For technical issues or feature requests, please check the troubleshooting section above or review the Apple TV app documentation for complete ecosystem information. 