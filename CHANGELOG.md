# Changelog

Versions follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html), and the
format is [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

What the numbers mean here:

- **Major** — a change a user cannot ignore: a setting that changes meaning, a
  figure that starts or stops being shown, a credential the widget no longer
  accepts.
- **Minor** — new capability: another metric, another section, another locale.
- **Patch** — fixes and internal work: a wrong figure, a layout bug, a
  translation update, a dependency bump.

## [Unreleased]

## [Unreleased]

### Removed

- **The quota trend is gone — chart and recording.** 0.4.0 recorded every
  refresh's quota percentages and drew them in the popup; the line was noise
  more than information and the bars did not change that, so the recording,
  the canvas and the `usageHistory` configuration entry are removed rather
  than shipped on unused. The twice-daily digest keeps its clock times and
  reports each provider's current usage only, dropping the "today" figure
  that only the recording could know.

## [0.4.0] - 2026-09-30

### Changed

- **The widget is now "AI Usage" (`sh.marble.ai.usage`), not "DeepSeek
  Usage".** It has covered three providers since the Kimi and Z.ai sections
  landed, and the old name promised only one of them. The plugin id moved with
  the name, so a widget instance added before this change has to be added
  again — a rename cannot carry a panel instance across ids. Credentials in
  KWallet are untouched (`deepseek-api-key`, `kimi-api-key`, `zai-api-key`
  keep their names on purpose), as are the settings keys.

### Added

- **A twice-daily usage digest, and every reminder is a setting.** Besides
  the reset warning, the widget now summarizes today's quota usage twice a
  day at settable times ("Kimi weekly quota: 30% used, +5% today · Z.ai
  weekly quota: 6% used, +2% today" — the today-figure is the day's movement
  from the recorded trend). A "Reminders" section in the settings turns each
  kind off, moves the reset warning's window (hours before) and bar (minimum
  unused), and sets the digest's two clock times; defaults stay 24 h / 20% /
  09:00 / 21:00, and day-stamps are local days.

- **A desktop reminder when a weekly quota is about to reset with most of it
  unused.** Inside the last day of the Kimi or Z.ai weekly window, with more
  than 20% of the quota unused, the widget sends one notification a day
  suggesting the per-day pace that would spend the rest on time ("60% unused,
  resets in 23h — about 63% per day would use it up"). The decision logic is
  js/reminder.js, thresholds pinned by tests; the notification goes through
  `notify-send` (the one binary this adds — absent means no reminder, never a
  broken widget), and the day it last fired is stored per provider so it
  cannot nag.

- **The Kimi and Z.ai sections record a quota trend.** Every refresh (at most
  one point per ten minutes, 512 points — about three and a half days) writes
  the headline quota's percentage to the applet configuration, and each
  provider's popup section draws it as a line over time: the Z.ai 5-hour
  window shows its fill-and-reset sawtooth, the Kimi weekly quota its drift.
  Percent is the recorded unit, so a reset cannot push the history out of
  range, and nothing but percentages is stored — no amounts, no keys.

- **The panel number is now an add-style composition.** The settings offer a
  combo of every provider metric; picking one appends it to the list below,
  each row removable with its own button, and the list's order is the panel's
  order ("$7.78 · 30% · 27%"). A provider without credentials or still loading
  is skipped rather than shown as a dash, and an empty list reduces the chip to
  the icon (the peak-rate dot is dropped too). A stored single metric keeps
  working unchanged until the composition is edited. The chip shows numbers
  only by default; a "Panel icons" setting puts each number's provider icon
  beside it (off, because several checked metrics with an icon each crowd a
  panel row, and the tooltip names every figure anyway). The generic widget
  icon steps aside whenever numbers are on the chip; only the icon-only mode
  and the status texts keep it. The provider icons live in the popup too.

- **The settings page is reordered by usage and every control reports its
  edits.** Panel (composition, icons, refresh, privacy) comes first, then the
  data window, then the three providers' credentials under their own headers.
  The page emits `configurationChanged` on every change, so the dialog's
  Apply/OK enablement tracks the page's own edits rather than the first click
  only, and the composition list is plain page state rather than a binding the
  framework's post-Apply echo could fight.

- **The popup separates its providers, and hides the ones not configured.**
  Each provider section now opens with a rule, and DeepSeek's balance hero,
  key figures and peak state appear only when DeepSeek has credentials —
  before, an unconfigured DeepSeek rendered a $0.00 hero and a column of
  dashes above the Kimi and Z.ai sections, which read as one undifferentiated
  block.

- **Z.ai (GLM Coding Plan) usage, beside the Kimi data.** A third provider:
  a "Z.ai" section in the popup lists the quota windows the monitor API
  reports — the 5-hour token window, the weekly quota and the monthly tool
  quota, each with its percentage, counts when the API carries them, and its
  reset time — plus the last 7 and 30 days of tokens and requests. The panel
  can show "Z.ai 5-hour usage" or "Z.ai quota left" as its number. The key is
  stored in KWallet as `zai-api-key` (tried as a bare Authorization value
  first, Bearer on retry — the endpoint has accepted both), and the base URL
  is a plain setting defaulting to `https://api.z.ai`. The contract is pinned
  by a recorded live probe: the quota endpoint's TOKENS_LIMIT rows carry only
  a percentage and a reset time today, so the panel's headline percent comes
  straight from the API; the absolute counts the reference tracker reads are
  honoured when they exist.

- **Kimi Code (Coding Plan) usage, beside the DeepSeek data.** The widget can
  now also show the Kimi weekly quota and the per-model limits: a "Kimi Code"
  section in the popup lists each quota with used / limit, percent and its reset
  time, and the panel can show "Kimi weekly usage" or "Kimi quota left" as its
  number. The key is stored in KWallet as `kimi-api-key` (a Kimi Code key,
  `sk-kimi-…` — Moonshot Open Platform keys are answered with 401), and the
  base URL is a plain setting defaulting to `https://api.kimi.com/coding/v1`.
  The data comes from the same `GET /usages` endpoint the Kimi CLI reads (with
  a `/usage` fallback), classified by real HTTP status codes — unlike the
  DeepSeek platform API, which answers 200 for auth failures. Either provider
  alone is enough: with no DeepSeek credentials the panel falls back to the
  Kimi headline number.

## [0.3.0] - 2026-09-27

### Added

- **The settings page says where the session token is, and opens the site that holds
  it.** A “How to get it” hint names the `userToken` entry and its DevTools path
  (Application/Storage → Local Storage) beside a button that opens
  `platform.deepseek.com` in the browser, so the token can be copied without hunting
  through the README first.

### Changed

- **Rich mode still needs a pasted session token: a username/password login is not
  possible and was not built.** The platform's login routes (`/auth-api/v0/*`) answer
  every request, browser-like or not, with an AWS WAF challenge that only a browser
  can pass, so no widget-side login window can work; the evidence and the A/B control
  are recorded in `docs/decisions-log.md` (D70). No password is stored.
- **The plugin id is now `sh.marble.deepseek.usage`** (was
  `org.deepseek.plasma.usage`). _Breaking for an existing install:_ the widget no
  longer resolves under the old id, so remove it from the panel and add it again — its
  settings return to their defaults. Wallet entries and account data are unaffected.
  The new namespace is the publisher's own rather than DeepSeek's; see D73.
- **The platform's refusals are readable.** "INVALID_PARAM", "Missing Token" and
  "Authorization Failed (invalid token)" are terse English codes that tell a new user
  nothing; they now render as a sentence saying what to do — add a token in the
  settings, paste a fresh one from platform.deepseek.com, or shorten the cost period.
  `Api.failureKind` names the three, and any refusal it does not recognise is still
  shown in the platform's own words so a bug report carries them.

### Fixed

- **The cost period can no longer be set past what the platform answers.** The
  settings offered 1–90 days, but the platform refuses any usage window longer than
  **31 days** with `code:0` and a business status of `INVALID_PARAM` — a refusal that
  arrives the same way for every token, so it reads as a broken credential. It is the
  second window bug of this kind: the replies carry no payload, and before the
  business-status handling landed both were reported as "Missing payload".
  `Api.MAX_USAGE_DAYS` is now the single ceiling, read by the spinner, the KConfigXT
  bound and the request, and a stored value above it is clamped rather than sent.
- **The session token is peeled no matter how it was copied.** `normalizeSessionToken`
  already handled the storage wrapper, a quoted copy and a whole `Bearer …` header, but
  not the wrapper whose quotes came out escaped (what `JSON.stringify(userToken)` in
  the console, or a log line, gives) or a hand-typed single-quoted object. Both still
  carry the wrapper's own `value` key, so both are peeled now; anything that does not
  begin with `{` is still returned untouched.

## [0.2.0] - 2026-09-27

### Added

- **Descriptions in every language the READMEs ship.** `metadata.json`
  `Description` is what the widget list and the default tooltip show, so a language
  with a README but no description is a language whose users see English in Plasma.
  `tests/metadata.test.mjs` now fails if a `README.<lang>.md` has no
  `Description[<locale>]`, or if that entry is still the English text.
- **`scripts/bump-version.sh`**, which moves the version in all three places it is
  written down — `package.json`, `metadata.json`'s `KPlugin.Version` and the newest
  `CHANGELOG.md` heading — and refuses the three ways that goes wrong: a version that
  is not SemVer, one that is not greater than the current one, and one with nothing
  under `[Unreleased]`.
- **Local git hooks** that run the CI jobs before a commit and a push, so a broken push
  is found in seconds rather than after a GitHub Actions round trip:
  `scripts/install-hooks.sh` points git at the tracked `scripts/hooks/`, and
  `scripts/gauntlet.sh` is the one implementation both hooks call.
- **Two guards for mistakes nothing was catching.** `translate/merge.sh --check` fails
  when an `i18n()` call has been added, changed or removed without re-extracting, which
  would otherwise leave a string out of the template and so out of all 17 catalogues.
  `tests/metadata.test.mjs` checks `metadata.json` against the keys KDE documents and
  against the plugin id's other four homes: the widget's namespace, the install
  script's `PLUGIN_ID`, the catalogue domain and the compiled `.mo` filenames.

### Fixed

- **A session token copied from the browser now works.** The platform's `userToken`
  entry stores a JSON object, `{"value":"…","__version":"0"}`, not the token, so
  copying it literally sent `Bearer {"value":…,"__version":"0"}` and the platform
  answered `Authorization Failed (invalid token)`. The widget unwraps the entry before
  use — as it does a quoted copy or a whole `Bearer …` header pasted from the network
  tab — and the READMEs now say which part of the entry is the token.
- **The usage window survives a daylight-saving change.** `start` was "local midnight
  N days ago" and `end` was tomorrow's, so a window spanning a transition was not
  exactly N days long and its two ends implied different offsets — while the request
  carries only one. The platform refused the whole window with `biz_code 1`,
  `INVALID_PARAM`. `start` is now derived from `end` by subtraction, which is also
  what the platform's own page asks for.
- **The platform's own reason is surfaced.** `parseEnvelope` honours the
  business-level `biz_code`/`biz_msg` inside `data`; reading only the outer `code`
  reported `INVALID_PARAM` as a generic "Missing payload", which named neither the
  fault nor the field at fault.

## [0.1.1] - 2026-09-27

Nothing inside the widget changed. This release is the documentation and the
repository around it, which is why it is a patch and not a minor: no new metric, no
new section, no locale.

### Added

- A **How to get the session token** section in all seven READMEs: where the value
  lives in the browser, and the name of the key it is stored under. The credentials
  table previously said only "the value the platform site keeps after you log in".

### Changed

- The **README screenshots render invented figures.** They were taken from a snapshot
  of a real account's usage page, which published that account's balance, its spend
  and the names of its API keys in every translated README.
- The development mock serves invented figures for the same reason, and its `--check`
  still recomputes every headline total from the same tables, so the fixture cannot
  drift from the numbers it declares.
- **Commits and tags are now signed** on `main` and on `v*`, the merge guard accepts
  squash only, and a separate ruleset requires a review from a code owner.

## [0.1.0] - 2026-09-26

First public release.

### Added

- Panel chip with a configurable metric (balance, today's spend, today's tokens,
  period spend, lifetime spend) and a peak / off-peak rate indicator.
- Popup with balance, today / period / lifetime spend, an estimated time left, a
  daily-spend sparkline, a token breakdown and a per-API-key breakdown.
- Two data sources: the official balance endpoint with an API key, and the
  platform usage API with a browser session token, falling back to the balance
  when the token stops working.
- Secrets in KWallet, never in the widget's configuration.
- 17 catalogues across 7 languages, with the README translated into each.
- Numbers, money and dates rendered in each locale's own conventions.
