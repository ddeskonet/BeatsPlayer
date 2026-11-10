BEATS PLAYER — SwiftUI, iOS 17/18

1. Xcode -> File > New > Project > iOS > App. Name: BeatsPlayer, Interface: SwiftUI, Language: Swift.
2. Delete the generated BeatsPlayerApp.swift and ContentView.swift. Drag these three files into the project:
   BeatsPlayerApp.swift, Player.swift, ContentView.swift (tick "Copy items if needed").
3. Target > Signing & Capabilities: choose your Team; "+ Capability" > Background Modes > tick "Audio, AirPlay, and Picture in Picture".
4. Run on your iPhone (Product > Run).

APP STORE:
- Apple Developer Program ($99/year), 1024x1024 app icon (Assets), unique Bundle Identifier.
- Product > Archive > Distribute App > App Store Connect; fill listing, screenshots, privacy policy URL; submit for review.
- Files are copied into the app's Documents folder; the app plays only the user's own files.

UNSIGNED IPA WITHOUT A MAC (GitHub Actions):
1. Create a free GitHub repo, upload ALL contents of this folder (including the hidden .github folder).
2. Repo > Actions > "Build IPA" > Run workflow. In ~5 min download BeatsPlayer.ipa from Artifacts (zip, unpack it).
3. Sign it yourself (Sideloadly, AltStore, Xcode, etc).
