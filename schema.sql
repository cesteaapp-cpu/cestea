-- Cestea · esquema de base de datos
-- Pégalo ENTERO en Supabase → SQL Editor → New query → Run. Se puede ejecutar más de una vez sin romper nada.

create extension if not exists pgcrypto;

-- ============ TABLAS ============
create table if not exists public.hogares (
  id uuid primary key default gen_random_uuid(),
  nombre text not null,
  codigo text not null unique,
  creado_por uuid default auth.uid() references auth.users(id) on delete set null,
  creado timestamptz not null default now()
);

create table if not exists public.miembros (
  hogar_id uuid not null references public.hogares(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  nombre text not null default 'Sin nombre',
  rol text not null default 'miembro',
  unido timestamptz not null default now(),
  primary key (hogar_id, user_id),
  unique (user_id)
);

-- Un solo almacén genérico: coll = despensa/lista/ofertas/..., id = identificador, data = contenido
create table if not exists public.items (
  hogar_id uuid not null references public.hogares(id) on delete cascade,
  coll text not null,
  id text not null,
  data jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  updated_by uuid default auth.uid(),
  primary key (hogar_id, coll, id)
);
create index if not exists items_hogar_coll on public.items (hogar_id, coll);

-- Contador diario de usos de la IA por familia (solo lo toca la función edge)
create table if not exists public.ia_uso (
  hogar_id uuid not null references public.hogares(id) on delete cascade,
  dia date not null,
  n int not null default 0,
  primary key (hogar_id, dia)
);

-- ============ SEGURIDAD (RLS) ============
alter table public.hogares enable row level security;
alter table public.miembros enable row level security;
alter table public.items enable row level security;
alter table public.ia_uso enable row level security;

create or replace function public.es_miembro(h uuid)
returns boolean language sql security definer stable set search_path = '' as $$
  select exists (select 1 from public.miembros where hogar_id = h and user_id = auth.uid());
$$;
revoke all on function public.es_miembro(uuid) from public, anon;
grant execute on function public.es_miembro(uuid) to authenticated;

drop policy if exists hogares_ver on public.hogares;
create policy hogares_ver on public.hogares for select to authenticated using (public.es_miembro(id));

drop policy if exists miembros_ver on public.miembros;
create policy miembros_ver on public.miembros for select to authenticated using (public.es_miembro(hogar_id));

drop policy if exists items_todo on public.items;
create policy items_todo on public.items for all to authenticated
  using (public.es_miembro(hogar_id)) with check (public.es_miembro(hogar_id));
-- ia_uso: sin políticas = nadie desde la app; la función edge usa la clave de servicio.

-- ============ FUNCIONES (crear / unirse / salir) ============
create or replace function public._codigo_nuevo()
returns text language plpgsql volatile set search_path = '' as $$
declare
  letras constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  c text;
begin
  loop
    c := '';
    for i in 1..8 loop
      c := c || substr(letras, 1 + floor(random() * length(letras))::int, 1);
    end loop;
    exit when not exists (select 1 from public.hogares where codigo = c);
  end loop;
  return c;
end $$;
revoke all on function public._codigo_nuevo() from public, anon, authenticated;

create or replace function public.mi_hogar()
returns json language plpgsql security definer stable set search_path = '' as $$
declare r json;
begin
  if auth.uid() is null then raise exception 'no_auth'; end if;
  select json_build_object(
    'id', h.id, 'nombre', h.nombre, 'codigo', h.codigo, 'rol', m.rol,
    'miembros', (select coalesce(json_agg(json_build_object('nombre', x.nombre, 'rol', x.rol) order by x.unido), '[]'::json)
                 from public.miembros x where x.hogar_id = h.id))
  into r
  from public.miembros m join public.hogares h on h.id = m.hogar_id
  where m.user_id = auth.uid();
  return r;
end $$;

create or replace function public.crear_hogar(p_nombre text, p_mi_nombre text)
returns json language plpgsql security definer set search_path = '' as $$
declare hid uuid; cod text;
begin
  if auth.uid() is null then raise exception 'no_auth'; end if;
  if exists (select 1 from public.miembros where user_id = auth.uid()) then raise exception 'ya_en_hogar'; end if;
  if length(trim(coalesce(p_nombre, ''))) < 2 then raise exception 'nombre_invalido'; end if;
  cod := public._codigo_nuevo();
  insert into public.hogares (nombre, codigo, creado_por) values (left(trim(p_nombre), 60), cod, auth.uid()) returning id into hid;
  insert into public.miembros (hogar_id, user_id, nombre, rol)
    values (hid, auth.uid(), left(coalesce(nullif(trim(p_mi_nombre), ''), 'Yo'), 40), 'admin');
  return public.mi_hogar();
end $$;

create or replace function public.unirse_hogar(p_codigo text, p_mi_nombre text)
returns json language plpgsql security definer set search_path = '' as $$
declare hid uuid;
begin
  if auth.uid() is null then raise exception 'no_auth'; end if;
  if exists (select 1 from public.miembros where user_id = auth.uid()) then raise exception 'ya_en_hogar'; end if;
  select id into hid from public.hogares where codigo = upper(regexp_replace(coalesce(p_codigo, ''), '[^A-Za-z0-9]', '', 'g'));
  if hid is null then raise exception 'codigo_invalido'; end if;
  insert into public.miembros (hogar_id, user_id, nombre, rol)
    values (hid, auth.uid(), left(coalesce(nullif(trim(p_mi_nombre), ''), 'Sin nombre'), 40), 'miembro');
  return public.mi_hogar();
end $$;

create or replace function public.salir_hogar()
returns void language plpgsql security definer set search_path = '' as $$
declare hid uuid;
begin
  if auth.uid() is null then raise exception 'no_auth'; end if;
  select hogar_id into hid from public.miembros where user_id = auth.uid();
  if hid is null then return; end if;
  delete from public.miembros where user_id = auth.uid();
  if not exists (select 1 from public.miembros where hogar_id = hid) then
    delete from public.hogares where id = hid;
  end if;
end $$;

create or replace function public.regenerar_codigo()
returns json language plpgsql security definer set search_path = '' as $$
declare hid uuid;
begin
  select hogar_id into hid from public.miembros where user_id = auth.uid() and rol = 'admin';
  if hid is null then raise exception 'solo_admin'; end if;
  update public.hogares set codigo = public._codigo_nuevo() where id = hid;
  return public.mi_hogar();
end $$;

-- contador de la IA: solo la función edge (clave de servicio) puede llamarlo
create or replace function public.ia_contar(p_hogar uuid, p_dia date)
returns int language sql security definer set search_path = '' as $$
  insert into public.ia_uso (hogar_id, dia, n) values (p_hogar, p_dia, 1)
  on conflict (hogar_id, dia) do update set n = public.ia_uso.n + 1
  returning n;
$$;

revoke all on function public.mi_hogar(), public.crear_hogar(text, text), public.unirse_hogar(text, text),
  public.salir_hogar(), public.regenerar_codigo(), public.ia_contar(uuid, date) from public, anon;
grant execute on function public.mi_hogar(), public.crear_hogar(text, text), public.unirse_hogar(text, text),
  public.salir_hogar(), public.regenerar_codigo() to authenticated;
grant execute on function public.ia_contar(uuid, date) to service_role;

-- ============ TIEMPO REAL ============
do $$ begin
  alter publication supabase_realtime add table public.items;
exception when duplicate_object then null; end $$;
