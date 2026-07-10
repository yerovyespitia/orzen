# Orzen Design Notes

## Liquid Glass controls

Use native Liquid Glass for interactive controls on iOS 26+ and macOS 26+.
Always preserve a restrained translucent fallback for earlier systems.

### One standalone button

Apply the effect directly to the button label after its final frame. The shape
must match the visible hit target.

```swift
Image(systemName: "list.bullet")
    .frame(width: 44, height: 44)
    .glassEffect(.regular.interactive(), in: Circle())
```

For Orzen player controls, use `PlayerIconButton` with
`usesGlassBackground: true`. It centralizes the native glass effect and its
pre-iOS-26 fallback. Do not add a manual black fill behind a control that also
receives native glass: it muddies the material and makes that control look
different from the rest.

### Several independent glass buttons

When nearby controls should remain visually separate but blend and animate as
a group, place the individually glassed controls inside a `GlassEffectContainer`.

```swift
GlassEffectContainer(spacing: 34) {
    rewindButton.glassEffect(.regular.interactive(), in: Circle())
    playPauseButton.glassEffect(.regular.interactive(), in: Circle())
    forwardButton.glassEffect(.regular.interactive(), in: Circle())
}
```

This is the player transport pattern: each control keeps its own circular hit
target and glass surface, while the container coordinates the nearby effects.

### One shared capsule containing multiple actions

When two or more actions should look like one control — for example player
subtitles and audio — apply **one** glass effect to the container, not to each
action within it.

```swift
GlassEffectContainer(spacing: 10) {
    HStack(spacing: 10) {
        subtitlesMenu
        audioMenu
    }
}
.glassEffect(.regular.interactive(), in: Capsule())
```

The child actions retain separate accessibility labels and tap areas. They must
not add their own circular glass backgrounds, otherwise the result becomes two
buttons instead of a single capsule.

### Player rules

- Back, rewind, play/pause, forward, next episode, and episode list use the
  same interactive circular Liquid Glass treatment.
- Audio and subtitles are the exception: they live in one shared glass capsule.
- Keep mobile action targets at least 44 points. The audio/subtitle actions use
  46 points to remain easy to tap.
- Disabled controls are intentionally attenuated by SwiftUI. Verify an enabled
  series episode before judging the active appearance of the episode-list
  button.
- Do not change the established 54/76-point center transport frames when
  adjusting their material.

### Appearance changes

Do not force `.preferredColorScheme(.dark)` at the iPhone root when the player
must respond to the device appearance. SwiftUI only redraws glass for the
current environment color scheme, so a forced root scheme causes inconsistent
Light Mode behavior.

The player uses native untinted glass in Dark Mode. In Light Mode, apply the
same subtle white tint to every player glass surface (individual circles and
shared capsules) so controls do not remain visually black over a dark video
frame. Keep the tint value centralized and identical across those surfaces.

The episode-list button must not be covered by a separate transparent hit
target. Give Back its own 44-point button frame instead of adding an overlay
near the header.

### Verification checklist

1. Build with the workspace for the iOS Simulator, not only the project:
   `xcodebuild -workspace Orzen.xcworkspace -scheme Orzen -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build`.
2. Install and launch the app on an iOS 26+ simulator.
3. Open the player and inspect the overlay in landscape.
4. Confirm that circular controls share the same native glass treatment, while
   audio/subtitles render as one capsule with two tappable actions.
5. Check a series with available episodes so the list button is enabled.
6. Switch the simulator between Light and Dark while the player is paused, and
   confirm every control updates to the matching stable material.
