# BookOrb: Unofficial Companion App (iOS)

Unofficial iOS companion reader for a self-hosted [BookOrbit](https://github.com/bookorbit/bookorbit) server, ported from the Android app in `../bookorbit-android`. SwiftUI + [Readium Swift toolkit](https://github.com/readium/swift-toolkit). Not affiliated with or endorsed by BookOrbit.

## Build

```bash
brew install xcodegen
xcodegen generate
open CompanionReader.xcodeproj
```

Or from the command line: `xcodebuild -project CompanionReader.xcodeproj -scheme CompanionReader -destination 'platform=iOS Simulator,name=iPhone 17' build`

## Done
Sign-in (https then http fallback, token refresh), Home shelves, Library (search, library/status filter, grid/list), book detail (status, rating, offline download), EPUB reader (tap zones, TOC, font/margins/justify, day/night, progress + reading-time sync, jump-to-other-device prompt), Browse (series, authors, SmartScopes), minutes-left-in-chapter estimate (learns your reading speed), Home widgets (clock, streak, goal, rhythm, projection, challenge, highlight of the day, longest wait, library overview) with the reading companion, customizable order/size/visibility, an About screen with the licence-required BookOrbit notice, Home Screen widgets (Continue reading, Reading stats, Reading companion) and an app-icon quick-action menu, offline outbox with retry, and two-way highlight sync (select text → Highlight; tap a highlight to recolor or delete; works offline and syncs with the web reader via EPUB CFIs).

## Not ported
Android-only features (launcher mode, e-ink display modes, volume-key page turns) are intentionally left out. Only EPUB is supported, as in the Android app.

## License
AGPL-3.0-only with the additional terms in ADDITIONAL_TERMS.md (derived from the Android app). Keep the attribution, and give a redistributed fork its own name.
