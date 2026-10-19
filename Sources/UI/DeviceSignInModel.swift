import Foundation
import Observation

@MainActor
@Observable
final class DeviceSignInModel {
    enum State: Equatable { case idle, starting, waiting, paused, complete, failed(String) }
    private(set) var state: State = .idle
    private(set) var challenge: DeviceChallenge?
    private(set) var manualURL: URL?
    private(set) var completeURL: URL?
    private(set) var expiresAt: Date?
    private(set) var statusMessage = ""
    private let connection: ConnectionStore
    private let now: () -> Date
    private let sleep: (TimeInterval) async throws -> Void
    private let onSuccess: () -> Void
    private var task: Task<Void, Never>?
    private var attempt = UUID()
    private var interval: TimeInterval = 5
    private var expectedGeneration: UUID?
    private var challengeClient: FiestaClient?

    init(connection: ConnectionStore, now: @escaping () -> Date = Date.init,
         sleep: @escaping (TimeInterval) async throws -> Void = { seconds in
             try await Task.sleep(for: .seconds(seconds))
         }, onSuccess: @escaping () -> Void) {
        self.connection = connection; self.now = now; self.sleep = sleep; self.onSuccess = onSuccess
    }

    func start() {
        cancel()
        guard connection.deviceSignInEnabled, let client = connection.client else {
            fail(DevicePollError(code: "feature_disabled").userMessage); return
        }
        state = .starting; statusMessage = "Creating your code…"
        let attempt = self.attempt
        let generation = connection.connectionGeneration
        expectedGeneration = generation
        challengeClient = client
        task = Task {
            do {
                let challenge = try await client.beginDeviceSignIn(deviceName: "Apple TV", appVersion: ConnectionStore.appVersion)
                guard isCurrent(attempt, generation) else {
                    Task { try? await client.cancelDeviceSignIn(deviceCode: challenge.deviceCode) }
                    return
                }
                let urls = try challenge.verificationURLs(baseURL: client.baseURL)
                self.challenge = challenge; manualURL = urls.manual; completeURL = urls.complete
                expiresAt = now().addingTimeInterval(min(600, challenge.expiresIn))
                interval = max(5, challenge.interval)
                state = .waiting
                Announce.say("Sign-in code ready: \(challenge.userCode.map(String.init).joined(separator: " ")). Waiting for approval in your browser.")
                statusMessage = DevicePollError(code: "authorization_pending").userMessage
                await poll(client: client, attempt: attempt, generation: generation)
            } catch { if isCurrent(attempt, generation) { fail(message(error)) } }
        }
    }

    func pause() {
        task?.cancel(); task = nil
        if state == .waiting || state == .starting { state = .paused }
    }
    func resume() {
        guard state == .paused else { return }
        guard let expiry = expiresAt, expiry > now() else {
            if challenge == nil { start() }
            else { fail(DevicePollError(code: "expired_token").userMessage) }
            return
        }
        guard let client = challengeClient, let generation = expectedGeneration,
              generation == connection.connectionGeneration else { cancel(); return }
        state = .waiting
        let attempt = self.attempt
        task = Task { await poll(client: client, attempt: attempt, generation: generation) }
    }
    func cancel() {
        let completed = state == .complete
        attempt = UUID(); task?.cancel(); task = nil
        if let challenge, let client = challengeClient {
            Task { try? await client.cancelDeviceSignIn(deviceCode: challenge.deviceCode) }
        }
        if !completed { connection.invalidatePendingSignIn() }
        challenge = nil; manualURL = nil; completeURL = nil; expiresAt = nil
        challengeClient = nil; expectedGeneration = nil
        state = .idle
    }
    private func isCurrent(_ attempt: UUID, _ generation: UUID) -> Bool {
        !Task.isCancelled && self.attempt == attempt && connection.connectionGeneration == generation
    }
    private func poll(client: FiestaClient, attempt: UUID, generation: UUID) async {
        var backoff: TimeInterval = interval
        while isCurrent(attempt, generation), let challenge, let expiry = expiresAt {
            if now() >= expiry { fail(DevicePollError(code: "expired_token").userMessage); return }
            do {
                try await sleep(min(backoff, max(0, expiry.timeIntervalSince(now()))))
                guard isCurrent(attempt, generation) else { return }
                guard now() < expiry else { fail(DevicePollError(code: "expired_token").userMessage); return }
                let result = try await client.pollDeviceSignIn(deviceCode: challenge.deviceCode)
                // Adoption also owns orphan revocation for a response that
                // arrives after cancellation or a host switch.
                try await connection.adoptDeviceCredential(result, expectedGeneration: generation, issuingClient: client)
                guard isCurrent(attempt, generation) else { return }
                self.challenge = nil; manualURL = nil; completeURL = nil; expiresAt = nil
                state = .complete; statusMessage = "Signed in."
                Announce.say(statusMessage)
                onSuccess(); return
            } catch {
                guard isCurrent(attempt, generation) else { return }
                if let error = error as? DevicePollError {
                    switch error.code {
                    case "authorization_pending": backoff = interval
                    case "slow_down": interval += 5; backoff = interval
                    default:
                        if error.status == 429 { backoff = max(interval, error.retryAfter ?? 30) }
                        else { fail(error.userMessage); return }
                    }
                    statusMessage = error.userMessage
                } else if let error = error as? FiestaError,
                          error == .unavailable || { if case .transport = error { return true }; return false }() {
                    statusMessage = error.userMessage + " Retrying…"
                    backoff = min(30, max(interval, backoff * 2))
                } else { fail(message(error)); return }
            }
        }
    }
    private func fail(_ message: String) {
        if let challenge, let client = challengeClient {
            Task { try? await client.cancelDeviceSignIn(deviceCode: challenge.deviceCode) }
        }
        challenge = nil; manualURL = nil; completeURL = nil; expiresAt = nil
        state = .failed(message); statusMessage = message; Announce.say(message)
    }
    private func message(_ error: Error) -> String {
        if let error = error as? DevicePollError { return error.userMessage }
        if let error = error as? DeviceCredentialError { return error.userMessage }
        return (error as? FiestaError)?.userMessage ?? "Couldn't complete sign-in. Try again."
    }
}
