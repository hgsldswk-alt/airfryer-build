import Foundation
import XCTest

final class FlowUITests: XCTestCase {
    private let app = XCUIApplication()
    private let fixture = """
    {"version":1,"foods":[{"catalogID":"fries","name":"Frozen fries","state":"Frozen","portion":"250 g","settings":{"celsius":185,"minutes":15,"reminder":"shake","reminderMinute":7}}]}
    """

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        executionTimeAllowance = 900
    }

    func testLookupStartPauseReplaceAndRestore() {
        launch(["-deny-notifications"])
        XCTAssertTrue(app.buttons["food.fries"].waitForExistence(timeout: 10))
        tap("food.fries")
        tap("food.start")
        exists("timer.notificationFallback")
        tap("timer.pause")
        tap("timer.resume")
        tap("timer.add1")
        tap("timer.back")
        tap("start.fries")
        let keep = app.alerts.buttons["Keep current"]
        XCTAssertTrue(keep.waitForExistence(timeout: 8))
        keep.tap()
        tap("home.timer")
        app.terminate()
        launch(["-deny-notifications"], reset: false)
        exists("timer.remaining")
    }

    func testSearchAndUnits() {
        launch()
        tap("units.fahrenheit")
        let search = app.textFields["home.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap()
        search.typeText("salmon")
        tap("start.salmon")
        exists("timer.remaining")
    }

    func testOvenConversionAcceptsTypedValues() {
        launch()
        tap("home.convert")
        let temperature = app.textFields["convert.temperature"]
        XCTAssertTrue(temperature.waitForExistence(timeout: 8))
        temperature.tap()
        temperature.typeText("200")
        let minutes = app.textFields["convert.minutes"]
        minutes.tap()
        minutes.typeText("20")
        exists("convert.result.temperature")
        exists("convert.result.minutes")
    }

    func testShakeConfirmOnceAndOneTapRestart() {
        launch(["-shake"])
        tap("start.fries")
        tap("timer.confirm")
        XCTAssertFalse(app.buttons["timer.confirm"].exists)
        tap("timer.stop")
        let stop = app.alerts.buttons["Stop timer"]
        XCTAssertTrue(stop.waitForExistence(timeout: 8))
        stop.tap()
        tap("start.fries")
        exists("timer.remaining")
    }

    func testCompletionExtraAndSaveWritesBack() {
        launch(["-done"])
        tap("start.fries")
        tap("done.add2")
        exists("timer.remaining")
        app.terminate()
        launch(["-done"])
        tap("start.fries")
        tap("done.temperature.down")
        tap("done.save")
        tap("saved.share")
        tap("share.image")
        exists("share.requested")
        tap("share.back")
        tap("saved.done")
        tap("home.fryers")
        tap("saved.food.fries")
        let temperature = app.descendants(matching: .any).matching(identifier: "food.temperature.value").firstMatch
        XCTAssertTrue(temperature.waitForExistence(timeout: 8))
        XCTAssertTrue(temperature.label.contains("180°C"))
    }

    func testFryerCreationAndCardPreviewImport() {
        let encoded = Data(fixture.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        launch(["-seed"], environment: ["AF_IMPORT_CODE": "AF1:" + encoded])
        tap("home.fryers")
        tap("fryers.add")
        let name = app.textFields["editor.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 8))
        name.tap()
        name.typeText("Guest fryer")
        tap("editor.save")
        tap("fryers.import")
        tap("import.commit")
        exists("import.status")
        tap("import.back")
        tap("fryers.import")
        tap("import.commit")
        XCTAssertTrue(app.staticTexts["This fryer already has the card."].waitForExistence(timeout: 8))
    }

    func testSwitchFryerAndMilestoneShare() {
        launch(["-seed-two", "-done"])
        tap("home.fryers")
        let other = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "fryer.choose.")).firstMatch
        XCTAssertTrue(other.waitForExistence(timeout: 8))
        other.tap()
        tap("home.fryers")
        let kitchen = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "fryer.choose.")).firstMatch
        XCTAssertTrue(kitchen.waitForExistence(timeout: 8))
        kitchen.tap()
        tap("start.fries")
        tap("done.save")
        tap("saved.milestone")
        tap("share.image")
        exists("share.requested")
    }

    func testAccessibilitySizeKeepsStartAvailable() {
        launch(["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXL"])
        tap("start.fries")
        exists("timer.remaining")
    }

    func testExpiredKeepsOldSettingsAndShare() {
        launch(["-seed", "-expired", "-done"])
        tap("home.fryers")
        tap("saved.food.fries")
        tap("food.start")
        tap("done.save")
        tap("pay.close")
        tap("done.share")
        tap("share.image")
        exists("share.requested")
    }

    func testThirdDayReviewAppearsBackAtHomeOnce() {
        launch(["-review-days", "-done"])
        tap("start.fries")
        tap("done.confirm")
        exists("app.notice")
        XCTAssertTrue(app.staticTexts["Review request eligible"].exists)
        tap("notice.dismiss")
        tap("start.fries")
        tap("done.confirm")
        XCTAssertFalse(app.staticTexts["Review request eligible"].waitForExistence(timeout: 2))
    }

    func testStoreScreenshots() {
        for language in [("en", "en_US"), ("zh-Hans", "zh_CN"), ("zh-Hant", "zh_TW")] {
            let prefix = "store-" + language.0 + "-"
            launch(["-seed", "-shake"], language: language)
            XCTAssertTrue(app.buttons["food.fries"].waitForExistence(timeout: 10))
            shot(prefix + "01-chart")
            tap("food.fries")
            shot(prefix + "02-food")
            tap("food.start")
            exists("timer.remaining")
            XCTAssertTrue(app.buttons["timer.confirm"].waitForExistence(timeout: 8))
            shot(prefix + "03-flip")
            launch(["-seed", "-done"], language: language)
            tap("start.fries")
            tap("done.temperature.down")
            shot(prefix + "04-save")
            tap("done.back")
            tap("home.fryers")
            shot(prefix + "05-fryers")
        }
    }

    func testPaidScreenshot() {
        launch(["-paid-mode", "-paywall"], language: ("zh-Hans", "zh_CN"))
        XCTAssertTrue(app.buttons["pay.close"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["pay.trial"].exists)
        shot("paid-01-paywall")
    }

    private func launch(_ flags: [String] = [], reset: Bool = true,
                        language: (String, String) = ("en", "en_US"), environment: [String: String] = [:]) {
        if app.state != .notRunning { app.terminate() }
        app.launchArguments = ["-ui-testing", "-celsius", "-AppleLanguages", "(\(language.0))",
                               "-AppleLocale", language.1] + (reset ? ["-reset"] : []) + flags
        app.launchEnvironment = environment
        app.launch()
    }

    private func tap(_ id: String, file: StaticString = #filePath, line: UInt = #line) {
        let element = app.buttons[id].firstMatch
        XCTAssertTrue(element.waitForExistence(timeout: 8), id, file: file, line: line)
        for _ in 0..<4 where !element.isHittable { app.swipeUp() }
        XCTAssertTrue(element.isHittable, id, file: file, line: line)
        element.tap()
    }

    private func exists(_ id: String, file: StaticString = #filePath, line: UInt = #line) {
        let element = app.descendants(matching: .any).matching(identifier: id).firstMatch
        XCTAssertTrue(element.waitForExistence(timeout: 8), id, file: file, line: line)
    }

    private func shot(_ name: String) {
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        let environment = ProcessInfo.processInfo.environment
        if let path = environment["SHOTS_DIR"] ?? environment["TEST_RUNNER_SHOTS_DIR"] {
            let folder = URL(fileURLWithPath: path, isDirectory: true)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try? screenshot.pngRepresentation.write(to: folder.appendingPathComponent(name + ".png"), options: .atomic)
        }
    }
}
