# Eclipse iPhone

A powerful iOS companion app for wirelessly transferring photos and videos to the Eclipse Apple TV application. Features seamless device discovery, real-time transfer progress, and intuitive media selection.

## Features

### 📱 **Wireless Media Transfer**
- **Auto-discovery** of nearby Apple TV devices running Eclipse
- **Real-time transfer progress** with visual indicators
- **Background transfer support** for uninterrupted communication
- **Transfer cancellation** with instant feedback
- **Encrypted connections** via MultipeerConnectivity

### 🖼️ **Media Selection & Management**
- **PhotoKit integration** for seamless access to your photo library
- **Multi-selection support** for batch transfers
- **Live preview** of selected media in collection view
- **Format validation** to ensure compatibility
- **Media type detection** (images and videos)

### 🔄 **Connection Management**
- **Automatic reconnection** when devices come back in range
- **Connection state monitoring** with visual feedback
- **Smart pairing** remembers previously connected devices
- **Network status awareness** with graceful error handling
- **Background task handling** maintains connections during app switching

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
2. **Open** the Eclipse iPhone app
3. **Wait** for automatic device discovery (usually 2-5 seconds)
4. **Connection established** indicator will appear

### 📸 **Transferring Media**
1. **Tap "Select Media"** to open the photo picker
2. **Choose photos/videos** from your library
3. **Tap "Send to Apple TV"** to begin transfer
4. **Monitor progress** with the built-in progress indicator
5. **View immediately** on your Apple TV once transfer completes

### 🔗 **Connection Management**
- **Green indicator**: Successfully connected to Apple TV
- **Orange indicator**: Searching for devices
- **Red indicator**: Connection failed or lost
- **Auto-reconnect**: App automatically reconnects when devices are in range

## Interface Overview

### **Main Screen Elements**
```
┌─────────────────────────┐
│      Eclipse Title      │
│   Connection Status     │
│                        │
│   [Select Media]       │
│                        │
│  Selected Media Grid   │
│                        │
│  [Send to Apple TV]    │
│     [Cancel]           │
└─────────────────────────┘
```

### **Connection States**
| Status | Visual | Description |
|--------|--------|-------------|
| **Connecting** | Orange pulse | Searching for Apple TV |
| **Connected** | Green solid | Ready to transfer |
| **Transferring** | Blue progress | Transfer in progress |
| **Disconnected** | Red/Gray | Connection lost |

## Technical Architecture

### **Core Components**
```swift
iPhoneMainViewController     // Main UI controller
iPhoneConnectionManager     // Network communication
MediaValidator             // File format validation
ImagePreviewCell          // Media thumbnail display
```

### **Network Layer**
- **Protocol**: MultipeerConnectivity framework
- **Service Type**: `eclipse-share` (matches Apple TV)
- **Security**: Encrypted peer-to-peer connections
- **Discovery**: Bonjour service advertising and browsing

### **Data Flow**
```
Photo Library → Media Selection → Validation → Transfer → Apple TV
      ↓              ↓              ↓           ↓         ↓
   PhotoKit    Collection View   Validator   MCSession  Display
```

## Development

### **Project Structure**
```
EclipseiPhone/
├── iPhoneMainViewController.swift    # Main app interface
├── iPhoneConnectionManager.swift     # Network management
├── MediaValidator.swift              # File validation
├── ImagePreviewCell.swift           # UI components
├── AppDelegate.swift                # App lifecycle
├── SceneDelegate.swift              # Scene management
├── Assets.xcassets/                 # App icons and images
└── Base.lproj/                      # Storyboards and localizations
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
- **Local processing**: No cloud storage or external servers
- **Encrypted transfers**: All data encrypted in transit
- **Permission-based access**: Requires explicit photo library permission
- **No data persistence**: Media only stored temporarily during transfer

### **Network Security**
- Peer-to-peer encryption via MultipeerConnectivity
- Local network only (no internet connectivity required)
- Device authentication and trusted connections

## Future Enhancements

### **Planned Features**
- [ ] **iPad optimization** with enhanced UI for larger screens
- [ ] **Batch operations** with queue management
- [ ] **Transfer history** and recently sent items
- [ ] **Compression options** for faster transfers
- [ ] **Dark mode** support

### **Potential Improvements**
- [ ] **Cloud backup** integration for settings
- [ ] **Multiple Apple TV** support
- [ ] **Live Photos** support
- [ ] **Audio file** compatibility

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