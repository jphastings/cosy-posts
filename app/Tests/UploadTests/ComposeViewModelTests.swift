import XCTest
@testable import CosyPostsAdmin

/// Behavioral tests for `ComposeViewModel`'s locale handling: removing entries,
/// promoting a new primary, and persisting the preferred starting language
/// (including exact region/script retention).
@MainActor
final class ComposeViewModelTests: XCTestCase {
    private var startingKey: String { ComposeViewModel.preferredStartingLanguageKey }
    private var draftKey: String { ComposeViewModel.composeDraftKey }

    override func setUp() async throws {
        // Start each test from a clean slate so persistence is deterministic and
        // independent of the host's real defaults.
        UserDefaults.standard.removeObject(forKey: startingKey)
        UserDefaults.standard.removeObject(forKey: draftKey)
    }

    override func tearDown() async throws {
        UserDefaults.standard.removeObject(forKey: startingKey)
        UserDefaults.standard.removeObject(forKey: draftKey)
    }

    // MARK: - removeLocale guards

    func testRemoveLocaleIsNoOpWithSingleEntry() {
        let vm = ComposeViewModel()
        XCTAssertEqual(vm.localeEntries.count, 1)

        vm.removeLocale(id: vm.localeEntries[0].id)

        XCTAssertEqual(vm.localeEntries.count, 1, "Cannot remove the only language")
    }

    func testRemovingSecondaryLeavesPrimaryIntact() {
        let vm = ComposeViewModel()
        let primaryID = vm.localeEntries[0].id
        vm.addLocale(Locale.Language(identifier: "cy"))
        XCTAssertEqual(vm.localeEntries.count, 2)

        vm.removeLocale(id: vm.localeEntries[1].id)

        XCTAssertEqual(vm.localeEntries.count, 1)
        XCTAssertEqual(vm.localeEntries[0].id, primaryID)
    }

    func testRemovingSecondaryDoesNotPersistOverride() {
        let vm = ComposeViewModel()
        vm.addLocale(Locale.Language(identifier: "cy"))

        vm.removeLocale(id: vm.localeEntries[1].id)

        XCTAssertNil(
            UserDefaults.standard.string(forKey: startingKey),
            "Removing a secondary must not touch the starting-language override"
        )
    }

    // MARK: - Promoting a new primary

    func testRemovingPrimaryPromotesNextEntry() {
        let vm = ComposeViewModel()
        let primaryID = vm.localeEntries[0].id
        let welsh = Locale.Language(identifier: "cy")
        vm.addLocale(welsh)

        vm.removeLocale(id: primaryID)

        XCTAssertEqual(vm.localeEntries.count, 1)
        XCTAssertEqual(vm.localeEntries[0].locale, welsh, "Next entry should be promoted to primary")
    }

    func testRemovingActivePrimaryMovesActiveToPromotedEntry() {
        let vm = ComposeViewModel()
        let primaryID = vm.localeEntries[0].id
        vm.addLocale(Locale.Language(identifier: "cy"))
        vm.activeLocaleID = primaryID

        vm.removeLocale(id: primaryID)

        XCTAssertEqual(vm.activeLocaleID, vm.localeEntries.first?.id)
    }

    // MARK: - Exact language persistence (fix for region/script collapse)

    func testPromotingPrimaryRetainsChosenScript() throws {
        try XCTSkipIf(
            Locale.current.language.languageCode?.identifier == "zh",
            "Device default is Chinese"
        )
        let vm = ComposeViewModel()
        let primaryID = vm.localeEntries[0].id
        vm.addLocale(Locale.Language(identifier: "zh-Hant"))

        vm.removeLocale(id: primaryID)

        // The chosen script must survive — not collapse to a bare "zh", which would
        // otherwise resolve to Simplified. (minimalIdentifier represents Traditional
        // as "zh-TW"; what matters is the script round-trips, not the literal string.)
        let stored = try XCTUnwrap(UserDefaults.standard.string(forKey: startingKey))
        XCTAssertEqual(Locale.Language(identifier: stored).script?.identifier, "Hant")
        XCTAssertEqual(vm.localeEntries[0].locale.script?.identifier, "Hant")
    }

    func testPromotingPrimaryRetainsChosenRegion() throws {
        try XCTSkipIf(
            Locale.current.language.minimalIdentifier == "en-GB",
            "Device default is already en-GB"
        )
        let vm = ComposeViewModel()
        let primaryID = vm.localeEntries[0].id
        vm.addLocale(Locale.Language(identifier: "en-GB"))

        vm.removeLocale(id: primaryID)

        // A region-tagged choice must not collapse to bare "en".
        XCTAssertEqual(UserDefaults.standard.string(forKey: startingKey), "en-GB")
    }

    func testStartingLanguageReflectsPersistedOverride() {
        UserDefaults.standard.set("zh-Hant", forKey: startingKey)

        // The override must reconstruct as Traditional Chinese, not bare "zh".
        XCTAssertEqual(ComposeViewModel.startingLanguage.languageCode?.identifier, "zh")
        XCTAssertEqual(ComposeViewModel.startingLanguage.script?.identifier, "Hant")

        // A fresh view model with no saved draft should open in the override language.
        let vm = ComposeViewModel()
        XCTAssertEqual(vm.localeEntries.first?.locale.script?.identifier, "Hant")
    }

    func testStartingLanguageFallsBackToDeviceWithoutOverride() {
        XCTAssertNil(UserDefaults.standard.string(forKey: startingKey))
        XCTAssertEqual(
            ComposeViewModel.startingLanguage.minimalIdentifier,
            Locale.current.language.minimalIdentifier
        )
    }

    // MARK: - Override clearing

    func testOverrideClearedWhenPrimaryReturnsToDeviceLanguage() throws {
        let device = Locale.current.language
        try XCTSkipIf(device.minimalIdentifier == "cy", "Device default is Welsh")

        let vm = ComposeViewModel() // primary == device language
        vm.addLocale(Locale.Language(identifier: "cy"))

        // Remove the device primary → Welsh promoted, override persisted.
        vm.removeLocale(id: vm.localeEntries[0].id)
        XCTAssertEqual(UserDefaults.standard.string(forKey: startingKey), "cy")

        // Re-add the device language, then remove Welsh → device promoted back to primary.
        vm.addLocale(device)
        vm.removeLocale(id: vm.localeEntries[0].id)

        XCTAssertNil(
            UserDefaults.standard.string(forKey: startingKey),
            "Override should be cleared once the primary matches the device language again"
        )
    }
}
