import SwiftUI

struct CredentialsView: View {
    @State private var viewModel = SettingsViewModel()

    var body: some View {
        Form {
            Section("App Store Connect API") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Key ID")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    TextField("", text: $viewModel.keyID)
                        .textFieldStyle(.plain)
                        .padding()
                        .inputBackground()
                        .clipShape(.rect(cornerRadius: 8))
#if !os(macOS)
                        .textInputAutocapitalization(.never)
#endif
                        .accessibilityIdentifier("credentials-key-id-field")
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Issuer ID")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    TextField("", text: $viewModel.issuerID)
                        .textFieldStyle(.plain)
                        .padding()
                        .inputBackground()
                        .clipShape(.rect(cornerRadius: 8))
#if !os(macOS)
                        .textInputAutocapitalization(.never)
#endif
                        .accessibilityIdentifier("credentials-issuer-id-field")
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Private Key (.p8 content)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    TextEditor(text: $viewModel.privateKeyPEM)
                        .frame(minHeight: 150)
                        .padding(8)
                        .inputBackground()
                        .clipShape(.rect(cornerRadius: 8))
                        .font(.system(.caption, design: .monospaced))
                        .accessibilityIdentifier("credentials-private-key-editor")

                    Text("Paste the full .p8 key including BEGIN and END lines.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let softValidationMessage = viewModel.softValidationMessage {
                    Label(softValidationMessage, systemImage: "exclamationmark.circle")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }

            Section {
                Button {
                    Task {
                        await viewModel.testConnection()
                    }
                } label: {
                    HStack {
                        Spacer()
                        if viewModel.isTestingConnection {
                            ProgressView()
                        } else {
                            Text("Test Connection")
                                .fontWeight(.semibold)
                        }
                        Spacer()
                    }
                }
                .disabled(viewModel.isTestingConnection)
                .accessibilityIdentifier("credentials-test-button")

                if let connectionMessage = viewModel.connectionMessage {
                    Label(connectionMessage, systemImage: viewModel.connectionSucceeded ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(viewModel.connectionSucceeded ? .green : .red)
                        .accessibilityIdentifier("credentials-result-label")
                }

                Button("Clear Credentials", role: .destructive) {
                    viewModel.clearCredentials()
                }
                .accessibilityIdentifier("credentials-clear-button")
            }

            Section("Instructions") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("1. In App Store Connect, open Users and Access.")
                    Text("2. Open Integrations and create/select an API key.")
                    Text("3. Copy Key ID + Issuer ID and paste your full .p8 key here.")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Credentials")
#if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .onAppear {
            viewModel.load()
        }
        .onChange(of: viewModel.keyID) { _, _ in
            viewModel.autoSave()
        }
        .onChange(of: viewModel.issuerID) { _, _ in
            viewModel.autoSave()
        }
        .onChange(of: viewModel.privateKeyPEM) { _, _ in
            viewModel.autoSave()
        }
    }
}

private extension View {
    @ViewBuilder
    func inputBackground() -> some View {
#if os(macOS)
        background(Color(nsColor: .textBackgroundColor))
#else
        background(Color(uiColor: .tertiarySystemBackground))
#endif
    }
}

#Preview {
    NavigationStack {
        CredentialsView()
    }
}
