import XCTest

@MainActor
final class DemoFlowTests: XCTestCase {
    private func tap(_ element: XCUIElement) { element.tap(); Thread.sleep(forTimeInterval: 0.7) }
    private func capture(_ app: XCUIApplication, _ name: String) {
        Thread.sleep(forTimeInterval: 1)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
    func testSection2() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-section2FailureChecks"]
        app.launch()
        XCTAssertTrue(app.buttons["demo.start"].waitForExistence(timeout: 20))
        tap(app.buttons["demo.start"])
        XCTAssertTrue(app.buttons["주말 나들이"].waitForExistence(timeout: 15))
        tap(app.buttons["주말 나들이"])
        XCTAssertTrue(app.buttons["folder.select"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["folder.addPhoto"].exists)
        capture(app, "01-folder-after")
        tap(app.buttons["folder.addPhoto"])
        XCTAssertTrue(app.buttons["닫기"].waitForExistence(timeout: 5))
        tap(app.buttons["닫기"])
        tap(app.buttons["folder.select"])
        XCTAssertFalse(app.buttons["folder.askSelected"].isEnabled)
        tap(app.buttons["사진"].firstMatch)
        XCTAssertTrue(app.buttons["folder.askSelected"].isEnabled)
        capture(app, "02-selection-after")
        tap(app.buttons["folder.askSelected"])
        XCTAssertTrue(app.staticTexts["질문입력"].waitForExistence(timeout: 10))
        tap(app.buttons.matching(identifier: "닫기").allElementsBoundByIndex.last { $0.isHittable }!)
        tap(app.buttons["선택 끝내기"])
        app.buttons["사진"].firstMatch.press(forDuration: 0.6)
        XCTAssertTrue(app.buttons["folder.askSelected"].waitForExistence(timeout: 5))
        tap(app.buttons["선택 끝내기"])
        tap(app.buttons["사진"].firstMatch)
        XCTAssertTrue(app.buttons["이 사진으로 질문 보내기"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.textFields["이 자리에 남길 댓글을 입력하세요"].exists)
        capture(app, "03-photo-after")
        let image = app.descendants(matching: .any).matching(identifier: "photo.detailImage").firstMatch
        XCTAssertTrue(image.waitForExistence(timeout: 5))
        image.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.6)).press(forDuration: 0.7)
        let field = app.textFields["이 자리에 남길 댓글을 입력하세요"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), app.debugDescription)
        tap(field)
        field.typeText("Please crop this part")
        capture(app, "04-comment-entry-after")
        tap(app.buttons["남기기"])
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
        tap(app.alerts.buttons["확인"])
        XCTAssertEqual(field.value as? String, "Please crop this part")
        tap(app.buttons["남기기"])
        let pin = app.buttons["나: Please crop this part"]
        XCTAssertTrue(pin.waitForExistence(timeout: 5), app.debugDescription)
        capture(app, "05-comment-nickname-after")
        tap(app.buttons["뒤로"])
        tap(app.buttons["사진"].firstMatch)
        XCTAssertTrue(pin.waitForExistence(timeout: 5), "Saved coordinate comment survives reopening")
        tap(pin)
        capture(app, "06-comment-reopened-after")
        tap(app.buttons["뒤로"])
        tap(app.buttons["채팅"])
        XCTAssertTrue(app.buttons["확인하러가기"].waitForExistence(timeout: 10))
        tap(app.buttons["확인하러가기"])
        let like = app.buttons["question.vote.like"]
        let dislike = app.buttons["question.vote.dislike"]
        XCTAssertTrue(like.waitForExistence(timeout: 10))
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: like)
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 10), .completed)
        capture(app, "07-vote-after")
        tap(like)
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5), "Injected vote failure must keep current photo")
        tap(app.alerts.buttons["확인"])
        XCTAssertFalse(app.buttons["이전 사진"].isEnabled)
        tap(like)
        XCTAssertTrue(app.buttons["이전 사진"].isEnabled)
        tap(dislike)
        tap(like)
        XCTAssertFalse(app.staticTexts["모든 사진에 의견을 남겼어요"].exists, "Last vote waits for explicit review completion")
        tap(app.buttons["이전 사진"])
        XCTAssertEqual(dislike.value as? String, "선택됨")
        tap(like)
        XCTAssertEqual(like.value as? String, "선택됨")
        capture(app, "08-vote-review-after")
        tap(app.buttons["완료"])
        XCTAssertTrue(app.staticTexts["모든 사진에 의견을 남겼어요"].waitForExistence(timeout: 5))
        capture(app, "09-vote-complete-after")
        tap(app.buttons["완료"])
        XCTAssertTrue(app.buttons["확인하러가기"].waitForExistence(timeout: 5))
    }
}

