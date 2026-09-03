-- ============================================================
-- WILD CATSアプリ: 会費未納の方への個別プッシュ通知(手動送信)
-- 作成日: 2026-09-02
--
-- 会計担当者(または管理者)が会計画面から「未払いの方に通知を送る」を
-- 押すと、未納の人1人につき1行このテーブルへ記録が入り、それをきっかけに
-- その人だけにプッシュ通知が送られる(お知らせ・スケジュール等の全体配信とは
-- 異なり、対象者個人だけに届く。通知カテゴリのON/OFF設定の対象外)。
--
-- 【重要】このファイルには合言葉(TRIGGER_SECRET)を仮の値のまま
-- 入れています。このリポジトリはPublic(誰でも閲覧可能)なので、
-- 実際の値をこのファイルに書いてコミットしないでください。
-- 実行前に、チャットでお伝えした実際の値に置き換えてから、
-- Supabaseの「SQL Editor」で実行してください。
--
-- 事前準備: Edge Function「send-push-notification」を、fee_reminder対応版に
-- 再デプロイしておく必要があります(別途チャットでご案内します)。
--
-- このSQLは Supabase の「SQL Editor」に貼り付けて実行してください。
-- 何度実行してもエラーにならない形にしています。
-- ============================================================

create extension if not exists pg_net;

create table if not exists fee_reminders (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null default '00000000-0000-0000-0000-000000000001' references clubs(id),
  user_id uuid not null references users(id) on delete cascade,
  period text not null, -- 'YYYY-MM'(どの月分の未納についての通知か)
  created_at timestamptz not null default now()
);

grant select, insert on fee_reminders to authenticated;
grant select on fee_reminders to service_role;

alter table fee_reminders enable row level security;

-- 会計担当者(is_finance_manager、管理者含む)のみ閲覧・送信できる
drop policy if exists fee_reminders_all on fee_reminders;
create policy fee_reminders_all on fee_reminders
  for all using (is_finance_manager()) with check (is_finance_manager());

-- ---- 挿入時にプッシュ通知を送るトリガー ----
create or replace function notify_fee_reminder()
returns trigger
language plpgsql
security definer
as $$
begin
  perform net.http_post(
    url := 'https://rjfbjlojnsbvcgpeccjq.supabase.co/functions/v1/send-push-notification',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-trigger-secret', '__TRIGGER_SECRET__'  -- ← ここを実際の値に置き換えてから実行してください
    ),
    body := jsonb_build_object('kind', 'fee_reminder', 'record', row_to_json(new))
  );
  return new;
end;
$$;

drop trigger if exists fee_reminders_push_notify on fee_reminders;
create trigger fee_reminders_push_notify
after insert on fee_reminders
for each row execute function notify_fee_reminder();

-- ============================================================
-- 以上で完了です。
-- ============================================================
