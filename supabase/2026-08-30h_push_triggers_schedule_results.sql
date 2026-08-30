-- ============================================================
-- WILD CATSアプリ: スケジュール・試合結果のプッシュ通知トリガー
-- 作成日: 2026-08-30
--
-- 【重要】このファイルには合言葉(TRIGGER_SECRET)を仮の値のまま
-- 入れています。このリポジトリはPublic(誰でも閲覧可能)なので、
-- 実際の値をこのファイルに書いてコミットしないでください。
-- 実行前に、チャットでお伝えした実際の値に置き換えてから、
-- Supabaseの「SQL Editor」で実行してください。
--
-- - スケジュール: 一括取り込み等での大量通知を避けるため、既存日程の
--   「更新」時のみ通知する(新規追加=INSERTは対象外)
-- - 試合結果: finishedがfalse→trueになった時のみ通知する
--   (スタッツ記録のたびに通知が飛ばないようにするため)
-- ============================================================

create extension if not exists pg_net;

-- ---- スケジュールの更新 ----
create or replace function notify_schedule_updated()
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
    body := jsonb_build_object('kind', 'schedule', 'record', row_to_json(new))
  );
  return new;
end;
$$;

drop trigger if exists schedule_days_push_notify on schedule_days;
create trigger schedule_days_push_notify
after update on schedule_days
for each row execute function notify_schedule_updated();

-- ---- 試合結果(終了時のみ) ----
create or replace function notify_game_finished()
returns trigger
language plpgsql
security definer
as $$
begin
  if new.finished = true and (old.finished is distinct from new.finished) then
    perform net.http_post(
      url := 'https://rjfbjlojnsbvcgpeccjq.supabase.co/functions/v1/send-push-notification',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-trigger-secret', '__TRIGGER_SECRET__'  -- ← ここを実際の値に置き換えてから実行してください
      ),
      body := jsonb_build_object('kind', 'results', 'record', row_to_json(new))
    );
  end if;
  return new;
end;
$$;

drop trigger if exists games_push_notify on games;
create trigger games_push_notify
after update on games
for each row execute function notify_game_finished();

-- ============================================================
-- 以上で完了です。
-- ============================================================
