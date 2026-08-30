// WILD CATS活動管理アプリ: プッシュ通知を送信するEdge Function
//
// announcements テーブルへの新規INSERTをきっかけに、Postgresのトリガー
// (supabase/2026-08-30f_push_trigger.sql、別途手元で用意)から呼び出される想定。
//
// 必要な環境変数(Supabaseダッシュボード or `supabase secrets set` で設定):
//   VAPID_PUBLIC_KEY   … index.htmlのVAPID_PUBLIC_KEYと同じ値
//   VAPID_PRIVATE_KEY  … 公開しない秘密鍵(index.htmlには絶対に書かない)
//   TRIGGER_SECRET     … Postgresトリガーからの呼び出しだけを受け付けるための合言葉
// SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY は、Supabaseが自動的に環境変数として渡してくれる。

import webpush from "npm:web-push@3.6.7";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const VAPID_PUBLIC_KEY = Deno.env.get("VAPID_PUBLIC_KEY")!;
const VAPID_PRIVATE_KEY = Deno.env.get("VAPID_PRIVATE_KEY")!;
const TRIGGER_SECRET = Deno.env.get("TRIGGER_SECRET")!;

webpush.setVapidDetails("mailto:admin@example.com", VAPID_PUBLIC_KEY, VAPID_PRIVATE_KEY);

Deno.serve(async (req) => {
  // Postgresのトリガー以外(第三者)から呼ばれないよう、合言葉を確認する
  if (req.headers.get("x-trigger-secret") !== TRIGGER_SECRET) {
    return new Response("Unauthorized", { status: 401 });
  }

  try {
    const payload = await req.json();
    const record = payload.record ?? {};
    const title = record.urgent ? `🚨 ${record.title || "お知らせ"}` : (record.title || "WILD CATS 新着のお知らせ");
    const body = record.body || "";

    // service_role権限でDBへ直接アクセスする(RLSをバイパスして全員分の購読・設定を読む必要があるため)
    const headers = {
      apikey: SERVICE_ROLE_KEY,
      Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
      "Content-Type": "application/json",
    };

    // 「お知らせ」の通知を明示的にオフにしている人のuser_idを集める
    const offRes = await fetch(
      `${SUPABASE_URL}/rest/v1/notification_preferences?notify_announcements=eq.false&select=user_id`,
      { headers },
    );
    if (!offRes.ok) throw new Error(`notification_preferences fetch failed (${offRes.status}): ${await offRes.text()}`);
    const offRows: { user_id: string }[] = await offRes.json();
    const offUserIds = new Set(offRows.map((r) => r.user_id));

    // 登録されている購読(端末)を全件取得し、オフにしている人を除外する
    // (notification_preferencesに行が無い人は「初期値=オン」として扱う)
    const subRes = await fetch(`${SUPABASE_URL}/rest/v1/push_subscriptions?select=*`, { headers });
    if (!subRes.ok) throw new Error(`push_subscriptions fetch failed (${subRes.status}): ${await subRes.text()}`);
    const subs: { user_id: string; endpoint: string; p256dh: string; auth: string }[] = await subRes.json();
    const targets = subs.filter((s) => !offUserIds.has(s.user_id));

    const results = await Promise.allSettled(
      targets.map((s) =>
        webpush.sendNotification(
          { endpoint: s.endpoint, keys: { p256dh: s.p256dh, auth: s.auth } },
          JSON.stringify({ title, body, url: "./" }),
        )
      ),
    );

    // 端末側で通知が無効化された等で無効になった購読(410 Gone/404)は、DBからも削除しておく
    const toDelete: string[] = [];
    results.forEach((r, i) => {
      if (r.status === "rejected") {
        const statusCode = (r.reason && (r.reason.statusCode || r.reason.status)) || null;
        if (statusCode === 404 || statusCode === 410) toDelete.push(targets[i].endpoint);
      }
    });
    if (toDelete.length) {
      const list = toDelete.map((e) => `"${e}"`).join(",");
      await fetch(`${SUPABASE_URL}/rest/v1/push_subscriptions?endpoint=in.(${list})`, {
        method: "DELETE",
        headers,
      });
    }

    return new Response(
      JSON.stringify({ sent: targets.length - toDelete.length, removed: toDelete.length }),
      { headers: { "Content-Type": "application/json" } },
    );
  } catch (e) {
    console.error(e);
    return new Response(JSON.stringify({ error: String(e) }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }
});
