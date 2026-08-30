-- ============================================================
-- WILD CATS活動管理アプリ: プッシュ通知の宛先・設定テーブル
-- 作成日: 2026-08-30
--
-- このSQLは Supabase の「SQL Editor」に貼り付けて実行してください。
-- 何度実行してもエラーにならない形にしています。
-- ============================================================

-- 通知の送信先(端末ごとの購読情報)。1人が複数端末を持つ場合もあるため、
-- user_idに対して複数行を持てる形にする。
create table if not exists push_subscriptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references users(id) on delete cascade,
  endpoint text not null unique,
  p256dh text not null,
  auth text not null,
  created_at timestamptz not null default now()
);

-- 通知の項目ごとのオン/オフ設定(1人1行)
create table if not exists notification_preferences (
  user_id uuid primary key references users(id) on delete cascade,
  notify_announcements boolean not null default true,
  notify_schedule boolean not null default true,
  notify_results boolean not null default true
);

grant select, insert, update, delete on push_subscriptions, notification_preferences to authenticated;

alter table push_subscriptions enable row level security;
alter table notification_preferences enable row level security;

-- push_subscriptions: 本人の購読情報のみ、本人が読み書きできる
-- (実際に通知を送るサーバー側の処理は、RLSを経由しないservice_role権限で
--  全員分を読み取るため、ここは「本人のみ」で問題ない)
drop policy if exists push_subscriptions_all on push_subscriptions;
create policy push_subscriptions_all on push_subscriptions
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());

-- notification_preferences: 本人の設定のみ、本人が読み書きできる
drop policy if exists notification_preferences_all on notification_preferences;
create policy notification_preferences_all on notification_preferences
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());

-- ============================================================
-- 以上で完了です。
-- ============================================================
