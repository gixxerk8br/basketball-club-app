-- ============================================================
-- WILD CATS活動管理アプリ: クラブ全体の設定(Band URL等)を保存するテーブル
-- 作成日: 2026-08-30
--
-- このSQLは Supabase の「SQL Editor」に貼り付けて実行してください。
-- 何度実行してもエラーにならない形にしています。
-- ============================================================

-- クラブ全体の設定(1行のみ運用。finance_settingsと同じパターン)
create table if not exists club_settings (
  club_id uuid primary key default '00000000-0000-0000-0000-000000000001' references clubs(id),
  band_url text
);
insert into club_settings (club_id)
values ('00000000-0000-0000-0000-000000000001')
on conflict (club_id) do nothing;

grant select, insert, update, delete on club_settings to authenticated;

alter table club_settings enable row level security;

-- 閲覧: 承認済み・停止されていない会員なら誰でも(Bandを見る/配信するボタンで全員が使うため)
drop policy if exists club_settings_select on club_settings;
create policy club_settings_select on club_settings
  for select using (is_active_member() or is_admin());

-- 変更: 管理者のみ
drop policy if exists club_settings_update on club_settings;
create policy club_settings_update on club_settings
  for update using (is_admin());

-- ============================================================
-- 以上で完了です。
-- ============================================================
