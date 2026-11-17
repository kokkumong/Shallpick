import XCTest

@MainActor
final class DemoFlowTests: XCTestCase {
    private var app: XCUIApplication!

    private func startDemo() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(ko)", "-AppleLocale", "ko_KR"]
        app.launch()
        XCTAssertTrue(app.buttons["demo.start"].waitForExistence(timeout: 20))
        capture("01-login")
        app.buttons["demo.start"].tap()
        XCTAssertTrue(app.buttons["주말 나들이"].waitForExistence(timeout: 10))
    }

    func testPhotoQuestionPersistsUntilReset() {
        startDemo()
        capture("02-home")
        app.buttons["주말 나들이"].tap()
        XCTAssertTrue(app.buttons["채팅"].waitForExistence(timeout: 5))
        capture("03-folder")
        app.buttons["채팅"].tap()
        XCTAssertTrue(app.buttons["질문에 첨부할 사진 고르기"].waitForExistence(timeout: 5))
        app.buttons["질문에 첨부할 사진 고르기"].tap()
        XCTAssertTrue(app.buttons["사진"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["사진"].element(boundBy: 0).tap()
        app.buttons["사진"].element(boundBy: 1).tap()
        capture("04-select")
        app.buttons["다음"].tap()
        let field = app.descendants(matching: .any).matching(identifier: "chat.draft").firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["사진 2장을 함께 보내요"].exists)
        field.tap()
        field.typeText("Can we share these photos?")
        app.buttons["보내기"].tap()
        XCTAssertTrue(app.staticTexts["Can we share these photos?"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["다시 보내기"].exists)
        app.buttons["뒤로"].tap()
        app.buttons["채팅"].tap()
        XCTAssertTrue(app.staticTexts["Can we share these photos?"].waitForExistence(timeout: 5))
        capture("05-chat")
        app.buttons["뒤로"].tap()
        app.buttons["뒤로"].tap()
        app.buttons["demo.reset"].tap()
        XCTAssertTrue(app.buttons["주말 나들이"].waitForExistence(timeout: 5))
        app.buttons["주말 나들이"].tap()
        app.buttons["채팅"].tap()
        XCTAssertTrue(app.staticTexts["같이 보고 골라보자!"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Can we share these photos?"].exists)
    }

    func testSampleUploadNotificationAndExit() {
        startDemo()
        app.buttons["주말 나들이"].tap()
        app.buttons["사진 올리기"].tap()
        XCTAssertTrue(app.buttons["demo.addPhotos"].waitForExistence(timeout: 5))
        app.buttons["demo.addPhotos"].tap()
        XCTAssertTrue(app.buttons["채팅"].waitForExistence(timeout: 5))
        app.buttons["채팅"].tap()
        XCTAssertTrue(app.buttons["질문에 첨부할 사진 고르기"].waitForExistence(timeout: 5))
        app.buttons["질문에 첨부할 사진 고르기"].tap()
        XCTAssertTrue(app.buttons["사진"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(identifier: "사진").count, 11)
        app.buttons["닫기"].tap()
        app.buttons["뒤로"].tap()
        app.buttons["뒤로"].tap()
        app.buttons["알림"].tap()
        XCTAssertTrue(app.buttons["바로 응답하기"].waitForExistence(timeout: 5))
        capture("06-question-alert")
        app.buttons["바로 응답하기"].tap()
        XCTAssertTrue(app.staticTexts["[샘플 질문] 이 사진 같이 올려도 괜찮을까?"].waitForExistence(timeout: 5))
        app.buttons["뒤로"].tap()
        app.buttons["뒤로"].tap()
        app.buttons["demo.exit"].tap()
        XCTAssertTrue(app.buttons["demo.start"].waitForExistence(timeout: 5))
    }

    func testFeedbackLayoutAndPinchZoom() {
        startDemo()
        XCTAssertFalse(app.buttons["검색"].exists)
        XCTAssertFalse(app.buttons["Grid"].exists)
        XCTAssertFalse(app.buttons["List"].exists)
        XCTAssertTrue(app.buttons["home.settings"].exists)
        XCTAssertLessThan(app.buttons["home.notifications"].frame.maxY, app.frame.height / 3)
        capture("feedback-home")

        app.buttons["주말 나들이"].tap()
        let add = app.buttons["folder.addPhotos"]
        let chat = app.buttons["folder.chat"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["필터"].exists)
        XCTAssertFalse(app.buttons["질문에 첨부할 사진 고르기"].exists)
        XCTAssertLessThan(add.frame.midX, app.frame.midX)
        XCTAssertGreaterThan(chat.frame.midX, app.frame.midX)
        XCTAssertGreaterThan(add.frame.minY, app.frame.height * 0.7)
        XCTAssertGreaterThan(chat.frame.minY, app.frame.height * 0.7)
        capture("feedback-folder-4-columns")

        let grid = app.descendants(matching: .any).matching(identifier: "folder.photoGrid").firstMatch
        XCTAssertTrue(grid.waitForExistence(timeout: 5))
        grid.pinch(withScale: 2.2, velocity: 1)
        XCTAssertTrue(waitForValue("2열, 사진 8장", on: grid))
        capture("feedback-folder-2-columns")
        grid.pinch(withScale: 1.5, velocity: 1)
        XCTAssertTrue(waitForValue("2열, 사진 8장", on: grid))
        grid.pinch(withScale: 0.35, velocity: -1)
        XCTAssertTrue(waitForValue("5열, 사진 8장", on: grid))
        grid.pinch(withScale: 0.7, velocity: -1)
        XCTAssertTrue(waitForValue("5열, 사진 8장", on: grid))
        capture("feedback-folder-5-columns")
        chat.tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "chat.draft").firstMatch.waitForExistence(timeout: 5))
    }

    private func waitForValue(_ value: String, on element: XCUIElement) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: element)
        return XCTWaiter.wait(for: [expectation], timeout: 5) == .completed
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
