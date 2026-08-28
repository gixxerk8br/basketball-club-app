-- ============================================================
-- WILD CATS活動管理アプリ: Supabase移行 フェーズ6(会費・会計)
-- 作成日: 2026-08-28
--
-- このSQLは Supabase の「SQL Editor」に貼り付けて実行してください。
-- 何度実行してもエラーにならない形にしています。
-- ============================================================

-- ------------------------------------------------------------
-- 1. テーブル定義
-- ------------------------------------------------------------

-- 月会費の設定(1行のみ運用)
create table if not exists finance_settings (
  club_id uuid primary key default '00000000-0000-0000-0000-000000000001' references clubs(id),
  monthly_fee int not null default 3000
);
insert into finance_settings (club_id, monthly_fee)
values ('00000000-0000-0000-0000-000000000001', 3000)
on conflict (club_id) do nothing;

-- 会費の納付記録
create table if not exists fee_payments (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null default '00000000-0000-0000-0000-000000000001' references clubs(id),
  user_id uuid not null references users(id) on delete cascade,
  period text not null, -- 'YYYY-MM'
  amount int not null,
  paid_date text,
  created_at timestamptz not null default now()
);

-- 収入・支出の帳簿
create table if not exists finance_entries (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null default '00000000-0000-0000-0000-000000000001' references clubs(id),
  date text,
  type text not null check (type in ('income', 'expense')),
  category text,
  description text,
  amount int not null,
  linked_fee_payment_id uuid references fee_payments(id) on delete set null,
  created_at timestamptz not null default now()
);

-- ------------------------------------------------------------
-- 2. テーブルへのアクセス権限(GRANT)
-- ------------------------------------------------------------

grant select, insert, update, delete on finance_settings, fee_payments, finance_entries to authenticated;

-- ------------------------------------------------------------
-- 3. RLS判定用のヘルパー関数を追加
-- ------------------------------------------------------------

-- 会計担当者(役割・権限の設定で付与された人、または管理者)かどうか
create or replace function is_finance_manager()
returns boolean
language sql security definer stable
as $$
  select exists(
    select 1 from users
    where id = auth.uid() and status = 'approved' and (role = 'admin' or can_manage_finance)
  );
$$;

-- ------------------------------------------------------------
-- 4. RLSを有効化
-- ------------------------------------------------------------

alter table finance_settings enable row level security;
alter table fee_payments enable row level security;
alter table finance_entries enable row level security;

-- ------------------------------------------------------------
-- 5. ポリシー(このSQLは何度再実行しても安全)
--    会計は「会計担当者または管理者」のみが閲覧・記録できる(画面自体もこの権限でしか開けない)。
-- ------------------------------------------------------------

drop policy if exists finance_settings_all on finance_settings;
create policy finance_settings_all on finance_settings
  for all using (is_finance_manager()) with check (is_finance_manager());

drop policy if exists fee_payments_all on fee_payments;
create policy fee_payments_all on fee_payments
  for all using (is_finance_manager()) with check (is_finance_manager());

drop policy if exists finance_entries_all on finance_entries;
create policy finance_entries_all on finance_entries
  for all using (is_finance_manager()) with check (is_finance_manager());

-- ============================================================
-- 以上でフェーズ6(最終フェーズ)のテーブル・RLSは完了です。
-- ============================================================
