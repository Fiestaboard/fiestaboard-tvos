import SwiftUI

/// Choosing a board, built the way tvOS presents a set of things to pick.
///
/// The boards found on the network are content: a row of cards, with the
/// platform's own focus treatment. Typing an address is the fallback for a
/// board Bonjour cannot see, so it sits below in plain system controls
/// rather than as a third amber slab competing with the list.
///
/// It is also the first screen anyone sees, App Review included, so it says
/// what a FiestaBoard is before it asks anyone to choose one.
struct ConnectScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: ConnectModel?

    private enum FocusTarget: Hashable {
        case board(String)
        case address
        case connect
        case searchAgain
    }

    /// Track the manual controls too, so discovery cannot steal their focus.
    @FocusState private var focusedControl: FocusTarget?
    @State private var focusRecovery = ConnectFocusRecovery<FocusTarget>()
    private struct FocusRequest: Hashable { let token: UUID; let target: FocusTarget }
    @State private var retryFocus: FocusRequest?
    /// One native scope owns both discovery cards and the manual fallback.
    @Namespace private var boardScope

    /// Injectable so tests can drive a screen that has boards on it and a
    /// connect in flight, matching `PanelsScreen` and `ViewerScreen`. Without
    /// it every render of this screen was the empty state, because the model
    /// only exists once `.onAppear` has built one.
    init(model: ConnectModel? = nil) {
        _model = State(initialValue: model)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Fiesta.Metrics.gutter) {
            header
                .frame(height: ScreenRhythm.headingHeight, alignment: .topLeading)
            errorBanner
            boards
                // 07b A1: the address row's label at y 800 (`166:147344`).
                .frame(height: 800 - Fiesta.Metrics.gutter - ScreenRhythm.contentTop)
            manualEntry
            Spacer(minLength: 0)
        }
        // A4a: no padding of its own; the system safe area is the 07b
        // title-safe (80/60). The A1 Screen slot is the whole 1920×1080
        // screen, so its probe covers the safe area and child probes stay
        // relative to the slot, as get_metadata reports them.
        .figmaNode(Self.a1Slot, coversSafeArea: true)
        .focusScope(boardScope)
        // No `.onExitCommand`: Connect is the app's root — it is where the
        // app opens with no board saved, and where forgetting one lands you.
        // There is nothing behind it, so Menu belongs to the system and
        // quitting to the Apple TV home screen is the correct behaviour.
        .onAppear {
            if model == nil { model = ConnectModel(app: app) }
            Task {
                #if DEBUG
                if let discovery = ConnectReviewDiscovery.fromLaunchArguments() {
                    await model?.startScan(using: discovery)
                    return
                }
                #endif
                await model?.startScan()
            }
        }
        .onDisappear { model?.stopScan(); focusRecovery.cancel(); retryFocus = nil }
        .onChange(of: focusedControl) { _, current in
            traceFocus("focus-change", detail: "current=\(String(describing: current)) connecting=\(model?.isConnecting == true)")
            if model?.isConnecting == true { focusRecovery.focusChanged(to: current) }
            if current != nil {
                traceFocus("clear-request-for-owner", detail: "current=\(String(describing: current)) request=\(String(describing: retryFocus))")
                retryFocus = nil
            }
        }
        .task(id: retryFocus) {
            traceFocus("request-task", detail: "request=\(String(describing: retryFocus)) scene=\(scenePhase) route=\(app.route) exists=\(retryFocus.map { focusTargetExists($0.target) } ?? false) canceled=\(Task.isCancelled)")
            guard !Task.isCancelled, let request = retryFocus, scenePhase == .active, app.route == .connect,
                  focusTargetExists(request.target),
                  focusedControl == nil || focusedControl == request.target else { return }
            // The failed response and the cleared binding have now rendered.
            // Reissue the binding so the native engine gets a real focus
            // transition even when its old SwiftUI value survived the failure.
            traceFocus("restore-focus-binding", detail: "target=\(request.target)")
            focusedControl = request.target
        }
        .onChange(of: boardIDs) { old, new in
            // Only when the first board lands, and only when nothing holds
            // focus yet. Once the remote is somewhere, a board appearing
            // later must not snatch it back mid-press.
            guard old.isEmpty, let first = new.first, focusedControl == nil else { return }
            focusedControl = .board(first)
        }
    }

    // MARK: Pieces

    private var header: some View {
        Group {
        #if DEBUG
        FiestaScreenHeading(title: TVCopy.Connect.title,
                            subtitle: TVCopy.Connect.subtitle,
                            context: TVCopy.Connect.eyebrow,
                            figma: Self.headingNodes)
        #else
        FiestaScreenHeading(title: TVCopy.Connect.title,
                            subtitle: TVCopy.Connect.subtitle,
                            context: TVCopy.Connect.eyebrow)
        #endif
        }
            .frame(maxWidth: 1200, alignment: .leading)
    }

    /// Every failure on this screen surfaces here, in the same place and the
    /// same destructive colour — whether it came from the connect attempt or
    /// from the app (a board that still needs its first account).
    ///
    /// The model's message wins: the app-level one is only cleared by
    /// transitions that do not happen while you stay on Connect, so reading
    /// it first made one unprovisioned board explain every later failure.
    @ViewBuilder
    private var errorBanner: some View {
        if let message = model?.errorMessage ?? app.errorMessage {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(Fiesta.Text.caption)
                .foregroundStyle(Fiesta.Colors.destructive)
                // Not "Problem connecting": a board that needs its first
                // account connected perfectly well.
                .accessibilityLabel("Alert. \(message)")
        }
    }

    @ViewBuilder
    private var boards: some View {
        let found = model?.boards ?? []
        if found.isEmpty {
            emptyState
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView(.vertical) {
                LazyVGrid(columns: Self.columns, spacing: 40) {
                    ForEach(found) { board in
                        card(for: board)
                    }
                    // A1: the scan keeps listening after the first hub, and
                    // says so beside the cards rather than going quiet.
                    if isLooking {
                        stillLooking
                    }
                }
                // Cards lift on focus; without room inside the scroll view
                // the lift is clipped at the edges.
                // 07b A1: the hub card at y 340 (`166:147325`).
                .padding(EdgeInsets(top: 340 - ScreenRhythm.contentTop, leading: Self.focusRoom,
                                    bottom: Self.focusRoom, trailing: Self.focusRoom))
            }
            // A5: widen the viewport by the focus room it spends on its
            // content, so the first card sits on the title-safe edge (A1's
            // x 80), not 16 pt inside it.
            .padding(.horizontal, -Self.focusRoom)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            // Two focus sections on this screen — the grid and the address
            // row — so the engine can cross from a card down to the field
            // rather than looking for something directly beneath it.
            .focusSection()
        }
    }

    /// The 07b A1 frame's Screen slot (`I<instance>;149:182603`).
    private static let a1Slot = "I166:147296;149:182603"

    // Probe ids that are *stored* (in the heading and the card) rather than
    // passed to the inlined `figmaNode` no-op must be DEBUG-only, or their
    // literals ship: the Release archive's probe check fails on them.
    #if DEBUG
    private static let headingNodes: FiestaScreenHeading.FigmaNodes? = .init(
        eyebrow: a1Slot + ";166:147308", title: a1Slot + ";166:147310", subtitle: a1Slot + ";166:147312")
    private static let cardTitleNode: String? = a1Slot + ";166:147327"
    #endif

    /// A1 `166:147340` "Scanning": the taco and one muted line, centred on
    /// the card row. Not focusable; it is status, not a control.
    private var stillLooking: some View {
        HStack(spacing: 16) {
            // The static brand mark, as A1 draws it (`Brand / Taco mark`,
            // 35 pt) — not the hopping loader, which would make this row
            // pull the eye from the hubs it is listed beside.
            TacoMarkView()
                .frame(width: 35, height: 35)
                .accessibilityHidden(true)
            Text(TVCopy.Connect.stillLooking)
                .font(Fiesta.Text.body)
                .foregroundStyle(Fiesta.Colors.mutedForeground)
                .lineLimit(1)
                .figmaNode(Self.a1Slot + ";166:147342", label: TVCopy.Connect.stillLooking)
        }
        // One line, extending right of its grid cell like A1's row beside
        // the card, rather than wrapping inside a 400 pt column.
        .fixedSize(horizontal: true, vertical: false)
        .frame(minHeight: Self.cardHeight, alignment: .leading)
    }

    /// `DiscoveredBoardCard`'s height (190 pt content + 2 × 28 pt padding).
    private static let cardHeight: CGFloat = 246

    /// Room inside the hub grid for a card's focus lift.
    private static let focusRoom: CGFloat = 16
    private static let columns = [GridItem(.adaptive(minimum: 400), spacing: 40, alignment: .topLeading)]

    private var boardIDs: [String] { model?.boards.map(\.id) ?? [] }

    private func card(for board: DiscoveredBoard) -> some View {
        var card = DiscoveredBoardCard(board: board,
                                       address: BoardAddressLabel.text(for: board),
                                       isConnecting: model?.connectInFlight(for: board.id) ?? false) {
            traceFocus("hub-action", detail: "target=board(\(board.id))")
            Task { await connect(from: .board(board.id)) { await model?.connect(to: board.host, name: board.name) } }
        }
        #if DEBUG
        card.figmaTitle = board.id == boardIDs.first ? Self.cardTitleNode : nil
        #endif
        return card
            .figmaNode(Self.a1Slot + ";166:147325", enabled: board.id == boardIDs.first)
            .focused($focusedControl, equals: .board(board.id))
            .prefersDefaultFocus(board.id == preferredBoardID, in: boardScope)
    }


    /// Whether the screen is still entitled to promise a board is coming.
    ///
    /// One state, asked once: the judgement is `ScanState`'s, so no pair of
    /// flags read here can describe a state the model is not in. A screen
    /// with no model yet is the same `.idle` as a model whose first scan is
    /// still a hop away — patient, not a verdict.
    private var isLooking: Bool {
        (model?.scanState ?? .idle).promisesABoardIsComing
    }

    /// Nothing found yet. Scanning is normal, so it is said in words next to
    /// the spinner and in muted foreground — never in the error colour.
    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "network")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(Fiesta.Colors.brand)
                .accessibilityHidden(true)
            emptyStateMessage
            if !isLooking {
                Button(TVCopy.Connect.searchAgain) { Task { await model?.rescan() } }
                    .focused($focusedControl, equals: .searchAgain)
                    .prefersDefaultFocus(retryFocus?.target == .searchAgain, in: boardScope)
                    .padding(.top, 12)
            }
        }
        .frame(maxWidth: 900)
        .focusSection()
    }

    @ViewBuilder
    private var emptyStateMessage: some View {
        VStack(spacing: 16) {
            if isLooking {
                TacoLoader(size: .large)
                    .accessibilityHidden(true)
                Text(TVCopy.Connect.looking)
                    .font(Fiesta.Text.body)
                    .foregroundStyle(Fiesta.Colors.foreground)
                Text(TVCopy.Connect.lookingDetail)
                    .font(Fiesta.Text.caption)
                    .foregroundStyle(Fiesta.Colors.mutedForeground)
            } else {
                Text(TVCopy.Connect.foundNothing)
                    .font(Fiesta.Text.body)
                    .foregroundStyle(Fiesta.Colors.foreground)
                // No mention of Settings › Privacy › Local Network: on
                // tvOS there is nothing there. tvOS is the one platform
                // that does not implement local network privacy — Apple's
                // TN3179 platform table lists it "no", in a revision later
                // than tvOS 26 — so there is no prompt to decline and no
                // toggle to send anyone to. A board that never appears is
                // off, on another network, or unreachable; it is never a
                // denied permission. Offering that path would point the
                // user at a screen that does not exist; see the
                // local-network entry in docs/HANDOFF.md before adding it.
                Text(TVCopy.Connect.foundNothingDetail)
                    .font(Fiesta.Text.caption)
                    .foregroundStyle(Fiesta.Colors.mutedForeground)
            }
        }
        .multilineTextAlignment(.center)
        // Combined so VoiceOver reads the state as one sentence. "Search
        // again" stays outside it: a combined parent swallows the button and
        // leaves nothing to press.
        .accessibilityElement(children: .combine)
    }

    /// The secondary path: a quiet label, a stock text field and a stock
    /// button, so it reads as the way out rather than as a peer of the list.
    ///
    /// It is visible and focusable in every state on purpose — it is the only
    /// route through this screen for anyone with no board on their network.
    private var manualEntry: some View {
        // 07b A1: the label at y 800, 32 tall; the field 18 below, at y 850.
        VStack(alignment: .leading, spacing: 18) {
            Text(TVCopy.Connect.manualLabel)
                .font(Fiesta.Text.caption)
                .foregroundStyle(Fiesta.Colors.mutedForeground)
                .frame(height: 32, alignment: .topLeading)
                .figmaNode(Self.a1Slot + ";166:147344", label: TVCopy.Connect.manualLabel)

            HStack(spacing: 20) {
                TextField(TVCopy.Connect.addressPlaceholder, text: manualAddressBinding)
                    .textContentType(.URL)
                    .autocorrectionDisabled()
                    .frame(maxWidth: 560)
                    // A1 "Text field (system)" sits on --secondary
                    // (`surfaceRaised`), not on the ground (review #16/#17,
                    // 4.2). tvOS draws its own translucent field platter
                    // whatever the style, so the token goes behind it, the
                    // same shape: one pill, the system's focus lift intact.
                    // The platter itself is system chrome (§2.1 waivers).
                    .background(Fiesta.Colors.surfaceRaised, in: Capsule())
                    .accessibilityLabel("FiestaBoard address")
                    .focused($focusedControl, equals: .address)
                    .prefersDefaultFocus(retryFocus?.target == .address, in: boardScope)
                    .figmaNode(Self.a1Slot + ";166:147347")

                // Not `.disabled` while a connect is in flight: on tvOS
                // disabling the focused control moves focus off it and it
                // does not reliably come back. `guard !isConnecting` in the
                // model is the re-entry guard; this is only the feedback.
                Button(TVCopy.Connect.connect) {
                    Task { await connect(from: .connect) { await model?.connectManually() } }
                }
                    .accessibilityLabel("Connect to the address you entered")
                    .focused($focusedControl, equals: .connect)
                    .prefersDefaultFocus(retryFocus?.target == .connect, in: boardScope)
                    .figmaNode(Self.a1Slot + ";166:147351", label: "Connect")

                if model?.manualConnectInFlight ?? false {
                    TacoLoader(size: .small)
                        .accessibilityHidden(true)
                }
            }
        }
        .focusSection()
    }

    private var preferredBoardID: String? {
        if let request = retryFocus {
            if case .board(let id) = request.target { return id }
            return nil
        }
        return boardIDs.first
    }

    private func focusTargetExists(_ target: FocusTarget) -> Bool {
        switch target {
        case .board(let id): return boardIDs.contains(id)
        case .address, .connect: return true
        case .searchAgain: return boardIDs.isEmpty && !isLooking
        }
    }

    @MainActor private func connect(from target: FocusTarget,
                                    perform: @MainActor () async -> Void) async {
        traceFocus("attempt-enter", detail: "target=\(target)")
        guard let model, !model.isConnecting else { return }
        retryFocus = nil
        let token = focusRecovery.begin(target: target, focused: focusedControl)
        traceFocus("attempt-begin", detail: "target=\(target) debt=\(String(describing: focusRecovery.target(for: token)))")
        await perform()
        let available = focusRecovery.target(for: token).map(focusTargetExists) ?? false
        let failed = app.route == .connect && (model.errorMessage ?? app.errorMessage) != nil
        traceFocus("attempt-completed", detail: "failed=\(failed) available=\(available) scene=\(scenePhase) debt=\(String(describing: focusRecovery.target(for: token)))")
        guard let target = focusRecovery.finish(token: token, failed: failed,
                                                focused: focusedControl, available: available),
              scenePhase == .active else { return }
        traceFocus("request-created", detail: "target=\(target)")
        // A retained binding is not proof that the native/AX owner survived
        // the response update. Clear it before the rendered task reissues the
        // target; resetFocus alone is a no-op for an already preferred owner.
        focusedControl = nil
        retryFocus = FocusRequest(token: token, target: target)
    }

    /// Opt-in native diagnostics only. No view, accessibility node or focus
    /// preference is added; CI retains the sandbox file beside xcresult.
    private func traceFocus(_ event: String, detail: String = "") {
        #if DEBUG
        guard ProcessInfo.processInfo.arguments.contains("-fiestaboard.connectFocusTrace") else { return }
        let row: [String: Any] = ["event": event, "detail": detail,
            "time": Date().timeIntervalSince1970, "pid": ProcessInfo.processInfo.processIdentifier,
            "focusedControl": String(describing: focusedControl),
            "request": String(describing: retryFocus)]
        guard let data = try? JSONSerialization.data(withJSONObject: row, options: [.sortedKeys]),
              let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return }
        let directory = cache.appendingPathComponent("ConnectFocusTrace", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("events.jsonl")
        if !FileManager.default.fileExists(atPath: file.path) {
            _ = FileManager.default.createFile(atPath: file.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: file) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: data + Data([10]))
        #endif
    }

    // MARK: Bindings
    //
    // Declared with an explicit type rather than built inline, per the build
    // hazard in docs/tvos-design.md.

    private var manualAddressBinding: Binding<String> {
        Binding(get: { model?.manualAddress ?? "" },
                set: { model?.manualAddress = $0 })
    }
}
