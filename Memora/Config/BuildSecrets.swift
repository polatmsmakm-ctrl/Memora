// This file is intentionally empty of secrets.
//
// The GitHub Actions workflow may overwrite it at build time with the value of the
// repository secret GEMINI_API_KEY (optional). Never commit a real key here.
// Any key compiled into an app binary can be extracted from the IPA, so the
// recommended setup is that each user pastes their own key in Settings → AI,
// where it is stored in the iOS Keychain.
enum BuildSecrets {
    static let geminiDefaultKey = ""
}
