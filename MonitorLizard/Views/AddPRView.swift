import SwiftUI

struct AddPRView: View {
    @ObservedObject var viewModel: PRMonitorViewModel
    @State private var urlText = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @FocusState private var isURLFieldFocused: Bool

    private var isValidURL: Bool {
        GitHubService.parsePRURL(urlText) != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add PR")
                .font(.headline)

            Text("Paste a GitHub PR URL to monitor it alongside your own PRs.")
                .font(.caption)
                .foregroundColor(.secondary)

            TextField("https://github.com/owner/repo/pull/123", text: $urlText)
                .textFieldStyle(.roundedBorder)
                .disabled(isLoading)
                .focused($isURLFieldFocused)
                .onSubmit {
                    guard isValidURL && !isLoading else { return }
                    Task { await addPR() }
                }

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            HStack {
                Spacer()

                Button("Cancel") {
                    NSApp.keyWindow?.close()
                }
                .disabled(isLoading)

                Button("Add") {
                    Task {
                        await addPR()
                    }
                }
                .disabled(!isValidURL || isLoading)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 420)
        .onAppear { isURLFieldFocused = true }
        .overlay {
            if isLoading {
                Color.clear
                    .allowsHitTesting(true)
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func addPR() async {
        isLoading = true
        errorMessage = nil
        do {
            try await viewModel.addOtherPR(urlString: urlText)
            NSApp.keyWindow?.close()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
