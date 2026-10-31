# Plan: notes show first, edit only on purpose (iPhone)

Status: approved by owner 2026-10-31, ready to implement on a Mac.
Scope: `EclipseiPhone` only. No Apple TV, Mac, protocol or iCloud change.

## Problem

Tapping a note card opens `MediaNoteComposerViewController` straight away, with the
keyboard up, so the editor covers the live preview. During a presentation, the
presenter wants to read the note under the preview without going into edit mode.

Today:
- Live note card under the preview (`LiveNoteCardView`): 3 lines, then "…".
  A tap → `handleLiveNoteTap` → composer sheet.
- Full-screen Preview note card (`MediaNoteCardView` inside `MediaNoteOverlayView`):
  5 lines. A tap → `presentNoteComposer` → composer sheet.
- The composer is a plain `UITextView`, so pasted rich text keeps only its characters
  and line breaks. Bullet or number characters survive when the source includes them
  as text, but wrapped list lines don't line up under the item text.

## Behavior to build

1. **A tap on a note card toggles expand/collapse in place. It never opens the editor.**
   - Collapsed: 3 lines under the live preview, 5 lines on Preview (unchanged).
   - Expanded: the whole note.
   - Only offer the toggle when the note is actually truncated. If it already fits,
     a tap does nothing; don't fake an expand.
   - Expanding animates the height change (about 0.25 s, ease-in-out) and relays out the
     chrome, so the grid below moves down. It never draws over the preview.
2. **A pencil button opens the editor.** It goes in the card's top-right corner: SF Symbol
   `square.and.pencil`, about 28 pt visible with a 44 pt hit area, label "Edit note". It's
   the only way into editing from the card. "Edit note" / "Add note" in the item menus
   stay as they are.
3. **The empty Preview card ("Tap to add a note", shown with the Always setting) still opens
   the editor when tapped.** It has nothing to expand. No pencil on the empty state.
4. **Expanded height is capped.** Under the live preview, about 40% of the visible height of
   the grid controller's safe area. On Preview, the overlay's existing 42% band. Above the cap,
   the text scrolls inside the card, and the pencil stays fixed in the corner.
5. **The card returns to collapsed when the item changes**: a new live item under the preview,
   or a swipe to another page on Preview. It also collapses when the note text changes after
   an edit. The expanded state is never saved.
6. **Lists get hanging indents (display only).** When the card text is drawn, lines starting
   with `•`, `◦`, `▪`, `-`, `*`, `–`, or `\d+[.)]` followed by whitespace get a
   `NSParagraphStyle` with `headIndent` set to the marker's width, so wrapped lines line up
   under the item text. A leading tab after a marker counts as the whitespace. Storage stays
   plain text: `MediaNoteStore`, iCloud and the Mac app are untouched.
7. **No change to how notes are stored.** A note belongs to the library item, so it shows in
   every Show that holds the item, and editing it anywhere changes it everywhere. This is
   intentional; don't add per-Show notes.

Accessibility:
- The card stays one element, with the trait `.button` and the label "Note. <text>".
- Its value is "Collapsed" or "Expanded", and only when the note is truncated.
- `accessibilityActivate` toggles it.
- The pencil is its own element ("Edit note"). Also add a custom action "Edit note" on the
  card, so VoiceOver users can edit without finding the button.

## Implementation

### New shared helper: `MediaNoteText.swift`
- `static func attributed(_ note: String, font: UIFont, color: UIColor) -> NSAttributedString`
  applies the hanging indents (item 6). Measure the marker plus the space after it with
  `font` to get `headIndent`.
- `static func isTruncated(_ attributed: NSAttributedString, width: CGFloat, lines: Int) -> Bool`
  compares the text's height at `lines` with its full height, using the same
  `boundingRect`/`sizeThatFits` approach that `LiveNoteCardView.height(forWidth:)` already uses.
- Both cards use it, so the two screens truncate and indent the same way.

The project uses file-system-synchronized groups, so new files don't need
`project.pbxproj` edits.

### `LiveNoteCardView` (live note under the preview)
- Add `private(set) var isExpanded = false`, `func setExpanded(_:animated:)`, and
  `var onEdit: (() -> Void)?`.
- Replace `bodyLabel` with a non-editable, non-selectable `UITextView` inside the card
  (`isScrollEnabled` is false while collapsed and true when expanded past the cap), or keep
  the `UILabel` inside a `UIScrollView`. Pick whichever keeps `height(forWidth:)` simple.
  Collapsed uses `maximumLineCount = 3` with tail truncation.
- `height(forWidth:maxHeight:)` returns the collapsed height, or `min(full, maxHeight)` when
  expanded. Reserve trailing room for the pencil on the first line (trailing text inset of
  about 36 pt, or an exclusion path) so the text never runs under it.
- Keep the card a `UIControl`, with `.touchUpInside` meaning toggle. The pencil is a
  `UIButton` subview, so its touches don't reach the card's tracking.
- Show the pencil only when the card is visible with a note. That's always the case for
  this card, since it's hidden without one.

### `LibraryGridViewController+LiveNote.swift`
- Add `var liveNoteExpanded = false` (stored property in `LibraryGridViewController.swift`
  next to `presentedLiveNoteId`).
- `handleLiveNoteTap` toggles `liveNoteExpanded` (only when truncated), calls
  `liveNoteCard.setExpanded`, then forces the chrome pass the same way `syncLiveNoteChrome`
  does (`lastLayoutWidth = 0; lastLayoutHeight = 0; updateChromeLayoutIfNeeded()`) inside
  `UIView.animate`, followed by `view.layoutIfNeeded()`.
- Add `@objc func handleLiveNoteEdit()`, which holds today's body of `handleLiveNoteTap`
  (presents the composer). Wire it through `liveNoteCard.onEdit` where the target is added
  (`LibraryGridViewController.swift:525`).
- `syncLiveNoteChrome()`: when `id != presentedLiveNoteId` or `note != presentedLiveNote`,
  reset `liveNoteExpanded = false` and call `liveNoteCard.setExpanded(false, animated: false)`
  before the relayout.
- `measuredLiveNoteHeight(width:)` passes the cap (item 4) through.

### Layout, especially landscape (`LibraryGridViewController+ChromeLayout.swift`)
- **Portrait/stacked:** `expandedHeroOverlayInset()` already adds `measuredLiveNoteHeight()`,
  so the grid inset grows with the expanded card. Check that the grid's content offset moves
  with the inset change and doesn't jump. Keep the user's scroll position relative to the
  first visible row.
- **Landscape side-by-side** (around line 510): the note height is subtracted from
  `availableHeight` and the hero is re-sized, so a tall expanded note shrinks the preview.
  The preview must stay readable. Measure the expanded note against a cap of
  `availableHeight - minimumHeroHeight` (keep the hero at least the height it has with the
  collapsed card, or at least 60% of it, whichever reads better on an iPhone SE in
  landscape), and let the card scroll above that.
- `noteBottomLimit` (`+ChromeInstall.swift:151`) already keeps the card above the safe
  bottom at `.defaultHigh`. Leave it.

### Preview overlay (`MediaNoteCardView`, `MediaNoteOverlayView`, `LocalMediaPreviewPageViewController`)
- `MediaNoteCardView`: the same expand state, pencil and `MediaNoteText` rendering. Collapsed
  is 5 lines. Expanded grows upward from the bottom (the card is bottom-pinned already),
  limited by the overlay's `card.topAnchor >= topAnchor + 24`. Above that, scroll inside.
- `MediaNoteOverlayView`: replace `onTap` with `onEdit`. A tap on a filled, truncated card
  toggles locally. A tap on the empty card calls `onEdit`. `reload()` collapses the card when
  the text changed.
- `LocalMediaPreviewPageViewController`: set `noteOverlay.onEdit = presentNoteComposer`.
  `resetZoom()` (called when the page stops being current) also collapses the card.
  Zooming already hides the overlay; leave that.
- Make sure a vertical pan inside the expanded, scrolling card doesn't start the gallery's
  dismiss or paging gesture. Give the scroll view priority, or set
  `require(toFail:)` on the host's pan if one exists.

### Composer (`MediaNoteComposerViewController`)
Unchanged apart from one detail. Since editing is now a deliberate choice, keep the keyboard
coming up on appear.

## Tests (`EclipseiPhoneTests`)
- `MediaNoteTextTests`:
  - marker detection for `•`, `-`, `*`, `1.`, `12)`, and tab after the marker
  - none for "-5 degrees" (no space after the marker) or for mid-line markers
  - `headIndent > 0` only on list lines
  - `isTruncated` is true for 4 lines at 3, false for 2 lines
- `LiveNoteChromeTests` additions:
  - the expanded height is ≥ the collapsed height and ≤ the cap
  - the collapsed height is unchanged from today for a short note (regression)
  - changing the live id resets the expanded state (test through a small pure helper if
    the view controller is hard to set up)
- Existing note tests (`MediaNoteStoreTests`, `CloudKitRemoteMediaPrefsTests`) must stay green.
- Full suite: CLAUDE.md records 1085 passing on 2026-10-02. Report the new count.

## Manual checks on device or simulator
1. Live a still with a 10-line note in portrait. A tap expands it and the grid slides down,
   another tap collapses it, the pencil opens the editor, and no tap on the card body opens
   the editor.
2. The same in landscape on the smallest iPhone. The preview stays usable and the long note
   scrolls inside the card.
3. A docked slideshow ribbon with a note. Spacing is still right in both states.
4. Advance to the next slide while expanded. The new note shows collapsed.
5. A short 1–2 line note: no expand, a tap does nothing, and the pencil still works.
6. Paste a bulleted and a numbered list from Notes and from Safari. Wrapped lines indent
   under the item text, and the Mac app shows the same plain text.
7. Preview: expand, swipe to the next image, and the next card shows collapsed. With the
   Always setting, a tap on the empty card opens the editor.
8. VoiceOver: the card reads its state, a double tap toggles, and the "Edit note" action works.
9. Dynamic Type at the largest size: the pencil doesn't overlap the text, and the cap still holds.

## Out of scope
- Rich text (bold and so on) in notes. It would need a new storage format and Mac app work.
- Per-Show notes.
- Showing notes on the Apple TV.

## Docs
When it ships, add one line to `CLAUDE.md`: "Note cards: tap expands or collapses, and the
pencil edits (2026-10-31)."
