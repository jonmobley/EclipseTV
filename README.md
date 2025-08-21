# Eclipse - Apple TV & iPhone Media Sharing System

A sophisticated dual-platform media sharing system that enables seamless wireless transfer and display of photos and videos between iPhone and Apple TV devices.

![Eclipse Logo](EclipseAppleTV/Images/eclipse-qrcode.png)

## 🌟 Overview

Eclipse consists of two companion apps that work together to provide a premium media viewing experience:

- **🍎 Eclipse Apple TV**: Advanced media display and management on Apple TV
- **📱 Eclipse iPhone**: Companion app for media selection and wireless transfer

## 🚀 Key Features

### 📺 Apple TV App
- **Fullscreen Media Display**: Optimized viewing with perfect aspect ratio handling
- **Grid Interface**: Beautiful 16:9 thumbnail grid with smooth navigation
- **Move Mode**: Intuitive drag-and-drop media reorganization
- **Wireless Reception**: Seamless media receiving from iPhone devices
- **Smart Caching**: Intelligent thumbnail and video caching for smooth performance
- **Apple TV Remote Optimized**: Gesture controls designed for the Apple TV remote

### 📱 iPhone App  
- **Media Selection**: Easy photo and video selection from your library
- **Wireless Transfer**: Encrypted peer-to-peer media sharing
- **Real-time Progress**: Visual transfer progress with cancellation support
- **Auto-discovery**: Automatic Apple TV device detection
- **Media Validation**: Smart format checking and optimization

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
cd "August 13th Version Here"
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
4. **Select media** on iPhone and transfer to Apple TV
5. **Enjoy fullscreen viewing** with Apple TV remote controls

### Apple TV Controls
| Gesture | Action |
|---------|--------|
| **Swipe Left/Right** | Navigate between media |
| **Swipe Up** | Enter grid view |
| **Swipe Down** | Exit grid/return to fullscreen |
| **Play/Pause** | Toggle grid/fullscreen modes |
| **Menu Button** | Options menu, exit modes, help |
| **Long Press** | Enter move mode (in grid view) |

### iPhone Interface
- **Green indicator**: Connected to Apple TV
- **Orange indicator**: Searching for devices  
- **Red indicator**: Connection failed or lost
- **Progress bar**: Shows transfer progress

## 🏗 Architecture

### Design Patterns
- **MVVM Architecture** with reactive programming (Combine)
- **Protocol-oriented programming** for modularity
- **Delegate patterns** for communication
- **Async/await** for modern concurrency

### Key Components

#### Apple TV App
```
Models/
├── MediaItem.swift          # Core data model
├── AppState.swift          # Application state
└── MediaError.swift        # Error handling

ViewModels/  
└── MediaLibraryViewModel.swift  # Business logic

Services/
├── MediaService.swift      # Media operations
├── ThumbnailService.swift  # Thumbnail management
└── ConnectionManager.swift # Network connectivity

Views/
├── ImageViewController.swift    # Main controller (modular)
├── ImageThumbnailCell.swift    # Grid cell implementation  
├── ToastView.swift             # User notifications
├── HelpView.swift              # Built-in help system
└── EmptyStateView.swift        # Empty state interface
```

#### iPhone App
```
├── iPhoneMainViewController.swift    # Main interface
├── iPhoneConnectionManager.swift     # Network management
├── MediaValidator.swift              # File validation
├── ImagePreviewCell.swift           # UI components
└── VideoThumbnailPreviewViewController.swift # Video preview
```

### Networking
- **Protocol**: MultipeerConnectivity with encryption
- **Service Type**: `eclipse-share`
- **Discovery**: Bonjour services for auto-discovery
- **Security**: Encrypted peer-to-peer connections
- **Reliability**: Auto-reconnection and retry logic

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

This project is provided as-is with no warranties. For educational and personal use.

## 🙏 Credits

**Eclipse** - Advanced media viewing and wireless connectivity for Apple TV
- **Architecture**: MVVM with reactive programming
- **Frameworks**: UIKit, AVKit, MultipeerConnectivity, Combine
- **Platform**: tvOS 17.0+ / iOS 16.0+

---

For detailed component documentation, see the individual README files in each app directory:
- [Apple TV App Documentation](EclipseAppleTV/README.md)
- [iPhone App Documentation](EclipseiPhone/README.md)
