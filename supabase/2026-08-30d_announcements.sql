-- ============================================================
-- WILD CATS活動管理アプリ: お知らせ(announcements)をSupabaseへ移行
-- 作成日: 2026-08-30
--
-- プッシュ通知を実装するための土台。今はブラウザのlocalStorageにしか
-- 保存されていない「お知らせ」を、他のデータと同じくSupabaseへ移す。
-- (家族間で共有されていなかった問題も、これで同時に解消される)
--
-- このSQLは Supabase の「SQL Editor」に貼り付けて実行してください。
-- 何度実行してもエラーにならない形にしています。
-- ============================================================

create table if not exists announcements (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null default '00000000-0000-0000-0000-000000000001' references clubs(id),
  category text,
  title text not null,
  body text,
  link_url text,
  link_label text,
  urgent boolean not null default false,
  date text not null,
  created_at timestamptz not null default now()
);

grant select, insert, update, delete on announcements to authenticated;

alter table announcements enable row level security;

-- 閲覧: 承認済み・停止されていない会員なら誰でも
drop policy if exists announcements_select on announcements;
create policy announcements_select on announcements
  for select using (is_active_member() or is_admin());

-- 追加・変更・削除: 管理者のみ(既存の管理画面の運用と同じ)
drop policy if exists announcements_insert on announcements;
create policy announcements_insert on announcements
  for insert with check (is_admin());
drop policy if exists announcements_update on announcements;
create policy announcements_update on announcements
  for update using (is_admin());
drop policy if exists announcements_delete on announcements;
create policy announcements_delete on announcements
  for delete using (is_admin());

-- ============================================================
-- 以上で完了です。
-- ============================================================
