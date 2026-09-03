// WILD CATS活動管理アプリ: プッシュ通知を送信するEdge Function
//
// 以下のPostgresトリガー(supabase/2026-08-30f_push_trigger.sql、別途手元で用意)から
// { kind: 'announcement'|'schedule'|'results'|'fee_reminder', record: {...} } の形で呼び出される想定。
//   - announcements への新規INSERT (kind: 'announcement')
//   - schedule_days への更新(既存日程の変更のみ。一括取り込み等での大量通知を避けるためINSERTは対象外) (kind: 'schedule')
//   - games の finished が false→true になった更新(試合終了時のみ) (kind: 'results')
//   - fee_reminders への新規INSERT (kind: 'fee_reminder')。会計担当者が会計画面から
//     手動で送信する、会費未納者1人ずつへの個別通知(record.user_id宛のみに送る。
//     他の3種と違い全体配信ではないため、通知カテゴリのON/OFF設定の対象外)
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

// kindごとに「通知設定のどの列を見るか」「通知の文面をどう組み立てるか」を定義する。
// fee_reminderだけは全体配信ではなく特定の1人(targetUserId)宛のため、prefColumnはnull。
function buildNotification(kind: string, record: Record<string, unknown>) {
  if (kind === "fee_reminder") {
    const period = (record.period as string) || "今月";
    const title = "💰 会費のお支払いのお願い";
    const body = `${period}分の会費がまだ確認できていません。ご確認をお願いします。`;
    return { targetUserId: record.user_id as string, prefColumn: null, title, body };
  }
  if (kind === "schedule") {
    const dayType = (record.day_type as string) || "予定";
    const eventName = record.event_name as string | null;
    const place = record.place as string | null;
    const date = (record.date as string) || "";
    const title = "🗓️ スケジュールが更新されました";
    const body = `${date} ${dayType}${eventName ? "(" + eventName + ")" : ""}${place ? " @" + place : ""}`;
    return { targetUserId: null, prefColumn: "notify_schedule", title, body };
  }
  if (kind === "results") {
    const quarters = (record.quarters as { home: number; away: number }[]) || [];
    const home = quarters.reduce((s, q) => s + (q.home || 0), 0);
    const away = quarters.reduce((s, q) => s + (q.away || 0), 0);
    const opponent = (record.opponent as string) || "対戦相手";
    const title = `🏆 試合結果: vs ${opponent}`;
    const body = `${home} - ${away}${home > away ? "(勝利)" : home < away ? "(敗北)" : "(引き分け)"}`;
    return { targetUserId: null, prefColumn: "notify_results", title, body };
  }
  // デフォルトはお知らせ扱い
  const title = record.urgent ? `🚨 ${record.title || "お知らせ"}` : ((record.title as string) || "WILD CATS 新着のお知らせ");
  const body = (record.body as string) || "";
  return { targetUserId: null, prefColumn: "notify_announcements", title, body };
}

Deno.serve(async (req) => {
  // Postgresのトリガー以外(第三者)から呼ばれないよう、合言葉を確認する
  if (req.headers.get("x-trigger-secret") !== TRIGGER_SECRET) {
    return new Response("Unauthorized", { status: 401 });
  }

  try {
    const payload = await req.json();
    const kind = payload.kind || "announcement";
    const record = payload.record ?? {};

    // service_role権限でDBへ直接アクセスする(RLSをバイパスして全員分の購読・設定を読む必要があるため)
    const headers = {
      apikey: SERVICE_ROLE_KEY,
      Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
      "Content-Type": "application/json",
    };

    // 試合結果(kind: 'results')は、games行にスコアが無く別テーブル(game_live_stats)に
    // あるため、通知文を組み立てる前にここで取得してrecordへ合成しておく
    if (kind === "results" && record.id) {
      const statsRes = await fetch(
        `${SUPABASE_URL}/rest/v1/game_live_stats?game_id=eq.${record.id}&select=quarters`,
        { headers },
      );
      if (statsRes.ok) {
        const statsRows: { quarters: unknown }[] = await statsRes.json();
        if (statsRows[0]) record.quarters = statsRows[0].quarters;
      }
    }

    const { targetUserId, prefColumn, title, body } = buildNotification(kind, record);

    let targets: { user_id: string; endpoint: string; p256dh: string; auth: string }[];
    if (targetUserId) {
      // 個人宛(fee_reminder): その人が登録している端末の購読だけを取得する。
      // カテゴリ設定(notification_preferences)は見ない=オフにしていても届く(会計上重要な通知のため)
      const subRes = await fetch(
        `${SUPABASE_URL}/rest/v1/push_subscriptions?user_id=eq.${targetUserId}&select=*`,
        { headers },
      );
      if (!subRes.ok) throw new Error(`push_subscriptions fetch failed (${subRes.status}): ${await subRes.text()}`);
      targets = await subRes.json();
    } else {
      // 全体配信(announcement/schedule/results): この項目の通知を明示的にオフにしている人のuser_idを集める
      const offRes = await fetch(
        `${SUPABASE_URL}/rest/v1/notification_preferences?${prefColumn}=eq.false&select=user_id`,
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
      targets = subs.filter((s) => !offUserIds.has(s.user_id));
    }

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
      JSON.stringify({ kind, sent: targets.length - toDelete.length, removed: toDelete.length }),
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
