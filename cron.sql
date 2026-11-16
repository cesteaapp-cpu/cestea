-- Cestea · búsqueda semanal de ofertas (opcional, después de desplegar la función "ofertas")
-- 1) Supabase → Database → Extensions: activa  pg_cron  y  pg_net.
-- 2) En Edge Functions → Secrets crea CRON_SECRET con una palabra larga inventada por ti.
-- 3) Cambia TU_CRON_SECRET (abajo) por esa misma palabra y ejecuta este SQL.

select cron.unschedule('cestea-ofertas') where exists (select 1 from cron.job where jobname = 'cestea-ofertas');

select cron.schedule(
  'cestea-ofertas',
  '17 6 * * 1',   -- lunes 06:17 UTC (07:17 o 08:17 en España)
  $$
  select net.http_post(
    url := 'https://uuysqysfunhcczxyxmnr.supabase.co/functions/v1/ofertas',
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-cron-secret', 'TU_CRON_SECRET'),
    body := jsonb_build_object('hogar_id', h.id),
    timeout_milliseconds := 140000
  )
  from public.hogares h;
  $$
);
