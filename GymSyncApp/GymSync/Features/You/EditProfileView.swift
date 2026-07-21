import SwiftUI
import PhotosUI

/// Phase F Task 6 — display name + avatar, wired from `YouTabView`'s
/// previously-inert "Edit" button (recorded deviation, task-2-report.md:
/// "Edit Profile is a future screen" — now fulfilled).
///
/// Two independent persistence paths, matching the GROUP avatar flow's own
/// split (`GroupView.membersList`'s avatar picker vs its separate "Add
/// member" field):
///   - Avatar: `PhotosPicker` → `ProfileRepository.setAvatar` uploads AND
///     writes `profiles.avatar_url` immediately on pick, no separate save
///     step — identical idiom to `GroupView`'s `.onChange(of: avatarItem)`.
///   - Display name: a plain `TextField` bound to local `@State`, persisted
///     only when the toolbar "Save" button is tapped
///     (`ProfileRepository.updateDisplayName`) — matches
///     `CreateGroupView`/`SeriesEditorView`'s explicit-save idiom for text
///     fields elsewhere in this app, rather than the avatar's
///     upload-on-pick pattern.
///
/// `onSaved` fires after EITHER path succeeds (avatar upload immediately;
/// display name on Save) so the caller can refresh `AppState.currentProfile`
/// without a full profile re-fetch — both `ProfileRepository.setAvatar` and
/// `.updateDisplayName` already return the fresh, full `Profile` row.
struct EditProfileView: View {
    let profile: Profile?
    let onSaved: (Profile) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.gsTheme) private var theme

    @State private var displayName: String
    @State private var avatarURL: URL?
    @State private var avatarItem: PhotosPickerItem?
    @State private var isSaving = false
    @State private var errorText: String?

    init(profile: Profile?, onSaved: @escaping (Profile) -> Void) {
        self.profile = profile
        self.onSaved = onSaved
        _displayName = State(initialValue: profile?.displayName ?? "")
        _avatarURL = State(initialValue: profile?.avatarURL)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Avatar picker row — same shape as GroupView.membersList's
                // avatar row (56pt preview + accent "Change Photo" link).
                HStack(spacing: 12) {
                    GSInitialsAvatar(name: initialsSourceName, avatarURL: avatarURL, size: 56)

                    PhotosPicker(selection: $avatarItem, matching: .images) {
                        Text("Change Photo")
                            .font(GSFont.bodyMedium(14, relativeTo: .body))
                            .foregroundStyle(theme.accent)
                    }
                }
                .padding(.vertical, 14)

                GSDivider()

                GSSectionHeader("Display name")
                    .padding(.top, 16)
                    .padding(.bottom, 8)

                TextField("Display name", text: $displayName)
                    .font(GSFont.body(14, relativeTo: .body))
                    .foregroundStyle(theme.text)
                    .tint(theme.accent)
                    .padding(.horizontal, 12)
                    .frame(height: 44)
                    .background(theme.surface)
                    .overlay(RoundedRectangle(cornerRadius: GSMetrics.radiusSm).strokeBorder(theme.divider, lineWidth: 1))

                if let profile {
                    Text("@\(profile.username)")
                        .font(GSFont.body(12, relativeTo: .caption))
                        .foregroundStyle(theme.neutral500)
                        .padding(.top, 6)
                }

                if let errorText {
                    Text(errorText)
                        .font(GSFont.body(12, relativeTo: .footnote))
                        .foregroundStyle(.red)
                        .padding(.top, 12)
                }

                Spacer(minLength: 16)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
        }
        .background(theme.bg)
        .scrollContentBackground(.hidden)
        .navigationTitle("Edit Profile")
        .navigationBarTitleDisplayMode(.inline)
        // Pushed from YouTabView's Settings Hub — see GSComponents.swift's GSHidesDock.
        .gsHidesDock()
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { Task { await save() } }
                    .font(GSFont.bold(14, relativeTo: .body))
                    .foregroundStyle(isSaving ? theme.neutral500 : theme.accent)
                    .disabled(isSaving)
            }
        }
        .onChange(of: avatarItem) {
            guard let item = avatarItem else { return }
            avatarItem = nil
            Task {
                do {
                    guard let data = try await item.loadTransferable(type: Data.self) else {
                        errorText = "That image couldn't be loaded."
                        return
                    }
                    let updated = try await ProfileRepository.setAvatar(imageData: data)
                    avatarURL = updated.avatarURL
                    errorText = nil
                    onSaved(updated)
                } catch let error as GymSyncError {
                    errorText = error.errorDescription
                } catch {
                    errorText = error.localizedDescription
                }
            }
        }
    }

    /// Live preview source for the avatar's initials fallback: the name
    /// being typed right now (matches `CreateGroupView`'s live-typed-name
    /// preview idiom), falling back to the username once the field is
    /// empty — never the stale `profile?.displayName` snapshot, so clearing
    /// the field previews the username-derived initials immediately.
    private var initialsSourceName: String {
        let trimmed = displayName.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { return trimmed }
        return profile?.username ?? ""
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            let updated = try await ProfileRepository.updateDisplayName(displayName)
            onSaved(updated)
            dismiss()
        } catch let error as GymSyncError {
            errorText = error.errorDescription
        } catch {
            errorText = error.localizedDescription
        }
    }
}
