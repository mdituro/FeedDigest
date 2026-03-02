import SwiftUI
import AuthenticationServices

struct AddMastodonAccountView: View {
    var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var instanceInput: String = ""
    @State private var isConnecting: Bool = false
    @State private var errorMessage: String?

    private let authSession = AuthSessionCoordinator()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Instance URL", text: $instanceInput, prompt: Text("mastodon.social"))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                } header: {
                    Text("Mastodon Instance")
                } footer: {
                    Text("Enter the domain name of your Mastodon instance, e.g. mastodon.social or fosstodon.org")
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }

                Section {
                    Button {
                        Task { await connect() }
                    } label: {
                        if isConnecting {
                            HStack {
                                ProgressView()
                                Text("Connecting…")
                            }
                        } else {
                            Text("Connect with OAuth")
                        }
                    }
                    .disabled(instanceInput.trimmingCharacters(in: .whitespaces).isEmpty || isConnecting)
                }
            }
            .navigationTitle("Add Mastodon")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func connect() async {
        isConnecting = true
        errorMessage = nil

        var rawInput = instanceInput.trimmingCharacters(in: .whitespaces).lowercased()
        if !rawInput.hasPrefix("http://") && !rawInput.hasPrefix("https://") {
            rawInput = "https://\(rawInput)"
        }
        guard let instanceURL = URL(string: rawInput) else {
            errorMessage = "Invalid instance URL."
            isConnecting = false
            return
        }

        do {
            let authURL = try await appState.addMastodonAccount(instanceURL: instanceURL)
            let callbackURL = try await authSession.authenticate(url: authURL, callbackScheme: "feeddigest")
            try await appState.completeMastodonOAuth(callbackURL: callbackURL)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isConnecting = false
    }
}

// MARK: - Auth Session Coordinator

final class AuthSessionCoordinator: NSObject, ASWebAuthenticationPresentationContextProviding {
    @MainActor
    func authenticate(url: URL, callbackScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: callbackScheme
            ) { callbackURL, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let callbackURL = callbackURL {
                    continuation.resume(returning: callbackURL)
                } else {
                    continuation.resume(throwing: URLError(.badServerResponse))
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            session.start()
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
}
