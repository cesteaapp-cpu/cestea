// Cestea · función "ofertas": busca en la web las ofertas vigentes de los productos de la lista
// y las guarda en la familia. La llama el botón de la app o, una vez por semana, el programador (cron.sql).
// Secretos: ANTHROPIC_API_KEY (obligatorio) y CRON_SECRET (solo para el programador semanal).
import { createClient } from "npm:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-cron-secret",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const out = (b: unknown, status = 200) =>
  new Response(JSON.stringify(b), { status, headers: { ...cors, "Content-Type": "application/json" } });
const slug = (s: string) => s.toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "").replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "").slice(0, 80);

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return out({ error: "metodo" }, 405);
  try {
    const apiKey = Deno.env.get("ANTHROPIC_API_KEY");
    if (!apiKey) return out({ error: "sin_clave" }, 500);
    const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

    // ¿quién llama? un usuario de la familia, o el programador con el secreto
    let hogar: string | null = null;
    const cron = Deno.env.get("CRON_SECRET");
    const body = await req.json().catch(() => ({}));
    if (cron && req.headers.get("x-cron-secret") === cron && typeof body.hogar_id === "string") {
      hogar = body.hogar_id;
    } else {
      const jwt = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
      const { data: u, error: ue } = await admin.auth.getUser(jwt);
      if (ue || !u?.user) return out({ error: "no_auth" }, 401);
      const { data: m } = await admin.from("miembros").select("hogar_id").eq("user_id", u.user.id).maybeSingle();
      if (!m) return out({ error: "sin_hogar" }, 403);
      hogar = m.hogar_id;
    }

    const dia = new Date().toISOString().slice(0, 10);
    const { data: n } = await admin.rpc("ia_contar", { p_hogar: hogar, p_dia: dia });
    if (typeof n === "number" && n > Number(Deno.env.get("IA_LIMITE_DIA") ?? "30")) return out({ error: "limite" }, 429);

    const { data: rows } = await admin.from("items").select("coll,id,data").eq("hogar_id", hogar).in("coll", ["settings", "list"]);
    const settings = rows?.find((r) => r.coll === "settings" && r.id === "main")?.data ?? {};
    const productos: string[] = (rows ?? []).filter((r) => r.coll === "list" && !r.data?.done).map((r) => String(r.data?.name ?? "")).filter(Boolean).slice(0, 15);
    if (!productos.length) return out({ ok: true, guardadas: 0, motivo: "lista_vacia" });
    const favs: string[] = Array.isArray(settings.favs) && settings.favs.length ? settings.favs : [settings.tienda ?? "Mercadona"];
    const tiendas = favs.slice(0, 4);
    const zona = [settings.provincia, settings.comunidad].filter(Boolean).join(", ");

    const prompt =
      `Hoy es ${dia}. Busca en la web las ofertas VIGENTES esta semana en España (${zona || "España"}) de estos productos: ${productos.join(", ")}.\n` +
      `Supermercados a revisar: ${tiendas.join(", ")} (folletos semanales y webs oficiales).\n` +
      `Reglas: solo precios que veas en una fuente real y actual; no inventes nada; si no encuentras un producto, no lo incluyas. ` +
      `Responde SOLO con un array JSON, sin texto extra: [{"product":"...","store":"uno de los supermercados","price":1.99,"was":2.49,"until":"AAAA-MM-DD o vacío","note":"formato y fuente breve"}]. ` +
      `"was" es el precio anterior (0 si no consta). Máximo 25 elementos. Si no hay nada fiable, responde [].`;

    const r = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: { "x-api-key": apiKey, "anthropic-version": "2023-06-01", "content-type": "application/json" },
      body: JSON.stringify({
        model: "claude-sonnet-5-5",
        max_tokens: 4000,
        tools: [{ type: "web_search_20250305", name: "web_search", max_uses: 5, user_location: { type: "approximate", country: "ES" } }],
        messages: [{ role: "user", content: prompt }],
      }),
    });
    if (!r.ok) { console.error("anthropic", r.status, await r.text()); return out({ error: "ia_error" }, 502); }
    const j = await r.json();
    const text = (j.content ?? []).filter((c: { type: string }) => c.type === "text").map((c: { text: string }) => c.text).join("");
    const a = text.indexOf("["), b = text.lastIndexOf("]");
    let found: Array<Record<string, unknown>> = [];
    try { found = JSON.parse(text.slice(a, b + 1)); } catch { found = []; }

    const hoy = dia;
    const nuevas = found
      .filter((o) => o && typeof o.product === "string" && Number(o.price) > 0 && tiendas.includes(String(o.store)))
      .slice(0, 40)
      .map((o) => ({
        hogar_id: hogar, coll: "offers", id: "auto-" + slug(String(o.store) + " " + String(o.product)),
        data: { product: String(o.product), store: String(o.store), price: Number(o.price), was: Number(o.was) || 0, until: String(o.until ?? ""), note: "automática · " + String(o.note ?? "").slice(0, 120), ts: Date.now() },
        updated_at: new Date().toISOString(),
      }));

    // quitar las automáticas anteriores y guardar las nuevas
    const { data: viejas } = await admin.from("items").select("id").eq("hogar_id", hogar).eq("coll", "offers").like("id", "auto-%");
    const ids = (viejas ?? []).map((v) => v.id).filter((id) => !nuevas.some((n) => n.id === id));
    if (ids.length) await admin.from("items").delete().eq("hogar_id", hogar).eq("coll", "offers").in("id", ids);
    if (nuevas.length) await admin.from("items").upsert(nuevas);
    return out({ ok: true, guardadas: nuevas.length, dia: hoy });
  } catch (e) {
    console.error(e);
    return out({ error: "interno" }, 500);
  }
});
