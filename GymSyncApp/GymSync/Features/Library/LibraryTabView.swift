import SwiftUI

struct LibraryTabView: View {
    enum SubTab: Hashable { case routines, exercises }
    @State private var selection: SubTab = .routines
    @Environment(\.gsTheme) private var theme

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Canvas: segmented sub-tab control at top of Library (Dossier §6)
                HStack {
                    segmentedControl
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(theme.bg)

                GSDivider()

                switch selection {
                case .routines:  RoutinesListView()
                case .exercises: ExercisesListView()
                }
            }
            .background(theme.bg)
            .navigationTitle("Library")
            .toolbarBackground(theme.surface, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }

    // Canvas: `.seg` — flat rectangle, 1px divider border, no radius, hugs content.
    private var segmentedControl: some View {
        HStack(spacing: 0) {
            segmentOption(title: "Routines", tab: .routines)
            segmentOption(title: "Exercises", tab: .exercises)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(theme.divider)
                        .frame(width: 1)
                }
        }
        .overlay(Rectangle().strokeBorder(theme.divider, lineWidth: 1))
    }

    // Canvas: `.seg-opt` — selected = accent fill + bg text, unselected = transparent.
    // 44pt minimum tap height per DEFECT audit, independent of the 7/12px visual padding.
    private func segmentOption(title: String, tab: SubTab) -> some View {
        let isSelected = selection == tab
        return Button {
            selection = tab
        } label: {
            Text(title)
                .font(GSFont.bodyMedium(13, relativeTo: .subheadline))
                .foregroundStyle(isSelected ? theme.bg : theme.text)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .frame(minHeight: 44)
                .background(isSelected ? theme.accent : Color.clear)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
