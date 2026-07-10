import SwiftUI

struct LibraryTabView: View {
    enum SubTab: Hashable { case routines, exercises }
    @State private var selection: SubTab = .routines

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $selection) {
                    Text("Routines").tag(SubTab.routines)
                    Text("Exercises").tag(SubTab.exercises)
                }
                .pickerStyle(.segmented)
                .padding()
                Divider()
                switch selection {
                case .routines:  RoutinesListView()
                case .exercises: ExercisesListView()
                }
            }
            .navigationTitle("Library")
        }
    }
}
