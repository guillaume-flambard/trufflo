import XCTest

final class StarterUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testCreateDogAndRecordManualWalk() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()
        let addDog = app.buttons["dog.add"]
        XCTAssertTrue(addDog.waitForExistence(timeout: 5))
        addDog.tap()
        let name = app.textFields["dog.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Oslo")
        app.buttons["dog.save"].tap()
        let addWalk = app.buttons["walk.manual.add"]
        XCTAssertTrue(addWalk.waitForExistence(timeout: 5))
        addWalk.tap()
        let minutes = app.textFields["walk.minutes"]
        XCTAssertTrue(minutes.waitForExistence(timeout: 5))
        minutes.tap()
        minutes.typeText("10")
        app.buttons["walk.save"].tap()
        let journal = app.tabBars.buttons["Journal"]
        XCTAssertTrue(journal.waitForExistence(timeout: 5))
        journal.tap()
        let manualRow = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "walk.row.")
        ).firstMatch
        XCTAssertTrue(manualRow.waitForExistence(timeout: 5))
        XCTAssertTrue(manualRow.label.contains("Saisie manuelle"))
    }

    @MainActor
    func testEmptyJournalStateAndGlobalErasure() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()
        let journal = app.tabBars.buttons["Journal"]
        XCTAssertTrue(journal.waitForExistence(timeout: 5))
        journal.tap()
        XCTAssertTrue(app.staticTexts["Aucune balade enregistrée"].waitForExistence(timeout: 5))

        app.tabBars.buttons["Aujourd'hui"].tap()
        app.buttons["dog.add"].tap()
        let name = app.textFields["dog.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Nala")
        app.buttons["dog.save"].tap()

        app.navigationBars.buttons["Réglages"].tap()
        app.buttons["Effacer toutes les données"].tap()
        let confirm = app.buttons["Tout effacer"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()

        // Erasure returns the first tab to its first-run state.
        XCTAssertTrue(app.buttons["dog.add"].waitForExistence(timeout: 5))
    }
}