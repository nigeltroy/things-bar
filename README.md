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
  with ⌘Z. To-dos with notes have a **Notes** button (or →/←) that shows the notes
  under the title. Completed to-dos move to the bottom of the list, checked, until the
  end of the day (or until you switch lists); click the check again to reopen one.
  The menu bar only ever shows open to-dos.
- **Settings** (gear, or ⌘,): shown inside the same panel. Source (built-in list,
  project, area or tag), filters, to-dos shown in the menu bar, title length,
  remaining count, appearance, open at login, and the Things auth token (stored in
  the Keychain).
- **Quick menu** (right-click): complete or open the top to-do, refresh, settings,
  check for updates.
- **Updates:** Settings → General → Check for Updates asks GitHub for the latest
  release; ThingsBar also checks on its own at most once a day (can be turned off).
  When a newer version exists, the footer says so, and **Install** (in Settings or the
  quick menu) downloads it, checks its signature, quits, replaces ThingsBar and
  reopens it, with [Sparkle](https://sparkle-project.org)'s standard progress window.
- **Keyboard:** ↑/↓ highlight a to-do, Space completes it, →/← show or hide its notes, Return edits it, ⌘⌫
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

Until releases are signed with a Developer ID (see [Signing](#signing-and-notarization)),
the app is ad-hoc signed and not notarized, so macOS blocks the first launch. Open
**System Settings → Privacy & Security**, scroll to the message about ThingsBar and
click **Open Anyway**. Later versions install from inside ThingsBar (0.7 and up), so
you only do this once.

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

The update test runs a real Sparkle update end to end. An old copy finds a newer one in
a local appcast, downloads it, checks its EdDSA signature, quits, is replaced and
reopens; with `TAMPER=1` the DMG is changed after signing and must be rejected. Both
copies use their own bundle ID and never read the Keychain or Things. It needs the
`things-bar` Sparkle key in your login Keychain (or `SPARKLE_KEY_FILE`):

```bash
scripts/test-update.sh
TAMPER=1 scripts/test-update.sh
```

## Releases (GitHub Actions)

`.github/workflows/build.yml` runs on every push and pull request. It runs the unit
tests, builds a universal app, packages the DMG, mounts it and smoke-tests the app
inside, then uploads the DMG as a workflow artifact.

**Every push to `main` releases itself.** Commits follow
[Conventional Commits](https://www.conventionalcommits.org), one change per commit,
and the commits since the last `v*` tag decide the next version
(`scripts/next-version.sh`):

| Commit | Example | Release |
|---|---|---|
| `feat:` | `feat: show notes in the list` | minor, 0.7.0 → 0.8.0 |
| `fix:`, `perf:`, `revert:` | `fix(panel): clip the glass to its corners` | patch, 0.7.0 → 0.7.1 |
| `type!:` or a `BREAKING CHANGE:` footer | `feat!: drop macOS 14` | major, 0.7.0 → 1.0.0 |
| `docs:`, `style:`, `refactor:`, `test:`, `build:`, `ci:`, `chore:` | `docs: explain the appcast` | none |

When there is a bump, the run tags the commit (`v0.8.0`) and publishes a GitHub Release
with `ThingsBar-0.8.0.dmg`, its SHA-256 checksum, `appcast.xml` and notes listing the
features and fixes. Subjects that aren't Conventional Commits get a warning in the run
and release nothing. The repository holds no version number: the app reads its version
from the bundle, which `build-app.sh` sets from the latest tag (CI: from the new one).
Installed copies read the appcast from
`https://github.com/nigeltroy/things-bar/releases/latest/download/appcast.xml`
(`SUFeedURL`). Sparkle installs an update only if its EdDSA signature matches
`SUPublicEDKey` in the installed app. The private key is the `SPARKLE_PRIVATE_KEY`
Actions secret; a copy lives in the login Keychain of the Mac that made it (account
`things-bar`). Keep a backup: without it, installed copies can't be updated in place.

### Signing and notarization

To remove the "Apple could not verify ThingsBar" warning, releases need a Developer ID
signature and Apple's notarization. The workflow does both as soon as these Actions
secrets exist, and stays ad-hoc signed without them:

1. Join the [Apple Developer Program](https://developer.apple.com/programs/) (paid).
2. In Xcode → Settings → Accounts → Manage Certificates, add a **Developer ID
   Application** certificate. In Keychain Access, export it with its private key as a
   `.p12` with a password.
3. In [App Store Connect → Users and Access → Integrations](https://appstoreconnect.apple.com/access/integrations/api),
   create a Team API key with the Developer role and download the `.p8`. Note its Key ID
   and the Issuer ID.
4. Add the secrets:

```bash
base64 -i DeveloperID.p12 | gh secret set DEVELOPER_ID_P12
gh secret set DEVELOPER_ID_P12_PASSWORD
base64 -i AuthKey_XXXXXXXXXX.p8 | gh secret set NOTARY_API_KEY
gh secret set NOTARY_KEY_ID
gh secret set NOTARY_ISSUER_ID
```

The next tagged release is then signed with the hardened runtime (plus the Apple
Events entitlement ThingsBar needs for Things), notarized and stapled. The release notes
say which kind of build it is. Developer ID also gives ThingsBar a stable identity, so
macOS keeps its Things (Automation) and Keychain permissions across updates. Ad-hoc
builds get a new identity with every version, so macOS may ask again after an update.

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
