import Foundation
import Observation

@MainActor
@Observable
final class SettingsModel {

    static let presetDiagonals: [Double] = [32, 43, 50, 55, 65, 75, 85]
    private static let tvAspectW = 16.0
    private static let tvAspectH = 9.0

    var panels: [Panel] = []
    var isLoading = false
    /// Whether `panels` describes a list the board actually sent.
    ///
    /// Not the same question as `panels.isEmpty`: a board with genuinely no
    /// panels and a board that could not be reached both leave the array
    /// empty, and `autoDimSummary` has to say very different things about
    /// them.
    var hasLoaded = false
    var errorMessage: String?
    var warningMessage: String?
    var resizeDiagonal: Double = 65
    var customDiagonalText = ""
    var sizing: BoardSizing = .fit
    var matrixPresentation: MatrixPresentation
    var matrixTransitionStyle: MatrixTransitionStyle
    var defaultPanelRef: String?
    /// This TV's say in the panel's nightly dim window.
    var autoDimOverride: AutoDimOverride = .followPanel
    /// Whether the board drifts to keep the TV's panel protection off it.
    var driftEnabled = false
    private var calibrations: [String: Double] = [:]
    /// Switches the user has flipped but the board has not confirmed yet.
    private var pendingAnimation: [String: Bool] = [:]
    private var pendingStyle: [String: PanelRenderStyle] = [:]
    private var pendingPanelWrites: Set<String> = []
    private var previewPanelID: String?
    private var preview: PanelPreviewState = .loading
    @ObservationIgnored private var previewGeneration = UUID()
    @ObservationIgnored private var loadGeneration = UUID()

    private let app: AppModel
    private let signage: SignageSettings
    private let clock: () -> Date

    init(app: AppModel,
         signage: SignageSettings = .shared,
         clock: @escaping () -> Date = Date.init) {
        self.app = app
        self.signage = signage
        self.clock = clock
        matrixPresentation = signage.matrixPresentation
        matrixTransitionStyle = signage.matrixTransitionStyle
        defaultPanelRef = app.connection.saved?.defaultPanelRef
        autoDimOverride = signage.autoDimOverride
        driftEnabled = signage.driftEnabled
        if let raw = UserDefaults.standard.string(forKey: "fiestaboard.sizing"),
           let stored = BoardSizing(rawValue: raw) {
            sizing = stored
        }
    }

    var boardName: String { app.connection.saved?.displayName ?? "Not connected" }

    var boardAddress: String { app.connection.saved?.host.absoluteString ?? "" }

    func previewState(for panel: Panel) -> PanelPreviewState {
        guard !current(panel).boardMissing else { return .unavailable }
        return previewPanelID == panel.id ? preview : .loading
    }

    /// Fetch only the selected panel. The caller's SwiftUI task owns cancellation;
    /// a generation also rejects late replies from overlapping retries.
    func loadPreview(for panel: Panel) async {
        guard !Task.isCancelled else { return }
        let panel = current(panel)
        let generation = UUID()
        previewGeneration = generation
        previewPanelID = panel.id
        preview = panel.boardMissing ? .unavailable : .loading
        guard !panel.boardMissing else { return }
        do {
            let frame = try await app.connection.authorized { try await $0.frame(ref: panel.id) }
            guard previewGeneration == generation else { return }
            guard !Task.isCancelled else { preview = .unavailable; return }
            preview = .ready(PanelPreview.make(from: frame, code62: panel.effectiveCode62))
        } catch {
            guard previewGeneration == generation else { return }
            preview = .unavailable
            guard !Task.isCancelled else { return }
            if let error = error as? FiestaError, error == .unauthorized {
                app.route = .signIn
            }
            // A missing preview must not replace an unrelated settings-save error.
        }
    }

    private var customDiagonalIsValid: Bool {
        customDiagonalText.isEmpty || (Double(customDiagonalText).map { (3...200).contains($0) } ?? false)
    }

    /// The grid `resizeDiagonal` would produce, computed locally so the
    /// change can be seen before the server reshapes anything.
    var previewGrid: String {
        guard customDiagonalIsValid else { return "—" }
        guard let grid = try? BoardGeometry.computeAutofitGrid(
            diagonal: resizeDiagonal, aspectW: Self.tvAspectW, aspectH: Self.tvAspectH) else {
            return "—"
        }
        return "\(grid.notesWide * BoardGeometry.noteCols) × \(grid.notesTall * BoardGeometry.noteRows)"
    }

    func load() async {
        guard !Task.isCancelled else { return }
        let generation = UUID()
        loadGeneration = generation
        isLoading = true
        errorMessage = nil
        defer { if loadGeneration == generation { isLoading = false } }
        do {
            let loaded = try await app.connection.authorized { try await $0.panels() }
            guard loadGeneration == generation, !Task.isCancelled else { return }
            panels = loaded
            hasLoaded = true
        } catch {
            guard loadGeneration == generation, !Task.isCancelled else { return }
            if let error = error as? FiestaError {
                if error == .unauthorized { app.route = .signIn }
                else { report(error: error.userMessage) }
            } else {
                report(error: FiestaError.transport("\(error)").userMessage)
            }
        }
    }

    /// Record an error or a warning and say it out loud — see
    /// `Announce.say(_:recordingIn:)`. The two messages are separate because
    /// they sit in separate places at the top of the list: a resize can warn
    /// about pages authored for the old grid and still have succeeded.
    private func report(error message: String) {
        Announce.say(message, recordingIn: &errorMessage)
    }

    private func report(warning message: String) {
        Announce.say(message, recordingIn: &warningMessage)
    }

    func setDefaultPanel(_ ref: String?) {
        app.connection.setDefaultPanel(ref: ref)
        defaultPanelRef = ref
    }

    func setSizing(_ sizing: BoardSizing) {
        self.sizing = sizing
        UserDefaults.standard.set(sizing.rawValue, forKey: "fiestaboard.sizing")
    }

    func setMatrixSizing(_ sizing: MatrixSizing) {
        saveMatrixPresentation(.init(sizing: sizing, diagonalInches: matrixPresentation.diagonalInches,
                                     pitchMillimeters: matrixPresentation.pitchMillimeters))
    }

    func setMatrixTransitionStyle(_ style: MatrixTransitionStyle) {
        matrixTransitionStyle = style
        signage.matrixTransitionStyle = style
    }

    func setMatrixDiagonal(_ inches: Double) {
        saveMatrixPresentation(.init(sizing: matrixPresentation.sizing, diagonalInches: inches,
                                     pitchMillimeters: matrixPresentation.pitchMillimeters))
    }

    func setMatrixPitch(_ millimeters: Double) {
        saveMatrixPresentation(.init(sizing: matrixPresentation.sizing, diagonalInches: matrixPresentation.diagonalInches,
                                     pitchMillimeters: millimeters))
    }

    private func saveMatrixPresentation(_ value: MatrixPresentation) {
        matrixPresentation = value
        signage.matrixPresentation = value
    }

    private func current(_ panel: Panel) -> Panel {
        panels.first { $0.id == panel.id } ?? panel
    }

    var stylePanels: [Panel] { panels.filter(\.supportsRenderStyle) }
    var flapPanels: [Panel] { panels.filter { $0.renderStyle == .splitFlap } }

    func renderStyle(for panel: Panel) -> PanelRenderStyle {
        pendingStyle[panel.id] ?? current(panel).renderStyle
    }

    func isSavingRenderStyle(for panel: Panel) -> Bool { pendingStyle[panel.id] != nil }
    func isSavingPanel(_ panel: Panel) -> Bool { pendingPanelWrites.contains(panel.id) }

    func setRenderStyle(_ style: PanelRenderStyle, for panel: Panel) async {
        guard current(panel).supportsRenderStyle, pendingPanelWrites.insert(panel.id).inserted else { return }
        defer { pendingPanelWrites.remove(panel.id) }
        errorMessage = nil
        pendingStyle[panel.id] = style
        defer { pendingStyle[panel.id] = nil }
        do {
            let result = try await app.connection.authorized {
                try await $0.updatePanel(id: panel.id, renderStyle: style)
            }
            if let index = panels.firstIndex(where: { $0.id == panel.id }) { panels[index] = result.panel }
        } catch FiestaError.unauthorized {
            app.route = .signIn
        } catch let error as FiestaError {
            report(error: "Couldn't save the display style. " + error.userMessage)
        } catch {
            report(error: "Couldn't save the display style.")
        }
    }

    /// Whether this panel's flaps animate.
    ///
    /// Read from the loaded list rather than from the `Panel` the caller is
    /// holding: a row built earlier hands back a value copied at build time,
    /// which goes stale as soon as anything updates the list, and the switch
    /// then sits on the old state.
    ///
    /// A flip the board has not confirmed yet wins over both, so the switch
    /// moves under the thumb instead of after a round trip.
    func animationEnabled(for panel: Panel) -> Bool {
        if let pending = pendingAnimation[panel.id] { return pending }
        return panels.first(where: { $0.id == panel.id })?.animationsEnabled
            ?? panel.animationsEnabled
    }

    func setAnimationEnabled(_ enabled: Bool, for panel: Panel) async {
        guard pendingPanelWrites.insert(panel.id).inserted else { return }
        defer { pendingPanelWrites.remove(panel.id) }
        errorMessage = nil
        pendingAnimation[panel.id] = enabled
        // However this ends, the switch goes back to describing the board.
        defer { pendingAnimation[panel.id] = nil }
        do {
            let result = try await app.connection.authorized {
                try await $0.updatePanel(id: panel.id, animationsEnabled: enabled)
            }
            if let index = panels.firstIndex(where: { $0.id == panel.id }) {
                panels[index] = result.panel
            }
        } catch FiestaError.unauthorized {
            app.route = .signIn
        } catch let error as FiestaError {
            report(error: "Couldn't save the animation setting. " + error.userMessage)
        } catch {
            report(error: "Couldn't save the animation setting.")
        }
    }

    // MARK: A board left on a wall

    func setAutoDimOverride(_ value: AutoDimOverride) {
        autoDimOverride = value
        signage.autoDimOverride = value
    }

    func setDriftEnabled(_ enabled: Bool) {
        driftEnabled = enabled
        signage.driftEnabled = enabled
    }

    /// Why the board is dim, in words, for the Section footer.
    ///
    /// The whole reason this screen exists: auto-dim is configured on the
    /// server and was invisible from the TV, so someone standing in front of
    /// a board that had gone dim had no way to learn why. It also says when
    /// FiestaBoard is *not* the culprit, because two of the three things
    /// that dim a wall-mounted TV are not this app.
    var autoDimSummary: String {
        // "No panel on this board is set to dim" is a claim about a list we
        // have. This used to be reached by every failure path in `load()`
        // too, because an unreachable board leaves `panels` empty exactly
        // like a board with nothing scheduled — so the screen that exists to
        // explain a dimmed board answered a question it had not asked the
        // board. `hasLoaded`, not `panels.isEmpty`, is what tells them apart.
        guard hasLoaded else {
            return isLoading ? Self.dimScheduleLoading : Self.dimScheduleUnknown
        }
        let scheduled = panels.filter { $0.autoDim.enabled }
        guard !scheduled.isEmpty else {
            return "No panel on this board is set to dim. If the picture still fades, it is the Apple TV's screen saver or the TV's own panel protection, not FiestaBoard."
        }
        var lines = scheduled.map { panel -> String in
            let from = Self.clockLabel(panel.autoDim.start)
            let until = Self.clockLabel(panel.autoDim.end)
            return "\(panel.name) dims from \(from) to \(until)."
        }
        if autoDimOverride == .neverDim {
            lines.append("This Apple TV is ignoring that and staying bright.")
        } else if let dimming = scheduled.first(where: { isDimmingNow($0) }) {
            lines.append("\(dimming.name) is dimmed right now.")
        }
        // Not "in the FiestaBoard app": the icon this is being read from is
        // labelled FiestaBoard. The schedule is edited on the board's own
        // web page, which is the thing that actually does the job.
        lines.append("The schedule itself belongs to the panel and is changed on your board's web page.")
        return lines.joined(separator: " ")
    }

    static let dimScheduleLoading = "Checking this board's dim schedule…"

    static let dimScheduleUnknown = """
        Couldn't reach this board, so whether any panel dims on a schedule is \
        unknown. If the picture has faded it could be that schedule, the Apple \
        TV's screen saver, or the TV's own panel protection.
        """

    private func isDimmingNow(_ panel: Panel) -> Bool {
        AutoDimWindow.isDimmed(panel.autoDim, at: clock())
    }

    /// "22:00" as the TV's user would read a clock.
    static func clockLabel(_ hhmm: String, locale: Locale = .current) -> String {
        guard let total = AutoDimWindow.minutes(from: hhmm) else { return hhmm }
        var calendar = Calendar(identifier: .gregorian)
        let utc = TimeZone(secondsFromGMT: 0) ?? .current
        calendar.timeZone = utc
        let parts = DateComponents(year: 2001, month: 1, day: 1,
                                   hour: total / 60, minute: total % 60)
        guard let date = calendar.date(from: parts) else { return hhmm }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = utc
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    func selectPreset(_ inches: Double) {
        resizeDiagonal = inches
        customDiagonalText = ""
    }

    func setCustomDiagonal(_ raw: String) {
        customDiagonalText = raw
        if let value = Double(raw), (3...200).contains(value) { resizeDiagonal = value }
    }

    func calibration(for panel: Panel) -> Double {
        calibrations[panel.id] ?? min(1.15, max(0.85, panel.calibrationScale))
    }

    func setCalibration(_ value: Double, for panel: Panel) {
        calibrations[panel.id] = min(1.15, max(0.85, value))
    }

    @discardableResult
    func saveCalibration(panel: Panel) async -> Bool {
        guard current(panel).renderStyle == .splitFlap, pendingPanelWrites.insert(panel.id).inserted else { return false }
        defer { pendingPanelWrites.remove(panel.id) }
        errorMessage = nil
        do {
            let scale = calibration(for: panel)
            let result = try await app.connection.authorized {
                try await $0.updatePanel(id: panel.id, calibration: scale)
            }
            if let index = panels.firstIndex(where: { $0.id == panel.id }) {
                panels[index] = result.panel
            }
            return true
        } catch FiestaError.unauthorized {
            app.route = .signIn
        } catch let error as FiestaError {
            report(error: "Couldn't save the calibration. " + error.userMessage)
        } catch {
            report(error: "Couldn't save the calibration.")
        }
        return false
    }

    func resize(panel: Panel) async {
        guard current(panel).renderStyle == .splitFlap, pendingPanelWrites.insert(panel.id).inserted else { return }
        defer { pendingPanelWrites.remove(panel.id) }
        errorMessage = nil
        warningMessage = nil
        guard customDiagonalIsValid else {
            report(error: "Enter a screen size from 3 to 200 inches.")
            return
        }
        do {
            let result = try await app.connection.authorized {
                try await $0.updatePanel(id: panel.id, diagonal: resizeDiagonal,
                                         aspectW: Self.tvAspectW, aspectH: Self.tvAspectH)
            }
            if !result.incompatibleReferences.isEmpty {
                let count = result.incompatibleReferences.count
                let noun = count == 1 ? "page was" : "pages were"
                report(warning: "The grid changed. \(count) \(noun) authored for the old size and won't fill this one — edit them on your board's web page.")
            }
            // The PATCH already returns the resized panel. A list reload can
            // arrive after another panel's style save and overwrite it with
            // an older value, despite each panel's own write guard.
            if let index = panels.firstIndex(where: { $0.id == panel.id }) {
                panels[index] = result.panel
            }
        } catch FiestaError.unauthorized {
            app.route = .signIn
        } catch let error as FiestaError {
            // The bare catch here threw the typed error away and blamed the
            // resize, so a board that answered 429 or replied in a shape this
            // app can't read looked identical to one that refused the grid.
            report(error: "Couldn't resize this panel. " + error.userMessage)
        } catch {
            report(error: "Couldn't resize this panel.")
        }
    }

    func signOut() {
        app.connection.signOut()
        app.clearTopShelf()
        app.route = .signIn
    }

    func forget() {
        app.disconnect()
    }
}
