import SwiftUI
import AuthenticationServices
import CryptoKit

struct SignInView: View {
    @State private var currentNonce: String = ""
    @State private var errorText: String?
    @Environment(AuthService.self) private var auth

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Text("Gym Sync")
                .font(.largeTitle.bold())
            Text("Lift together, anywhere.")
                .font(.title3)
                .foregroundStyle(.secondary)
            Spacer()
            SignInWithAppleButton(.signIn) { req in
                let nonce = Self.randomNonce()
                currentNonce = nonce
                req.requestedScopes = [.fullName, .email]
                req.nonce = Self.sha256(nonce)
            } onCompletion: { result in
                Task { await handle(result) }
            }
            .signInWithAppleButtonStyle(.black)
            .frame(height: 50)
            .padding(.horizontal, 32)

            if let errorText {
                Text(errorText).foregroundStyle(.red).font(.footnote)
            }
            Spacer(minLength: 40)
        }
    }

    @MainActor
    private func handle(_ result: Result<ASAuthorization, Error>) async {
        do {
            switch result {
            case .success(let auth):
                guard
                    let credential = auth.credential as? ASAuthorizationAppleIDCredential,
                    let tokenData = credential.identityToken,
                    let token = String(data: tokenData, encoding: .utf8)
                else {
                    errorText = "Missing identity token from Apple."
                    return
                }
                try await AuthService.shared.signInWithApple(identityToken: token,
                                                             nonce: currentNonce)
            case .failure(let err):
                errorText = ErrorMapping.map(err).errorDescription
            }
        } catch {
            errorText = ErrorMapping.map(error).errorDescription
        }
    }

    private static func randomNonce(length: Int = 32) -> String {
        let charset: [Character] =
            Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remaining = length
        while remaining > 0 {
            var random: UInt8 = 0
            let status = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
            precondition(status == errSecSuccess)
            if random < charset.count {
                result.append(charset[Int(random)])
                remaining -= 1
            }
        }
        return result
    }

    private static func sha256(_ input: String) -> String {
        let hash = SHA256.hash(data: Data(input.utf8))
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}
