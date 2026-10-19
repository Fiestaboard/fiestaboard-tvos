import SwiftUI
import Observation

@MainActor
@Observable
final class SignInModel {
    var username = ""
    var password = ""
    private(set) var errorMessage: String?
    private(set) var isSubmitting = false

    private let app: AppModel
    private var submissionGeneration = UUID()

    init(app: AppModel) { self.app = app }

    func useAnotherBoard() {
        submissionGeneration = UUID()
        app.disconnect()
    }

    /// What Menu does here.
    ///
    /// Sign in is never the root — it is reached from Connect, and at launch
    /// when a saved session has lapsed — so it has to handle the exit
    /// command or tvOS quits the app. Back goes to choosing a board, which
    /// is the screen behind it in both cases. It deliberately does *not*
    /// forget the board the way "Use another board" does: a Menu press is a
    /// reflex, and losing the saved connection to one would be a surprise.
    func back() {
        submissionGeneration = UUID()
        app.connection.invalidatePendingSignIn()
        app.route = .connect
    }

    // MARK: Editing

    /// Editing clears the last failure.
    ///
    /// The message is a verdict on the credential that was just refused.
    /// Leaving it above the fields while someone types a new one means the
    /// screen — and VoiceOver, reading down the list — contradicts the thing
    /// the user is in the middle of fixing.
    func setUsername(_ value: String) {
        username = value
        clearError()
    }

    func setPassword(_ value: String) {
        password = value
        clearError()
    }

    private func clearError() {
        // @Observable notifies on every set, not only on a change, and this
        // runs once per character from the on-screen keyboard. Only touch it
        // when there is something to clear.
        if errorMessage != nil { errorMessage = nil }
    }

    // MARK: Submitting

    func submit() async {
        guard !isSubmitting else { return }

        // Trim the username, never the password.
        //
        // The board refuses to create a username with leading or trailing
        // whitespace at all (`_validate_username` in the server's auth
        // service), so a stray space off the on-screen keyboard can only
        // ever produce "that didn't work" — and the way that reads to
        // someone holding a remote is "retype the password". Two of those
        // and the board's ten-failures-a-minute lockout takes over. The same
        // trim keeps a stray newline out of the credential the keychain
        // stores.
        let name = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !password.isEmpty else {
            fail("Enter your username and password.")
            return
        }
        username = name

        isSubmitting = true
        clearError()
        // Otherwise a sign-in against a board that has gone quiet is up to
        // twenty seconds of a screen that never acknowledged the press.
        Announce.say("Signing in…")
        let generation = submissionGeneration
        defer { isSubmitting = false }
        do {
            try await app.connection.signIn(username: name, password: password)
            guard generation == submissionGeneration, !Task.isCancelled else { return }
            password = ""
            app.finishSignIn()
        } catch {
            guard generation == submissionGeneration, !Task.isCancelled,
                  !(error is CancellationError) else { return }
            if let error = error as? DeviceCredentialError {
                fail(error.userMessage)
            } else if let error = error as? DevicePollError {
                fail(error.userMessage)
            } else if let error = error as? FiestaError {
                fail(error == .unauthorized ? "That username or password didn't work." : error.userMessage)
            } else {
                fail(FiestaError.transport("\(error)").userMessage)
            }
        }
    }

    /// Record a failure and say it out loud — see
    /// `Announce.say(_:recordingIn:)`, whose argument this screen is the
    /// worked example of.
    ///
    /// Deliberately **not** accompanied by clearing `password`: retyping a
    /// password on a remote is punishing enough that it is worth leaving a
    /// wrong one on screen to be corrected.
    private func fail(_ message: String) {
        Announce.say(message, recordingIn: &errorMessage)
    }
}

/// Signing in, built like a tvOS settings screen: a grouped `List` of
/// `Section`s with stock fields and buttons. Explanatory copy lives in the
/// section footers, where the platform puts it, rather than as loose text
/// stacked between controls.
struct SignInScreen: View {
    @Environment(AppModel.self) private var app
    @State private var model: SignInModel?
    @State private var deviceSignInEnabled = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            List {
                errorSection
                if deviceSignInEnabled {
                    Section {
                        Button("Sign in with a phone or computer") { app.route = .deviceSignIn }
                            .accessibilityIdentifier("device-sign-in")
                    } footer: {
                        Text("Scan a QR code or enter a short code in your browser. You can also use username and password below.")
                    }
                }
                credentialsSection
                submitSection
                anotherBoardSection
            }
            .listStyle(.grouped)
            .frame(maxWidth: 1120)
            .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // Not the root: without this, Menu falls through to the system and
        // quits the app. See `SignInModel.back()`.
        .onExitCommand { model?.back() }
        .onAppear {
            if model == nil { model = SignInModel(app: app) }
            deviceSignInEnabled = app.connection.deviceSignInEnabled
        }
        .task {
            try? await app.connection.refreshSignInCapability()
            deviceSignInEnabled = app.connection.deviceSignInEnabled
        }
    }

    private var boardName: String {
        app.connection.saved?.displayName ?? "FiestaBoard"
    }

    /// Whether the password is about to cross the network in the clear.
    ///
    /// A FiestaBoard serves no TLS, so on a LAN this is true of every board
    /// and it is the ordinary case rather than the alarming one — which is
    /// why the disclosure below is a plain footer line and not a warning in
    /// amber. Nil `saved` claims nothing: we do not know the scheme.
    private var isUnencrypted: Bool {
        app.connection.saved?.host.scheme?.lowercased() == "http"
    }

    private var header: some View {
        FiestaScreenHeading(title: "Sign in", subtitle: "Use the account you created on your FiestaBoard.",
                            context: boardName)
        .padding(.horizontal, Fiesta.Metrics.safeInset)
        .padding(.top, Fiesta.Metrics.safeInset)
        .padding(.bottom, 12)
    }

    // MARK: Sections

    /// One place for failures, in the error colour, above the fields.
    ///
    /// Nothing here is focusable, so this is what a sighted user reads and
    /// `SignInModel.fail` is what everyone else hears. Both are needed.
    @ViewBuilder
    private var errorSection: some View {
        if let message = model?.errorMessage {
            Section {
                Text(message)
                    .foregroundStyle(Fiesta.Colors.destructive)
                    .accessibilityLabel("Sign-in problem. \(message)")
            }
        }
    }

    private var credentialsSection: some View {
        Section {
            TextField("Username", text: usernameBinding)
                .textContentType(.username)
                .autocorrectionDisabled()
                .accessibilityLabel("Username")

            // A real SecureField, and no show/hide toggle: a password
            // revealed on a sixty-five inch screen in a living room is a
            // worse default than the typing it saves.
            SecureField("Password", text: passwordBinding)
                .textContentType(.password)
                .accessibilityLabel("Password")
        } header: {
            Text("Your FiestaBoard account")
        } footer: {
            credentialsFooter
        }
    }

    /// Two facts about the password: where it is kept, and how it travels.
    ///
    /// Built as a named property rather than inline in the `Section` — a
    /// conditional inside a footer builder is exactly the shape that puts
    /// this file past the type checker's budget (see docs/tvos-design.md).
    private var credentialsFooter: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Said plainly because it is a real commitment: the credential is
            // kept so a lapsed session never sends anyone back to a remote.
            Text(deviceSignInEnabled ? "Only a revocable TV credential is stored in this Apple TV’s Keychain. Your account password is not saved." : "Your username and password are stored in this Apple TV’s Keychain for this server’s legacy sign-in.")

            if isUnencrypted {
                Text("The connection to this board isn't encrypted. That's normal for a device on your own network — it has no certificate to prove who it is — but anyone who can watch that network could read your password. Sign in only on a network you trust.")
            }
        }
        // One passage, not two rows to swipe through.
        .accessibilityElement(children: .combine)
    }

    private var submitSection: some View {
        Section {
            // Deliberately not `.disabled(isSubmitting)`. This button is the
            // focus owner at the moment it is pressed, and disabling the
            // focused control on tvOS moves focus off it and does not
            // reliably bring it back. `SignInModel.submit`'s `guard
            // !isSubmitting` is the re-entrancy guard instead.
            Button("Sign in") { Task { await model?.submit() } }
                .accessibilityLabel("Sign in to \(boardName)")
        } footer: {
            submitFooter
        }
    }

    @ViewBuilder
    private var submitFooter: some View {
        if model?.isSubmitting ?? false {
            HStack(spacing: 12) {
                ProgressView()
                    .tint(Fiesta.Colors.brand)
                    .accessibilityHidden(true)
                Text("Signing in…")
            }
        }
    }

    /// Secondary to signing in, and it throws the saved board away, so it
    /// sits in its own section below with a destructive role and a footer
    /// that says what it costs.
    private var anotherBoardSection: some View {
        Section {
            Button("Use another board", role: .destructive) { model?.useAnotherBoard() }
                .accessibilityLabel("Use another board")
        } footer: {
            Text("Forgets \(boardName) on this Apple TV and looks for another board.")
        }
    }

    // MARK: Bindings
    //
    // Explicit types, not inline `Binding(get:set:)` inside a Section — see
    // the build hazard in docs/tvos-design.md.

    private var usernameBinding: Binding<String> {
        Binding(get: { model?.username ?? "" },
                set: { model?.setUsername($0) })
    }

    private var passwordBinding: Binding<String> {
        Binding(get: { model?.password ?? "" },
                set: { model?.setPassword($0) })
    }
}
