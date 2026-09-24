import SwiftUI

/// Choosing a board, built the way tvOS presents a set of things to pick.
///
/// The boards found on the network are content: a row of cards, with the
/// platform's own focus treatment. Typing an address is the fallback for a
/// board Bonjour cannot see, so it sits below in plain system controls
/// rather than as a third amber slab competing with the list.
struct ConnectScreen: View {
    @Environment(AppModel.self) private var app
    @State private var model: ConnectModel?

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
            Task { await model?.startScan() }
        }
        .onDisappear { model?.stopScan() }
    }

    // MARK: Pieces

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Find your FiestaBoard")
                .font(.system(size: 56, weight: .bold))
                .foregroundStyle(Fiesta.Colors.foreground)

            if !(model?.boards.isEmpty ?? true) {
                Text("Choose the board this Apple TV should show.")
                    .font(Fiesta.Text.caption)
                    .foregroundStyle(Fiesta.Colors.mutedForeground)
            }
        }
    }

    /// Every failure on this screen surfaces here, in the same place and the
    /// same destructive colour — whether it came from the connect attempt or
    /// from the app (a board that still needs its first account).
    @ViewBuilder
    private var errorBanner: some View {
        if let message = app.errorMessage ?? model?.errorMessage {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(Fiesta.Text.caption)
                .foregroundStyle(Fiesta.Colors.destructive)
                .accessibilityLabel("Problem connecting. \(message)")
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
                        card(for: board, among: found)
                    }
                }
                // Cards lift on focus; without room inside the scroll view
                // the lift is clipped at the edges.
                .padding(.vertical, 36)
                .padding(.horizontal, 16)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private static let columns = [GridItem(.adaptive(minimum: 400), spacing: 40, alignment: .topLeading)]

    private func card(for board: DiscoveredBoard, among found: [DiscoveredBoard]) -> some View {
        DiscoveredBoardCard(board: board,
                            address: BoardAddressLabel.text(for: board, among: found)) {
            Task { await model?.connect(to: board.host, name: board.name) }
        }
    }

    /// Nothing found yet. Scanning is normal, so it is said in words next to
    /// the spinner and in muted foreground — never in the error colour.
    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 16) {
            if model?.isScanning ?? true {
                ProgressView()
                    .tint(Fiesta.Colors.brand)
                    .accessibilityHidden(true)
                Text("Looking for FiestaBoards on this network…")
                    .font(Fiesta.Text.body)
                    .foregroundStyle(Fiesta.Colors.foreground)
                Text("This takes a few seconds. Your board needs to be powered on and on the same network as this Apple TV.")
                    .font(Fiesta.Text.caption)
                    .foregroundStyle(Fiesta.Colors.mutedForeground)
            } else {
                Text("No FiestaBoards found")
                    .font(Fiesta.Text.body)
                    .foregroundStyle(Fiesta.Colors.foreground)
                Text("Enter your board's address below to connect to it directly.")
                    .font(Fiesta.Text.caption)
                    .foregroundStyle(Fiesta.Colors.mutedForeground)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: 900)
        .accessibilityElement(children: .combine)
    }

    /// The secondary path: a quiet label, a stock text field and a stock
    /// button, so it reads as the way out rather than as a peer of the list.
    private var manualEntry: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Or enter the address")
                .font(Fiesta.Text.caption)
                .foregroundStyle(Fiesta.Colors.mutedForeground)

            HStack(spacing: 20) {
                TextField("192.168.1.50", text: manualAddressBinding)
                    .textContentType(.URL)
                    .autocorrectionDisabled()
                    .frame(maxWidth: 560)
                    .accessibilityLabel("FiestaBoard address")

                Button("Connect") { Task { await model?.connectManually() } }
                    .accessibilityLabel("Connect to the address you entered")
            }
        }
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
