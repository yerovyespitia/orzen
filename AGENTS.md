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

## SwiftUI design consistency

- Before adding or changing a screen, inspect the existing view, its neighboring screens, and any available app screenshots. Match Orzen's established spacing, typography, colors, cards, icons, and control placement.
- Reuse the app's existing row and control patterns. Do not assume a default SwiftUI `Form`, `Toggle`, `DisclosureGroup`, or `NavigationLink` has the intended appearance or interaction.
- For controls that look like full-width rows, make the entire row interactive, including its empty space, and check that the visible affordance matches what happens on click or tap.
- After a UI change, review the rendered result and exercise the affected interaction when the app or a preview is available. A successful build alone does not establish that the design matches Orzen.
- Keep macOS and iOS layouts consistent with each platform's existing Orzen design while preserving their distinct behavior.

## Refactoring safety

- For behavior-preserving refactors, establish proportionate tests around the behavior being moved before making structural changes.
- Keep platform-specific playback behavior explicit and verify both macOS and iOS code paths when the affected code is conditional by platform.
- Before and after changing `StreamPlayerView`, run the shared `Orzen` scheme on both supported platforms. Keep Derived Data outside the repository:

  ```sh
  xcodebuild -project Orzen.xcodeproj -scheme Orzen -destination 'platform=macOS' -derivedDataPath /tmp/orzen-tests-derived CODE_SIGNING_ALLOWED=NO test
  xcodebuild -workspace Orzen.xcworkspace -scheme Orzen -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/orzen-ios-tests-derived CODE_SIGNING_ALLOWED=NO test
  ```
