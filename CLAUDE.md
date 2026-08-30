# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A single-file web app for managing a youth basketball club (志免南ワイルドキャッツ / WILD CATS): schedule/calendar, carpool coordination, live game stats, results with video/live-stream embeds, club dues bookkeeping, push notifications, and admin/member management. Backed by **Supabase** (Postgres + Auth + Row Level Security + Edge Functions) — there is no other backend framework. Deployed as a static site via **GitHub Pages**, publicly at https://gixxerk8br.github.io/basketball-club-app/. Everything is in Japanese (UI text, comments, data).

The repo (`gixxerk8br/basketball-club-app`) is **Public**. Never commit real secret values (API private keys, webhook shared secrets) — see "Push notifications" below for how this project handles that.

## Commands

No build/lint/test tooling for the front end — plain HTML/CSS/JS loaded via CDN (Tailwind CSS JIT, Alpine.js 3, Chart.js 4), no `package.json`, no bundler.

Preview locally (serving over HTTP matters — `file://` breaks Supabase session handling and localStorage in some browsers):
```
npx http-server -p 5500 -c-1 .
```
`.claude/launch.json` defines this as the `static-server` preview config.

**Deploying the front end**: any commit pushed to `main` auto-publishes to GitHub Pages within about a minute — no manual deploy step, no build.

**Deploying the Edge Function** (only needed if you touch `supabase/functions/send-push-notification/`):
```
npx supabase functions deploy send-push-notification --no-verify-jwt
```
The Supabase CLI is linked to project ref `rjfbjlojnsbvcgpeccjq`. On this machine its login session is shared between the user's own PowerShell and Claude's Bash tool (same OS user account), so `npx supabase db query --linked "<sql>"` can run SQL directly against the live database from either — this is how Edge Function debugging and one-off test-data insert/cleanup got done during development. Treat this as real production access: prefer handing the user a SQL file to run for anything that changes durable schema/policy (keeps a record, matches how every other migration in `supabase/*.sql` was delivered), but ad-hoc verification/cleanup queries run directly are fine — always clean up any test rows immediately after.

There are no automated tests. Verify changes by loading the page, logging in (or driving `window.Alpine.$data(document.querySelector('[x-data]'))` directly in a test tab), and checking the browser console for errors.

## Architecture

### Single file, Supabase-backed

Everything — markup, styles, and logic — still lives in `index.html`, one Alpine.js component (`x-data="app()"`) covering the whole page; no routing, no components, no build step. The file is organized into two halves, both internally marked with `<!-- ===== -->` / `// =====` banners for each feature area (ホーム, スケジュール, 配車, 試合結果, スタッツ, 会計, 管理者ダッシュボード). When editing a feature, search for its banner comment rather than scanning the whole file.

What changed from the original prototype: nearly all state now lives in Supabase, fetched after login and written back immediately on each mutation — there is no batch "save" step and no meaningful localStorage persistence anymore. `persist()` is now a no-op (kept only so old call sites don't error); the only thing ever written to `localStorage` today is the "remember last login email" convenience value.

Supabase client setup (top of the `<script>` block): `SUPABASE_URL`, `SUPABASE_ANON_KEY` (safe to expose in client code — RLS enforces actual access), `CLUB_ID` (fixed single-tenant UUID, matches the row inserted by `supabase/phase2_schema.sql`), `sb` (the client instance, named to avoid colliding with the CDN's global `supabase`), `VAPID_PUBLIC_KEY` (for push notifications, also safe to expose).

### Fetch-and-reconstruct pattern

Every feature area follows the same shape: `fetchXFromSupabase()` fetches one or more normalized Postgres tables in parallel (`Promise.all`), then reconstructs them into the exact nested JS object shapes the UI already expects — e.g. `scheduleDays[]` merges `schedule_days` + `attendance` + `carpool_responses` + `carpool_assignments` + `carpool_spot_riders`; `games[]` merges `games` + `game_media` + `game_live_stats`. Mutators write to Supabase first, then optimistically patch the local mirror so the UI updates without a refetch. All the fetches run inside `loadCurrentUserFromSupabase()`, called both on login and on session restore in `init()`.

### RLS and the permission model

Every table has RLS enabled. Roles: `role==='admin'` on a `users` row implies every other permission. Below that, four independent per-member boolean flags grant scoped authority, each with an `isXManager` getter that ORs the flag with `isAdmin`: `canManageCarpool`→`isCarpoolManager`, `canManageFinance`→`isFinanceManager`, `canManageLive`→`isLiveManager`, `canManageStats`→`isStatsManager`. Admins grant/revoke these per member from the 🔑役割・権限の設定 table in the admin dashboard — all four go through one generic `toggleMemberFlag(id, flag, checked)` with a `columnMap`; add new flags there, not a bespoke function. Tab visibility (`visibleTabs`) hides the 会費/スタッツ tabs entirely (not just their contents) for members without the matching flag.

For games specifically, the model is deliberately split three ways at the **table** level, not just in the UI: `games` (core: opponent/date/category/finished — admin-only insert/update/delete), `game_media` (video/live-stream URLs — insert admin-only, update requires `isLiveManager`), `game_live_stats` (quarters/playerStats/log — insert admin-only, update requires `isStatsManager`). This was an explicit user decision (asked via a plan-mode question, not assumed) to keep "who can create a game record" separate from "who can stream it" separate from "who can record its stats" — enforced at RLS, not just hidden buttons. Creating a brand-new `games` row (i.e. registering a new opponent) stays admin-only everywhere, including the stats screen's own quick-add — a non-admin `isStatsManager` can only record stats for opponents an admin already registered.

RLS helper functions (all `SECURITY DEFINER`, to avoid self-recursion): `is_admin()`, `is_active_member()`, `current_family_id()`, `is_carpool_manager()`, `is_finance_manager()`, `is_live_manager()`, `is_stats_manager()`, `person_belongs_to_current_family(pid)`.

**"Automatically expose new tables" is disabled on this Supabase project.** Every new table needs an explicit `grant ... to authenticated` (for the browser client) — and, separately, `grant ... to service_role` for any table an Edge Function needs to read/write, since `service_role` bypasses RLS but not GRANTs. Easy to forget the `service_role` half specifically (bit twice while building push notifications, on `notification_preferences`/`push_subscriptions` and again on `game_live_stats`) — if a new Edge Function starts throwing "permission denied for table X", check this first.

### Core entities (Supabase tables → JS shapes)

- **users/families/family_members/players** ↔ `members[]`/`players[]`: one login (`users` row, `role` admin/member, `status` pending/approved/suspended) per family; `family_id` links siblings/guardians (`family_members`, no login of their own) and the stats roster (`players`; hard-delete is blocked once any `game_live_stats.player_stats` entry references them — change `status` instead). Self-service editing lives in the 👤 個人設定 modal: members can add/edit/delete their own `family_members` rows and *add* (but not edit/delete) their own `players` rows — editing/deleting an existing player stays admin-only, matching `players_update`/`players_delete` RLS, to protect stats integrity.
- **schedule_days** (+ `event_name`, added 2026-08-30) **+ attendance + carpool_*** ↔ `scheduleDays[]`. `event_name` is the dedicated "what's happening" field (tournament name, etc.) — added because `memo` used to double as this, conflating the event title with free-form notes. The CSV bulk-import (`parseCalendarText()`) carries `event_name` as an **optional trailing 8th column** specifically for backward compatibility with already-shared CSV text in the old 7-column order — never reorder existing CSV columns, only append.
- **games/game_media/game_live_stats** ↔ `games[]` (see the RLS split above). Removing an opponent chip in the day editor (`removeOpponent()`) now also deletes the linked `games` row (cascades to `game_media`/`game_live_stats`) if one was already created — confirmed via a dialog, since it can delete real recorded stats.
- **finance_settings/fee_payments/finance_entries** ↔ `financeSettings`/`feePayments`/`financeEntries` (unchanged shape from the original design).
- **announcements** (migrated to Supabase 2026-08-30; previously localStorage-only, which meant it never synced between family members' devices) ↔ `announcements[]`.
- **club_settings** (added 2026-08-30) — one row, admin-editable via ⚙️管理: `band_url` (opens Band's group page — "Bandを見る") and `band_live_url` (opens Band's `/create-live` page — "Bandで配信する"), both surfaced as Home-screen quick-access buttons that individually hide until their URL is set. **In-app camera-capture live streaming was deliberately not built** — there's no free way to do real-time video ingest/transcode/CDN delivery at this project's budget — Band's own LIVE feature is the actual delivery mechanism; this app only deep-links into it, with a confirm-dialog on the broadcast button to guard against accidental taps.
- **push_subscriptions/notification_preferences** (added 2026-08-30) — see "Push notifications" below.

### Push notifications

Full pipeline: browser Notification permission → `sw.js` (service worker; **must stay at the site root**, not moved into a subfolder, or its scope breaks) registers a push subscription against `VAPID_PUBLIC_KEY` → saved to `push_subscriptions` (one row per device, since one person may have several) → `notification_preferences` (one row per user, three booleans; a missing row means "all categories on" — the client and the Edge Function both treat absence as the default-on case, so don't assume every subscriber has a preferences row).

Sending is server-side. Postgres triggers (`pg_net.http_post`, defined in `supabase/2026-08-30f_push_trigger.sql` and `supabase/2026-08-30h_push_triggers_schedule_results.sql`) call the `send-push-notification` Edge Function (`supabase/functions/send-push-notification/index.ts`) on:
- `announcements` **AFTER INSERT**
- `schedule_days` **AFTER UPDATE only** (deliberately not INSERT — a bulk CSV import would otherwise fire dozens of notifications at once)
- `games` **AFTER UPDATE only when `finished` flips false→true** (not on every stat recorded, which would be constant noise during a live game)

The Edge Function branches on a `kind` field in the trigger payload (`'announcement' | 'schedule' | 'results'`), maps it to the matching `notification_preferences` column, and — for `results` specifically — makes an extra fetch to `game_live_stats` since the `games` row itself has no score column. Auth between trigger and function is a shared `TRIGGER_SECRET` header (`x-trigger-secret`), not a real Supabase JWT (function deployed with `--no-verify-jwt`), since this is a server-to-server call with no browser-facing caller.

**Secrets never live in this repo.** `VAPID_PRIVATE_KEY` and `TRIGGER_SECRET` are set as Edge Function secrets once via `npx supabase secrets set KEY=value` (from the user's own terminal originally, to avoid Claude ever handling a Supabase personal access token). The trigger SQL files committed here keep the real `TRIGGER_SECRET` redacted as `__TRIGGER_SECRET__` with a comment explaining why — if you regenerate either secret, re-deploy the function and re-run the trigger SQL with the new value substituted in a local copy, never committed.

**iOS Safari only delivers push notifications if the site was added to the Home Screen first** (iOS 16.4+) — a plain Safari tab doesn't receive them. This is a platform limitation to communicate to users, not a bug to chase.

### Non-obvious UI/behavior conventions

- **Chart.js instances are kept outside Alpine's reactive state** (module-level `const _charts = {}` above `function app()`), because Chart.js's internal object graph is circular and Alpine's proxy-based reactivity chokes on that. Charts are (re)created imperatively in `$nextTick()` inside `renderPlayerCompareChart()` / `renderPlayerDetailChart()`, always `.destroy()`-ing the previous instance first.
- **Live-record editing (`canManageLive`) and stats-recording (`canManageStats`) are both gated by their own permission flag**, same `isXManager` pattern — not by `isAdmin` alone. Other game-record edits (`openGameModal`, `deleteGame`, adding a new opponent from anywhere) remain admin-only by contrast.
- **Practice-day attendance is opt-out, not opt-in**: for `dayType==='練習'` the UI only offers a "mark yourself absent" toggle (`toggleMyAbsence`/`absenteeNames`), on the assumption everyone attends by default. Game-type days (公式戦/カップ戦/練習試合) use the normal 参加/不参加/未定 three-way picker. Don't unify these two without confirming — it's intentional.
- **Mobile bottom nav deliberately excludes 管理**: `mobileNavTabs` filters the `admin` tab out of the phone bottom-nav and access moves to a small ⚙️ icon in the header instead (admin-only). Separately, a 👤 icon in the header (visible to **everyone**, not admin-gated) opens the 個人設定 modal — notification preferences, logged-in email display, password change, and the self-service family-member editing described above. Don't conflate the two header icons; they're different audiences.
- **Date-keyed lookups assume `YYYY-MM-DD` strings** compared with plain string `>=`/`localeCompare` (no `Date` parsing) throughout the schedule/carpool/stats code — keep new date fields in that exact zero-padded format or comparisons/sorting will silently misbehave.
- **`carpoolAgendaEvents` (配車) vs `gameAgendaEvents` (スタッツ) intentionally use different filters** over the same `scheduleDays[]`: carpool shows any non-練習/非-休み day regardless of whether opponents are registered yet (carpool logistics often need arranging before the bracket draw is known), while stats requires `opponents.length` since each opponent maps 1:1 to a `games` row. If you add a third day-selector somewhere, pick deliberately rather than copy-pasting one of these.
