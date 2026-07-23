import XCTest

class RunnerUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        let app = XCUIApplication()
        setupSnapshot(app)
        app.launch()
    }

    func testScreenshots() throws {
        let app = XCUIApplication()

        // Wait for app to fully load (onboarding or home screen)
        sleep(2)

        // ── Screenshot 1: Onboarding ─────────────────────────────────────
        snapshot("01_Onboarding")

        // Advance through onboarding if visible
        for _ in 0..<4 {
            let nextBtn = app.buttons["Next"]
            let startBtn = app.buttons["Get started"]
            if startBtn.exists {
                snapshot("02_Onboarding_Last")
                startBtn.tap()
                sleep(1)
                break
            } else if nextBtn.exists {
                nextBtn.tap()
                sleep(1)
            } else {
                break
            }
        }

        // ── Screenshot 2: Home / Data tab ────────────────────────────────
        sleep(1)
        snapshot("03_Home")

        // ── Screenshot 3: Workout tab ────────────────────────────────────
        let workoutTab = app.tabBars.buttons["Workout"]
        if workoutTab.exists {
            workoutTab.tap()
            sleep(1)
            snapshot("04_Workout")
        }

        // ── Screenshot 4: Settings (HR Zones) ───────────────────────────
        let settingsBtn = app.navigationBars.buttons.matching(
            NSPredicate(format: "label CONTAINS 'bar_chart' OR label CONTAINS 'Settings'")
        ).firstMatch
        if settingsBtn.exists {
            settingsBtn.tap()
            sleep(1)
            snapshot("05_Settings")
            app.navigationBars.buttons.firstMatch.tap()
        }
    }
}
