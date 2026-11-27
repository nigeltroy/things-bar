# ThingsBar

A macOS menu bar app that shows your top Things 3 to-do and lets you add,
complete, edit, schedule, cancel and delete to-dos without opening Things.

- **Auth token first:** ThingsBar needs Things' auth token to work. Until one is
  saved, the menu bar reads "ThingsBar" and the panel only asks for the token;
  Things isn't read at all.
- **Menu bar:** text only, never an icon. Shows the top 1, 2 or 3 to-dos of
  the list you choose, separated by " | ", in Things' own order, fitted to a Narrow,
  Medium or Wide width so macOS never hides it. It updates within about 2 s of
  changes made in Things, reordering included.
- **Panel** (click): a grayscale Liquid Glass panel under the menu bar, like the
  system's menu extras. It holds the whole list, an add field, hover actions and an
  inline editor. Drag rows to reorder them; the new order is saved to Things (Today
  and Inbox). Complete, cancel, trash and reorder can be undone from the footer or
  with ⌘Z.
- **Settings** (gear, or ⌘,): shown inside the same panel. Source (built-in list,
  project, area or tag), filters, to-dos shown in the menu bar, title length,
  remaining count, appearance, open at login, and the Things auth token (stored in
  the Keychain).
- **Quick menu** (right-click): complete or open the top to-do, refresh, settings,
  check for updates.
- **Updates:** Settings → General → Check for Updates asks GitHub for the latest
  release; ThingsBar also checks on its own at most once a day (can be turned off).
  When a newer version exists, the footer says so and Download opens its disk image.
- **Keyboard:** ↑/↓ highlight a to-do, Space completes it, Return edits it, ⌘⌫
  trashes it, ⌘↑/⌘↓ and ⌥⌘↑/⌥⌘↓ move it, ⌘Z undoes, ⌘N new to-do, ⌘, settings,
  Esc back or close, ⌘Q quit.
- **Accessibility:** all text and placeholders meet WCAG 4.5:1 and glyphs 3:1 over
  the glass in dark and light (checked by the self-test's contrast audit), Increase Contrast raises
  it further and adds a panel border, Reduce Motion turns off animation, and rows
  have VoiceOver labels and actions.

Requires macOS 14+ and Things 3 (tested with Things 3.25).

## Install

Download the latest `ThingsBar-<version>.dmg` from the repository's
**Releases** page, open it and drag **ThingsBar** onto **Applications**.

The app is ad-hoc signed, not notarized by Apple, so macOS blocks the first
launch. Open **System Settings → Privacy & Security**, scroll to the message about
ThingsBar and click **Open Anyway**. You only need to do this once per version.

## Build from source

```bash
./scripts/build-app.sh               # build/ThingsBar.app (release, this Mac's arch, ad-hoc signed)
./scripts/build-app.sh --universal   # Apple silicon + Intel
./scripts/make-dmg.sh                # build/ThingsBar.dmg from build/ThingsBar.app
open build/ThingsBar.app
```

To keep it, copy `build/ThingsBar.app` to `/Applications` before turning on
**Open at login**.

On first use macOS asks whether ThingsBar may control Things. Choose OK. You can
change this later in System Settings → Privacy & Security → Automation.

**Auth token:** ThingsBar needs Things' URL-scheme token before it does anything. In
Things, open Settings → General → Enable Things URLs → Manage, copy the token, and
paste it into the panel when ThingsBar asks. ThingsBar checks the token with Things
before saving it, by asking Things to update a to-do ID that doesn't exist (so nothing
can change) and reading Things' reply on its `thingsbar://` callback URL. If Things
later stops accepting the token, ThingsBar asks for it again. Change or remove it in
Settings → Things access.

## Tests

```bash
swift test                                   # unit tests (no Things needed)
THINGSBAR_INTEGRATION=1 THINGS_AUTH_TOKEN=… swift test --filter LiveThings
THINGSBAR_NETWORK=1 swift test --filter LiveGitHub   # reads the latest GitHub release
```

The integration tests drive the real Things. They create uniquely named to-dos
(`tbtest-…`) and move them to Things' Trash afterwards.

The app can also test itself without Accessibility or Screen Recording access. It
opens its own panel and checks its placement, settings navigation and Esc handling,
measures that hovering doesn't resize rows, checks the no-token prompt, and writes a
JSON report plus PNG renders of its views. A contrast audit (`contrast.json`) renders
every text, placeholder and glyph in dark and light, with and without Increase
Contrast, over typical and worst-case glass, and measures the pixels. Real Liquid Glass is composited by the window server, so the renders
approximate it over a sample wallpaper:

```bash
build/ThingsBar.app/Contents/MacOS/ThingsBar --selftest /tmp/tb            # fixture data
build/ThingsBar.app/Contents/MacOS/ThingsBar --selftest /tmp/tb --selftest-live --selftest-source Anytime
THINGS_AUTH_TOKEN=… build/ThingsBar.app/Contents/MacOS/ThingsBar --selftest /tmp/tb --selftest-live --selftest-actions
```

## Releases (GitHub Actions)

`.github/workflows/build.yml` runs on every push and pull request. It runs the unit
tests, builds a universal app, packages the DMG, mounts it and smoke-tests the app
inside, then uploads the DMG as a workflow artifact.

To publish a release, tag a commit and push the tag:

```bash
git tag v1.0.0 && git push origin v1.0.0
```

The tag sets the app version (`1.0.0`), and the workflow attaches
`ThingsBar-1.0.0.dmg` and its SHA-256 checksum to a new GitHub Release.

## How it talks to Things

Sources: Cultured Code's [URL scheme](https://culturedcode.com/things/support/articles/2803573/)
and [AppleScript](https://culturedcode.com/things/support/articles/4562654/) docs,
plus Things' scripting dictionary (`sdef /Applications/Things3.app`).

| Operation | Mechanism | Why |
|---|---|---|
| Read lists, projects, areas, tags, to-dos | Apple Events (one per property, about 0.2 s per list) | The URL scheme can't read |
| Add | URL scheme `add` | AppleScript `make … at` put to-dos in the Inbox regardless of target |
| Edit title/notes/deadline/tags, schedule | URL scheme `update` + auth token | Documented; supports "This Evening"; runs in the background |
| Complete, cancel, delete (to Trash) | Apple Events `set status` / `delete` | Synchronous, real errors; the URL scheme has no delete |
| Reorder Today | Repeated "move to top": `update when=evening`, then `when=today` | Things has no reorder API (see below) |
| Reorder Inbox | Repeated "move to top": Apple Event `move` to Someday, then back to Inbox | Same; needs no token |
| Notice changes made in Things | Every 2 s, compare IDs, modification dates and titles (three small Apple Events) | Things has no change notifications |

Design decisions:

- **Raw Apple Events, not `NSAppleScript`.** `NSAppleScript` deadlocks when run
  off the main thread in any process with a main run loop, which includes every
  AppKit app. Running it on the main thread would freeze the UI whenever Things is
  slow. Raw Apple Events, built from the four-char codes in Things' dictionary, are
  safe on a background queue and take about 0.04 s each.
- **URL-scheme writes are verified.** `open` is fire-and-forget, so after each add
  or update the client re-reads Things until the change shows up. That way a wrong
  token or disabled URLs show up as an error instead of failing silently.
- **Optimistic UI.** Completed and deleted rows disappear immediately and come back,
  with an error, if Things refuses.
- **The token** lives in the Keychain and is never written to disk or committed.

## Limitations

- **Reordering:** Things documents no way to set a to-do's position (AppleScript,
  URL scheme or JSON). In two lists there is a reliable "move to top": in Today,
  rescheduling This Evening → Today; in the Inbox, moving to another list and back.
  Any order can be built from moves to the top, so after a drop ThingsBar sends the
  fewest moves needed (dragging an item up costs one), re-reads Things to confirm,
  and rolls back with a message if Things disagrees. Drags in Today make any moved
  This Evening to-dos daytime ones. Projects, areas, Anytime and Someday can't be
  reordered this way without side effects (to-dos would move to the bottom or lose
  their headings), so there the panel follows Things' order; reorder in Things and
  ThingsBar updates within about 2 s.
- "When" can't be changed on repeating to-dos (a Things URL-scheme restriction).
- Headings and checklists aren't shown or edited (not available via AppleScript).
- Things has no change notifications, so ThingsBar polls a cheap fingerprint every
  2 s and re-reads when it changes, plus a full re-read every 30 s and whenever the
  panel opens.

## Layout

```
Sources/ThingsBarCore/   models, filters, Apple Events, URL builder, client, store (unit-tested)
Sources/ThingsBar/       AppKit status item, SwiftUI popover and settings, theme, self-test
Tests/ThingsBarCoreTests unit tests plus opt-in live integration tests
scripts/build-app.sh     builds and wraps the executable into ThingsBar.app
scripts/make-dmg.sh      packages the app into a drag-to-install DMG
.github/workflows/       CI build, DMG artifact and tagged releases
```
