import SwiftUI

struct YouTabView: View {
    @Environment(AuthService.self) private var auth
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button("Sign Out") {
                        Task {
                            do { try await auth.signOut() }
                            catch { errorText = ErrorMapping.map(error).errorDescription }
                        }
                    }
                    .foregroundStyle(.red)
                }
                if let errorText {
                    Section { Text(errorText).foregroundStyle(.red) }
                }
            }
            .navigationTitle("You")
        }
    }
}
