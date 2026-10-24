import SwiftUI

/// Every edit is local and explicit; the OLED answer is informational only.
struct OLEDCareScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .top, spacing: 40) {
            VStack(alignment: .leading, spacing: 24) {
                Text("Preview — app output only").font(.headline)
                TimelineView(.periodic(from: .now, by: 1)) { time in
                    let offset = app.oledCare.movement && !reduceMotion
                        ? BoardDrift.offset(at: time.date, amplitude: Double(app.oledCare.movementRange)) : .zero
                    ZStack {
                        Color.black
                        Text("FIESTA\nBOARD").font(.system(size: 42, weight: .bold, design: .monospaced))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.white)
                            .opacity(Double(app.oledCare.brightness) / 100)
                            .offset(x: offset.x, y: offset.y)
                    }
                }
                .frame(height: 240)
                .accessibilityLabel("Brightness and movement preview")
                Text("These options may reduce OLED wear. They cannot guarantee burn-in prevention or override your TV's protections.")
                Text("Applies only to this Apple TV. You can change every option regardless of your answer.")
            }
            .font(.body)
            .frame(width: 450)
            .padding(.top, 30)
            .accessibilityElement(children: .combine)
            List {
                question
                brightnessAndMovement
                night
                scheduledRest
                breaks
                rotation
                disconnect
                Section {
                    Toggle("Allow system screensaver", isOn: binding(\.allowScreensaver))
                        .accessibilityIdentifier("oled.screensaver")
                } footer: {
                    Text("Device settings control screensaver timing. Rest releases the keep-awake request. System sleep may return to Home; automatic wake is not promised.")
                }
            }
            .listStyle(.grouped)
            .accessibilityIdentifier("oled.controls")
        }
        .padding(.horizontal, 60)
        .navigationTitle("OLED care")
    }

    private var question: some View {
        Section {
            ForEach([OLEDAnswer.yes, .no, .unsure, .skip], id: \.self) { answer in
                Button {
                    var c = app.oledCare; c.answer = answer; c.invitationDismissed = true
                    app.saveOLEDCare(c)
                } label: {
                    HStack { Text(answerLabel(answer)); Spacer(); if app.oledCare.answer == answer { Image(systemName: "checkmark") } }
                }
                .accessibilityLabel(answerLabel(answer))
                .accessibilityValue(app.oledCare.answer == answer ? "Selected" : "")
            }
        } header: { Text("Will you use this with an OLED TV?") }
        footer: { Text("Optional. Choosing Yes enables nothing. Configure only the options you want below.") }
    }
    private var brightnessAndMovement: some View {
        Section {
            numberChoice("How bright should the board be?", key: \.brightness, values: [25, 50, 75, 100], suffix: "%")
                .accessibilityIdentifier("oled.brightness")
            Toggle("Gently move the image?", isOn: binding(\.movement))
            numberChoice("Movement range", key: \.movementRange, values: [8, 24], suffix: " points")
        } header: { Text("Brightness & movement") }
        footer: { Text("Brightness scales app output, not TV hardware brightness. Gentle: 8 points; Wider: 24 points. Movement reserves a small inset and can reduce usable area. Reduce Motion pauses continuous movement.") }
    }
    private var night: some View {
        Section {
            Picker("When should night dimming apply?", selection: binding(\.nightMode)) {
                Text("Follow panel schedule").tag(OLEDNightMode.followPanel)
                Text("Never dim").tag(OLEDNightMode.never)
                Text("Custom schedule").tag(OLEDNightMode.custom)
            }
            if app.oledCare.nightMode == .custom {
                timeChoice("Night starts", key: \.nightStart)
                timeChoice("Night ends", key: \.nightEnd)
            }
            numberChoice("Night output level", key: \.nightLevel, values: [10, 25, 35, 50], suffix: "%")
        } header: { Text("Night dimming") }
        footer: { Text("Uses this TV's local time. Equal start and end disables a window. Night level multiplies board brightness. The panel's shared schedule is never edited here.") }
    }
    private var scheduledRest: some View {
        Section {
            Toggle("Rest on a daily schedule?", isOn: binding(\.restEnabled))
            timeChoice("Rest starts", key: \.restStart)
            timeChoice("Rest ends", key: \.restEnd)
        } header: { Text("Scheduled rest") }
        footer: { Text("Shows full black, not standby. Normal system sleep may follow. A remote press resumes viewing for 5 minutes. Equal times disable rest.") }
    }
    private var breaks: some View {
        Section {
            Toggle("Take periodic viewing breaks?", isOn: binding(\.breaksEnabled))
            numberChoice("Break every", key: \.breakInterval, values: [30, 60, 120], suffix: " minutes")
            numberChoice("Break duration", key: \.breakDuration, values: [1, 5, 10], suffix: " minutes")
        } header: { Text("Periodic breaks") }
        footer: { Text("Counts active foreground viewing. A remote press ends a break and starts a new interval. Leaving the app pauses the interval and ends an active break.") }
    }
    private var rotation: some View {
        Section {
            Toggle("Rotate the board's position?", isOn: binding(\.rotationEnabled))
            ForEach(OLEDPlacement.allCases, id: \.self) { position in
                Toggle(placementLabel(position), isOn: Binding(get: { app.oledCare.placements.contains(position) }, set: { enabled in
                    var c = app.oledCare
                    c.placements.removeAll { $0 == position }
                    if enabled { c.placements.append(position) }
                    app.saveOLEDCare(c)
                }))
            }
            numberChoice("Change position every", key: \.rotationInterval, values: [1, 5, 15], suffix: " minutes")
            if app.oledCare.placements.count < 2 { Text("Select at least two positions to rotate.") }
        } header: { Text("Board layout / position rotation") }
        footer: { Text("Compacts the same live board to 80% of available width and height, then changes its placement. Shared panel contents stay the same. Positions change without animated travel.") }
    }
    private var disconnect: some View {
        Section {
            Picker("When disconnected", selection: binding(\.disconnected)) {
                Text("Keep last frame").tag(OLEDDisconnect.keep)
                Text("Dim after delay").tag(OLEDDisconnect.dim)
                Text("Rest after delay").tag(OLEDDisconnect.rest)
            }
            numberChoice("Unavailable for", key: \.disconnectDelay, values: [1, 5, 15], suffix: " minutes")
        } header: { Text("Unavailable boards") }
        footer: { Text("Also applies while connecting or showing missing/deleted boards. Dimming uses the night level. Recovery resumes automatically; a remote press temporarily resumes for 5 minutes.") }
    }
    private func binding<T>(_ key: WritableKeyPath<OLEDCareConfiguration, T>) -> Binding<T> {
        Binding(get: { app.oledCare[keyPath: key] }, set: { value in
            var c = app.oledCare; c[keyPath: key] = value; app.saveOLEDCare(c)
        })
    }
    private func numberChoice(_ title: String, key: WritableKeyPath<OLEDCareConfiguration, Int>, values: [Int], suffix: String) -> some View {
        Picker(title, selection: binding(key)) {
            ForEach(values, id: \.self) { Text("\($0)\(suffix)").tag($0) }
        }
    }
    private func timeChoice(_ title: String, key: WritableKeyPath<OLEDCareConfiguration, Int>) -> some View {
        NavigationLink {
            List {
                Picker("Hour", selection: Binding(get: { app.oledCare[keyPath: key] / 60 }, set: { hour in
                    var c = app.oledCare; c[keyPath: key] = hour * 60 + c[keyPath: key] % 60; app.saveOLEDCare(c)
                })) { ForEach(0..<24, id: \.self) { Text(String(format: "%02d", $0)).tag($0) } }
                Picker("Minute", selection: Binding(get: { app.oledCare[keyPath: key] % 60 }, set: { minute in
                    var c = app.oledCare; c[keyPath: key] = c[keyPath: key] / 60 * 60 + minute; app.saveOLEDCare(c)
                })) { ForEach(0..<60, id: \.self) { Text(String(format: "%02d", $0)).tag($0) } }
            }.navigationTitle(title)
        } label: {
            LabeledContent(title, value: String(format: "%02d:%02d", app.oledCare[keyPath: key] / 60, app.oledCare[keyPath: key] % 60))
        }
    }
    private func answerLabel(_ answer: OLEDAnswer) -> String {
        switch answer { case .yes: return "Yes"; case .no: return "No"; case .unsure: return "Not sure"; default: return "Skip" }
    }
    private func placementLabel(_ position: OLEDPlacement) -> String {
        switch position { case .center: return "Center"; case .upperLeft: return "Upper left"; case .upperRight: return "Upper right"; case .lowerLeft: return "Lower left"; case .lowerRight: return "Lower right" }
    }
}
