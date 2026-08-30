-- ============================================================
-- WILD CATS活動管理アプリ: 「スタッツ管理」権限の追加
-- 作成日: 2026-08-30
--
-- このSQLは Supabase の「SQL Editor」に貼り付けて実行してください。
-- 何度実行してもエラーにならない形にしています。
-- ============================================================

-- 1. 列を追加(配車管理・会計担当・配信管理と同じ形式)
alter table users add column if not exists can_manage_stats boolean not null default false;

-- 2. スタッツ管理者(役割・権限の設定で付与された人、または管理者)かどうかを判定する関数
create or replace function is_stats_manager()
returns boolean
language sql security definer stable
as $$
  select exists(
    select 1 from users
    where id = auth.uid() and status = 'approved' and (role = 'admin' or can_manage_stats)
  );
$$;

-- 3. game_live_stats(スタッツの記録・修正)の更新ポリシーを、
--    「承認済み会員なら誰でも」から「スタッツ管理者(または管理者)のみ」に変更する。
--    閲覧(select)・試合の新規作成(insert、管理者のみ)は変更しない。
drop policy if exists game_live_stats_update on game_live_stats;
create policy game_live_stats_update on game_live_stats
  for update using (is_stats_manager() or is_admin());

-- ============================================================
-- 以上で完了です。
-- ============================================================
