# Cestea · puesta en marcha

Enlace final de la app: **https://cesteaapp-cpu.github.io/cestea/**

## 1. Base de datos (Supabase, 2 minutos)
1. Entra en tu proyecto **cestea** → **SQL Editor** → **New query**.
2. Abre `supabase/schema.sql`, copia TODO su contenido, pégalo y pulsa **Run**. Debe decir "Success".

## 2. Ajustes de acceso (Supabase)
1. **Authentication → Sign In / Providers → Email**: desactiva **Confirm email** (así podéis entrar sin esperar a un correo).
2. **Authentication → URL Configuration**:
   - Site URL: `https://cesteaapp-cpu.github.io/cestea/`
   - Redirect URLs: añade la misma dirección.

## 3. Subir la app a GitHub
1. Descomprime el zip.
2. Abre https://github.com/cesteaapp-cpu/cestea → **Add file → Upload files**.
3. Arrastra el CONTENIDO de la carpeta (index.html, config.js, sw.js, manifest.webmanifest, la carpeta icons y la carpeta supabase) y pulsa **Commit changes**.
4. **Settings → Pages → Build and deployment**: Source = **Deploy from a branch**, Branch = **main** y carpeta **/ (root)** → **Save**.
5. En 1-2 minutos la app estará en el enlace de arriba.

## 4. Primer uso
1. Abre el enlace → **Crear una cuenta nueva** → correo y contraseña.
2. **Crear la familia** (nombre de la familia y tu nombre).
3. En la pestaña **Zona → Mi familia** verás el **código de la familia**. Tu pareja crea su cuenta, elige «Tengo un código» y lo escribe.
4. Instalar: iPhone → Safari → Compartir → Añadir a pantalla de inicio. Android → Chrome → ⋮ → Instalar aplicación.

## 5. (Opcional) Activar la IA: menús y foto de la despensa
Sin esto, la app funciona entera menos «Crear menú» y «Detectar con foto».
1. Crea una clave en https://console.anthropic.com y pon un **límite de gasto mensual** (por ejemplo 5 €).
2. En Supabase → **Edge Functions → Deploy a new function → Via Editor**. Nombre: `ia`. Pega el contenido de `supabase/functions/ia/index.ts`. Desactiva **Verify JWT** (la función ya comprueba el usuario) y despliega.
3. **Edge Functions → Secrets**: añade `ANTHROPIC_API_KEY` con tu clave. Opcional: `IA_LIMITE_DIA` (usos por familia y día, 30 por defecto).

## 6. (Opcional) Búsqueda de ofertas en la web
Hace que el botón «Buscar ofertas ahora» busque folletos y webs de los supermercados que marcaste, y que se actualice sola cada lunes.
1. Crea otra función en Edge Functions con el nombre `ofertas` y pega `supabase/functions/ofertas/index.ts`. Desactiva **Verify JWT** y despliega. Usa la misma clave `ANTHROPIC_API_KEY` del paso 5.
2. Para la búsqueda semanal automática: crea el secreto `CRON_SECRET` (una palabra larga inventada), activa las extensiones `pg_cron` y `pg_net` en Database → Extensions, cambia `TU_CRON_SECRET` en `supabase/cron.sql` por esa palabra y ejecútalo en el editor SQL.
3. Cada búsqueda gasta algo de tu crédito de Anthropic (la búsqueda web se cobra aparte). Mira el coste real en tu consola de Anthropic las primeras semanas.

## Si cambias archivos más adelante
Sube la versión nueva a GitHub y cambia `V = "cestea-v1"` por `"cestea-v2"` en `sw.js`, para que los móviles descarguen la actualización.
