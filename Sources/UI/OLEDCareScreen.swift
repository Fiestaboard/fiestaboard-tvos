import SwiftUI

/// A8b (`248:110205`): OLED care as one page of summary rows in two columns,
/// each opening its own page. Every edit is local to this Apple TV.
///
/// DD23 removed the OLED yes/no question, the live preview (the TV is the
/// preview), the burn-in disclaimer (now one sentence on About › Screen
/// protection) and Done. DD10 keeps two one-line caveats under the rows.
struct OLEDCareScreen: View {
    @Environment(AppModel.self) private var app

    static let subtitle = "Keeps the board bright where it matters and gives the panel rest so it doesn’t burn in."
    static let keepAwakeCaveat = "Keep-awake: this Apple TV stays on while a board is showing; only Rest (scheduled or disconnected) lets it sleep."
    static let disconnectedCaveat = "When disconnected = the hub can’t be reached: keep the last frame, dim, or rest after the delay. A remote press resumes for 5 min."
    /// Movement choices (07b G9 9b `278:138887`; TV wrap-up S-T4).
    static let movementGentleSubtitle = "Shifts the board a few pixels over 20 min"
    static let movementWiderSubtitle = "Larger shifts for long, static days"
    static let movementFooter = "Reduce Motion pauses movement."

    var body: some View {
        let summary = OLEDCareSummary(app.oledCare, neverDim: false)
        VStack(alignment: .leading, spacing: 0) {
            OLEDCareHeader(title: "OLED care")
            Text(Self.subtitle)
                .font(Fiesta.Text.body)
                .foregroundStyle(Fiesta.Colors.mutedForeground)
                .padding(.top, 16)
            HStack(alignment: .top, spacing: 40) {
                List {
                    row("Board brightness", summary.brightness, id: "oled.brightness", route: .brightness)
                    row("Movement", summary.movement, id: "oled.movement", route: .movement)
                    row("Night dimming", summary.night, id: "oled.night", route: .night)
                    row("Scheduled rest", summary.rest, id: "oled.rest", route: .rest)
                }
                List {
                    row("Periodic breaks", summary.breaks, id: "oled.breaks", route: .breaks)
                    row("Layout rotation", summary.rotation, id: "oled.rotation", route: .rotation)
                    row("When disconnected", summary.disconnected, id: "oled.disconnected", route: .disconnected)
                    row("Allow Apple TV screen saver", summary.screensaver, id: "oled.screensaver", route: .screensaver)
                }
            }
            .listStyle(.grouped)
            .scrollClipDisabled()
            .frame(height: 440)
            .padding(.top, 40)
            VStack(alignment: .leading, spacing: 12) {
                Text(Self.keepAwakeCaveat)
                Text(Self.disconnectedCaveat)
            }
            .font(Fiesta.Text.caption)
            .foregroundStyle(Fiesta.Colors.mutedForeground)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Fiesta.Colors.background)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            // Opening OLED care is the answer to the optional invitation.
            guard !app.oledCare.invitationDismissed else { return }
            var c = app.oledCare; c.invitationDismissed = true; app.saveOLEDCare(c)
        }
    }

    private func row(_ title: String, _ value: String, id: String, route: OLEDRoute) -> some View {
        NavigationLink(value: SettingsScreen.Destination.oled(route)) {
            HStack {
                Text(title).lineLimit(1)
                Spacer()
                Text(value).interactiveSecondaryForeground().lineLimit(1)
            }
        }
        .accessibilityIdentifier(id)
        .accessibilityLabel(title)
        .accessibilityValue(value)
    }
}

/// The OLED care pages' heading: "<hub> · Only this Apple TV" over the title.
struct OLEDCareHeader: View {
    @Environment(AppModel.self) private var app
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(app.connection.saved?.displayName ?? "Hub") · Only this Apple TV")
                .font(Fiesta.Text.caption1)
                .foregroundStyle(Fiesta.Colors.brand)
            Text(title)
                .font(Fiesta.Text.title)
                .foregroundStyle(Fiesta.Colors.foreground)
                .accessibilityAddTraits(.isHeader)
        }
        .padding(.top, 30)
    }
}

/// A8b·1 (`279:139039`): night dimming, which lives only here (DD17).
struct NightDimmingScreen: View {
    @Environment(AppModel.self) private var app

    static let footer = "Night dim level multiplies the board brightness. It is also used when disconnected › Dim."

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            OLEDCareHeader(title: "Night dimming")
            List {
                Section {
                    mode(.followPanel, "Follow panel", detail: "Uses the shared schedule set on your phone")
                    mode(.never, "Never", detail: nil)
                    mode(.custom, "Custom", detail: "Only this TV")
                }
                Section {
                    if app.oledCare.nightMode == .custom {
                        OLEDTimeRow(field: .nightStart)
                        OLEDTimeRow(field: .nightEnd)
                    }
                    NavigationLink(value: SettingsScreen.Destination.oled(.nightDimLevel)) {
                        LabeledContent("Night dim level", value: "\(app.oledCare.nightLevel) %")
                    }
                } header: {
                    if app.oledCare.nightMode == .custom {
                        Text("Custom schedule · Only this Apple TV").foregroundStyle(Fiesta.Colors.mutedForeground)
                    }
                } footer: {
                    Text(Self.footer).foregroundStyle(Fiesta.Colors.mutedForeground)
                }
            }
            .listStyle(.grouped)
            .scrollClipDisabled()
            .frame(width: 1200)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Fiesta.Colors.background)
        .toolbar(.hidden, for: .navigationBar)
    }

    private func mode(_ value: OLEDNightMode, _ title: String, detail: String?) -> some View {
        Button {
            var c = app.oledCare; c.nightMode = value; app.saveOLEDCare(c)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                    if let detail { Text(detail).font(Fiesta.Text.caption).interactiveSecondaryForeground() }
                }
                Spacer()
                if app.oledCare.nightMode == value { Image(systemName: "checkmark") }
            }
        }
        .accessibilityLabel(title)
        .accessibilityValue(app.oledCare.nightMode == value ? "Selected" : "")
    }
}

/// One choice from a list; picking it saves and goes back.
struct OLEDChoicePage<Value: Hashable>: View {
    @Environment(AppModel.self) private var app
    @Environment(\.settingsBack) private var goBack
    let title: String
    let options: [(Value, String)]
    let key: WritableKeyPath<OLEDCareConfiguration, Value>
    var footer: String? = nil

    var body: some View {
        List {
            Section {
                ForEach(options.indices, id: \.self) { index in
                    let option = options[index]
                    Button {
                        var c = app.oledCare; c[keyPath: key] = option.0; app.saveOLEDCare(c)
                        goBack()
                    } label: {
                        HStack { Text(option.1); Spacer(); if app.oledCare[keyPath: key] == option.0 { Image(systemName: "checkmark") } }
                    }
                    .accessibilityLabel(option.1)
                    .accessibilityValue(app.oledCare[keyPath: key] == option.0 ? "Selected" : "")
                }
            } footer: {
                if let footer { Text(footer).foregroundStyle(Fiesta.Colors.mutedForeground) }
            }
        }
        .listStyle(.grouped)
        .navigationTitle(title)
    }
}

/// A 12-hour time on this TV's clock (CANON), chosen by hour and minute.
struct OLEDTimeRow: View {
    @Environment(AppModel.self) private var app
    let field: OLEDTimeField

    var body: some View {
        NavigationLink(value: SettingsScreen.Destination.oled(.time(field))) {
            LabeledContent(field.title, value: Clock12.label(minutes: app.oledCare[keyPath: field.key]))
        }
    }
}

private struct OLEDTimeEditor: View {
    @Environment(AppModel.self) private var app
    let field: OLEDTimeField

    var body: some View {
        List {
            NavigationLink(value: SettingsScreen.Destination.oled(.hour(field))) {
                LabeledContent("Hour", value: Clock12.label(minutes: app.oledCare[keyPath: field.key] / 60 * 60))
            }
            .accessibilityIdentifier("oled.time.hour")
            .accessibilityLabel("Hour")
            .accessibilityValue(Clock12.label(minutes: app.oledCare[keyPath: field.key] / 60 * 60))
            NavigationLink(value: SettingsScreen.Destination.oled(.minute(field))) {
                LabeledContent("Minute", value: String(format: ":%02d", app.oledCare[keyPath: field.key] % 60))
            }
            .accessibilityIdentifier("oled.time.minute")
            .accessibilityLabel("Minute")
            .accessibilityValue(String(format: ":%02d", app.oledCare[keyPath: field.key] % 60))
        }
        .navigationTitle(field.title)
    }
}

/// A native vertical choice list keeps every hour and AM/PM readable.
/// Default Picker presentation laid all 24 hours out as narrow segments.
private struct OLEDTimeChoices: View {
    @Environment(\.settingsBack) private var goBack
    let title: String
    let options: [(Int, String)]
    @Binding var selection: Int
    @FocusState private var focusedChoice: Int?

    var body: some View {
        ScrollViewReader { scroll in
            List {
                ForEach(options, id: \.0) { option in
                    Button {
                        selection = option.0
                        goBack()
                    } label: {
                        HStack {
                            Text(option.1).lineLimit(1)
                            Spacer()
                            if selection == option.0 { Image(systemName: "checkmark") }
                        }
                    }
                    .accessibilityLabel(option.1)
                    .accessibilityValue(selection == option.0 ? "Selected" : "")
                    .focused($focusedChoice, equals: option.0)
                    .id(option.0)
                }
            }
            .listStyle(.grouped)
            .defaultFocus($focusedChoice, selection)
            .task {
                scroll.scrollTo(selection, anchor: .center)
                focusedChoice = selection
            }
        }
        .navigationTitle(title)
    }
}

private struct OLEDMovementPage: View {
    @Environment(AppModel.self) private var app
    @Environment(\.settingsBack) private var goBack

    var body: some View {
        List {
            Section {
                choice("Off", selected: !app.oledCare.movement) { $0.movement = false }
                choice("Gentle", subtitle: OLEDCareScreen.movementGentleSubtitle,
                       selected: app.oledCare.movement && app.oledCare.movementRange <= 8) { $0.movement = true; $0.movementRange = 8 }
                choice("Wider", subtitle: OLEDCareScreen.movementWiderSubtitle,
                       selected: app.oledCare.movement && app.oledCare.movementRange > 8) { $0.movement = true; $0.movementRange = 24 }
            } footer: {
                Text(OLEDCareScreen.movementFooter)
                    .foregroundStyle(Fiesta.Colors.mutedForeground)
            }
        }
        .listStyle(.grouped)
        .navigationTitle("Movement")
    }

    private func choice(_ title: String, subtitle: String? = nil, selected: Bool,
                        apply: @escaping (inout OLEDCareConfiguration) -> Void) -> some View {
        Button {
            var c = app.oledCare; apply(&c); app.saveOLEDCare(c); goBack()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                    if let subtitle {
                        Text(subtitle)
                            .font(Fiesta.Text.caption)
                            .interactiveSecondaryForeground()
                    }
                }
                Spacer()
                if selected { Image(systemName: "checkmark") }
            }
        }
        .accessibilityLabel(title)
        .accessibilityValue(selected ? "Selected" : "")
        .accessibilityHint(subtitle ?? "")
    }
}

private struct OLEDRestPage: View {
    @Environment(AppModel.self) private var app
    var body: some View {
        List {
            Section {
                Toggle("Rest on a daily schedule", isOn: OLEDBinding(app: app, key: \.restEnabled).binding)
                OLEDTimeRow(field: .restStart)
                OLEDTimeRow(field: .restEnd)
            } footer: {
                Text("Shows full black, not standby, and lets this Apple TV sleep. A remote press resumes viewing for 5 minutes. Equal times turn rest off.")
                    .foregroundStyle(Fiesta.Colors.mutedForeground)
            }
        }
        .listStyle(.grouped)
        .navigationTitle("Scheduled rest")
    }
}

private struct OLEDBreaksPage: View {
    @Environment(AppModel.self) private var app
    var body: some View {
        List {
            Section {
                Toggle("Take periodic breaks", isOn: OLEDBinding(app: app, key: \.breaksEnabled).binding)
                Picker("Break every", selection: OLEDBinding(app: app, key: \.breakInterval).binding) {
                    ForEach([30, 60, 120], id: \.self) { Text("\($0) min").tag($0) }
                }
                Picker("Break for", selection: OLEDBinding(app: app, key: \.breakDuration).binding) {
                    ForEach([1, 5, 10], id: \.self) { Text("\($0) min").tag($0) }
                }
            } footer: {
                Text("Counts time spent viewing. A remote press ends a break and starts a new interval.")
                    .foregroundStyle(Fiesta.Colors.mutedForeground)
            }
        }
        .listStyle(.grouped)
        .navigationTitle("Periodic breaks")
    }
}

private struct OLEDRotationPage: View {
    @Environment(AppModel.self) private var app
    var body: some View {
        List {
            Section {
                Toggle("Rotate the board's position", isOn: OLEDBinding(app: app, key: \.rotationEnabled).binding)
                ForEach(OLEDPlacement.allCases, id: \.self) { position in
                    Toggle(Self.label(position), isOn: Binding(get: { app.oledCare.placements.contains(position) }, set: { enabled in
                        var c = app.oledCare
                        c.placements.removeAll { $0 == position }
                        if enabled { c.placements.append(position) }
                        app.saveOLEDCare(c)
                    }))
                }
                Picker("Change position every", selection: OLEDBinding(app: app, key: \.rotationInterval).binding) {
                    ForEach([1, 5, 15], id: \.self) { Text("\($0) min").tag($0) }
                }
                if app.oledCare.placements.count < 2 { Text("Select at least two positions to rotate.") }
            } footer: {
                Text("Shrinks the same live board to 80% and moves it between the positions you choose.")
                    .foregroundStyle(Fiesta.Colors.mutedForeground)
            }
        }
        .listStyle(.grouped)
        .navigationTitle("Layout rotation")
    }

    private static func label(_ position: OLEDPlacement) -> String {
        switch position {
        case .center: return "Center"
        case .upperLeft: return "Upper left"
        case .upperRight: return "Upper right"
        case .lowerLeft: return "Lower left"
        case .lowerRight: return "Lower right"
        }
    }
}

private struct OLEDDisconnectedPage: View {
    @Environment(AppModel.self) private var app
    var body: some View {
        List {
            Section {
                Picker("When disconnected", selection: OLEDBinding(app: app, key: \.disconnected).binding) {
                    Text("Keep last frame").tag(OLEDDisconnect.keep)
                    Text("Dim after delay").tag(OLEDDisconnect.dim)
                    Text("Rest after delay").tag(OLEDDisconnect.rest)
                }
                Picker("After", selection: OLEDBinding(app: app, key: \.disconnectDelay).binding) {
                    ForEach([1, 5, 15], id: \.self) { Text("\($0) min").tag($0) }
                }
            } footer: {
                Text(OLEDCareScreen.disconnectedCaveat).foregroundStyle(Fiesta.Colors.mutedForeground)
            }
        }
        .listStyle(.grouped)
        .navigationTitle("When disconnected")
    }
}

/// A binding that saves each change to this TV's OLED care.
private struct OLEDBinding<T> {
    let app: AppModel
    let key: WritableKeyPath<OLEDCareConfiguration, T>
    @MainActor var binding: Binding<T> {
        Binding(get: { app.oledCare[keyPath: key] }, set: { value in
            var c = app.oledCare; c[keyPath: key] = value; app.saveOLEDCare(c)
        })
    }
}

/// All OLED levels share Settings' typed path. Selection and Menu each pop
/// exactly one recorded level, including consecutive input during animation.
enum OLEDRoute: Hashable {
    case brightness, movement, night, nightDimLevel, rest, breaks, rotation, disconnected, screensaver
    case time(OLEDTimeField), hour(OLEDTimeField), minute(OLEDTimeField)

    @MainActor @ViewBuilder func destination(app: AppModel) -> some View {
        switch self {
        case .brightness:
            OLEDChoicePage(title: "Board brightness", options: [25, 50, 75, 100].map { ($0, "\($0) %") }, key: \.brightness,
                           footer: "Scales the app’s output, not the TV’s own brightness.")
        case .movement: OLEDMovementPage()
        case .night: NightDimmingScreen()
        case .nightDimLevel:
            OLEDChoicePage(title: "Night dim level", options: [10, 25, 35, 50].map { ($0, "\($0) %") }, key: \.nightLevel,
                           footer: NightDimmingScreen.footer)
        case .rest: OLEDRestPage()
        case .breaks: OLEDBreaksPage()
        case .rotation: OLEDRotationPage()
        case .disconnected: OLEDDisconnectedPage()
        case .screensaver:
            OLEDChoicePage(title: "Allow Apple TV screen saver", options: [(false, "Off"), (true, "On")], key: \.allowScreensaver,
                           footer: "Apple TV’s own settings control the screen saver’s timing.")
        case .time(let field): OLEDTimeEditor(field: field)
        case .hour(let field):
            OLEDTimeChoices(title: "Hour", options: (0..<24).map { ($0, Clock12.label(minutes: $0 * 60)) },
                            selection: field.component(app: app, hour: true))
        case .minute(let field):
            OLEDTimeChoices(title: "Minute", options: stride(from: 0, to: 60, by: 5).map { ($0, String(format: ":%02d", $0)) },
                            selection: field.component(app: app, hour: false))
        }
    }
}

enum OLEDTimeField: Hashable {
    case nightStart, nightEnd, restStart, restEnd

    var title: String {
        switch self {
        case .nightStart: return "Night starts"
        case .nightEnd: return "Night ends"
        case .restStart: return "Rest starts"
        case .restEnd: return "Rest ends"
        }
    }
    var key: WritableKeyPath<OLEDCareConfiguration, Int> {
        switch self {
        case .nightStart: return \.nightStart
        case .nightEnd: return \.nightEnd
        case .restStart: return \.restStart
        case .restEnd: return \.restEnd
        }
    }
    @MainActor func component(app: AppModel, hour: Bool) -> Binding<Int> {
        Binding(get: {
            let value = app.oledCare[keyPath: key]
            return hour ? value / 60 : value % 60
        }, set: { value in
            var configuration = app.oledCare
            let previous = configuration[keyPath: key]
            configuration[keyPath: key] = hour ? value * 60 + previous % 60 : previous / 60 * 60 + value
            app.saveOLEDCare(configuration)
        })
    }
}

extension EnvironmentValues {
    @Entry var settingsBack: () -> Void = {}
}
