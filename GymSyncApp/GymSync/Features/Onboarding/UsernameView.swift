import SwiftUI

struct UsernameView: View {
    @Binding var chosenProfile: Profile?

    @State private var username: String = ""
    @State private var isChecking = false
    @State private var isAvailable: Bool?
    @State private var errorText: String?
    @State private var isSubmitting = false

    @Environment(\.gsTheme) private var theme

    // Canvas suggestions — static display only
    private let suggestions = ["alex_j", "alexbench", "ajlifts"]

    var body: some View {
        ZStack(alignment: .bottom) {
            theme.bg.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Step indicator row
                    HStack(spacing: 10) {
                        Text("STEP 2 OF 3")
                            .font(GSFont.bold(12, relativeTo: .caption2))
                            .tracking(0.6)
                            .foregroundColor(theme.neutral700)

                        Spacer()

                        // Progress pips
                        HStack(spacing: 4) {
                            Rectangle().fill(theme.accent).frame(width: 22, height: 4)
                            Rectangle().fill(theme.accent).frame(width: 22, height: 4)
                            Rectangle().fill(theme.neutral300).frame(width: 22, height: 4)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 52)
                    .padding(.bottom, 10)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Pick your username")
                            .font(GSFont.bold(28, relativeTo: .title))
                            .foregroundColor(theme.text)

                        Text("Your crew will find you by this. 3–24 characters — letters, numbers, underscores.")
                            .font(GSFont.body(14, relativeTo: .subheadline))
                            .foregroundColor(theme.neutral700)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 20)

                    // Username field — bordered, accent outline when focused
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Username")
                            .font(GSFont.bodyMedium(11, relativeTo: .caption2))
                            .tracking(0.5)
                            .foregroundColor(theme.neutral700)

                        HStack(spacing: 0) {
                            Text("@")
                                .font(GSFont.bold(18, relativeTo: .title3))
                                .foregroundColor(theme.neutral500)

                            TextField("", text: $username)
                                .font(GSFont.bold(18, relativeTo: .title3))
                                .foregroundColor(theme.text)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .textContentType(.username)
                                .padding(.leading, 2)
                                .onChange(of: username) { _, newValue in
                                    Task { await checkAvailability(newValue) }
                                }

                            // Availability indicator
                            if isChecking {
                                ProgressView().controlSize(.small).tint(theme.accent)
                                    .padding(.trailing, 4)
                            } else if let isAvailable, !username.isEmpty {
                                HStack(spacing: 5) {
                                    Image(systemName: isAvailable ? "checkmark" : "xmark")
                                        .font(.system(size: 12, weight: .bold))
                                    Text(isAvailable ? "Available" : "Taken")
                                        .font(GSFont.bold(12, relativeTo: .caption))
                                }
                                .foregroundColor(isAvailable ? theme.accent700 : .red)
                            }
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 52)
                        .background(theme.surface)
                        .overlay(
                            Rectangle().strokeBorder(
                                username.isEmpty ? theme.divider : theme.accent,
                                lineWidth: 1
                            )
                        )
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 14)

                    if let errorText {
                        Text(errorText)
                            .font(GSFont.body(13, relativeTo: .footnote))
                            .foregroundColor(.red)
                            .padding(.horizontal, 20)
                            .padding(.top, 6)
                    }

                    // Suggestions
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Suggestions")
                            .font(GSFont.body(11, relativeTo: .caption2))
                            .foregroundColor(theme.neutral700)

                        HStack(spacing: 6) {
                            ForEach(suggestions, id: \.self) { suggestion in
                                Button {
                                    username = suggestion
                                    Task { await checkAvailability(suggestion) }
                                } label: {
                                    Text("@\(suggestion)")
                                        .font(GSFont.bodyMedium(12, relativeTo: .caption))
                                        .foregroundColor(theme.accent)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .frame(minWidth: 0)
                                }
                                .buttonStyle(.plain)
                                .background(theme.surface)
                                .overlay(Rectangle().strokeBorder(theme.neutral300, lineWidth: 1))
                                .frame(minHeight: 44)
                                .contentShape(Rectangle())
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 10)

                    // Bottom padding so content clears sticky CTA
                    Spacer().frame(height: 100)
                }
            }

            // Sticky bottom CTA
            VStack(spacing: 0) {
                GSDivider()
                Button {
                    Task { await submit() }
                } label: {
                    if isSubmitting {
                        ProgressView().tint(theme.bg)
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Continue")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(GSPrimaryButtonStyle())
                .disabled(username.count < AppConfig.usernameMinLength
                          || isAvailable != true
                          || isSubmitting)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .padding(.bottom, 22)
            }
            .background(theme.bg)
        }
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
