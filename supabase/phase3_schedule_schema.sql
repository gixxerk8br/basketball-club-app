-- ============================================================
-- WILD CATS活動管理アプリ: Supabase移行 フェーズ3(スケジュール・出欠)
-- 作成日: 2026-08-28
--
-- このSQLは Supabase の「SQL Editor」に貼り付けて実行してください。
-- 何度実行してもエラーにならない形にしています。
-- 配車・試合結果・スタッツ・会費は今回は対象外(引き続きlocalStorageのまま)です。
-- ============================================================

-- ------------------------------------------------------------
-- 1. テーブル定義
-- ------------------------------------------------------------

-- 日程(1日1件)。配車データ(carpoolResponses等)は今回は含まず、引き続き端末側で管理する。
create table if not exists schedule_days (
  date text primary key,
  club_id uuid not null default '00000000-0000-0000-0000-000000000001' references clubs(id),
  duty text,
  day_type text,
  meet_place text,
  meet_time text,
  place text,
  memo text,
  opponents jsonb not null default '[]',
  materials jsonb not null default '[]',
  created_at timestamptz not null default now()
);

-- 出欠(日程 × ログインユーザーで1行)。以前は氏名文字列でキーにしていたが、user_idに変更する。
create table if not exists attendance (
  date text not null references schedule_days(date) on delete cascade,
  user_id uuid not null references users(id) on delete cascade,
  status text not null check (status in ('yes', 'no', 'undecided')),
  updated_at timestamptz not null default now(),
  primary key (date, user_id)
);

-- ------------------------------------------------------------
-- 2. テーブルへのアクセス権限(GRANT)
--   (「Automatically expose new tables」をオフにしているため、フェーズ2と同様に必要)
-- ------------------------------------------------------------

grant select, insert, update, delete on schedule_days, attendance to authenticated;

-- ------------------------------------------------------------
-- 3. RLSを有効化
-- ------------------------------------------------------------

alter table schedule_days enable row level security;
alter table attendance enable row level security;

-- ------------------------------------------------------------
-- 4. ポリシー(このSQLは何度再実行しても安全)
-- ------------------------------------------------------------

-- schedule_days: 承認済み・停止されていない会員なら誰でも閲覧可
drop policy if exists schedule_days_select on schedule_days;
create policy schedule_days_select on schedule_days
  for select using (is_active_member() or is_admin());

-- schedule_days: 登録・変更・削除は管理者のみ(既存の管理者限定編集と一致)
drop policy if exists schedule_days_insert on schedule_days;
create policy schedule_days_insert on schedule_days
  for insert with check (is_admin());
drop policy if exists schedule_days_update on schedule_days;
create policy schedule_days_update on schedule_days
  for update using (is_admin());
drop policy if exists schedule_days_delete on schedule_days;
create policy schedule_days_delete on schedule_days
  for delete using (is_admin());

-- attendance: 承認済み・停止されていない会員なら誰でも閲覧可(参加人数の集計等に必要)
drop policy if exists attendance_select on attendance;
create policy attendance_select on attendance
  for select using (is_active_member() or is_admin());

-- attendance: 自分の出欠だけ本人が登録・変更できる(管理者はどの家庭の分でも可)
drop policy if exists attendance_insert on attendance;
create policy attendance_insert on attendance
  for insert with check (user_id = auth.uid() or is_admin());
drop policy if exists attendance_update on attendance;
create policy attendance_update on attendance
  for update using (user_id = auth.uid() or is_admin());

-- ============================================================
-- 以上でフェーズ3のテーブル・RLSは完了です。
-- ============================================================
