### api/generate-training-session.js Usuarios sin membresia activa pueden usar el asistente sobre cualquier club
- Archivo: api/generate-training-session.js:989
- Que hace hoy (codigo real, citando la linea, no supongas ni inventes): `authenticateClubRequest()` consulta `club_memberships`, pero si hay `membershipError || !membership` devuelve `{ ok: true, role: "authenticated_guest", userId: userData.user.id, clubId }` en vez de 403. El handler acepta ese `access.ok` en `api/generate-training-session.js:261` y sigue generando.
- Por que es grave: cualquier usuario autenticado puede mandar un `club.id` de un club LUD donde no es miembro y consumir el endpoint critico de generacion. No lee datos privados por si solo, porque el payload viene del cliente, pero rompe el control de acceso del flujo de DT y habilita abuso/costos y escritura posterior de contexto bajo un club ajeno.
- Severidad: critica
- Fix sugerido (concreto, 1-3 lineas): si el club no es manual verificado, `!membership` debe devolver 403. No usar rol `authenticated_guest` para clubes LUD; validar membresia activa y rol escritor antes de generar.

### api/generate-training-session.js El modo manual permite escribir memoria RAG en un UUID ajeno
- Archivo: api/generate-training-session.js:953
- Que hace hoy (codigo real, citando la linea, no supongas ni inventes): `isIndependentClub` se calcula desde campos controlados por el payload (`club.data_source`, `club.league` o `clubId.startsWith("externo-")`) y si es true devuelve acceso ok con `clubId` en `api/generate-training-session.js:974`. Luego `persistGeneratedContext()` usa service role e inserta `club_id: access.clubId` en `training_context_documents` en `api/generate-training-session.js:1097`.
- Por que es grave: un usuario autenticado puede mandar `club.data_source = "manual"` y un `club.id` UUID de otro club. Si la generacion termina bien, el backend intenta guardar memoria de IA bajo ese club con service role, sin validar ownership ni colaboracion. Eso puede contaminar el RAG que despues reciben DTs reales de ese club.
- Severidad: critica
- Fix sugerido (concreto, 1-3 lineas): para clubes manuales, validar ownership/colaboracion contra `club_documents`/`club_collaborators` antes de aceptar el `clubId`. No persistir RAG con service role si el acceso no esta atado a una membresia/ownership comprobada.

### supabase/migrations/20260827090000_rag_permissions_active_fix.sql RAG no aisla por categoria
- Archivo: supabase/migrations/20260827090000_rag_permissions_active_fix.sql:119
- Que hace hoy (codigo real, citando la linea, no supongas ni inventes): `match_training_context` filtra por `filter_user_id` o por membresia activa del club en las lineas 120-129, y por `filter_club_id` en las lineas 131-134. No compara `d.category_id` con ninguna categoria permitida ni recibe un `filter_category_id`.
- Por que es grave: un DT limitado a Categoria A puede obtener, via el asistente, contexto historico de Categoria B del mismo club si los embeddings son similares. Es fuga de notas tacticas, planes y diagnosticos entre cuerpos tecnicos/categorias.
- Severidad: alta
- Fix sugerido (concreto, 1-3 lineas): agregar `filter_category_id` al RPC y exigir `d.category_id = filter_category_id` salvo admins. Reutilizar `can_access_club_category(d.club_id, d.category_id)` dentro del SQL, incluso cuando el llamado venga desde service role.

### supabase/migrations/20260827090000_rag_permissions_active_fix.sql La policy de RAG permite contaminar clubes ajenos
- Archivo: supabase/migrations/20260827090000_rag_permissions_active_fix.sql:82
- Que hace hoy (codigo real, citando la linea, no supongas ni inventes): la policy `training_context_insert_own_or_club` permite insert si `user_id = auth.uid()` en la linea 87, sin exigir que `club_id` pertenezca al usuario. La policy de select permite leer si existe membresia activa del club en las lineas 73-79, sin validar quien creo el documento.
- Por que es grave: un usuario autenticado puede insertar un documento RAG con su propio `user_id` pero con `club_id` de otro club; luego miembros reales de ese club pueden recuperar ese contenido porque el select se basa en membresia del club, no en el creador. Es una via directa de poisoning de memoria tactica.
- Severidad: critica
- Fix sugerido (concreto, 1-3 lineas): cambiar el `with check` para exigir membresia/colaboracion sobre `club_id` siempre que `club_id` no sea null. No permitir `user_id = auth.uid()` como bypass cuando se setea un club ajeno.

### api/generate-training-session.js La memoria generada se pierde silenciosamente por columna inexistente
- Archivo: api/generate-training-session.js:1097
- Que hace hoy (codigo real, citando la linea, no supongas ni inventes): `persistGeneratedContext()` inserta en `training_context_documents` con `source_type: mode` en `api/generate-training-session.js:1101`. Pero la tabla creada en `supabase/migrations/20260827090000_rag_permissions_active_fix.sql:54` define `id, club_id, category_id, user_id, content, metadata, embedding, created_at` y no define `source_type`. El `catch (_) { return; }` de `api/generate-training-session.js:1110` traga el error.
- Por que es grave: cada plan generado parece exitoso, pero el contexto historico no queda guardado en RAG si el esquema desplegado sigue estas migraciones. El DT pierde memoria de trabajo entre sesiones y el sistema no avisa que no persistio.
- Severidad: alta
- Fix sugerido (concreto, 1-3 lineas): agregar migracion para `source_type` o quitar ese campo del insert. No tragar el error: loguear/retornar un estado parcial para saber que la generacion salio pero la memoria no se guardo.

### supabase/migrations/20260728120000_cantera_access_foundation.sql El CHECK de club_tactical_data rechaza tipos que la app ya usa
- Archivo: supabase/migrations/20260728120000_cantera_access_foundation.sql:85
- Que hace hoy (codigo real, citando la linea, no supongas ni inventes): `club_tactical_data.type` solo acepta `('session', 'match_plan', 'rival_report', 'staff_note')`. El codigo actual guarda `attendance` en `lib/screens/asistencia_screen.dart:222`, `calendar` en `lib/screens/calendario_screen.dart:189`, `match_preparation` en `lib/screens/match_preparation_screen.dart:354`, y `methodology` en `lib/screens/configuracion_club_screen.dart:407`.
- Por que es grave: esos guardados colaborativos fallan contra Supabase por constraint o quedan reintentando en la cola offline. En varios flujos se usan `unawaited(...)` y la UI muestra guardado local, por ejemplo asistencia muestra `Asistencia guardada.` en `lib/screens/asistencia_screen.dart:231`, dejando al DT creyendo que el cuerpo tecnico comparte un dato que nunca subio.
- Severidad: alta
- Fix sugerido (concreto, 1-3 lineas): migrar el CHECK para incluir todos los tipos usados o reemplazarlo por tabla/enum versionado. Hasta entonces, mapear los tipos nuevos a uno permitido y guardar `kind` dentro de `content`.
