-- ============================================================
-- WILD CATS活動管理アプリ: Supabase移行 フェーズ2(認証・会員情報)
-- 作成日: 2026-08-28
--
-- このSQLは Supabase の「SQL Editor」に貼り付けて実行してください。
-- 対象は「ログイン・家庭・選手ロースター」の5テーブルのみです。
-- スケジュール・配車・試合結果・会計は次のフェーズで別途追加します。
-- ============================================================

-- ------------------------------------------------------------
-- 1. テーブル定義
-- ------------------------------------------------------------

-- クラブ(将来の複数クラブ対応の土台。今は1行のみ運用)
create table if not exists clubs (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  created_at timestamptz not null default now()
);

-- 家庭(在籍状態: active=利用中 / suspended=利用停止)
create table if not exists families (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references clubs(id),
  status text not null default 'active' check (status in ('active', 'suspended')),
  created_at timestamptz not null default now()
);

-- ログインアカウント(Supabase Authの auth.users と1:1で対応)
create table if not exists users (
  id uuid primary key references auth.users(id) on delete cascade,
  club_id uuid not null references clubs(id),
  family_id uuid not null references families(id),
  name text not null,
  email text not null,
  role text not null default 'member' check (role in ('admin', 'member')),
  can_manage_carpool boolean not null default false,
  can_manage_finance boolean not null default false,
  can_manage_live boolean not null default false,
  status text not null default 'pending' check (status in ('pending', 'approved', 'suspended')),
  created_at timestamptz not null default now()
);

-- 選手ロースター(スタッツ記録用。既存の players[] に対応)
create table if not exists players (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references clubs(id),
  family_id uuid references families(id),
  name text not null,
  number text,
  status text not null default 'active' check (status in ('active', 'graduated', 'withdrawn')),
  created_at timestamptz not null default now()
);

-- ログインを持たない家族(もう一方の保護者、または家族同乗者)
create table if not exists family_members (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references families(id),
  kind text not null check (kind in ('guardian', 'rider')),
  name text not null,
  relation text,
  created_at timestamptz not null default now()
);

-- ------------------------------------------------------------
-- 1.5 テーブルへのアクセス権限(GRANT)を付与
--   プロジェクト作成時に「Automatically expose new tables」をオフにしたため、
--   新しく作ったテーブルにはAPI経由でアクセスするための権限がまだ無い。
--   ここで明示的に付与する(実際に何が見えるか・書けるかは、この後設定するRLSポリシーが決める)。
-- ------------------------------------------------------------

grant usage on schema public to authenticated;
grant select, insert, update, delete on clubs, families, users, players, family_members to authenticated;

-- ------------------------------------------------------------
-- 2. 固定のクラブ行を1つだけ作成(アプリ側にも同じIDを埋め込みます)
-- ------------------------------------------------------------

insert into clubs (id, name)
values ('00000000-0000-0000-0000-000000000001', '志免南ワイルドキャッツ')
on conflict (id) do nothing;

-- ------------------------------------------------------------
-- 3. RLS判定用のヘルパー関数(SECURITY DEFINERでポリシーの無限再帰を防ぐ)
-- ------------------------------------------------------------

create or replace function current_family_id()
returns uuid
language sql security definer stable
as $$
  select family_id from users where id = auth.uid();
$$;

create or replace function is_admin()
returns boolean
language sql security definer stable
as $$
  select exists(
    select 1 from users where id = auth.uid() and role = 'admin' and status = 'approved'
  );
$$;

create or replace function is_active_member()
returns boolean
language sql security definer stable
as $$
  select exists(
    select 1 from users where id = auth.uid() and status = 'approved'
  );
$$;

-- ------------------------------------------------------------
-- 4. RLSを有効化
-- ------------------------------------------------------------

alter table clubs enable row level security;
alter table families enable row level security;
alter table users enable row level security;
alter table players enable row level security;
alter table family_members enable row level security;

-- ------------------------------------------------------------
-- 5. ポリシー
-- ------------------------------------------------------------

-- (このSQLは何度再実行しても安全なように、作成前に同名のポリシーを一旦削除します)

-- clubs: 承認済み会員・管理者のみ閲覧可(書き込みは今回は無し)
drop policy if exists clubs_select on clubs;
create policy clubs_select on clubs
  for select using (is_active_member() or is_admin());

-- families: 承認済み・停止されていない会員なら誰でも閲覧可(配車で他家庭の名前を表示するため)
--   停止中(suspended)・承認待ち(pending)のアカウントは is_active_member() が false になるため何も見えない
drop policy if exists families_select on families;
create policy families_select on families
  for select using (is_active_member() or is_admin());

-- families: サインアップ中の認証済みユーザーなら新規作成可
--   (対応する users 行が無い空の family 行が作られても実害が無いための簡略化)
drop policy if exists families_insert on families;
create policy families_insert on families
  for insert to authenticated with check (true);

-- families: 更新(利用停止/再開)は管理者のみ
drop policy if exists families_update on families;
create policy families_update on families
  for update using (is_admin());

-- users: 承認済み・停止されていない会員なら誰でも全件を閲覧可(配車の相手家庭の名前表示等に必要)。
--   停止中・承認待ちのアカウントは自分自身の行しか見えない(is_active_member()がfalseのため)
drop policy if exists users_select on users;
create policy users_select on users
  for select using (id = auth.uid() or is_active_member() or is_admin());

-- users: サインアップ時、自分自身のidでのみ作成可
drop policy if exists users_insert on users;
create policy users_insert on users
  for insert to authenticated with check (id = auth.uid());

-- users: 更新(承認・権限付与・停止)は管理者のみ
--   (本人による自己編集は今のアプリに機能自体が無いため許可しない)
drop policy if exists users_update on users;
create policy users_update on users
  for update using (is_admin());

-- users: 完全削除は管理者のみ
drop policy if exists users_delete on users;
create policy users_delete on users
  for delete using (is_admin());

-- players: ロースターは承認済み会員なら誰でも閲覧可
drop policy if exists players_select on players;
create policy players_select on players
  for select using (is_active_member() or is_admin());

-- players: サインアップ時に自分の家庭の選手として登録可能。それ以外の更新・削除は管理者のみ
drop policy if exists players_insert on players;
create policy players_insert on players
  for insert with check (family_id = current_family_id() or is_admin());
drop policy if exists players_update on players;
create policy players_update on players
  for update using (is_admin());
drop policy if exists players_delete on players;
create policy players_delete on players
  for delete using (is_admin());

-- family_members: 承認済み・停止されていない会員なら誰でも閲覧可(配車の同乗者表示に必要)
drop policy if exists family_members_select on family_members;
create policy family_members_select on family_members
  for select using (is_active_member() or is_admin());

-- family_members: サインアップ時、自分の家庭分として作成可(管理者は誰の分でも可)
drop policy if exists family_members_insert on family_members;
create policy family_members_insert on family_members
  for insert with check (family_id = current_family_id() or is_admin());

-- family_members: 更新・削除は自分の家庭分 or 管理者
drop policy if exists family_members_update on family_members;
create policy family_members_update on family_members
  for update using (family_id = current_family_id() or is_admin());
drop policy if exists family_members_delete on family_members;
create policy family_members_delete on family_members
  for delete using (family_id = current_family_id() or is_admin());

-- ============================================================
-- 以上でフェーズ2のテーブル・RLSは完了です。
--
-- 【重要】実行後、最初の管理者アカウントを作る手順:
-- 1. まずアプリ(index.html)から通常どおり1回サインアップしてください
-- 2. Supabaseの「Table Editor」→ users テーブルを開く
-- 3. 自分の行を見つけて、role列を admin に、status列を approved に書き換えて保存
-- これで管理者としてログインできるようになります(以降は管理画面から他の家庭を承認できます)。
-- ============================================================
