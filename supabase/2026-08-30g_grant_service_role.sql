-- ============================================================
-- WILD CATSアプリ: Edge Function(service_role)へのアクセス権限を追加
-- 作成日: 2026-08-30
--
-- 「自動公開」をオフにしているこのプロジェクトでは、通常のブラウザ用の
-- authenticatedロールだけでなく、Edge Functionsが使うservice_roleにも
-- 明示的にGRANTが必要だった(見落としていた)。
--
-- このSQLは Supabase の「SQL Editor」に貼り付けて実行してください。
-- ============================================================

grant select, delete on push_subscriptions to service_role;
grant select on notification_preferences to service_role;

-- ============================================================
-- 以上で完了です。
-- ============================================================
