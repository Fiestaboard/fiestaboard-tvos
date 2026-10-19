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
    @State private var model: ConnectModel?

    private enum FocusTarget: Hashable {
        case board(String)
        case address
        case connect
        case searchAgain
    }

    /// Track the manual controls too, so discovery cannot steal their focus.
    @FocusState private var focusedControl: FocusTarget?
    /// The scope `prefersDefaultFocus` is answered in, so the first board is
    /// the default when focus enters the grid, as on `PanelsScreen`.
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
            errorBanner
            boards
            manualEntry
        }
        .padding(Fiesta.Metrics.safeInset)
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
        .onDisappear { model?.stopScan() }
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
        FiestaScreenHeading(title: "Find your FiestaBoard",
                            subtitle: "Bring your split-flap and LED matrix panels to this TV. Choose a FiestaBoard on your network to get started.")
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
                }
                // Cards lift on focus; without room inside the scroll view
                // the lift is clipped at the edges.
                .padding(.vertical, 36)
                .padding(.horizontal, 16)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .focusScope(boardScope)
            // Two focus sections on this screen — the grid and the address
            // row — so the engine can cross from a card down to the field
            // rather than looking for something directly beneath it.
            .focusSection()
        }
    }

    private static let columns = [GridItem(.adaptive(minimum: 400), spacing: 40, alignment: .topLeading)]

    private var boardIDs: [String] { model?.boards.map(\.id) ?? [] }

    private func card(for board: DiscoveredBoard) -> some View {
        DiscoveredBoardCard(board: board,
                            address: BoardAddressLabel.text(for: board),
                            isConnecting: model?.connectInFlight(for: board.id) ?? false) {
            Task { await model?.connect(to: board.host, name: board.name) }
        }
        .focused($focusedControl, equals: .board(board.id))
        .prefersDefaultFocus(board.id == boardIDs.first, in: boardScope)
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
                Button("Search again") { Task { await model?.rescan() } }
                    .focused($focusedControl, equals: .searchAgain)
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
                Text("Looking for FiestaBoards on this network…")
                    .font(Fiesta.Text.body)
                    .foregroundStyle(Fiesta.Colors.foreground)
                Text("This takes a few seconds. Your board needs to be powered on and on the same network as this Apple TV.")
                    .font(Fiesta.Text.caption)
                    .foregroundStyle(Fiesta.Colors.mutedForeground)
            } else {
                Text("No FiestaBoard on this network yet")
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
                Text("This Apple TV is still listening; a board appears here within a few seconds of being powered on. If yours is on a different network, enter its address below.")
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
        VStack(alignment: .leading, spacing: 12) {
            Text("Or enter your board's address")
                .font(Fiesta.Text.caption)
                .foregroundStyle(Fiesta.Colors.mutedForeground)

            HStack(spacing: 20) {
                TextField("192.168.1.50 or board.local", text: manualAddressBinding)
                    .textContentType(.URL)
                    .autocorrectionDisabled()
                    .frame(maxWidth: 560)
                    .accessibilityLabel("FiestaBoard address")
                    .focused($focusedControl, equals: .address)

                // Not `.disabled` while a connect is in flight: on tvOS
                // disabling the focused control moves focus off it and it
                // does not reliably come back. `guard !isConnecting` in the
                // model is the re-entry guard; this is only the feedback.
                Button("Connect") { Task { await model?.connectManually() } }
                    .accessibilityLabel("Connect to the address you entered")
                    .focused($focusedControl, equals: .connect)

                if model?.manualConnectInFlight ?? false {
                    TacoLoader(size: .small)
                        .accessibilityHidden(true)
                }
            }
        }
        .focusSection()
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
