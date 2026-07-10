import SwiftUI

struct HomeView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Text("Welcome to Gym Sync")
                    .font(.title2.bold())
                Text("Start a solo workout from Library → Routines.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .navigationTitle("Home")
        }
    }
}
