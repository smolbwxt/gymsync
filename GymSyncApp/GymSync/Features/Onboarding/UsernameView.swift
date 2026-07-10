import SwiftUI

struct UsernameView: View {
    @Binding var chosenProfile: Profile?

    @State private var username: String = ""
    @State private var isChecking = false
    @State private var isAvailable: Bool?
    @State private var errorText: String?
    @State private var isSubmitting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Pick your username")
                    .font(.title2.bold())
                Text("Your friends will see this. 3–24 characters, letters, digits, and underscores.")
                    .foregroundStyle(.secondary)
            }
            TextField("username", text: $username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textContentType(.username)
                .padding(12)
                .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 10))
                .onChange(of: username) { _, newValue in
                    Task { await checkAvailability(newValue) }
                }

            if isChecking { ProgressView().controlSize(.small) }
            else if let isAvailable, !username.isEmpty {
                Label(isAvailable ? "Available" : "Taken",
                      systemImage: isAvailable ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(isAvailable ? .green : .red)
            }
            if let errorText { Text(errorText).foregroundStyle(.red) }

            Spacer()

            Button {
                Task { await submit() }
            } label: {
                if isSubmitting {
                    ProgressView().tint(.white)
                } else {
                    Text("Continue").frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(username.count < AppConfig.usernameMinLength
                      || isAvailable != true
                      || isSubmitting)
        }
        .padding()
    }

    @MainActor
    private func checkAvailability(_ raw: String) async {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= AppConfig.usernameMinLength else {
            isAvailable = nil
            return
        }
        isChecking = true
        defer { isChecking = false }
        do { isAvailable = try await ProfileRepository.usernameAvailable(trimmed) }
        catch { errorText = ErrorMapping.map(error).errorDescription }
    }

    @MainActor
    private func submit() async {
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            let created = try await ProfileRepository.create(username: username)
            chosenProfile = created
        } catch {
            errorText = ErrorMapping.map(error).errorDescription
        }
    }
}
