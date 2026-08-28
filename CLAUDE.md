# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A single-file prototype web app for managing a youth basketball club (志免南ワイルドキャッツ / WILD CATS): schedule/calendar, carpool coordination, live game stats, results with video/live-stream embeds, club dues bookkeeping, and admin/member management. No backend — all state lives in the browser's `localStorage`. Everything is in Japanese (UI text, comments, data).

## Commands

There is no build, lint, or test tooling — this is plain HTML/CSS/JS loaded via CDN, no `package.json`, no bundler.

To preview the app, serve the directory over HTTP (opening `index.html` directly as `file://` breaks `localStorage` in some browsers):

```
npx http-server -p 5500 -c-1 .
```

`.claude/launch.json` defines this as the `static-server` preview config (port 5500, cache disabled via `-c-1` so edits show up on refresh without a hard reload).

There are no automated tests. Verify changes by loading the page, using the demo login buttons (see below), and checking the browser console for Alpine/JS errors.

## Architecture

### Single file, in-page sections

Everything — markup, styles, and logic — lives in `index.html` (~2400 lines). It is one Alpine.js component (`x-data="app()"`) covering the whole page; there is no routing, no components, no build step. Libraries are CDN `<script>` tags: Tailwind CSS (JIT, utility classes only), Alpine.js 3, and Chart.js 4.

The file is organized into two halves, both internally marked with `<!-- ===== -->` / `// =====` banners for each feature area (ホーム, スケジュール, 配車, 試合結果, スタッツ, 会計, 管理者ダッシュボード):
- **Markup** (`<body>`): screen sections gated by `x-show="activeTab==='...'"`, plus modals (day editor, announcement, game editor, live-stream setup, player detail, bylaws) toggled by `show*Modal` booleans.
- **Logic** (`<script>` near the bottom): the `app()` function returning one large Alpine data object — state, computed `get`ters, and methods, grouped by the same feature-area banners.

When editing a feature, search for its banner comment rather than scanning the whole file.

### State, persistence, and the two data-shape eras

`init()` loads `localStorage['bbclub_prototype_data']` via `Object.assign(this, JSON.parse(saved))` if present, otherwise calls `seedDemoData()` and persists. `persist()` writes a fixed subset of top-level arrays/objects back to that key (see the list in `persist()` — anything not listed there is UI-only scratch state and won't survive a reload). There's no schema migration: if you rename/restructure a persisted field, existing users' `localStorage` will hold the old shape until they hit **⚙️ 管理 → 🛠 データ管理 → すべてのデータをリセットする** (calls `resetAllData()`), which is the reset path to reach for during manual testing after a data-model change.

`seedDemoData()` builds the demo dataset in two different text-import formats that both exist in the codebase — don't confuse them:
- `parseLegacySeedText()` parses the large pipe-delimited `calendarText` block seeded from the club's real historical calendar (`日付|当番|行事名|色|予定@時間;予定@時間`). It's a one-time seed transform and infers `dayType` from the old tag/color scheme.
- `parseCalendarText()` parses the comma-delimited format (`日付,当番,種類,会場,集合場所,集合時間,メモ`) used by the live admin-facing bulk-import textarea on the schedule screen (`importScheduleCSV()`).

### Core entities and how they link

- **`members`**: login accounts (guardians), each with a `familyMembers[]` array (the guardian plus siblings/the player, each tagged with a `relation` like 選手/父/母/兄/姉/弟/妹). The signup form groups these into three visual categories (guardian/player/family-rider) via `familyMemberCategory()`, but the underlying array/shape is unchanged. Permissions are per-member booleans (`canManageCarpool`, `canManageFinance`, `canManageLive`) checked alongside `role==='admin'` via `isCarpoolManager` / `isFinanceManager` / `isLiveManager` getters — admin implies all three. `status` is `'pending' | 'approved' | 'suspended'`; suspended accounts are blocked at `login()` and re-checked on every `init()` (in case an already-logged-in session's member was suspended since the last visit). `toggleMemberSuspend()` / `deleteMemberPermanently()` (admin-only, both in the admin dashboard) never touch `players[]`/`games[]`/`scheduleDays[]`, so historical records survive a family being suspended or deleted.
- **`players`**: the stats roster (jersey number + name + `status`: `'active' | 'graduated' | 'withdrawn'`, default active). Separate from `members`/`familyMembers`. Signing up with a family member tagged 選手 auto-adds them here (see `signup()`). `removePlayer()` refuses to hard-delete a player who has any `game.playerStats` entry (redirect to changing `status` instead) — hard delete is only for roster-entry mistakes with no history. `activePlayers` (status-filtered) is used for the live stat-recording picker; the box-score tables still show `players` (all, including graduated/withdrawn) so past games keep showing everyone who played.
- **`scheduleDays`**: one entry per calendar date (`date` is the key, not an id you look up separately). A day has at most one `dayType` (練習/公式戦/カップ戦/練習試合/休み) — there's no concept of multiple events on one day. Game-type days can carry multiple `opponents[]` (for カップ戦 tournaments with several matches in a day). Attendance (`attendance{name:status}`) and carpool responses (`carpoolResponses`, `carpoolAssignments`, `carpoolSpotRiders`) are both stored **per day**, not per opponent — one carpool answer covers the whole outing even if it's a multi-game tournament day. `materials[]` (`{label, url}`) holds any number of link-only attachments (Google Drive etc. — never raw files) for that day; `saveDay()` strips out rows with an empty `url` before persisting.
- **`games`**: the stats/results record for one opponent matchup. Created lazily by `linkGamesForDay()` when a schedule day's `opponents[]` are saved — each opponent entry gets a `gameId` pointing into `games`. Editing schedule-day opponents and editing `games` are therefore two different code paths that must stay in sync; `games` also holds `videoUrl`/`photoUrl`/`liveUrl`/`isLive`/`finished` and per-quarter score (`quarters[]`) and per-player box score (`playerStats{playerId: {...}}`).
- **Carpool is managed per individual person, not per family headcount.** `carpoolResponses{memberId: {status, capacity, riders:[familyMemberId,...]}}` — `riders` is which of that family's own `familyMembers` are actually going (defaults to everyone, editable via `toggleMyCarpoolRider`). `carpoolAssignments{personId: driverMemberId}` is a flat 1:1 map (one person → at most one driver; no split/count logic needed since a person is atomic). `carpoolSpotRiders[]` (`{id, name}`) holds ad-hoc one-off riders not tied to any registered family (added/removed via `addCarpoolSpotRider()`/`removeCarpoolSpotRider()`), and they plug into the same `carpoolAssignments` map by their own `id`. The admin assembly UI lets `carpoolSelectedRiders[]` hold **multiple** selected people at once; `assignSelectedTo(driverId)` assigns all of them together and refuses the whole batch (no partial assignment) if it would exceed that driver's `capacity`. `carpoolStatusOptions` is the single source of truth for the five status values (配車可能/配車可能(別便可)/別便可/配車不可/不参加) — add new statuses there, not by hardcoding strings.
- **Live stats recording** (`recordShot`, `recordSimpleStat`): both push an entry onto `game.log[]` (tagged `kind: 'shot'|'simple'|'opp'`) before mutating `playerStats`/`quarters`, and `undoLastStat()` replays that log in reverse. When adding a new stat type, wire it into the undo path too, or undo will silently under/over-correct.
- **Finance**: `feePayments[]` (one row per member per `YYYY-MM` period) are separate from `financeEntries[]` (the income/expense ledger), linked by `linkedFeePaymentId`. `markFeePaid()` deletes-then-recreates rather than updating in place — mirror that pattern if you touch it, since it's how duplicate-entry prevention works.

### Non-obvious UI/behavior conventions

- **Chart.js instances are kept outside Alpine's reactive state** (module-level `const _charts = {}` above `function app()`), because Chart.js's internal object graph is circular and Alpine's proxy-based reactivity chokes on that. Charts are (re)created imperatively in `$nextTick()` inside `renderPlayerCompareChart()` / `renderPlayerDetailChart()`, always `.destroy()`-ing the previous instance first.
- **Live streaming is gated by the `canManageLive` permission** (checked via the `isLiveManager` getter, same pattern as `isCarpoolManager`/`isFinanceManager`), not by `isAdmin` alone. This used to be open to every logged-in member as a deliberate product decision; that was reversed on 2026-08-28 at the user's explicit request (analogous to Band's per-member posting permissions) — admins grant/revoke it per member from the 🔑役割・権限の設定 table in the admin dashboard, same UI pattern as the other two manager flags. Other game-record edits (`openGameModal`, `deleteGame`) remain admin-only by contrast.
- **Practice-day attendance is opt-out, not opt-in**: for `dayType==='練習'` the UI only offers a "mark yourself absent" toggle (`toggleMyAbsence`/`absenteeNames`), on the assumption everyone attends by default. Game-type days (公式戦/カップ戦/練習試合) use the normal 参加/不参加/未定 three-way picker. Don't unify these two without confirming — it's intentional, not leftover inconsistency.
- **Mobile bottom nav deliberately excludes 管理**: `mobileNavTabs` filters the `admin` tab out of the phone bottom-nav (too many tabs to fit on a narrow screen) and access moves to a small ⚙️ icon in the header instead. If you add another top-level tab, check both `visibleTabs` (desktop nav) and `mobileNavTabs` (phone nav) render sanely.
- **Date-keyed lookups assume `YYYY-MM-DD` strings** compared with plain string `>=`/`localeCompare` (no `Date` parsing) throughout the schedule/carpool/stats code — keep new date fields in that exact zero-padded format or comparisons/sorting will silently misbehave.
