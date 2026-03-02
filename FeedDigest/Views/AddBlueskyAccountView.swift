import SwiftUI

struct AddBlueskyAccountView: View {
    var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var handle: String = ""
    @State private var appPassword: String = ""
    @State private var isConnecting: Bool = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Handle", text: $handle, prompt: Text("you.bsky.social"))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.emailAddress)
                    SecureField("App Password", text: $appPassword, prompt: Text("xxxx-xxxx-xxxx-xxxx"))
                } header: {
                    Text("Bluesky Credentials")
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Use an App Password, not your main password.")
                        Text("Generate one in Bluesky → Settings → App Passwords.")
                    }
                    .font(.caption)
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
                                Text("Signing in…")
                            }
                        } else {
                            Text("Sign In")
                        }
                    }
                    .disabled(handle.trimmingCharacters(in: .whitespaces).isEmpty
                              || appPassword.isEmpty
                              || isConnecting)
                }
            }
            .navigationTitle("Add Bluesky")
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

        let cleanHandle = handle.trimmingCharacters(in: .whitespaces).lowercased()
        do {
            try await appState.addBlueskyAccount(handle: cleanHandle, appPassword: appPassword)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isConnecting = false
    }
}
