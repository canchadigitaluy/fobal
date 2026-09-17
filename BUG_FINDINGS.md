### lib/services/club_access_service.dart Fallback de membresia libera todas las categorias
- Archivo: lib/services/club_access_service.dart:57
- Que hace hoy (codigo real, no supongas): `activeMemberships()` intenta leer `category_ids`; si falla cualquier cosa en ese `select`, hace retry sin `category_ids`. `ClubMembership.fromJson` entonces deja `categoryIds` vacio, y `accessibleCategories()` devuelve todas las categorias cuando `categoryIds.isEmpty`.
- Por que es un bug (que dato se pierde/ignora/oculta y en que pantalla se nota): un fallo transitorio o de esquema en la columna convierte silenciosamente un acceso acotado por categoria en acceso completo al club. Se nota en el selector global, home, estadisticas, asistencia, reservas y cualquier pantalla filtrada por `ClubAccessService.accessibleCategories`.
- Severidad: alta
- Fix sugerido (una linea, concreto): si falla leer `category_ids`, no asumir lista vacia como "todas"; devolver error/estado degradado o preservar el cache previo de categorias asignadas.

### lib/screens/estadisticas_screen.dart Estadisticas LUD esconden errores como datos vacios
- Archivo: lib/screens/estadisticas_screen.dart:69
- Que hace hoy (codigo real, no supongas): `_load()` hace `catchError((_) => null)` para tabla, `catchError((_) => <LudFixtureMatch>[])` para resultados y `catchError((_) => players)` para jugadores LUD.
- Por que es un bug (que dato se pierde/ignora/oculta y en que pantalla se nota): si LUD, Supabase o el endpoint fallan, la pantalla Estadisticas queda con paneles `_NoData` o datos locales viejos sin avisar que hubo error. El DT ve "sin datos" o estadisticas pobres, no "fallo la carga".
- Severidad: alta
- Fix sugerido (una linea, concreto): propagar un estado de error parcial en `_StatsData` y mostrar un aviso/CTA de reintento por tabla, resultados y jugadores.

### lib/services/club_access_service.dart Historial de resultados se corta antes de que Estadisticas pueda comparar tendencias
- Archivo: lib/services/club_access_service.dart:297
- Que hace hoy (codigo real, no supongas): `loadResults()` ordena los partidos jugados y devuelve `played.take(5).toList()`. En `estadisticas_screen.dart:605`, la lectura intenta calcular `prev5 = played.skip(5).take(5)`, pero esa lista siempre llega vacia.
- Por que es un bug (que dato se pierde/ignora/oculta y en que pantalla se nota): la pantalla Estadisticas tiene codigo para comparar ultimos 5 contra 5 anteriores, pero el servicio ya descarto todo lo anterior. La lectura "en alza/en baja" nunca puede aparecer aunque existan 10+ resultados reales.
- Severidad: media
- Fix sugerido (una linea, concreto): hacer que `loadResults()` acepte un limite mayor o devuelva todo el historial necesario, y limitar a 5 solo en los widgets de "ultimos resultados".

### api/lud-team-fixture.js El endpoint de historial tambien descarta todo salvo 5 partidos
- Archivo: api/lud-team-fixture.js:67
- Que hace hoy (codigo real, no supongas): cuando `history=1`, el handler filtra jugados, ordena por fecha descendente y hace `.slice(0, 5)` antes de responder; el fallback publico hace lo mismo en `api/lud-team-fixture.js:202`.
- Por que es un bug (que dato se pierde/ignora/oculta y en que pantalla se nota): aunque el cliente deje de truncar, la API ya elimino resultados anteriores. Afecta Estadisticas, Home y cualquier lectura de forma/historial que necesite mas que los ultimos cinco.
- Severidad: media
- Fix sugerido (una linea, concreto): agregar parametro `limit`/`allHistory` y no aplicar `.slice(0, 5)` para consumidores analiticos.

### api/lud-team-fixture.js Pre Senior no matchea si una fuente usa guion y otra no
- Archivo: api/lud-team-fixture.js:692
- Que hace hoy (codigo real, no supongas): `categoryMatches()` normaliza espacios a guiones; solo entra al caso especial si `requested.includes("presenior")`, y ahi acepta `presenior` o `pre-senior` en el haystack.
- Por que es un bug (que dato se pierde/ignora/oculta y en que pantalla se nota): si la categoria pedida es "Pre Senior", queda como `pre-senior`, no entra al caso especial y exige que la fuente tambien contenga `pre-senior`. Si LUD publica `presenior`, el fixture queda vacio aunque haya partidos.
- Severidad: alta
- Fix sugerido (una linea, concreto): normalizar `pre-senior` y `presenior` al mismo token antes de comparar.

### api/lud-team-standings.js Tabla Pre Senior tiene el mismo mismatch de guion
- Archivo: api/lud-team-standings.js:249
- Que hace hoy (codigo real, no supongas): `categoryMatches()` devuelve `haystack.includes("presenior")` solo cuando el `requested` contiene `presenior`; no contempla que `requested` sea `pre-senior`.
- Por que es un bug (que dato se pierde/ignora/oculta y en que pantalla se nota): para categorias "Pre Senior" vs "Presenior", la tabla puede volver `rows: []` y la UI muestra sin posicion verificable. Se nota en Home, Estadisticas y Preparacion de partido.
- Severidad: alta
- Fix sugerido (una linea, concreto): compartir una normalizacion de categorias con fixture y convertir ambas variantes a `presenior`.

### api/lud-team-context.js La cache pierde categorias sintetizadas desde season-players
- Archivo: api/lud-team-context.js:233
- Que hace hoy (codigo real, no supongas): la respuesta viva usa `mergeCategories(rawCategories, currentEntries)` para agregar categorias que no vinieron en `/categories/`, pero `cacheContext()` guarda solo `rawCategories.map(...)` en `lud_team_categories`.
- Por que es un bug (que dato se pierde/ignora/oculta y en que pantalla se nota): si LUD no expone una categoria en `/teams/{id}/categories/` pero si aparece en `season-players`, la respuesta viva la muestra; la respuesta cacheada la pierde. Cuando LUD cae y se usa cache, esa categoria desaparece de acceso/home/estadisticas/reservas sin error visible.
- Severidad: alta
- Fix sugerido (una linea, concreto): cachear el `categorySource`/`categories` ya mergeado, no solo `rawCategories`.

### api/lud-team-context.js IDs de jugador cacheados no coinciden con los IDs vivos
- Archivo: api/lud-team-context.js:286
- Que hace hoy (codigo real, no supongas): la respuesta viva crea `id: lud-player-${playerId}-${normalize(entry.category)}`; `loadCachedContext()` reconstruye `id: lud-player-${player.lud_player_id}` sin el sufijo de categoria.
- Por que es un bug (que dato se pierde/ignora/oculta y en que pantalla se nota): `preservePlayerProfiles()` cruza perfiles por `player.id`. Si un dia se carga contexto cacheado, los jugadores no matchean contra los perfiles existentes y se pierden notas/manual edits/status en pantallas de plantel, estadisticas y generador de entrenamientos.
- Severidad: alta
- Fix sugerido (una linea, concreto): persistir y devolver el mismo `id` estable que usa la respuesta viva, incluyendo sufijo de categoria.

### api/lud-team-context.js Cache de jugadores colapsa al mismo jugador entre categorias
- Archivo: api/lud-team-context.js:250
- Que hace hoy (codigo real, no supongas): `cacheContext()` upsertea `lud_players` con `{ onConflict: "lud_player_id" }`, aunque la respuesta viva deduplica por `${categoryId}-${playerId}`.
- Por que es un bug (que dato se pierde/ignora/oculta y en que pantalla se nota): si un jugador aparece en mas de una categoria/temporada, la cache conserva un solo `source_payload`. En fallback cacheado, ese jugador queda asociado a una sola categoria o con `categoryId` vacio, bajando `playerCount` y vaciando planteles parcialmente.
- Severidad: alta
- Fix sugerido (una linea, concreto): guardar jugadores cacheados por `(lud_team_id, category_id, lud_player_id)` o persistir la lista viva completa por categoria.

### lib/services/club_access_service.dart loadTacticalData limita antes de filtrar por tipo real
- Archivo: lib/services/club_access_service.dart:464
- Que hace hoy (codigo real, no supongas): `loadTacticalData(limit)` ordena todo `club_tactical_data` por `created_at` y aplica `.limit(limit)` antes de que pantallas como calendario, asistencia, cuota, reservas y home filtren por `record.type`.
- Por que es un bug (que dato se pierde/ignora/oculta y en que pantalla se nota): con suficientes registros nuevos de otros tipos, un calendario, reporte o asistencia mas viejo queda fuera de los 80/100 registros y la pantalla se ve incompleta aunque el dato exista en Supabase.
- Severidad: media
- Fix sugerido (una linea, concreto): permitir filtrar por `type`/`category_id` en la query del servicio antes de aplicar `limit`.

### api/review-club-membership.js El backend trunca categorias asignadas sin avisar
- Archivo: api/review-club-membership.js:62
- Que hace hoy (codigo real, no supongas): `categoryIds` se construye con `slice(0, 2)` y luego se guarda tal cual en `category_ids`.
- Por que es un bug (que dato se pierde/ignora/oculta y en que pantalla se nota): si el cliente o una futura UI manda tres o mas categorias, el backend descarta las extras silenciosamente. El administrador ve que guardo una lista, pero el DT pierde acceso a categorias no persistidas.
- Severidad: media
- Fix sugerido (una linea, concreto): validar y rechazar con error explicito cuando llegan mas categorias que el maximo, o quitar el maximo si el negocio permite mas.
