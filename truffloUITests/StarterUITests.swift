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
        let note = app.textFields["walk.note"]
        XCTAssertTrue(note.waitForExistence(timeout: 5), "le champ de note doit être identifié")
        note.tap()
        note.typeText("Balade tranquille au parc.")
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
        let manualQuality = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Déclarée à la main")
        ).firstMatch
        XCTAssertTrue(
            manualQuality.waitForExistence(timeout: 5),
            "AC-014 : la fiche doit afficher la qualité « Déclarée à la main » stockée"
        )
        let unmeasured = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Non mesurée")
        ).firstMatch
        XCTAssertTrue(
            unmeasured.waitForExistence(timeout: 5),
            "la distance non mesurée doit s'écrire « Non mesurée », jamais « 0 »"
        )
        XCTAssertTrue(
            app.staticTexts["Balade tranquille au parc."].waitForExistence(timeout: 5),
            "AC-003 : la note saisie doit être lisible dans le détail"
        )
        XCTAssertTrue(
            app.staticTexts["Oslo"].waitForExistence(timeout: 5),
            "AC-003 : le détail doit lister le chien présent"
        )
        let ended = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Fin de la balade")
        ).firstMatch
        XCTAssertTrue(
            ended.waitForExistence(timeout: 5),
            "AC-003 : le détail doit afficher la date de fin"
        )
        let duration = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "10 min")
        ).firstMatch
        XCTAssertTrue(
            duration.waitForExistence(timeout: 5),
            "AC-003 : la durée saisie doit être lisible dans le détail"
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

    @MainActor
    func testStartPauseResumeFinishGpsWalk() throws {
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

        let start = app.buttons["Démarrer une balade"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        start.tap()

        XCTAssertTrue(
            app.buttons["walk.minimize"].waitForExistence(timeout: 10),
            "l'écran de balade en direct doit s'ouvrir"
        )
        XCTAssertTrue(
            app.staticTexts["walk.timer"].waitForExistence(timeout: 5),
            "le chronomètre doit être lisible"
        )
        XCTAssertTrue(
            app.staticTexts["walk.distance"].waitForExistence(timeout: 5),
            "la distance doit être exposée à l'accessibilité"
        )
        let signalLive = Self.signal(app, reads: "Actif").waitForExistence(timeout: 20)
        let signalSearching = Self.signal(app, reads: "Recherche").exists
        XCTAssertTrue(
            signalLive || signalSearching,
            "le signal doit passer en Actif avec une position simulée, sinon afficher Recherche"
        )
        // AC-018: one primary while recording. Finishing is a paused-state choice.
        XCTAssertFalse(
            app.buttons["walk.finish"].exists,
            "Terminer ne doit pas être proposé pendant l'enregistrement"
        )
        XCTAssertFalse(app.buttons["walk.note"].exists, "aucune note pendant la balade")
        XCTAssertFalse(app.buttons["walk.more"].exists, "aucun menu pendant la balade")

        app.buttons["Mettre en pause"].tap()
        XCTAssertTrue(
            app.buttons["Reprendre la balade"].waitForExistence(timeout: 5),
            "la pause doit proposer la reprise"
        )
        XCTAssertTrue(
            app.buttons["Terminer la balade"].exists,
            "AC-019 : la pause doit proposer la fin, en second"
        )

        app.buttons["Reprendre la balade"].tap()
        XCTAssertTrue(
            app.buttons["Mettre en pause"].waitForExistence(timeout: 5),
            "la reprise doit revenir à l'enregistrement"
        )

        app.buttons["Mettre en pause"].tap()
        XCTAssertTrue(app.buttons["walk.finish"].waitForExistence(timeout: 5))
        app.buttons["walk.finish"].tap()
        let finishSheet = app.sheets["Terminer et enregistrer la balade ?"]
        let confirmationShown = finishSheet.waitForExistence(timeout: 5)
        if !confirmationShown {
            let frame = XCUIScreen.main.screenshot().pngRepresentation
            try? frame.write(to: URL(fileURLWithPath: "/tmp/trufflo-finish.png"))
            try? app.debugDescription.write(
                toFile: "/tmp/trufflo-finish-hierarchy.txt",
                atomically: true,
                encoding: .utf8
            )
        }
        XCTAssertTrue(confirmationShown, "la confirmation de fin de balade doit s'afficher")
        let continueButton = app.buttons["Continuer"]
        let continueShown = continueButton.waitForExistence(timeout: 5)
        if !continueShown {
            try? app.debugDescription.write(
                toFile: "/tmp/trufflo-continuer-hierarchy.txt",
                atomically: true,
                encoding: .utf8
            )
        }
        XCTAssertTrue(continueShown, "le bouton Continuer doit être exposé à l'accessibilité")

        let confirmFinish = finishSheet.buttons["Terminer la balade"]
        XCTAssertTrue(confirmFinish.waitForExistence(timeout: 5))
        confirmFinish.tap()

        // AC-021: the summary takes the screen over, and the note is written there.
        let done = app.buttons["walk.summary.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 10), "le bilan doit s'ouvrir après la fin")
        let summaryNote = app.textFields["walk.summary.note"]
        XCTAssertTrue(summaryNote.waitForExistence(timeout: 5), "le bilan doit proposer la note")
        summaryNote.tap()
        summaryNote.typeText("Balade au parc.")
        done.tap()

        let journal = app.tabBars.buttons["Journal"]
        XCTAssertTrue(journal.waitForExistence(timeout: 10))
        journal.tap()
        let row = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "walk.row.")
        ).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "la balade terminée doit apparaître au journal")
        XCTAssertTrue(
            row.label.contains("Suivi GPS"),
            "l'origine de la balade doit être « Suivi GPS »"
        )

        row.tap()
        let qualityRow = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Mesure")
        ).firstMatch
        XCTAssertTrue(
            qualityRow.waitForExistence(timeout: 5),
            "AC-013 : la fiche source doit afficher la qualité de mesure dans le détail"
        )
        // The detail is a lazy List: with the map and the measures above it, the
        // note sits under the fold and is not in the hierarchy until scrolled to.
        var scrolls = 0
        while !app.staticTexts["Balade au parc."].exists && scrolls < 4 {
            app.swipeUp()
            scrolls += 1
        }
        XCTAssertTrue(
            app.staticTexts["Balade au parc."].waitForExistence(timeout: 5),
            "AC-022 : la note saisie au bilan doit être lisible dans le détail"
        )
    }

    @MainActor
    func testColdRelaunchInterruptsTheWalkAndOffersThreeExits() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-hasCompletedOnboarding", "YES"]
        app.launch()

        app.navigationBars.buttons["Réglages"].tap()
        app.buttons["Effacer toutes les données"].tap()
        let wipe = app.buttons["Tout effacer"]
        XCTAssertTrue(wipe.waitForExistence(timeout: 5))
        wipe.tap()

        XCTAssertTrue(app.buttons["dog.add"].waitForExistence(timeout: 5))
        app.buttons["dog.add"].tap()
        let name = app.textFields["dog.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Oslo")
        app.buttons["dog.save"].tap()

        let start = app.buttons["Démarrer une balade"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        start.tap()
        XCTAssertTrue(
            app.buttons["walk.minimize"].waitForExistence(timeout: 10),
            "l'écran de balade en direct doit s'ouvrir"
        )
        XCTAssertTrue(app.staticTexts["walk.timer"].waitForExistence(timeout: 5))

        app.terminate()
        app.launch()

        XCTAssertTrue(
            app.staticTexts["Balade interrompue"].waitForExistence(timeout: 10),
            "AC-010 : après une fermeture forcée, la session doit apparaître interrompue"
        )
        let show = app.buttons["Revenir à la balade"]
        XCTAssertTrue(show.waitForExistence(timeout: 5))
        show.tap()

        XCTAssertTrue(
            app.buttons["walk.minimize"].waitForExistence(timeout: 10),
            "AC-010 : la session interrompue doit se rouvrir"
        )
        // The notice lives eight seconds by design: read it first, before the
        // other checks spend that time on a slow runner (CI run 37507936154).
        XCTAssertTrue(
            app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS %@", "Données conservées jusqu'au dernier point enregistré")
            ).firstMatch.waitForExistence(timeout: 5),
            "le message temporaire doit dire ce qui est conservé"
        )
        XCTAssertTrue(
            app.buttons["Reprendre à partir de maintenant"].waitForExistence(timeout: 5),
            "AC-010 : la reprise à partir de maintenant doit être proposée"
        )
        XCTAssertTrue(
            app.buttons["Terminer avec les données enregistrées"].exists,
            "AC-010 : la fin avec les données enregistrées doit être proposée"
        )
        // AC-020: correction left the live screen; manual entry lives on the home tab.
        XCTAssertFalse(app.buttons["Corriger"].exists, "aucun bouton Corriger pendant la balade")
        XCTAssertTrue(
            Self.signal(app, reads: "Interrompue").waitForExistence(timeout: 5),
            "l'état affiché doit nommer l'interruption"
        )

        app.buttons["walk.finish"].tap()
        let recoverSheet = app.sheets["Terminer avec les données enregistrées ?"]
        XCTAssertTrue(recoverSheet.waitForExistence(timeout: 5), "la fin doit être confirmée")
        recoverSheet.buttons["Terminer avec les données enregistrées"].tap()
        let done = app.buttons["walk.summary.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 10), "le bilan doit s'ouvrir après la fin")
        done.tap()

        let bannerGone = expectation(
            for: NSPredicate(format: "exists == false"),
            evaluatedWith: app.buttons["Revenir à la balade"],
            handler: nil
        )
        let outcome = XCTWaiter().wait(for: [bannerGone], timeout: 15)
        XCTAssertEqual(
            outcome, .completed,
            "AC-010 : la fin depuis l'interruption doit retirer la session de l'accueil"
        )

        app.tabBars.buttons["Journal"].tap()
        let row = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "walk.row.")
        ).firstMatch
        XCTAssertTrue(
            row.waitForExistence(timeout: 5),
            "AC-010 : la balade interrompue puis terminée doit figer au journal"
        )
        XCTAssertTrue(row.label.contains("Suivi GPS"))

        app.tabBars.buttons["Aujourd'hui"].tap()
        app.navigationBars.buttons["Réglages"].tap()
        app.buttons["Effacer toutes les données"].tap()
        let wipeAgain = app.buttons["Tout effacer"]
        XCTAssertTrue(wipeAgain.waitForExistence(timeout: 5))
        wipeAgain.tap()
        XCTAssertTrue(app.buttons["dog.add"].waitForExistence(timeout: 5))
    }

    /// The F02 screen-lock recipe: two minutes away from the app must not stop
    /// the walk. XCUITest exposes no lock command on this SDK, so the test
    /// presses Home to put the app in the background, the state a locked screen
    /// creates.
    ///
    /// The trace needs something to record, and only the host can move a
    /// simulated position. `tools/sim/gps-journeys.sh` starts a waypoint route
    /// with `simctl location start` before the run, and the simulator keeps
    /// emitting along it for the whole journey, so no in-test handshake is
    /// needed. Run it through that script, not through a bare TruffloFull run.
    @MainActor
    func testWalkKeepsCountingWhileTheAppIsInBackground() throws {
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

        let start = app.buttons["Démarrer une balade"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        start.tap()
        XCTAssertTrue(
            app.buttons["walk.minimize"].waitForExistence(timeout: 10),
            "l'écran de balade en direct doit s'ouvrir"
        )
        XCTAssertTrue(
            Self.signal(app, reads: "Actif").waitForExistence(timeout: 20),
            "la position simulée doit rendre le signal actif avant l'arrière-plan"
        )
        let timerEl = app.staticTexts["walk.timer"]
        XCTAssertTrue(timerEl.waitForExistence(timeout: 5), "le chronomètre doit être affiché")
        let timerBefore = timerEl.label
        let distance = app.staticTexts.matching(Self.distanceValuePredicate).firstMatch
        XCTAssertTrue(distance.waitForExistence(timeout: 5), "l'affichage de distance doit exister")
        let distanceBefore = distance.label
        let beforeMeters = Self.meters(from: distanceBefore) ?? 0

        XCUIDevice.shared.press(.home)

        XCTAssertTrue(
            app.wait(for: .runningBackground, timeout: 5),
            "la pression Home doit envoyer l'application en arrière-plan sans la suspendre"
        )

        let awayWindow = expectation(description: "deux minutes en arrière-plan")
        _ = XCTWaiter().wait(for: [awayWindow], timeout: 125)

        app.activate()
        XCTAssertTrue(
            app.buttons["walk.minimize"].waitForExistence(timeout: 15),
            "après le retour au premier plan, l'écran de balade doit être affiché"
        )
        let timerAfter = app.staticTexts["walk.timer"]
        XCTAssertTrue(timerAfter.waitForExistence(timeout: 10), "le chronomètre doit être relu")
        XCTAssertGreaterThanOrEqual(
            Self.seconds(from: timerAfter.label),
            Self.seconds(from: timerBefore) + 100,
            "la durée doit continuer de croître en arrière-plan (avant \(timerBefore), après \(timerAfter.label))"
        )
        XCTAssertTrue(
            Self.signal(app, reads: "Actif").waitForExistence(timeout: 20),
            "le signal GPS doit repasser à Actif au retour"
        )

        var advanced = false
        for _ in 0..<30 {
            if let now = Self.meters(from: distance.label), now >= beforeMeters + 40 {
                advanced = true
                break
            }
            let slice = expectation(description: "attente d'un point de tracé")
            _ = XCTWaiter().wait(for: [slice], timeout: 1)
        }
        XCTAssertTrue(
            advanced,
            "le tracé doit avancer pendant l'arrière-plan (avant \(distanceBefore), après \(distance.label))"
        )
    }

    /// The F02 revocation recipe: losing the location permission during a live
    /// walk must interrupt it with a message, keep the known duration frozen
    /// and invent no distance.
    ///
    /// Only the host can revoke a permission, so this journey keeps a
    /// handshake: the test drops the marker, `tools/sim/gps-journeys.sh`
    /// watches for it and revokes. It also runs in its own xcodebuild
    /// invocation, because the revocation disables location for the whole
    /// simulator and would silently starve the next journey.
    @MainActor
    func testRevokingLocationMidWalkInterruptsWithoutInventingDistance() throws {
        try? FileManager.default.removeItem(atPath: "/tmp/trufflo-revoke-go")
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

        let start = app.buttons["Démarrer une balade"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        start.tap()
        XCTAssertTrue(
            app.buttons["walk.minimize"].waitForExistence(timeout: 10),
            "l'écran de balade en direct doit s'ouvrir"
        )
        XCTAssertTrue(
            Self.signal(app, reads: "Actif").waitForExistence(timeout: 20),
            "le signal doit être actif avant la révocation"
        )
        let timerEl = app.staticTexts["walk.timer"]
        XCTAssertTrue(timerEl.waitForExistence(timeout: 5))
        let timerAtStart = timerEl.label
        let distance = app.staticTexts.matching(Self.distanceValuePredicate).firstMatch
        XCTAssertTrue(distance.waitForExistence(timeout: 5), "l'affichage de distance doit exister")

        try? "go".write(toFile: "/tmp/trufflo-revoke-go", atomically: true, encoding: .utf8)

        // AC-020: the cause and what is kept arrive as one temporary notice, not
        // as a modal the person has to dismiss while holding a leash.
        let interruption = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@",
                        "La localisation n'est plus autorisée",
                        "Données conservées jusqu'au dernier point enregistré")
        ).firstMatch
        XCTAssertTrue(
            interruption.waitForExistence(timeout: 45),
            "la révocation en cours de balade doit afficher le message d'interruption"
        )
        XCTAssertFalse(app.alerts.firstMatch.exists, "aucune alerte modale pour une interruption")

        XCTAssertTrue(
            Self.signal(app, reads: "Interrompue").waitForExistence(timeout: 5),
            "le signal doit nommer l'interruption, jamais « Arrêté »"
        )
        XCTAssertFalse(Self.signal(app, reads: "Arrêté").exists)
        XCTAssertTrue(app.buttons["Reprendre à partir de maintenant"].exists, "la reprise doit être proposée")
        XCTAssertTrue(
            app.buttons["Terminer avec les données enregistrées"].exists,
            "la fin avec les données enregistrées doit être proposée"
        )
        XCTAssertFalse(app.buttons["Corriger"].exists, "aucun bouton Corriger pendant la balade")
        XCTAssertTrue(
            app.buttons["walk.interrupted.settings"].exists,
            "un refus de permission doit proposer les réglages, seule issue qui répare"
        )

        let settle = expectation(description: "état interrompu stabilisé")
        _ = XCTWaiter().wait(for: [settle], timeout: 3)
        let frozenTimer = timerEl.label
        let frozenDistance = distance.label
        let hold = expectation(description: "aucune écriture après l'interruption")
        _ = XCTWaiter().wait(for: [hold], timeout: 6)

        XCTAssertEqual(
            timerEl.label, frozenTimer,
            "la durée figée ne doit plus bouger après l'interruption (\(frozenTimer))"
        )
        XCTAssertEqual(
            distance.label, frozenDistance,
            "aucune distance ne doit être inventée après l'interruption (\(frozenDistance) -> \(distance.label))"
        )
        XCTAssertGreaterThanOrEqual(
            Self.seconds(from: frozenTimer),
            Self.seconds(from: timerAtStart),
            "la durée connue avant la révocation doit être conservée, pas remise à zéro"
        )
    }

    /// AC-006 / finding F1: a start refused by a withdrawn permission must offer
    /// the two exits the spec names, not a dead "OK". The permission is revoked
    /// by `tools/sim/gps-journeys.sh` before the app launches, so this journey
    /// needs no mid-test handshake, and the refusal is proven to leave no walk
    /// behind rather than only to look refused.
    @MainActor
    func testDeniedPermissionOffersSettingsAndManualEntry() throws {
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

        let start = app.buttons["Démarrer une balade"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        start.tap()

        // A refused start is explained on Today, in a sheet: the live screen must
        // not open behind it, since no walk has begun.
        let settings = app.buttons["walk.blocked.settings"]
        XCTAssertTrue(
            settings.waitForExistence(timeout: 10),
            "un refus doit proposer d'ouvrir les réglages"
        )
        XCTAssertFalse(app.buttons["walk.minimize"].exists,
                       "l'écran de balade ne doit pas s'ouvrir derrière un refus")
        let manual = app.buttons["walk.blocked.manual"]
        XCTAssertTrue(
            manual.exists,
            "un refus doit proposer la saisie manuelle"
        )
        XCTAssertTrue(
            app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS %@", "La localisation est refusée")
            ).firstMatch.exists,
            "le motif du refus doit être nommé"
        )
        XCTAssertTrue(app.buttons["walk.blocked.dismiss"].exists, "le refus doit rester annulable")

        // Manual entry has to be genuinely reachable, not merely present.
        manual.tap()
        XCTAssertTrue(
            app.navigationBars["Balade passée"].waitForExistence(timeout: 10),
            "la saisie manuelle doit s'ouvrir depuis le refus"
        )
        XCTAssertTrue(app.textFields["walk.minutes"].exists)
        app.navigationBars["Balade passée"].buttons["Annuler"].tap()

        // Back on Today, with nothing started.
        XCTAssertTrue(
            app.buttons["Démarrer une balade"].waitForExistence(timeout: 10),
            "l'accueil doit rester affiché après le refus"
        )

        // No phantom session: a refused start must not leave a walk in the log.
        app.tabBars.buttons["Journal"].tap()
        XCTAssertTrue(
            app.staticTexts["Aucune balade enregistrée"].waitForExistence(timeout: 5),
            "un refus ne doit créer aucune balade"
        )
    }

    /// The signal indicator is one accessibility element whose label is
    /// "Signal GPS : <mot>". Matching on identifier and full label keeps "Actif"
    /// from colliding with other texts that merely contain the word.
    private static func signal(_ app: XCUIApplication, reads word: String) -> XCUIElement {
        app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier == %@ AND label == %@", "walk.signal", "Signal GPS : \(word)")
        ).firstMatch
    }

    private static var distanceValuePredicate: NSPredicate {
        NSPredicate(format: "label MATCHES '^[0-9.,]+ (m|km)$' OR label == 'Non mesurée'")
    }

    private static func seconds(from label: String) -> Int {
        let parts = label.split(separator: ":").map { Int($0) ?? 0 }
        if parts.count == 3 { return parts[0] * 3600 + parts[1] * 60 + parts[2] }
        if parts.count == 2 { return parts[0] * 60 + parts[1] }
        return 0
    }

    private static func meters(from label: String) -> Double? {
        if label == "Non mesurée" { return nil }
        let parts = label.split(separator: " ")
        guard parts.count == 2, let value = Double(parts[0]) else { return nil }
        return parts[1] == "km" ? value * 1000 : value
    }
}