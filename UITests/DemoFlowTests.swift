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
        app.buttons["내 계정"].tap()
        capture(app, "02b-account")
        let requestSwitch = app.switches["settings.requests"]
        XCTAssertTrue(requestSwitch.waitForExistence(timeout: 5))
        let wasOn = requestSwitch.value as? String
        requestSwitch.tap()
        app.buttons["설정 닫기"].tap()
        app.buttons["내 계정"].tap()
        XCTAssertNotEqual(requestSwitch.value as? String, wasOn, "Notification preference should survive reopening settings")
        requestSwitch.tap()
        app.buttons["닉네임 수정"].tap()
        capture(app, "02c-profile-edit")
        app.buttons["닫기"].tap()
        app.buttons["설정 닫기"].tap()
        folder.tap()
        XCTAssertTrue(app.buttons["채팅"].waitForExistence(timeout: 10))
        let unread = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "읽지 않은 글 1개"), object: app.buttons["채팅"])
        XCTAssertEqual(XCTWaiter.wait(for: [unread], timeout: 5), .completed)
        capture(app, "03-latest-folder")
        let grid = app.scrollViews["folder.photoGrid"]
        XCTAssertTrue(grid.waitForExistence(timeout: 5), app.debugDescription)
        grid.pinch(withScale: 2.8, velocity: 1)
        XCTAssertEqual(grid.value as? String, "2열")
        capture(app, "03c-grid-two-columns")
        grid.pinch(withScale: 0.2, velocity: -1)
        XCTAssertEqual(grid.value as? String, "6열")
        capture(app, "03d-grid-six-columns")
        grid.pinch(withScale: 1.5, velocity: 1)
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
        app.buttons["완료"].tap()
        app.buttons["뒤로"].tap()
        XCTAssertEqual(app.buttons["채팅"].value as? String, "읽지 않은 글 없음")
        capture(app, "09b-unread-cleared")
    }

    func testAdditionalReviewScreens() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["demo.start"].waitForExistence(timeout: 20))
        app.buttons["demo.start"].tap()
        XCTAssertTrue(app.buttons["주말 나들이"].waitForExistence(timeout: 15))

        app.buttons["검색"].tap()
        capture(app, "10-home-search")
        let search = app.textFields["폴더 이름, 참여자 검색"]
        search.tap()
        search.typeText("No matching folder")
        capture(app, "11-home-no-results")
        app.buttons["검색 닫기"].tap()
        app.buttons["알림"].tap()
        capture(app, "12-notifications")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.3)).tap()
        app.buttons["폴더 추가"].tap()
        capture(app, "13-add-folder-menu")
        app.buttons["새 폴더 만들기"].tap()
        capture(app, "14-create-folder")
        app.buttons["닫기"].tap()
        app.buttons["폴더 추가"].tap()
        app.buttons["코드로 참여하기"].tap()
        capture(app, "15-join-code")
        app.buttons["닫기"].tap()
        app.buttons["폴더 추가"].tap()
        app.buttons["QR로 참여하기"].tap()
        capture(app, "16-join-qr")
        app.buttons["닫기"].tap()

        app.buttons["주말 나들이"].tap()
        XCTAssertTrue(app.buttons["채팅"].waitForExistence(timeout: 10))
        app.buttons["주말 나들이"].tap()
        capture(app, "17-folder-invite")
        app.buttons["닫기"].tap()
        app.buttons["필터"].tap()
        capture(app, "18-photo-filters")
        app.buttons["필터 닫기"].tap()
        app.buttons["사진 올리기"].tap()
        capture(app, "19-demo-photo-upload")
        app.buttons["닫기"].tap()
        app.buttons["사진"].firstMatch.press(forDuration: 0.7)
        capture(app, "20-photo-selection")
        let photos = app.buttons.matching(identifier: "사진")
        for index in 1..<min(photos.count, 8) { photos.element(boundBy: index).tap() }
        app.buttons["고른 사진으로 질문 보내기"].tap()
        XCTAssertTrue(app.staticTexts["질문입력"].waitForExistence(timeout: 10))
        capture(app, "21-compose-question")
        let preview = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "고른 사진 ")).firstMatch
        preview.tap()
        capture(app, "22-selected-photo-viewer")
        app.buttons["닫기"].tap()
        let suggest = app.buttons["추려보기"]
        if suggest.waitForExistence(timeout: 20) {
            suggest.tap()
            capture(app, "23-otter-suggestions")
            app.buttons["닫기"].tap()
        }
        app.buttons["닫기"].tap()
        app.buttons["선택 끝내기"].tap()
        app.buttons["채팅"].tap()
        XCTAssertTrue(app.buttons["확인하러가기"].waitForExistence(timeout: 10))
        app.buttons["질문에 첨부할 사진 고르기"].tap()
        capture(app, "24-chat-photo-picker")
        app.buttons["닫기"].tap()
        let result = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "하늘님이 확인했어요")).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 5), app.debugDescription)
        result.tap()
        XCTAssertTrue(app.staticTexts["1 / 3"].waitForExistence(timeout: 5))
        capture(app, "25-question-results")
        let comment = app.buttons["하늘님의 댓글: [샘플 의견] 여기는 조금 잘라주면 좋겠어"]
        if comment.exists { comment.tap() }
        capture(app, "26-result-comment")
        app.buttons["다음 사진"].tap()
        capture(app, "27-result-dislike")
        app.buttons["완료"].tap()
        app.buttons["확인하러가기"].tap()
        let photo = app.descendants(matching: .any).matching(identifier: "question.photo").firstMatch
        for _ in 0..<3 {
            XCTAssertTrue(photo.waitForExistence(timeout: 5))
            photo.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.2))
                .press(forDuration: 0.05, thenDragTo: photo.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.8)))
        }
        XCTAssertTrue(app.staticTexts["모든 사진에 의견을 남겼어요"].waitForExistence(timeout: 5))
        capture(app, "28-response-complete")
    }

    func testReducedMotionFlow() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-reviewReduceMotion"]
        app.launch()
        XCTAssertTrue(app.buttons["demo.start"].waitForExistence(timeout: 20))
        app.buttons["demo.start"].tap()
        XCTAssertTrue(app.buttons["주말 나들이"].waitForExistence(timeout: 15))
        app.buttons["주말 나들이"].tap()
        XCTAssertTrue(app.buttons["채팅"].waitForExistence(timeout: 10))
        app.buttons["사진"].firstMatch.tap()
        XCTAssertTrue(app.buttons["이 사진으로 질문 보내기"].waitForExistence(timeout: 10))
        capture(app, "29-reduced-motion-photo")
        app.buttons["뒤로"].tap()
        app.buttons["채팅"].tap()
        XCTAssertTrue(app.buttons["확인하러가기"].waitForExistence(timeout: 10))
        app.buttons["확인하러가기"].tap()
        let photo = app.descendants(matching: .any).matching(identifier: "question.photo").firstMatch
        XCTAssertTrue(photo.waitForExistence(timeout: 5))
        photo.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.2))
            .press(forDuration: 0.05, thenDragTo: photo.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.8)))
        let previous = app.buttons["이전 사진"]
        let moved = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: previous)
        XCTAssertEqual(XCTWaiter.wait(for: [moved], timeout: 5), .completed)
        previous.tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "내가 남긴 의견: 좋아").firstMatch.waitForExistence(timeout: 5))
        capture(app, "30-reduced-motion-vote")
    }
}
