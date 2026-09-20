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
        } catch {
            errorMessage = "Couldn't reach your FiestaBoard. Check it's still on."
        }
    }
}

struct SignInScreen: View {
    @Environment(AppModel.self) private var app
    @State private var model: SignInModel?

    var body: some View {
        VStack(alignment: .leading, spacing: Fiesta.Metrics.gutter) {
            Text("Sign in").font(Fiesta.Text.title)
                .foregroundStyle(Fiesta.Colors.foreground)

            Text(app.connection.saved?.displayName ?? "FiestaBoard")
                .font(Fiesta.Text.body)
                .foregroundStyle(Fiesta.Colors.mutedForeground)

            TextField("Username", text: Binding(
                get: { model?.username ?? "" }, set: { model?.username = $0 }))
                .textContentType(.username)
                .autocorrectionDisabled()

            SecureField("Password", text: Binding(
                get: { model?.password ?? "" }, set: { model?.password = $0 }))
                .textContentType(.password)

            if let message = model?.errorMessage {
                Text(message).font(Fiesta.Text.caption)
                    .foregroundStyle(Fiesta.Colors.destructive)
            }

            // Said plainly because it is a real commitment: the credential is
            // kept so a lapsed session never sends anyone back to a remote.
            Text("Your sign-in is stored on this Apple TV so it stays connected.")
                .font(Fiesta.Text.caption)
                .foregroundStyle(Fiesta.Colors.mutedForeground)

            FiestaButton("Sign in") { Task { await model?.submit() } }
            FiestaButton("Use another board") { model?.useAnotherBoard() }
        }
        .padding(Fiesta.Metrics.safeInset)
        .frame(maxWidth: 900, alignment: .leading)
        .onAppear { if model == nil { model = SignInModel(app: app) } }
    }
}
