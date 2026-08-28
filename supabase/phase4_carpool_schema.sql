-- ============================================================
-- WILD CATS活動管理アプリ: Supabase移行 フェーズ4(配車)
-- 作成日: 2026-08-28
--
-- このSQLは Supabase の「SQL Editor」に貼り付けて実行してください。
-- 何度実行してもエラーにならない形にしています。
-- ============================================================

-- ------------------------------------------------------------
-- 1. テーブル定義
-- ------------------------------------------------------------

-- 配車の可否回答(日程×家庭で1行)。riders は「実際に乗る家族メンバー/選手のID一覧」。
create table if not exists carpool_responses (
  date text not null references schedule_days(date) on delete cascade,
  user_id uuid not null references users(id) on delete cascade,
  status text not null,
  capacity int not null default 0,
  riders jsonb not null default '[]',
  updated_at timestamptz not null default now(),
  primary key (date, user_id)
);

-- 配車の割り当て(誰がどの車に乗るか)。person_idは選手/家族同乗者のID(uuid文字列)か
-- スポット同乗者のID('spot_...'形式)のどちらかが入るため text 型。
create table if not exists carpool_assignments (
  date text not null references schedule_days(date) on delete cascade,
  person_id text not null,
  driver_user_id uuid not null references users(id) on delete cascade,
  primary key (date, person_id)
);

-- 登録家族に属さない、その日限定の同乗者(イレギュラー対応)
create table if not exists carpool_spot_riders (
  id text primary key,
  date text not null references schedule_days(date) on delete cascade,
  name text not null
);

-- ------------------------------------------------------------
-- 2. テーブルへのアクセス権限(GRANT)
-- ------------------------------------------------------------

grant select, insert, update, delete on carpool_responses, carpool_assignments, carpool_spot_riders to authenticated;

-- ------------------------------------------------------------
-- 3. RLS判定用のヘルパー関数を追加
-- ------------------------------------------------------------

-- 配車管理者(役割・権限の設定で付与された人、または管理者)かどうか
create or replace function is_carpool_manager()
returns boolean
language sql security definer stable
as $$
  select exists(
    select 1 from users
    where id = auth.uid() and status = 'approved' and (role = 'admin' or can_manage_carpool)
  );
$$;

-- 指定した乗車者(選手/家族同乗者のID)が、自分の家庭に属する人かどうか
-- (配車を出せなくなった/配車不可でなくなった際に、自分に関係する割り当てだけを
--  配車管理者でなくても解除できるようにするために使う)
create or replace function person_belongs_to_current_family(pid text)
returns boolean
language sql security definer stable
as $$
  select exists(select 1 from family_members where id::text = pid and family_id = current_family_id())
      or exists(select 1 from players where id::text = pid and family_id = current_family_id());
$$;

-- ------------------------------------------------------------
-- 4. RLSを有効化
-- ------------------------------------------------------------

alter table carpool_responses enable row level security;
alter table carpool_assignments enable row level security;
alter table carpool_spot_riders enable row level security;

-- ------------------------------------------------------------
-- 5. ポリシー(このSQLは何度再実行しても安全)
-- ------------------------------------------------------------

-- carpool_responses: 承認済み・停止されていない会員なら誰でも閲覧可
drop policy if exists carpool_responses_select on carpool_responses;
create policy carpool_responses_select on carpool_responses
  for select using (is_active_member() or is_admin());

-- carpool_responses: 自分の家庭の回答だけ本人が登録・変更できる
drop policy if exists carpool_responses_insert on carpool_responses;
create policy carpool_responses_insert on carpool_responses
  for insert with check (user_id = auth.uid() or is_admin());
drop policy if exists carpool_responses_update on carpool_responses;
create policy carpool_responses_update on carpool_responses
  for update using (user_id = auth.uid() or is_admin());

-- carpool_assignments: 承認済み・停止されていない会員なら誰でも閲覧可
drop policy if exists carpool_assignments_select on carpool_assignments;
create policy carpool_assignments_select on carpool_assignments
  for select using (is_active_member() or is_admin());

-- carpool_assignments: 割り当ての新規作成・変更は配車管理者のみ
drop policy if exists carpool_assignments_insert on carpool_assignments;
create policy carpool_assignments_insert on carpool_assignments
  for insert with check (is_carpool_manager() or is_admin());
drop policy if exists carpool_assignments_update on carpool_assignments;
create policy carpool_assignments_update on carpool_assignments
  for update using (is_carpool_manager() or is_admin());

-- carpool_assignments: 削除は配車管理者に加えて、運転者本人・乗車者本人の家庭も
-- (「配車不可でなくなった」等の自己都合の解除ができるようにするため)
drop policy if exists carpool_assignments_delete on carpool_assignments;
create policy carpool_assignments_delete on carpool_assignments
  for delete using (
    driver_user_id = auth.uid()
    or person_belongs_to_current_family(person_id)
    or is_carpool_manager()
    or is_admin()
  );

-- carpool_spot_riders: 承認済み・停止されていない会員なら誰でも閲覧可
drop policy if exists carpool_spot_riders_select on carpool_spot_riders;
create policy carpool_spot_riders_select on carpool_spot_riders
  for select using (is_active_member() or is_admin());

-- carpool_spot_riders: 追加・削除は配車管理者のみ
drop policy if exists carpool_spot_riders_insert on carpool_spot_riders;
create policy carpool_spot_riders_insert on carpool_spot_riders
  for insert with check (is_carpool_manager() or is_admin());
drop policy if exists carpool_spot_riders_delete on carpool_spot_riders;
create policy carpool_spot_riders_delete on carpool_spot_riders
  for delete using (is_carpool_manager() or is_admin());

-- ============================================================
-- 以上でフェーズ4のテーブル・RLSは完了です。
-- ============================================================
