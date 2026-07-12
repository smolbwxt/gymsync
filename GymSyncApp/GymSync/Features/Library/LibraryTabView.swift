import SwiftUI

struct LibraryTabView: View {
    enum SubTab: Hashable { case routines, exercises }
    @State private var selection: SubTab = .routines
    @Environment(\.gsTheme) private var theme

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Canvas: segmented sub-tab control at top of Library
                Picker("", selection: $selection) {
                    Text("Routines").tag(SubTab.routines)
                    Text("Exercises").tag(SubTab.exercises)
                }
                .pickerStyle(.segmented)
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
}
