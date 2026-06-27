// DemoAlbum.swift
import Foundation

/// Built-in account manifest used for testing the remote-album pipeline without hosting
/// a manifest or typing a code on the TV. The media URLs are public sample assets, so
/// loading the demo still exercises the real HTTPS download + on-disk + display path.
///
/// Bump an item's `checksum` to force a re-download when validating change detection.
enum DemoAlbum {
    static let manifest = AlbumManifest(
        version: 1,
        code: "000000",
        albums: [
            AlbumManifestAlbum(
                id: "demo-scenery",
                name: "Scenery",
                items: [
                    AlbumManifestItem(id: "demo-lake",
                                      url: "https://picsum.photos/id/1015/1920/1080",
                                      type: "image",
                                      name: "Lake",
                                      checksum: "v1"),
                    AlbumManifestItem(id: "demo-road",
                                      url: "https://picsum.photos/id/1039/1920/1080",
                                      type: "image",
                                      name: "Road",
                                      checksum: "v1")
                ]),
            AlbumManifestAlbum(
                id: "demo-mixed",
                name: "Mixed Media",
                items: [
                    AlbumManifestItem(id: "demo-dog",
                                      url: "https://picsum.photos/id/1025/1920/1080",
                                      type: "image",
                                      name: "Dog",
                                      checksum: "v1"),
                    AlbumManifestItem(id: "demo-clip",
                                      url: "https://test-videos.co.uk/vids/bigbuckbunny/mp4/h264/360/Big_Buck_Bunny_360_10s_1MB.mp4",
                                      type: "video",
                                      name: "Sample Clip",
                                      checksum: "v1")
                ])
        ]
    )
}
