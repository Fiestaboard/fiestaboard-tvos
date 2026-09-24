import SwiftUI
import Observation

@MainActor
@Observable
final class SignInModel {
    var username = ""
    var password = ""
    var errorMessage: String?
    var isSubmitting = false

    private let app: AppModel

    init(app: AppModel) { self.app = app }

    func useAnotherBoard() { app.disconnect() }

    /// What Menu does here.
    ///
    /// Sign in is never the root — it is reached from Connect, and at launch
    /// when a saved session has lapsed — so it has to handle the exit
    /// command or tvOS quits the app. Back goes to choosing a board, which
    /// is the screen behind it in both cases. It deliberately does *not*
    /// forget the board the way "Use another board" does: a Menu press is a
    /// reflex, and losing the saved connection to one would be a surprise.
    func back() { app.route = .connect }

    func submit() async {
        guard !isSubmitting else { return }
        guard !username.isEmpty, !password.isEmpty else {
            errorMessage = "Enter your username and password."
            return
        }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        do {
            try await app.connection.signIn(username: username, password: password)
            app.route = .panels
        } catch FiestaError.unauthorized {
            errorMessage = "That username or password didn't work."
        } catch let error as FiestaError {
            // A lockout in particular must not read as a wrong password —
            // the board is refusing to even consider one for a minute.
            errorMessage = error.userMessage
        } catch {
            errorMessage = FiestaError.transport("\(error)").userMessage
        }
    }
}

/// Signing in, built like a tvOS settings screen: a grouped `List` of
/// `Section`s with stock fields and buttons. Explanatory copy lives in the
/// section footers, where the platform puts it, rather than as loose text
/// stacked between controls.
struct SignInScreen: View {
    @Environment(AppModel.self) private var app
    @State private var model: SignInModel?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            List {
                errorSection
                credentialsSection
                submitSection
                anotherBoardSection
            }
            .listStyle(.grouped)
        }
        // Not the root: without this, Menu falls through to the system and
        // quits the app. See `SignInModel.back()`.
        .onExitCommand { model?.back() }
        .onAppear { if model == nil { model = SignInModel(app: app) } }
    }

    private var boardName: String {
        app.connection.saved?.displayName ?? "FiestaBoard"
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Sign in")
                .font(.system(size: 56, weight: .bold))
                .foregroundStyle(Fiesta.Colors.foreground)
            Text(boardName)
                .font(Fiesta.Text.caption)
                .foregroundStyle(Fiesta.Colors.mutedForeground)
        }
        .padding(.horizontal, Fiesta.Metrics.safeInset)
        .padding(.top, Fiesta.Metrics.safeInset)
        .padding(.bottom, 12)
    }

    // MARK: Sections

    /// One place for failures, in the error colour, above the fields.
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

            SecureField("Password", text: passwordBinding)
                .textContentType(.password)
                .accessibilityLabel("Password")
        } header: {
            Text("Your FiestaBoard account")
        } footer: {
            // Said plainly because it is a real commitment: the credential is
            // kept so a lapsed session never sends anyone back to a remote.
            Text("Your sign-in is stored on this Apple TV so it stays connected.")
        }
    }

    private var submitSection: some View {
        Section {
            Button("Sign in") { Task { await model?.submit() } }
                .accessibilityLabel("Sign in to \(boardName)")
        } footer: {
            if model?.isSubmitting ?? false {
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
                set: { model?.username = $0 })
    }

    private var passwordBinding: Binding<String> {
        Binding(get: { model?.password ?? "" },
                set: { model?.password = $0 })
    }
}
