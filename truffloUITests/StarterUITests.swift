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

    /// The third journey: correct a profile, then remove a single walk while the
    /// rest of the journal stays. Both flows end on a screen that proves the change.
    @MainActor
    func testEditDogProfileAndDeleteSingleWalk() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()

        XCTAssertTrue(app.buttons["dog.add"].waitForExistence(timeout: 5))
        app.buttons["dog.add"].tap()
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

        app.tabBars.buttons["Journal"].tap()
        let walkRow = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "walk.row.")
        ).firstMatch
        XCTAssertTrue(walkRow.waitForExistence(timeout: 5))
        walkRow.tap()

        // AC-003: the detail names the origin and never writes an unmeasured
        // distance as "0". Both strings are matched as substrings because a
        // LabeledContent row is exposed as one label, not two static texts.
        let origin = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Saisie manuelle")
        ).firstMatch
        XCTAssertTrue(
            origin.waitForExistence(timeout: 5),
            "le détail n'affiche pas l'origine « Saisie manuelle »"
        )
        let unmeasured = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Non mesurée")
        ).firstMatch
        XCTAssertTrue(
            unmeasured.waitForExistence(timeout: 5),
            "la distance non mesurée doit s'écrire « Non mesurée », jamais « 0 »"
        )

        let deleteWalk = app.buttons["walk.delete"]
        XCTAssertTrue(deleteWalk.waitForExistence(timeout: 5))
        XCTAssertTrue(
            deleteWalk.label.hasPrefix("Supprimer la balade"),
            "AC-007 : le bouton de suppression doit nommer la balade, pas seulement « Supprimer »"
        )
        deleteWalk.tap()
        let confirmWalk = app.buttons["Supprimer définitivement"]
        XCTAssertTrue(confirmWalk.waitForExistence(timeout: 5))
        confirmWalk.tap()
        XCTAssertTrue(app.staticTexts["Aucune balade enregistrée"].waitForExistence(timeout: 5))

        app.tabBars.buttons["Mes chiens"].tap()
        let dogRow = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "dog.row.")
        ).firstMatch
        XCTAssertTrue(dogRow.waitForExistence(timeout: 5))
        dogRow.tap()

        let edit = app.buttons["dog.edit"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        edit.tap()
        let editName = app.textFields["dog.name"]
        XCTAssertTrue(editName.waitForExistence(timeout: 5))
        editName.tap()
        editName.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 10))
        editName.typeText("Oslothe")
        app.buttons["dog.save"].tap()
        XCTAssertTrue(app.navigationBars["Oslothe"].waitForExistence(timeout: 5))
    }
}