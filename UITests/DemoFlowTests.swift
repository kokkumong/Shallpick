import XCTest

@MainActor
final class DemoFlowTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
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
        capture("02-home")
        app.buttons["주말 나들이"].tap()
        XCTAssertTrue(app.buttons["질문에 첨부할 사진 고르기"].waitForExistence(timeout: 5))
        capture("03-folder")
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
        app.buttons["주말 나들이"].tap()
        app.buttons["사진 올리기"].tap()
        XCTAssertTrue(app.buttons["demo.addPhotos"].waitForExistence(timeout: 5))
        app.buttons["demo.addPhotos"].tap()
        XCTAssertTrue(app.buttons["질문에 첨부할 사진 고르기"].waitForExistence(timeout: 5))
        app.buttons["질문에 첨부할 사진 고르기"].tap()
        XCTAssertTrue(app.buttons["사진"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(identifier: "사진").count, 11)
        app.buttons["닫기"].tap()
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

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
