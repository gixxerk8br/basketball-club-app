-- ============================================================
-- WILD CATS活動管理アプリ: Supabase移行 フェーズ5(試合結果・スタッツ)
-- 作成日: 2026-08-28
--
-- このSQLは Supabase の「SQL Editor」に貼り付けて実行してください。
-- 何度実行してもエラーにならない形にしています。
-- ============================================================

-- ------------------------------------------------------------
-- 1. テーブル定義
-- ------------------------------------------------------------

-- 試合の基本情報。編集・削除は管理者のみ。
create table if not exists games (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null default '00000000-0000-0000-0000-000000000001' references clubs(id),
  opponent text not null,
  date text,
  place text,
  category text,
  round_label text,
  finished boolean not null default false,
  created_at timestamptz not null default now()
);

-- 動画・ライブ配信URL。編集は配信管理者のみ。
create table if not exists game_media (
  game_id uuid primary key references games(id) on delete cascade,
  video_url text not null default '',
  photo_url text not null default '',
  live_url text not null default '',
  is_live boolean not null default false
);

-- 試合中のスタッツ記録。承認済み会員なら誰でも記録・取消できる(既存どおり)。
create table if not exists game_live_stats (
  game_id uuid primary key references games(id) on delete cascade,
  quarters jsonb not null default '[{"home":0,"away":0},{"home":0,"away":0},{"home":0,"away":0},{"home":0,"away":0}]',
  player_stats jsonb not null default '{}',
  log jsonb not null default '[]'
);

-- ------------------------------------------------------------
-- 2. テーブルへのアクセス権限(GRANT)
-- ------------------------------------------------------------

grant select, insert, update, delete on games, game_media, game_live_stats to authenticated;

-- ------------------------------------------------------------
-- 3. RLS判定用のヘルパー関数を追加
-- ------------------------------------------------------------

-- 配信管理者(役割・権限の設定で付与された人、または管理者)かどうか
create or replace function is_live_manager()
returns boolean
language sql security definer stable
as $$
  select exists(
    select 1 from users
    where id = auth.uid() and status = 'approved' and (role = 'admin' or can_manage_live)
  );
$$;

-- ------------------------------------------------------------
-- 4. RLSを有効化
-- ------------------------------------------------------------

alter table games enable row level security;
alter table game_media enable row level security;
alter table game_live_stats enable row level security;

-- ------------------------------------------------------------
-- 5. ポリシー(このSQLは何度再実行しても安全)
-- ------------------------------------------------------------

-- games: 承認済み・停止されていない会員なら誰でも閲覧可
drop policy if exists games_select on games;
create policy games_select on games
  for select using (is_active_member() or is_admin());

-- games: 追加・変更・削除は管理者のみ
drop policy if exists games_insert on games;
create policy games_insert on games
  for insert with check (is_admin());
drop policy if exists games_update on games;
create policy games_update on games
  for update using (is_admin());
drop policy if exists games_delete on games;
create policy games_delete on games
  for delete using (is_admin());

-- game_media: 承認済み・停止されていない会員なら誰でも閲覧可
drop policy if exists game_media_select on game_media;
create policy game_media_select on game_media
  for select using (is_active_member() or is_admin());

-- game_media: 追加は管理者(試合作成時に初期行を作るため)、変更は配信管理者
drop policy if exists game_media_insert on game_media;
create policy game_media_insert on game_media
  for insert with check (is_admin());
drop policy if exists game_media_update on game_media;
create policy game_media_update on game_media
  for update using (is_live_manager());

-- game_live_stats: 承認済み・停止されていない会員なら誰でも閲覧可
drop policy if exists game_live_stats_select on game_live_stats;
create policy game_live_stats_select on game_live_stats
  for select using (is_active_member() or is_admin());

-- game_live_stats: 追加は管理者(試合作成時に初期行を作るため)、
-- 変更(スタッツ記録・取消)は承認済み会員なら誰でも(既存どおり)
drop policy if exists game_live_stats_insert on game_live_stats;
create policy game_live_stats_insert on game_live_stats
  for insert with check (is_admin());
drop policy if exists game_live_stats_update on game_live_stats;
create policy game_live_stats_update on game_live_stats
  for update using (is_active_member() or is_admin());

-- ============================================================
-- 以上でフェーズ5のテーブル・RLSは完了です。
-- ============================================================
