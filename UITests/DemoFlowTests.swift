import XCTest

@MainActor
final class DemoFlowTests: XCTestCase {
    private func tap(_ element: XCUIElement) {
        element.tap()
        Thread.sleep(forTimeInterval: 0.7)
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testSection2() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["demo.start"].waitForExistence(timeout: 20))
        tap(app.buttons["demo.start"])
        XCTAssertTrue(app.buttons["주말 나들이"].waitForExistence(timeout: 15))
        tap(app.buttons["주말 나들이"])
        let request = app.buttons["folder.askSelected"]
        XCTAssertTrue(request.waitForExistence(timeout: 10))
        XCTAssertEqual(request.label, "요청하기")
        XCTAssertTrue(request.isEnabled)
        XCTAssertTrue(app.buttons["folder.addPhoto"].exists)
        capture(app, "10-gallery-request-after")

        tap(request)
        XCTAssertTrue(app.buttons["선택 끝내기"].exists)
        XCTAssertFalse(request.isEnabled, "An empty selection cannot open the request composer")
        tap(app.buttons["사진"].firstMatch)
        XCTAssertTrue(request.isEnabled)
        capture(app, "11-gallery-selection-after")
        tap(request)
        XCTAssertTrue(app.staticTexts["질문입력"].waitForExistence(timeout: 10))
        capture(app, "12-gallery-compose-after")
        tap(app.buttons.matching(identifier: "닫기").allElementsBoundByIndex.last { $0.isHittable }!)

        // Cancelling composition retains the selection; toggling it off blocks an empty request.
        XCTAssertTrue(request.isEnabled)
        tap(app.buttons["사진"].firstMatch)
        XCTAssertFalse(request.isEnabled)
        tap(app.buttons["선택 끝내기"])
        XCTAssertTrue(request.isEnabled)
        tap(app.buttons["folder.select"])
        XCTAssertFalse(request.isEnabled)
    }
}
