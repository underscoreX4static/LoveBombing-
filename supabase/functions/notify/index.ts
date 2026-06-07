// =====================================================================
//  Supabase Edge Function: "notify"
//  Sends a Telegram message SERVER-SIDE so the bot token is never in the
//  client code. The browser just calls this function; the token lives in
//  Supabase secrets.
//
//  DEPLOY (two ways):
//   A) Dashboard: Edge Functions -> Create a function -> name it "notify"
//      -> paste this file -> Deploy. Then turn OFF "Enforce JWT" so the
//      public questionnaire (index.html) can call it.
//   B) CLI:  supabase functions deploy notify --no-verify-jwt
//
//  SET THE SECRETS (do NOT reuse the old leaked token — /revoke it first
//  in @BotFather and generate a fresh one):
//   • Dashboard: Edge Functions -> Secrets -> add
//       TELEGRAM_TOKEN   = <your NEW bot token>
//       TELEGRAM_CHAT_ID = 8734644816
//   • CLI: supabase secrets set TELEGRAM_TOKEN=... TELEGRAM_CHAT_ID=...
// =====================================================================

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(payload: unknown, status = 200) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });

  const token = Deno.env.get("TELEGRAM_TOKEN");
  const chat = Deno.env.get("TELEGRAM_CHAT_ID");
  if (!token || !chat) return json({ ok: false, error: "not configured" }, 500);

  const body = await req.json().catch(() => ({} as Record<string, unknown>));
  const name = (body.name as string) || "she";
  let text: string;

  if (body.kind === "date") {
    text =
      `Brooo 💌\nDid you miss me? → YES\nWanna be my wife? → YES\n` +
      `Last date before the 88 days: ${body.slot ?? "?"}\n— ${name} 💖`;
  } else if (body.kind === "reply") {
    text = `💌 ${name} answered Day ${body.day}:\n"${body.text ?? ""}"`;
  } else {
    text = String(body.text ?? "💌 ping");
  }

  // basic guard against absurdly long payloads
  text = text.slice(0, 1500);

  const r = await fetch(`https://api.telegram.org/bot${token}/sendMessage`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ chat_id: chat, text, disable_web_page_preview: true }),
  });
  const data = await r.json().catch(() => ({ ok: false }));
  return json({ ok: !!data.ok });
});
