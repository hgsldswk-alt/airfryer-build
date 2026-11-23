import CoreImage
import XCTest

final class CoreTests: XCTestCase {
    let start = ClockReading(date: Date(timeIntervalSince1970: 86_000), uptime: 1_000)

    func testGuideAndUnitConversions() throws {
        XCTAssertEqual(Foods.starter.count, 14)
        XCTAssertTrue(Foods.starter.allSatisfy { $0.defaults.valid })
        XCTAssertTrue(Foods.starter.allSatisfy { ($0.minC...$0.maxC).contains($0.defaults.celsius) })
        XCTAssertEqual(TemperatureUnit.fahrenheit.label(190), "374°F")
        for value in Settings.temperatures {
            XCTAssertEqual(TemperatureUnit.fahrenheit.canonical(TemperatureUnit.fahrenheit.displayed(value)), value)
        }
        XCTAssertFalse(Settings(celsius: 231, minutes: 14).valid)
        XCTAssertFalse(Settings(celsius: 190, minutes: 181).valid)
        XCTAssertFalse(Settings(celsius: 190, minutes: 5, reminder: .flip, reminderMinute: 5).valid)
        var one = Settings(celsius: 190, minutes: 1, reminder: .flip, reminderMinute: 3)
        one.normalizeReminder()
        XCTAssertEqual(one.reminder, .none)
        XCTAssertTrue(one.valid)
    }

    func testOvenConversionChecksEarlyAndRespectsBounds() {
        XCTAssertEqual(OvenConversion.suggest(oven: 400, minutes: 20, unit: .fahrenheit),
                       .init(temperature: 375, firstCheck: 16))
        XCTAssertEqual(OvenConversion.suggest(oven: 200, minutes: 1, unit: .celsius),
                       .init(temperature: 186, firstCheck: 1))
        XCTAssertEqual(OvenConversion.suggest(oven: 260, minutes: 20, unit: .celsius)?.temperature, 230)
        XCTAssertNil(OvenConversion.suggest(oven: 90, minutes: 20, unit: .celsius))
        XCTAssertNil(OvenConversion.suggest(oven: 200, minutes: 0, unit: .celsius))
    }

    func testTimerPauseRemindersAndExtraCook() {
        var timer = makeTimer()
        timer.pause(at: clock(3 * 60))
        XCTAssertEqual(timer.elapsed(at: clock(6 * 60)), 180)
        timer.resume(at: clock(6 * 60))
        XCTAssertFalse(timer.reminderIsDue(at: clock(9 * 60)))
        XCTAssertTrue(timer.reminderIsDue(at: clock(10 * 60)))
        timer.confirmReminder(at: clock(11 * 60))
        timer.add(minutes: 1, at: clock(11 * 60))
        XCTAssertFalse(timer.reminderIsDue(at: clock(12 * 60)))
        XCTAssertEqual(timer.actual(celsius: 180).reminderMinute, 8)
        XCTAssertEqual(timer.remaining(at: clock(18 * 60)), 0)
        timer.add(minutes: 2, at: clock(18 * 60))
        XCTAssertEqual(timer.remaining(at: clock(18 * 60)), 120)
        let actual = timer.actual(celsius: 180)
        XCTAssertEqual(actual.minutes, 17)
        XCTAssertEqual(actual.celsius, 180)
    }

    func testTimerCrossesMidnightRecoversAndHandlesClockShift() throws {
        let timer = makeTimer()
        var recovered = try JSONDecoder().decode(CookTimer.self, from: JSONEncoder().encode(timer))
        recovered.recover(at: clock(500))
        XCTAssertEqual(recovered.remaining(at: clock(500)), 340)
        let shifted = ClockReading(date: start.date.addingTimeInterval(270), uptime: start.uptime + 540)
        recovered.reanchor(at: shifted)
        XCTAssertEqual(recovered.remaining(at: shifted), 300)
        recovered.recover(at: ClockReading(date: shifted.date.addingTimeInterval(2_000), uptime: 20))
        XCTAssertNil(recovered.runningSince)
        XCTAssertEqual(recovered.spent, recovered.total)
    }

    func testLateReminderDoesNotReappearDuringExtraTime() {
        var timer = makeTimer()
        timer.add(minutes: 2, at: clock(900))
        XCTAssertFalse(timer.reminderIsDue(at: clock(910)))
        XCTAssertEqual(timer.actual(celsius: 190).minutes, 16)
    }

    func testCalibrationsAreIsolatedAndCompletionIsIdempotent() throws {
        var state = AppState()
        let food = Foods.starter[0]
        let originalID = state.activeFryerID
        let session = makeTimer(key: state.key(for: food))
        let settings = session.actual(celsius: 180)
        state.timer = session
        XCTAssertFalse(state.finish(session, settings: settings, portion: "400 g", note: "crisp", save: true, at: clock(840).date))
        _ = state.finish(session, settings: settings, portion: "250 g", note: "", save: true, at: clock(840).date)
        XCTAssertEqual(state.records.count, 1)
        XCTAssertEqual(state.settings(for: food, at: state.primaryKey(for: food)).celsius, 180)
        XCTAssertEqual(state.settings(for: food, at: state.key(for: food)).celsius, 190)
        XCTAssertEqual(state.calibrations.first?.key.portion, "400 g")
        state.activeFryerID = UUID()
        state.fryers.append(Fryer(id: state.activeFryerID))
        XCTAssertEqual(state.settings(for: food, at: state.primaryKey(for: food)).celsius, 190)
        XCTAssertEqual(state.records.first?.key.fryerID, originalID)
    }

    func testMilestoneCountsDistinctSavedFoods() {
        var state = AppState()
        let ids = [0, 0, 4, 9]
        for (index, id) in ids.enumerated() {
            let food = Foods.starter[id]
            let session = CookTimer(key: state.key(for: food), food: food, fryerName: nil,
                                    portion: food.portion, settings: food.defaults, now: start)
            state.timer = session
            let result = state.finish(session, settings: food.defaults, portion: "", note: "", save: true, at: start.date)
            XCTAssertEqual(result, index == 3)
        }
        XCTAssertEqual(state.calibrations.count, 3)
    }

    func testOldStateRestoresDefaultsWithoutReplacingFryers() throws {
        let id = UUID()
        let old: [String: Any] = ["fryers": [["id": id.uuidString, "name": "My fryer", "archived": false]],
                                  "activeFryerID": id.uuidString]
        let state = try JSONDecoder().decode(AppState.self, from: JSONSerialization.data(withJSONObject: old))
        XCTAssertEqual(state.fryer.id, id)
        XCTAssertEqual(state.fryer.title, "My fryer")
        XCTAssertTrue(state.preferred.contains { $0.id == "fries" })
        XCTAssertTrue(state.records.isEmpty)
    }

    func testTrialAndBuyoutBoundariesWithRevocation() {
        var account = Entitlement(firstOpen: start.date)
        XCTAssertFalse(Launch.freePeriod)
        XCTAssertTrue(account.hasPro(at: start.date, free: false))
        XCTAssertTrue(account.hasPro(at: start.date.addingTimeInterval(30 * 86_400 - 1), free: false))
        XCTAssertFalse(account.hasPro(at: account.trialEnd, free: false))
        account.trialClaimedAt = start.date.addingTimeInterval(2 * 86_400)
        XCTAssertEqual(account.trialStart, start.date)
        account.proStartedAt = start.date.addingTimeInterval(8_000)
        account.trialClaimedAt = start.date.addingTimeInterval(-86_400)
        XCTAssertEqual(account.trialStart, account.trialClaimedAt)
        let expired = account.trialEnd.addingTimeInterval(1)
        account.purchasedPro = true
        XCTAssertTrue(account.hasPro(at: expired, free: false))
        account.purchasedPro = false
        XCTAssertFalse(account.hasPro(at: expired, free: false))
    }

    func testShareSchemaAndSeparatedImport() throws {
        let sample = ShareFood(catalogID: "fries", name: "Fries", state: "Frozen", portion: "250 g",
                               settings: Settings(celsius: 185, minutes: 15))
        let code = ShareCode(foods: [sample])
        XCTAssertEqual(try ShareCode.decode(code.encode()), code)
        XCTAssertThrowsError(try ShareCode.decode("AF2:xyz"))
        XCTAssertThrowsError(try ShareCode.decode("AF1:/"))
        XCTAssertThrowsError(try ShareCode.decode("AF1:" + String(repeating: "A", count: 8_193)))
        XCTAssertThrowsError(try ShareCode(foods: [sample, sample]).encode())
        var invalid = sample
        invalid.settings.minutes = 0
        XCTAssertThrowsError(try ShareCode(foods: [invalid]).encode())
        var state = AppState()
        let id = state.activeFryerID
        XCTAssertTrue(try state.addCard(code, to: id))
        XCTAssertFalse(try state.addCard(code, to: id))
        let imported = try XCTUnwrap(state.custom.first)
        XCTAssertEqual(imported.food.group, .friend)
        XCTAssertEqual(imported.originalID, "fries")
        XCTAssertEqual(state.settings(for: Foods.starter[0], at: state.key(for: Foods.starter[0])).celsius, 190)
    }

    func testQRDecodesBothPlaceholderAndStoreURL() throws {
        for storeID in [nil, "1234567890"] as [String?] {
            let url = ShareQR.downloadURL(storeID: storeID)
            let bitmap = try XCTUnwrap(ShareQR.image(for: url)?.cgImage)
            let detector = try XCTUnwrap(CIDetector(ofType: CIDetectorTypeQRCode, context: nil,
                                                   options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]))
            let decoded = detector.features(in: CIImage(cgImage: bitmap)).compactMap { ($0 as? CIQRCodeFeature)?.messageString }
            XCTAssertEqual(decoded, [url.absoluteString])
        }
    }

    func testReviewRequiresThreeDifferentLocalDays() {
        var progress = CoreReviewProgress()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        progress.record(at: start.date, calendar: calendar)
        progress.record(at: start.date, calendar: calendar)
        progress.record(at: start.date.addingTimeInterval(86_400), calendar: calendar)
        XCTAssertFalse(progress.isEligible)
        progress.record(at: start.date.addingTimeInterval(172_800), calendar: calendar)
        XCTAssertTrue(progress.isEligible)
    }

    private func makeTimer(key: FoodKey = FoodKey(fryerID: UUID(), foodID: "fries")) -> CookTimer {
        let food = Foods.starter[0]
        return CookTimer(key: key, food: food, fryerName: nil, portion: food.portion, settings: food.defaults, now: start)
    }

    private func clock(_ seconds: TimeInterval) -> ClockReading {
        ClockReading(date: start.date.addingTimeInterval(seconds), uptime: start.uptime + seconds)
    }
}
