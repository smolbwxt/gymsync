import SwiftUI
import AuthenticationServices
import CryptoKit

struct SignInView: View {
    @State private var currentNonce: String = ""
    @State private var errorText: String?
    @Environment(AuthService.self) private var auth
    @Environment(\.gsTheme) private var theme

    var body: some View {
        ZStack {
            theme.accent.ignoresSafeArea()

            VStack(spacing: 0) {
                // Hero content — centred vertically
                VStack(alignment: .leading, spacing: 0) {
                    Text("GYM SYNC")
                        .font(GSFont.bold(13, relativeTo: .caption))
                        .tracking(2.4)
                        .foregroundColor(theme.bg.opacity(0.85))

                    Text("Lift together,\nanywhere.")
                        .font(GSFont.bold(52, relativeTo: .largeTitle))
                        .foregroundColor(theme.bg)
                        .lineSpacing(2)
                        .padding(.top, 14)

                    Text("Take turns on the bar with your crew over live voice — reps, weight, and heart rate, shared in real time.")
                        .font(GSFont.body(15, relativeTo: .body))
                        .foregroundColor(theme.bg.opacity(0.9))
                        .padding(.top, 16)
                        .frame(maxWidth: 280, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 28)
                .padding(.top, 52)
                .frame(maxHeight: .infinity)

                // Bottom CTA stack
                VStack(spacing: 12) {
                    SignInWithAppleButton(.signIn) { req in
                        let nonce = Self.randomNonce()
                        currentNonce = nonce
                        req.requestedScopes = [.fullName, .email]
                        req.nonce = Self.sha256(nonce)
                    } onCompletion: { result in
                        Task { await handle(result) }
                    }
                    .signInWithAppleButtonStyle(.white)
                    .frame(height: 50)

                    if let errorText {
                        Text(errorText)
                            .font(GSFont.body(11, relativeTo: .caption))
                            .foregroundColor(theme.bg.opacity(0.85))
                    }

                    Text("By continuing you agree to the Terms & Privacy Policy.")
                        .font(GSFont.body(11, relativeTo: .caption))
                        .foregroundColor(theme.bg.opacity(0.75))
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
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
