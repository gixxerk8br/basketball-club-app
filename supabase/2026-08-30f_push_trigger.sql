-- ============================================================
-- WILD CATS活動管理アプリ: お知らせ投稿時にプッシュ通知を送るトリガー
-- 作成日: 2026-08-30
--
-- 【重要】このファイルには合言葉(TRIGGER_SECRET)を仮の値のまま
-- 入れています。このリポジトリはPublic(誰でも閲覧可能)なので、
-- 実際の値をこのファイルに書いてコミットしないでください。
-- 実行前に、チャットでお伝えした実際の値に置き換えてから、
-- Supabaseの「SQL Editor」で実行してください(このファイル自体を
-- 直接コピーして使わないよう、お願いします)。
--
-- 事前準備: Edge Function「send-push-notification」のデプロイと、
-- そのFunctionにTRIGGER_SECRET等のシークレットを設定しておく必要があります
-- (この手順は別途チャットでご案内します)。
-- ============================================================

create extension if not exists pg_net;

create or replace function notify_new_announcement()
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
    body := jsonb_build_object('record', row_to_json(new))
  );
  return new;
end;
$$;

drop trigger if exists announcements_push_notify on announcements;
create trigger announcements_push_notify
after insert on announcements
for each row execute function notify_new_announcement();

-- ============================================================
-- 以上で完了です。
-- ============================================================
