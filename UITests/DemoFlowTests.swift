import XCTest

@MainActor
final class DemoFlowTests: XCTestCase {
    private func capture(_ app: XCUIApplication, _ name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testLatestQuestionFlow() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        capture(app, "01-launch")
        let start = app.buttons["demo.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 20), app.debugDescription)
        start.tap()
        let folder = app.buttons["주말 나들이"]
        XCTAssertTrue(folder.waitForExistence(timeout: 15), app.debugDescription)
        capture(app, "02-latest-home")
        folder.tap()
        XCTAssertTrue(app.buttons["채팅"].waitForExistence(timeout: 10))
        capture(app, "03-latest-folder")
        app.buttons["채팅"].tap()
        let review = app.buttons["확인하러가기"]
        XCTAssertTrue(review.waitForExistence(timeout: 10), app.debugDescription)
        if !review.isHittable { app.swipeDown() }
        capture(app, "04-question-chat")
        review.tap()
        let photo = app.descendants(matching: .any).matching(identifier: "question.photo").firstMatch
        XCTAssertTrue(photo.waitForExistence(timeout: 10), app.debugDescription)
        capture(app, "05-photo-response")

        // Long press opens the existing, position-specific comment interaction.
        photo.press(forDuration: 0.7)
        let field = app.textViews.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5), app.debugDescription)
        field.tap()
        field.typeText("Please crop this part")
        app.buttons["댓글 남기기"].tap()
        let pin = app.buttons["내 댓글: Please crop this part"]
        XCTAssertTrue(pin.waitForExistence(timeout: 5), app.debugDescription)
        capture(app, "06-pinned-comment")
        app.buttons["완료"].tap()
        XCTAssertTrue(review.waitForExistence(timeout: 5))
        review.tap()
        XCTAssertTrue(pin.waitForExistence(timeout: 5), "Pinned comment should survive leaving and reopening the question")
        capture(app, "07-persisted-comment")
    }
}
