# Screen layout

Use `orzen/Components/OrzenScreen.swift` for sidebar screens other than Home and
for collection detail screens. The reference for collection details is Dropped,
which is rendered by `CollectionDetailView`.

## Shared components

- `OrzenScreen`: black background, top-leading layout, fixed heading outside the
  scroll area, and spacing between heading, controls, and content. It does not
  create a navigation stack.
- `OrzenScreenHeading`: shared font, weight, color, and title placement. Pass
  trailing buttons or loading indicators through its accessories builder;
  accessories must stay compact and must not change the title's height.
- `OrzenScreenScrollView`: vertical scroll, shared edge effect, and bottom inset.
- `OrzenPosterGrid`: adaptive macOS columns / three iPhone columns and shared
  poster spacing. The caller supplies cards, context actions, and navigation.
- `OrzenCollectionScreen`: collection heading on macOS, inline navigation title
  on iOS, and the existing back/escape interaction. Use it for every collection
  detail, including Downloads.
- `DetailUnavailableView`: shared empty and unavailable states. Use `.card` for
  inline states, `.centered` for page-level states, and the optional retry title
  and action for recoverable errors.
- `OrzenSectionHeading`: consistent section labels with optional leading and
  trailing controls. Pass the existing section font and insets when a screen
  already has platform-specific metrics.

Screen insets live in `OrzenScreenLayout`: horizontal 16, macOS top 8, bottom 20,
and spacing 20. Do not add another horizontal inset around a grid or heading.
On macOS the screen owns the horizontal inset; on iOS scroll content owns it.
For standalone controls, use `orzenScreenContentInset()` so they align too.

## Collection example

```swift
OrzenCollectionScreen(title: title) {
    if items.isEmpty {
        DetailUnavailableView(
            systemImage: icon,
            title: "No items yet",
            message: message
        )
        .orzenScreenContentInset()
    } else {
        OrzenScreenScrollView {
            OrzenPosterGrid {
                // Existing poster cards and this collection's actions.
            }
        }
    }
}
```

## Empty and error states

Keep the existing screen-specific title and message, and use
`DetailUnavailableView` for the presentation. Catalog and Search errors use the
centered style with a Retry action; Search's no-results state uses the centered
style without an action. Collection, episode, source, and playback messages keep
using the compact card style.

## Platform behavior and verification

Collections and Addons roots retain iOS large navigation titles and bounce
behavior. Movies and Series retain their custom heading and filter strip.
Search retains its search field and the iPhone system search flow. Settings
retains its native iPhone grouped list. Home keeps its artwork-led layout.

After a layout change, compare Movies, Series, Collections, Addons, Search, and
Settings at the same macOS window size. Headings and leading content edges must
align. Compare Dropped and Downloads with content and check an empty collection.
Scroll a populated grid, open a poster, return, and check the Addons action.
Also verify collection titles, safe-area insets, and back navigation on iPhone.
Builds and unit tests cannot establish visual consistency.
