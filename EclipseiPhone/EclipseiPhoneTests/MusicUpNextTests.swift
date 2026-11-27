//
//  MusicUpNextTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Testing
import Foundation
@testable import EclipseiPhone

struct MusicUpNextTests {

    private let a = UUID(), b = UUID(), c = UUID()

    @Test func addToQueueAppendsInOrder() {
        var list = MusicUpNext()
        list.add(a)
        list.add(b)
        #expect(list.trackIds == [a, b])
    }

    @Test func addToQueueKeepsAnAlreadyQueuedSongInPlace() {
        var list = MusicUpNext()
        list.add(a)
        list.add(b)
        list.add(a)
        #expect(list.trackIds == [a, b])
    }

    @Test func playNextGoesFirst() {
        var list = MusicUpNext()
        list.add(a)
        list.playNext(b)
        #expect(list.trackIds == [b, a])
    }

    @Test func playNextMovesAnAlreadyQueuedSongToTheFront() {
        var list = MusicUpNext()
        list.add(a)
        list.add(b)
        list.add(c)
        list.playNext(c)
        #expect(list.trackIds == [c, a, b])
    }

    @Test func removeAndClear() {
        var list = MusicUpNext()
        list.add(a)
        list.add(b)
        list.remove(a)
        #expect(list.trackIds == [b])
        list.removeAll()
        #expect(list.isEmpty)
    }

    @Test func removeAtIndexReturnsTheSong() {
        var list = MusicUpNext()
        list.add(a)
        list.add(b)
        #expect(list.remove(at: 1) == b)
        #expect(list.remove(at: 5) == nil)
        #expect(list.trackIds == [a])
    }

    @Test func moveReorders() {
        var list = MusicUpNext()
        list.add(a)
        list.add(b)
        list.add(c)
        list.move(from: 0, to: 2)
        #expect(list.trackIds == [b, c, a])
        list.move(from: 2, to: 0)
        #expect(list.trackIds == [a, b, c])
        list.move(from: 9, to: 0)
        #expect(list.trackIds == [a, b, c])
    }

    @Test func popFirstSkipsSongsThatCannotPlay() {
        var list = MusicUpNext()
        list.add(a)
        list.add(b)
        list.add(c)
        let popped = list.popFirst { $0 != a }
        #expect(popped == b)
        #expect(list.trackIds == [c])
        #expect(list.popFirst { _ in false } == nil)
        #expect(list.isEmpty)
    }
}

@MainActor
struct MusicTrackEndTests {

    @Test func upNextPlaysEvenWithAutoplayOff() {
        #expect(AudioPlayerController.trackEndAction(
            hasPlayableUpNext: true, playsNext: false, queueIsEmpty: false
        ) == .playNext)
    }

    @Test func autoplayAdvancesThePlaylist() {
        #expect(AudioPlayerController.trackEndAction(
            hasPlayableUpNext: false, playsNext: true, queueIsEmpty: false
        ) == .playNext)
    }

    @Test func autoplayOffParks() {
        #expect(AudioPlayerController.trackEndAction(
            hasPlayableUpNext: false, playsNext: false, queueIsEmpty: false
        ) == .park)
    }

    @Test func emptyPlaylistParks() {
        #expect(AudioPlayerController.trackEndAction(
            hasPlayableUpNext: false, playsNext: true, queueIsEmpty: true
        ) == .park)
    }

    @Test func playlistTitleNamesTheSourceAndCount() {
        #expect(AudioNowPlayingViewController.playlistSectionTitle(
            playlistName: "Walk-in", trackCount: 5, hasUpNext: false
        ) == "Walk-in · 5 tracks")
        #expect(AudioNowPlayingViewController.playlistSectionTitle(
            playlistName: nil, trackCount: 5, hasUpNext: true
        ) == "Then Music · 5 tracks")
        #expect(AudioNowPlayingViewController.playlistSectionTitle(
            playlistName: "Walk-in", trackCount: 1, hasUpNext: false
        ) == "Now Playing")
    }
}
