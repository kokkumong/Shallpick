import XCTest

@MainActor
final class DemoFlowTests: XCTestCase {
    private func tap(_ element: XCUIElement) {
        element.tap()
        // XCTest's idle signal can precede SwiftUI's navigation/presentation completion.
        Thread.sleep(forTimeInterval: 0.7)
    }

    private func tap(_ point: XCUICoordinate) {
        point.tap()
        Thread.sleep(forTimeInterval: 0.7)
    }

    private func closeTopSheet(_ app: XCUIApplication) {
        let buttons = app.buttons.matching(identifier: "닫기").allElementsBoundByIndex
        guard let close = buttons.last(where: { $0.isHittable }) else {
            XCTFail("No visible close button. \(app.debugDescription)")
            return
        }
        tap(close)
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        // Allow native push/pop and sheet animations to finish before taking evidence.
        Thread.sleep(forTimeInterval: 2)
        // Dismiss the simulator keyboard's first-run tutorial, not application content.
        if app.buttons["Continue"].exists && app.buttons["Continue"].isHittable {
            tap(app.buttons["Continue"])
        }
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
        tap(start)
        let folder = app.buttons["주말 나들이"]
        XCTAssertTrue(folder.waitForExistence(timeout: 15), app.debugDescription)
        capture(app, "02-latest-home")
        tap(app.buttons["내 계정"])
        capture(app, "02b-account")
        let requestSwitch = app.switches["settings.requests"]
        XCTAssertTrue(requestSwitch.waitForExistence(timeout: 5))
        let wasOn = requestSwitch.value as? String
        tap(requestSwitch)
        tap(app.buttons["설정 닫기"])
        tap(app.buttons["내 계정"])
        XCTAssertNotEqual(requestSwitch.value as? String, wasOn, "Notification preference should survive reopening settings")
        tap(requestSwitch)
        tap(app.buttons["닉네임 수정"])
        capture(app, "02c-profile-edit")
        tap(app.buttons["닫기"])
        tap(app.buttons["설정 닫기"])
        tap(folder)
        XCTAssertTrue(app.buttons["채팅"].waitForExistence(timeout: 10))
        let unread = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "읽지 않은 글 1개"), object: app.buttons["채팅"])
        XCTAssertEqual(XCTWaiter.wait(for: [unread], timeout: 5), .completed)
        capture(app, "03-latest-folder")
        let grid = app.scrollViews["folder.photoGrid"]
        XCTAssertTrue(grid.waitForExistence(timeout: 5), app.debugDescription)
        grid.pinch(withScale: 2.8, velocity: 1)
        XCTAssertEqual(grid.value as? String, "2열")
        capture(app, "03c-grid-two-columns")
        // The scroll view's accessibility frame includes the header. Start the
        // contracting gesture inside a visible photo so both touches reach the grid.
        app.buttons["사진"].firstMatch.pinch(withScale: 0.2, velocity: -1)
        Thread.sleep(forTimeInterval: 0.5)
        XCTAssertEqual(grid.value as? String, "6열")
        capture(app, "03d-grid-six-columns")
        grid.pinch(withScale: 1.5, velocity: 1)
        tap(app.buttons["사진"].firstMatch)
        XCTAssertTrue(app.buttons["이 사진으로 질문 보내기"].waitForExistence(timeout: 10))
        capture(app, "03b-latest-photo-detail")
        tap(app.buttons["뒤로"])
        XCTAssertTrue(app.buttons["채팅"].waitForExistence(timeout: 10))
        tap(app.buttons["채팅"])
        let review = app.buttons["확인하러가기"]
        XCTAssertTrue(review.waitForExistence(timeout: 10), app.debugDescription)
        if !review.isHittable { app.swipeDown() }
        capture(app, "04-question-chat")
        tap(review)
        let photo = app.descendants(matching: .any).matching(identifier: "question.photo").firstMatch
        XCTAssertTrue(photo.waitForExistence(timeout: 10), app.debugDescription)
        // Automatic hint may still be animating; wait until it has ended.
        Thread.sleep(forTimeInterval: 4)
        capture(app, "05-photo-response")

        // Long press opens the existing, position-specific comment interaction.
        photo.press(forDuration: 0.7)
        let field = app.textFields["이 자리에 남길 댓글을 입력하세요"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), app.debugDescription)
        tap(field)
        field.typeText("Please crop this part")
        tap(app.buttons["댓글 남기기"])
        let pin = app.buttons["내 댓글: Please crop this part"]
        XCTAssertTrue(pin.waitForExistence(timeout: 5), app.debugDescription)
        capture(app, "06-pinned-comment")
        tap(app.buttons["완료"])
        XCTAssertTrue(review.waitForExistence(timeout: 5))
        tap(review)
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
        tap(previous)
        let vote = app.descendants(matching: .any).matching(identifier: "내가 남긴 의견: 좋아").firstMatch
        XCTAssertTrue(vote.waitForExistence(timeout: 5))
        capture(app, "08-photo-vote")
        tap(app.buttons["완료"])
        tap(review)
        tap(previous)
        XCTAssertTrue(vote.waitForExistence(timeout: 5), "Vote should survive reopening the question")
        XCTAssertTrue(pin.exists)
        capture(app, "09-persisted-vote-and-comment")
        tap(app.buttons["완료"])
        tap(app.buttons["뒤로"])
        XCTAssertEqual(app.buttons["채팅"].value as? String, "읽지 않은 글 없음")
        capture(app, "09b-unread-cleared")
    }

    func testAdditionalReviewScreens() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-reviewCapture"]
        app.launch()
        XCTAssertTrue(app.buttons["demo.start"].waitForExistence(timeout: 20))
        tap(app.buttons["demo.start"])
        XCTAssertTrue(app.buttons["주말 나들이"].waitForExistence(timeout: 15))

        tap(app.buttons["검색"])
        capture(app, "10-home-search")
        let search = app.textFields["폴더 이름, 참여자 검색"]
        tap(search)
        search.typeText("No matching folder")
        capture(app, "11-home-no-results")
        tap(app.buttons["검색 닫기"])
        tap(app.buttons["알림"])
        capture(app, "12-notifications")
        tap(app.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.3)))
        tap(app.buttons["폴더 추가"])
        capture(app, "13-add-folder-menu")
        tap(app.buttons["새 폴더 만들기"])
        capture(app, "14-create-folder")
        tap(app.buttons["닫기"])
        tap(app.buttons["폴더 추가"])
        tap(app.buttons["코드로 참여하기"])
        capture(app, "15-join-code")
        tap(app.buttons["닫기"])
        tap(app.buttons["폴더 추가"])
        tap(app.buttons["QR로 참여하기"])
        capture(app, "16-join-qr")
        tap(app.buttons["닫기"])

        tap(app.buttons["주말 나들이"])
        XCTAssertTrue(app.buttons["채팅"].waitForExistence(timeout: 10))
        tap(app.buttons["주말 나들이"])
        XCTAssertTrue(app.buttons["초대하기"].waitForExistence(timeout: 10))
        capture(app, "17-folder-invite")
        tap(app.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.2)))
        tap(app.buttons["필터"])
        XCTAssertTrue(app.buttons["필터 닫기"].waitForExistence(timeout: 5))
        capture(app, "18-photo-filters")
        tap(app.buttons["필터 닫기"])
        tap(app.buttons["사진 올리기"])
        XCTAssertTrue(app.buttons["사진"].firstMatch.waitForExistence(timeout: 10))
        let fullAccess = app.buttons["Allow Full Access"]
        if fullAccess.waitForExistence(timeout: 3) { tap(fullAccess) }
        capture(app, "19-photo-library-upload")
        tap(app.buttons["닫기"])
        app.buttons["사진"].firstMatch.press(forDuration: 0.7)
        XCTAssertTrue(app.buttons["고른 사진으로 질문 보내기"].waitForExistence(timeout: 5),
                      "Long press must select without opening photo detail. \(app.debugDescription)")
        capture(app, "20-photo-selection")
        let photos = app.buttons.matching(identifier: "사진")
        XCTAssertGreaterThanOrEqual(photos.count, 8, app.debugDescription)
        for photo in photos.allElementsBoundByIndex.dropFirst().prefix(7) { tap(photo) }
        tap(app.buttons["고른 사진으로 질문 보내기"])
        XCTAssertTrue(app.staticTexts["질문입력"].waitForExistence(timeout: 10))
        capture(app, "21-compose-question")
        let preview = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "고른 사진 ")).firstMatch
        tap(preview)
        capture(app, "22-selected-photo-viewer")
        // The existing viewer closes by tapping the margin above the image.
        tap(app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)))
        let suggest = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "비슷한 사진이")).firstMatch
        XCTAssertTrue(suggest.waitForExistence(timeout: 20), app.debugDescription)
        tap(suggest)
        capture(app, "23-otter-suggestions")
        closeTopSheet(app)
        closeTopSheet(app)
        tap(app.buttons["선택 끝내기"])
        tap(app.buttons["채팅"])
        XCTAssertTrue(app.buttons["확인하러가기"].waitForExistence(timeout: 10))
        tap(app.buttons["질문에 첨부할 사진 고르기"])
        capture(app, "24-chat-photo-picker")
        tap(app.buttons["닫기"])
        let result = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "하늘님이 확인했어요")).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 5), app.debugDescription)
        tap(result)
        XCTAssertTrue(app.staticTexts["1 / 3"].waitForExistence(timeout: 5))
        capture(app, "25-question-results")
        let comment = app.buttons["하늘님의 댓글: [샘플 의견] 여기는 조금 잘라주면 좋겠어"]
        if comment.exists { tap(comment) }
        capture(app, "26-result-comment")
        tap(app.buttons["다음 사진"])
        capture(app, "27-result-dislike")
        app.swipeUp()
        capture(app, "27b-result-voters-and-comments")
        tap(app.buttons["완료"])
        tap(app.buttons["확인하러가기"])
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
        // Use the actual system preference: accessibilityReduceMotion is read-only.
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        settings.launch()
        let accessibility = settings.staticTexts["Accessibility"]
        for _ in 0..<5 where !accessibility.isHittable { settings.swipeUp() }
        XCTAssertTrue(accessibility.waitForExistence(timeout: 10))
        tap(accessibility)
        tap(settings.staticTexts["Motion"])
        let reduceMotion = settings.switches["REDUCE_MOTION"]
        XCTAssertTrue(reduceMotion.waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 2)
        for _ in 0..<3 where reduceMotion.value as? String != "1" {
            tap(reduceMotion)
            Thread.sleep(forTimeInterval: 1)
        }
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "1"), object: reduceMotion)
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 5), .completed)
        capture(settings, "29a-system-reduce-motion-enabled")
        defer {
            settings.activate()
            if reduceMotion.exists && reduceMotion.value as? String == "1" {
                tap(reduceMotion.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)))
            }
        }
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["demo.start"].waitForExistence(timeout: 20))
        tap(app.buttons["demo.start"])
        XCTAssertTrue(app.buttons["주말 나들이"].waitForExistence(timeout: 15))
        tap(app.buttons["주말 나들이"])
        XCTAssertTrue(app.buttons["채팅"].waitForExistence(timeout: 10))
        tap(app.buttons["사진"].firstMatch)
        XCTAssertTrue(app.buttons["이 사진으로 질문 보내기"].waitForExistence(timeout: 10))
        capture(app, "29-reduced-motion-photo")
        tap(app.buttons["뒤로"])
        tap(app.buttons["채팅"])
        XCTAssertTrue(app.buttons["확인하러가기"].waitForExistence(timeout: 10))
        tap(app.buttons["확인하러가기"])
        let photo = app.descendants(matching: .any).matching(identifier: "question.photo").firstMatch
        XCTAssertTrue(photo.waitForExistence(timeout: 5))
        photo.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.2))
            .press(forDuration: 0.05, thenDragTo: photo.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.8)))
        let previous = app.buttons["이전 사진"]
        let moved = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: previous)
        XCTAssertEqual(XCTWaiter.wait(for: [moved], timeout: 5), .completed)
        tap(previous)
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "내가 남긴 의견: 좋아").firstMatch.waitForExistence(timeout: 5))
        capture(app, "30-reduced-motion-vote")
    }

    func testQuestionAlertAndEmptyFolder() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-demoQuestionAlert"]
        app.launch()
        XCTAssertTrue(app.buttons["demo.start"].waitForExistence(timeout: 20))
        tap(app.buttons["demo.start"])
        XCTAssertTrue(app.buttons["바로 응답하기"].waitForExistence(timeout: 10))
        capture(app, "31-incoming-question-alert")
        tap(app.buttons["나중에!"])
        tap(app.buttons["폴더 추가"])
        tap(app.buttons["새 폴더 만들기"])
        app.textFields.firstMatch.typeText("Review folder")
        tap(app.buttons["확인"])
        XCTAssertTrue(app.buttons["초대하기"].waitForExistence(timeout: 10))
        capture(app, "32a-new-folder-invite")
        // The create-folder invite uses the native sheet dismiss gesture.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.69))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.97)))
        Thread.sleep(forTimeInterval: 0.7)
        let folder = app.buttons["Review folder"]
        XCTAssertTrue(folder.waitForExistence(timeout: 10))
        tap(folder)
        XCTAssertTrue(app.buttons["채팅"].waitForExistence(timeout: 10))
        capture(app, "32-empty-folder")
    }

    func testMainUpdates() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-reviewCapture"]
        app.launch()
        XCTAssertTrue(app.buttons["demo.start"].waitForExistence(timeout: 20))
        tap(app.buttons["demo.start"])
        let folder = app.buttons["주말 나들이"]
        XCTAssertTrue(folder.waitForExistence(timeout: 15))
        folder.press(forDuration: 1.2)
        XCTAssertTrue(app.buttons["폴더 나가기"].waitForExistence(timeout: 5), app.debugDescription)
        capture(app, "33-folder-context-menu")
        tap(app.buttons["폴더 나가기"])
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
        capture(app, "34-leave-folder-confirmation")
        tap(app.buttons["취소"])
        tap(app.buttons["내 계정"])
        XCTAssertTrue(app.buttons["settings.avatar"].waitForExistence(timeout: 5))
        tap(app.buttons["settings.avatar"])
        XCTAssertTrue(app.buttons["사진 보관함"].waitForExistence(timeout: 5))
        capture(app, "35-avatar-source-menu")
        tap(app.buttons["사진 보관함"])
        capture(app, "36-avatar-photo-library")
        // Do not upload a profile or leave a server folder. This test checks native UI only.
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["demo.start"].waitForExistence(timeout: 20))
        tap(app.buttons["demo.start"])
        tap(app.buttons["주말 나들이"])
        let photos = app.buttons.matching(identifier: "사진")
        XCTAssertTrue(photos.firstMatch.waitForExistence(timeout: 10))
        photos.element(boundBy: 0).press(forDuration: 0.5,
            thenDragTo: photos.element(boundBy: 2))
        XCTAssertTrue(app.buttons["고른 사진으로 질문 보내기"].waitForExistence(timeout: 5), app.debugDescription)
        capture(app, "37-drag-photo-selection")
    }

    func testCommentAndGuide() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-reviewCapture", "-freshGuide", "-failFirstPhotoComment"]
        app.launch()
        XCTAssertTrue(app.buttons["demo.start"].waitForExistence(timeout: 20))
        tap(app.buttons["demo.start"])
        tap(app.buttons["주말 나들이"])
        tap(app.buttons["사진"].firstMatch)
        let otter = app.buttons["photoDetail.ask"]
        XCTAssertTrue(otter.waitForExistence(timeout: 10))
        XCTAssertGreaterThan(otter.frame.midX, app.frame.width / 2)
        XCTAssertGreaterThan(otter.frame.midY, app.frame.height * 0.65)
        capture(app, "38-detail-otter-bottom")
        let field = app.descendants(matching: .any).matching(identifier: "photoDetail.commentInput").firstMatch
        tap(field)
        field.typeText("This is my favorite photo")
        capture(app, "39-detail-comment-keyboard")
        tap(app.buttons["photoDetail.sendComment"])
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
        tap(app.alerts.buttons["확인"])
        XCTAssertEqual(field.value as? String, "This is my favorite photo", "Failed comment must retain its draft")
        tap(app.buttons["photoDetail.sendComment"])
        XCTAssertTrue(app.staticTexts["This is my favorite photo"].waitForExistence(timeout: 5))
        tap(app.buttons["뒤로"])
        tap(app.buttons["채팅"])
        let card = app.buttons["사진 댓글: This is my favorite photo"]
        XCTAssertTrue(card.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(app.buttons.matching(identifier: "사진 댓글: This is my favorite photo").count, 1)
        capture(app, "40-chat-photo-comment")
        tap(card)
        XCTAssertTrue(otter.waitForExistence(timeout: 5))
        let body = app.staticTexts["This is my favorite photo"]
        XCTAssertTrue(body.waitForExistence(timeout: 5))
        capture(app, "41-chat-to-photo-comment")
        body.press(forDuration: 1.0)
        XCTAssertTrue(app.buttons["삭제"].waitForExistence(timeout: 5))
        tap(app.buttons["삭제"])
        tap(app.buttons["뒤로"])
        let removed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: card)
        XCTAssertEqual(XCTWaiter.wait(for: [removed], timeout: 10), .completed)
        capture(app, "42-chat-deleted-comment")

        let review = app.buttons["확인하러가기"]
        if !review.isHittable { app.swipeDown() }
        tap(review)
        let skip = app.buttons["question.swipeGuide.skip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 10), app.debugDescription)
        let firstGuide = XCTAttachment(screenshot: app.screenshot())
        firstGuide.name = "43-first-swipe-guide"; firstGuide.lifetime = .keepAlways; add(firstGuide)
        tap(skip)
        let like = app.descendants(matching: .any).matching(identifier: "내가 남긴 의견: 좋아").firstMatch
        let dislike = app.descendants(matching: .any).matching(identifier: "내가 남긴 의견: 싫어").firstMatch
        XCTAssertFalse(like.exists); XCTAssertFalse(dislike.exists)
        tap(app.buttons["완료"])
        tap(review)
        Thread.sleep(forTimeInterval: 1)
        XCTAssertFalse(skip.exists, "Completed hint must not replay automatically")
        tap(app.buttons["question.showSwipeGuide"])
        XCTAssertTrue(skip.waitForExistence(timeout: 3))
        let finished = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: skip)
        XCTAssertEqual(XCTWaiter.wait(for: [finished], timeout: 6), .completed)
        XCTAssertFalse(like.exists); XCTAssertFalse(dislike.exists)
        capture(app, "44-response-after-demo-no-vote")
    }

}
