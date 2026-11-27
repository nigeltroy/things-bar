# ThingsBar

A macOS menu bar app that shows your top Things 3 to-do and lets you add,
complete, edit, schedule, cancel and delete to-dos without opening Things.

- **Menu bar:** the first to-do of the list you choose, in Things' own order.
- **Popover** (click): the whole list, an add field, hover actions, an inline editor.
- **Quick menu** (right-click): complete or open the top to-do, refresh, settings.
- **Settings:** source (built-in list, project, area or tag), tag/deadline/date/text
  filters, title length, remaining count, refresh interval, appearance, open at login,
  and the Things auth token (stored in the Keychain).
- **Design:** low-contrast warm dark theme modelled on Claude's dark mode (light and
  system appearances also available).

Requires macOS 14+ and Things 3 (tested with Things 3.25).

## Build and run

```bash
./scripts/build-app.sh          # builds build/ThingsBar.app (release, ad-hoc signed)
open build/ThingsBar.app
```

To keep it, copy `build/ThingsBar.app` to `/Applications` before turning on
**Open at login**.

On first use macOS asks whether ThingsBar may control Things. Choose OK. You can
change this later in System Settings → Privacy & Security → Automation.

**Auth token:** editing needs Things' URL-scheme token. In Things, open Settings →
General → Enable Things URLs → Manage, copy the token, and paste it into ThingsBar's
Settings. Reading, adding, completing and deleting work without it.

## Tests

```bash
swift test                                   # unit tests (no Things needed)
THINGSBAR_INTEGRATION=1 THINGS_AUTH_TOKEN=… swift test --filter LiveThings
```

The integration tests drive the real Things. They create uniquely named to-dos
(`tbtest-…`) and move them to Things' Trash afterwards.

The app can also test itself without Accessibility or Screen Recording access. It
writes a JSON report and PNG renders of its own views:

```bash
build/ThingsBar.app/Contents/MacOS/ThingsBar --selftest /tmp/tb            # fixture data
build/ThingsBar.app/Contents/MacOS/ThingsBar --selftest /tmp/tb --selftest-live --selftest-source Anytime
THINGS_AUTH_TOKEN=… build/ThingsBar.app/Contents/MacOS/ThingsBar --selftest /tmp/tb --selftest-live --selftest-actions
```

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
| Move to top (Today only) | `update when=evening`, then `when=today` | Things has no reorder API (see below) |

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
  URL scheme or JSON). Rescheduling a Today to-do This Evening → Today moves it to
  the top of Today. ThingsBar uses that for **Move to Top** and checks that it
  worked. Arbitrary drag-and-drop reordering isn't possible; reorder in Things
  (Open in Things) and ThingsBar follows.
- "When" can't be changed on repeating to-dos (a Things URL-scheme restriction).
- Headings and checklists aren't shown or edited (not available via AppleScript).
- Things has no change notifications, so ThingsBar re-reads every 15 s to 5 min
  (configurable), and whenever the popover opens.

## Layout

```
Sources/ThingsBarCore/   models, filters, Apple Events, URL builder, client, store (unit-tested)
Sources/ThingsBar/       AppKit status item, SwiftUI popover and settings, theme, self-test
Tests/ThingsBarCoreTests unit tests plus opt-in live integration tests
scripts/build-app.sh     builds and wraps the executable into ThingsBar.app
```
