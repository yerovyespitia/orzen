# Repository guidance

## Graphify

- Consult the existing Graphify graph when an architecture, dependency, or impact question spans several files and the graph is likely to reduce codebase discovery work.
- Prefer focused commands such as `graphify path`, `graphify explain`, and narrowly scoped `graphify query` calls. Do not treat the generated report as mandatory context for every task.
- Treat Graphify results as navigation hints, not as the source of truth. Verify every relevant relationship in the Swift source before changing code, especially relationships involving SwiftUI property wrappers, `ObservableObject`, shared framework imports, or inferred call edges.
- If the graph is missing or stale and updating it would materially help the task, rebuild only the code graph from the repository root:

  ```sh
  graphify extract orzen --code-only --out . --max-workers 1
  graphify cluster-only . --no-label
  ```

- Do not install Graphify hooks or assistant skills, modify agent instructions automatically, or commit `graphify-out/` unless the user explicitly asks.

## Refactoring safety

- For behavior-preserving refactors, establish proportionate tests around the behavior being moved before making structural changes.
- Keep platform-specific playback behavior explicit and verify both macOS and iOS code paths when the affected code is conditional by platform.
- Before and after changing `StreamPlayerView`, run the shared `Orzen` scheme on both supported platforms. Keep Derived Data outside the repository:

  ```sh
  xcodebuild -project Orzen.xcodeproj -scheme Orzen -destination 'platform=macOS' -derivedDataPath /tmp/orzen-tests-derived CODE_SIGNING_ALLOWED=NO test
  xcodebuild -workspace Orzen.xcworkspace -scheme Orzen -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/orzen-ios-tests-derived CODE_SIGNING_ALLOWED=NO test
  ```
