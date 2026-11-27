//
//  CountdownClockSyncTests.swift
//  EclipseiPhoneTests
//
//  Mode, To Time target, caption and plate: iCloud record mapping, saved JSON
//  from before these fields existed, Show Live state and the To Time math.
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import CloudKit
import Foundation
import Testing
@testable import EclipseiPhone

struct CountdownClockSyncTests {

    private typealias Key = CloudKitSchema.CountdownKey

    // MARK: - Record Mapping

    @Test func recordRoundTripKeepsEveryClockField() throws {
        let settings = CountdownClockSettings(
            mode: .timeOfDay,
            targetMinutes: 18 * 60 + 30,
            targetDay: "2026-12-24",
            targetTimeZone: "America/New_York",
            caption: "Doors open in",
            style: .simple
        )
        let item = ShowCountdown(showId: UUID(), name: "Doors", duration: 90, clock: settings)
        let record = CloudKitRecordMapper.makeCountdownRecord(from: item)
        #expect(record[Key.mode] as? String == "timeOfDay")
        #expect(record[Key.style] as? String == "simple")
        #expect(record[Key.targetMinutes] as? Int == 1110)
        let decoded = try #require(CloudKitRecordMapper.countdown(from: record))
        #expect(decoded.clock == settings)
    }

    @Test func recordFromOlderAppReadsAsPlainCountdownWithPlate() throws {
        let record = CloudKitRecordMapper.makeCountdownRecord(
            from: ShowCountdown(showId: UUID(), name: "Old", duration: 60)
        )
        for key in [Key.mode, Key.style, Key.caption, Key.targetDay, Key.targetTimeZone] {
            record[key] = nil
        }
        let decoded = try #require(CloudKitRecordMapper.countdown(from: record))
        #expect(decoded.clock == CountdownClockSettings())
        #expect(decoded.clock.showsPlate)
    }

    @Test func plainCountdownAddsNoNewFieldsToItsRecord() {
        let record = CloudKitRecordMapper.makeCountdownRecord(
            from: ShowCountdown(showId: UUID(), name: "Plain", duration: 60)
        )
        for key in [Key.mode, Key.style, Key.caption, Key.targetDay,
                    Key.targetTimeZone, Key.targetMinutes] {
            #expect(record[key] == nil)
        }
    }

    @Test func clearingACaptionWritesEmptySoTheMacClearsItToo() {
        var item = ShowCountdown(
            showId: UUID(), name: "Doors", duration: 60,
            clock: .init(caption: "Up next")
        )
        let record = CloudKitRecordMapper.makeCountdownRecord(from: item)
        #expect(record[Key.caption] as? String == "Up next")
        item.clock.caption = ""
        let updated = CloudKitRecordMapper.makeCountdownRecord(from: item, existing: record)
        #expect(updated[Key.caption] as? String == "")
    }

    @Test func reusedRecordKeepsTheMacsTargetAndUnknownFields() {
        let record = CloudKitRecordMapper.makeCountdownRecord(
            from: ShowCountdown(showId: UUID(), name: "Doors", duration: 60)
        )
        record[Key.targetMinutes] = 600 as CKRecordValue
        record["macOnlyField"] = "kept" as CKRecordValue
        let item = ShowCountdown(showId: UUID(), name: "Doors", duration: 60)
        let updated = CloudKitRecordMapper.makeCountdownRecord(from: item, existing: record)
        #expect(updated[Key.targetMinutes] as? Int == 600)
        #expect(updated["macOnlyField"] as? String == "kept")
    }

    @Test func unknownValuesFallBackAndMinutesAreClamped() throws {
        let record = CloudKitRecordMapper.makeCountdownRecord(
            from: ShowCountdown(showId: UUID(), name: "Odd", duration: 60)
        )
        record[Key.mode] = "lapTimer" as CKRecordValue
        record[Key.style] = "neon" as CKRecordValue
        record[Key.targetMinutes] = 5000 as CKRecordValue
        let decoded = try #require(CloudKitRecordMapper.countdown(from: record))
        #expect(decoded.clock.mode == .countdown)
        #expect(decoded.clock.style == .card)
        #expect(decoded.clock.targetMinutes == 1439)
    }

    // MARK: - Saved JSON

    @Test func countdownSavedBeforeClockOptionsStillDecodes() throws {
        let json = """
        {"id":"\(UUID().uuidString)","showId":"\(UUID().uuidString)",
         "name":"Break","duration":120,"createdAt":0}
        """
        let item = try JSONDecoder().decode(ShowCountdown.self, from: Data(json.utf8))
        #expect(item.clock == CountdownClockSettings())
        #expect(item.tileTitle() == "Break\n2:00")
    }

    @Test func savedJSONRoundTripsClockOptions() throws {
        let item = ShowCountdown(
            showId: UUID(), name: "Walk-in", duration: 60,
            clock: .init(mode: .countUp, caption: "Get ready", style: .simple)
        )
        let data = try JSONEncoder().encode(item)
        let decoded = try JSONDecoder().decode(ShowCountdown.self, from: data)
        #expect(decoded == item)
        #expect(decoded.tileTitle() == "Walk-in\n0:00")
    }

    @Test func unknownSavedModeDecodesAsCountdown() throws {
        let json = #"{"mode":"future","caption":"Hi"}"#
        let settings = try JSONDecoder().decode(
            CountdownClockSettings.self, from: Data(json.utf8)
        )
        #expect(settings.mode == .countdown)
        #expect(settings.caption == "Hi")
        #expect(settings.style == .card)
    }

    // MARK: - To Time Math

    @Test func targetOnADayInANamedZone() throws {
        let settings = CountdownClockSettings(
            mode: .timeOfDay, targetMinutes: 18 * 60 + 30,
            targetDay: "2026-12-24", targetTimeZone: "America/New_York"
        )
        let target = try #require(settings.targetDate(relativeTo: Date()))
        // 6:30 PM EST is 23:30 UTC.
        #expect(target == Date(timeIntervalSince1970: 1_798_155_000))
    }

    @Test func passedTargetWithoutADayDoesNotRollToTomorrow() {
        let fivePM = Date(timeIntervalSince1970: 1_795_626_000)
        let settings = CountdownClockSettings(
            mode: .timeOfDay, targetMinutes: 16 * 60, targetTimeZone: "UTC"
        )
        #expect(settings.secondsUntilTarget(now: fivePM) == 0)
        #expect(settings.idleFaceText(duration: 60, held: nil, now: fivePM).hasPrefix("to "))
    }

    // MARK: - Show Live

    @Test func showLiveStateFromOlderDirectorDecodes() throws {
        let json = #"{"remaining":0,"duration":60,"running":false}"#
        let state = try JSONDecoder().decode(ShowLiveCountdownState.self, from: Data(json.utf8))
        #expect(state.countsUp == nil)
        #expect(state.isAtEnd)
        let countUp = ShowLiveCountdownState(remaining: 0, duration: 60, running: true, countsUp: true)
        #expect(countUp.isAtEnd == false)
    }
}
