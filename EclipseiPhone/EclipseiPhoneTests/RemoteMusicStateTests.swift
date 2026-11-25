//
//  RemoteMusicStateTests.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import Testing
@testable import EclipseiPhone

/// The Mac's music state decodes on the phone, extra fields are ignored,
/// and the music commands use the names the Mac expects.
struct RemoteMusicStateTests {

    @Test func decodesMacMusicStateIgnoringTrackLists() throws {
        let json = """
        {"title":"Walk On","isPlaying":true,"isPaused":false,"autoPlayNext":true,
         "busVolume":0.8,"busMuted":false,"playlists":[],"tracks":[]}
        """
        let state = try JSONDecoder().decode(RemoteMusicState.self, from: Data(json.utf8))
        #expect(state.title == "Walk On")
        #expect(state.isPlaying)
        #expect(!state.busMuted)
    }

    @Test func musicCommandsUseMacWireNames() throws {
        let data = try JSONEncoder().encode(RemoteCommand(action: .musicFadeOut))
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains("\"musicFadeOut\""))
        #expect(RemoteCommandAction.musicToggleMute.rawValue == "musicToggleMute")
    }
}
