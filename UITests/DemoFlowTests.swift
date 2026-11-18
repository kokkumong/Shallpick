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
        app.buttons["사진"].firstMatch.tap()
        XCTAssertTrue(app.buttons["이 사진으로 질문 보내기"].waitForExistence(timeout: 10))
        capture(app, "03b-latest-photo-detail")
        app.buttons["뒤로"].tap()
        XCTAssertTrue(app.buttons["채팅"].waitForExistence(timeout: 10))
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
        let field = app.textFields["이 자리에 남길 댓글을 입력하세요"]
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

        // The long press above placed a tappable pin at the image center.
        // Start on unobstructed photo content, as a person would, not on that button.
        let swipeStart = photo.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.2))
        let swipeEnd = photo.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.8))
        swipeStart.press(forDuration: 0.05, thenDragTo: swipeEnd)
        let previous = app.buttons["이전 사진"]
        let nextPhoto = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: previous)
        XCTAssertEqual(XCTWaiter.wait(for: [nextPhoto], timeout: 5), .completed,
                       "Voting should move to the next unanswered photo. \(app.debugDescription)")
        previous.tap()
        let vote = app.descendants(matching: .any).matching(identifier: "내가 남긴 의견: 좋아").firstMatch
        XCTAssertTrue(vote.waitForExistence(timeout: 5))
        capture(app, "08-photo-vote")
        app.buttons["완료"].tap()
        review.tap()
        previous.tap()
        XCTAssertTrue(vote.waitForExistence(timeout: 5), "Vote should survive reopening the question")
        XCTAssertTrue(pin.exists)
        capture(app, "09-persisted-vote-and-comment")
    }
}
