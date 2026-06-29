# Eclipse Apple TV

A sophisticated Apple TV application for displaying and managing fullscreen media with wireless connectivity to iOS devices. Built with UIKit around a `MediaDataSource` single-source-of-truth, with Combine used for lightweight reactive updates.

## Features

### 📺 **Media Display & Management**
- **Fullscreen media viewing** with optimal aspect ratio handling
- **Grid view interface** with rounded corner thumbnails and 16:9 aspect ratio optimization
- **Dual-mode navigation**: Switch seamlessly between grid and fullscreen views
- **Move mode**: Reorganize your local library with intuitive drag-and-drop
- **Remote albums**: Read-only cloud albums (synced via a 6-digit account code) shown as extra grid sections
- **Sample media**: Bundled samples load on the first launch only, so the app is never empty out of the box
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
- **Optimized Siri Remote controls**:
  - Play/Pause: Toggle between grid and fullscreen
  - Menu: In fullscreen, return to grid; in grid, open the options menu (albums, help)
  - Swipe Left/Right: Navigate between items in fullscreen
  - Long Press: Enter move mode to reorder the local library (grid view)
- **Focus management** optimized for the Siri Remote
- **Comprehensive help system** with contextual guidance

### ⚡ **Performance & User Experience**
- **Async image loading** with memory optimization
- **Intelligent thumbnail caching** via VideoThumbnailCache (memory + disk)
- **Performance monitoring** for smooth playback
- **Toast notifications** for user feedback
- **Empty state handling** with helpful instructions
- **Error recovery** with detailed error reporting

## Architecture

### 🏗️ **Single Source of Truth**
`MediaDataSource` owns the media list, current index, and persistence; the UI observes it.
```
MediaDataSource.swift        # Single source of truth for media list + persistence

Models/
├── MediaItem.swift          # Core data model for media files (path-based identity)
├── AppState.swift          # Per-file video settings (mute/loop) storage
└── MediaError.swift        # Comprehensive error handling

ViewModels/
└── MediaLibraryViewModel.swift  # Sample-media loading + video settings access

Services/
├── MediaService.swift      # Bundled sample-media loading
├── ConnectionManager.swift # iPhone connectivity (Multipeer, encryption required)
└── TVLibrarySync.swift     # Mirrors the local library to the connected iPhone

RemoteAlbum/                 # Read-only cloud albums
├── AlbumConfig.swift        # Manifest host, code rules, Supabase Realtime credentials
├── AlbumManifest.swift      # JSON wire format for account albums
├── RemoteAlbumSync.swift    # HTTPS manifest fetch + media download
└── RealtimeAlbumNotifier.swift # Supabase Realtime push to re-sync on change
RemoteAlbumStore.swift       # Downloaded albums (read-only), separate from the library

VideoThumbnailCache.swift    # Memory + disk thumbnail cache

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
Bundled sample media is loaded on the first launch only (so the app is never empty out
of the box); afterward the app shows the user's real library. To customize the samples,
add image sets to `Assets.xcassets`:
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
| Control | Action |
|---------|--------|
| **Play/Pause** | Toggle between grid and fullscreen |
| **Menu Button** | In fullscreen: return to grid. In grid: open the options menu |
| **Swipe Left/Right** | Navigate between items in fullscreen |
| **Long Press** | Enter move mode to reorder the local library (grid view) |
| **Select** | Choose media, confirm actions |

Cloud album items are read-only — no move/delete on the TV.

### ⚙️ **Advanced Features**
- **Move Mode**: Long press a local-library item in grid view to reorder it
- **Remote Albums**: Enter a 6-digit account code from the options menu to sync read-only cloud albums
- **Help System**: Access via Menu (in grid) → options → "Show Help"

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
- iPhone link: MultipeerConnectivity with required encryption
  - Service Type: `eclipse-share`
  - Bonjour Services: `_eclipse-share._tcp`, `_eclipse-share._udp`
- Cloud albums: HTTPS manifest + media fetch from the hosted account
- Realtime: Supabase Realtime WebSocket to re-sync albums when they change on the server

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
- `MediaDataSource` single source of truth, with Combine for lightweight updates
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
- Architecture: `MediaDataSource`-centered single source of truth (UIKit, not full MVVM)
- Frameworks: UIKit, AVKit, MultipeerConnectivity, Combine
- Platform: tvOS 17.0+
