# Eclipse Apple TV

A sophisticated Apple TV application for displaying and managing fullscreen media with wireless connectivity to iOS devices. Built with modern iOS development practices using MVVM architecture and reactive programming.

## Features

### 📺 **Media Display & Management**
- **Fullscreen media viewing** with optimal aspect ratio handling
- **Grid view interface** with rounded corner thumbnails and 16:9 aspect ratio optimization
- **Dual-mode navigation**: Switch seamlessly between grid and fullscreen views
- **Move mode**: Reorganize your media library with intuitive drag-and-drop
- **Smart media detection**: Automatic format recognition and validation

### 🎬 **Supported Media Formats**
- **Images**: JPEG, PNG, HEIC with high-resolution support
- **Videos**: MP4, MOV with duration tracking and playback controls
- **Automatic format detection** and error handling for unsupported files

### 📱 **Wireless Connectivity**
- **MultipeerConnectivity integration** for seamless iPhone pairing
- **Auto-discovery** of nearby iPhone devices running Eclipse companion app
- **Real-time transfer progress** with cancellation support
- **Background transfer handling** with connection state monitoring
- **Encrypted transfers** for security

### 🎮 **Apple TV Navigation**
- **Optimized gesture controls**:
  - Swipe Left/Right: Navigate between media
  - Swipe Up: Show grid view
  - Swipe Down: Exit grid view or return to fullscreen
  - Play/Pause: Toggle between grid and fullscreen modes
  - Menu: Show options menu, exit modes, or access help
- **Focus management** optimized for Apple TV remote
- **Comprehensive help system** with contextual guidance

### ⚡ **Performance & User Experience**
- **Async image loading** with memory optimization
- **Intelligent thumbnail caching** via ThumbnailService
- **Performance monitoring** for smooth playback
- **Toast notifications** for user feedback
- **Empty state handling** with helpful instructions
- **Error recovery** with detailed error reporting

## Architecture

### 🏗️ **MVVM Design Pattern**
```
Models/
├── MediaItem.swift          # Core data model for media files
├── AppState.swift          # Application state management
└── MediaError.swift        # Comprehensive error handling

ViewModels/
└── MediaLibraryViewModel.swift  # Business logic and data binding

Services/
├── MediaService.swift      # Media file operations
├── ThumbnailService.swift  # Thumbnail generation and caching
└── ConnectionManager.swift # Network connectivity

Views/
├── ImageViewController.swift    # Main view controller (modular)
├── ImageThumbnailCell.swift    # Grid cell implementation
├── ToastView.swift             # User feedback notifications
├── HelpView.swift              # Built-in help system
└── EmptyStateView.swift        # Empty state interface
```

### 📊 **Data Management**
- **MediaDataSource**: Centralized, observable data source
- **Reactive programming** with Combine framework
- **Persistent storage** for recently viewed media
- **Smart file validation** and cleanup

## Requirements

- **Xcode 15.0+**
- **tvOS 17.0+**
- **Apple TV HD or Apple TV 4K**
- **iOS companion app** for media transfer (optional)

## Installation & Setup

### 1. **Project Setup**
```bash
git clone [repository-url]
cd EclipseAppleTV
open EclipseAppleTV.xcodeproj
```

### 2. **Asset Configuration**
Add sample images to `Assets.xcassets`:
- Create image sets: `sample1`, `sample2`, `sample3`
- Use high-resolution images (recommended: 1920×1080 or higher)
- Landscape orientation optimal for TV display

### 3. **Build & Deploy**
- Select Apple TV target device or simulator
- Build and run the application
- Grant local network permissions when prompted

## Usage Guide

### 🎯 **Getting Started**
1. **Launch** the Eclipse app on your Apple TV
2. **Connect** your iPhone running the Eclipse companion app
3. **Transfer media** wirelessly from your iPhone
4. **Enjoy** fullscreen media viewing with gesture controls

### 📱 **iPhone Integration**
- Download and install the Eclipse iPhone companion app
- Ensure both devices are on the same Wi-Fi network
- The Apple TV app will auto-discover nearby iPhone devices
- Select media on iPhone and transfer to Apple TV instantly

### 🎮 **Navigation Controls**
| Gesture | Action |
|---------|--------|
| **Swipe Left/Right** | Navigate between media |
| **Swipe Up** | Enter grid view |
| **Swipe Down** | Exit grid/return to fullscreen |
| **Play/Pause** | Toggle grid/fullscreen modes |
| **Menu Button** | Options menu, exit modes, help |
| **Select** | Choose media, confirm actions |

### ⚙️ **Advanced Features**
- **Move Mode**: Long press in grid view to reorganize media
- **Help System**: Access via Menu → "Show Help"
- **Media Management**: View file details, formats, and transfer history

## Troubleshooting

### **Connection Issues**
- Ensure both devices are on the same Wi-Fi network
- Check that local network permissions are granted
- Restart both apps if connection fails
- Verify Bonjour services are not blocked by network settings

### **Media Transfer Problems**
- Supported formats: JPEG, PNG, HEIC (images), MP4, MOV (videos)
- Check available storage space on Apple TV
- Large files may take longer to transfer
- Cancel and retry if transfer stalls

### **Performance Issues**
- Clear cached thumbnails if experiencing slowdowns
- Restart app for memory cleanup
- Check network bandwidth for video playback issues

## Technical Details

### **Network Configuration**
- Service Type: `eclipse-share`
- Protocol: MultipeerConnectivity with encryption
- Bonjour Services: `_eclipse-share._tcp`, `_eclipse-share._udp`

### **File Storage**
- Local caching for recently viewed media
- Automatic cleanup of old files
- Efficient thumbnail generation and storage

### **Performance Optimization**
- Async image loading and processing
- Memory-conscious media handling
- Optimized for 4K displays and HDR content

## Development

### **Code Style**
- Swift 5.5+ with async/await
- MVVM architecture with Combine
- Comprehensive error handling
- Modular, testable design

### **Key Components**
- **MediaDataSource**: Central data management
- **ConnectionManager**: Network communication
- **ImageViewController**: Main UI coordinator
- **Performance monitoring**: Built-in analytics

## License

This project is provided as-is with no warranties. For educational and personal use.

## Credits

**Eclipse Apple TV** - Advanced media viewing and wireless connectivity for Apple TV
- Architecture: MVVM with reactive programming
- Frameworks: UIKit, AVKit, MultipeerConnectivity, Combine
- Platform: tvOS 17.0+
