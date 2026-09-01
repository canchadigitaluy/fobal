# fobal - Handoff completo para Claude Code

Fecha de corte: 2026-09-01  
Repositorio local: `C:\Users\franc\delclub`  
URL estable de producción: `https://web-tau-gules-52.vercel.app`  
Stack principal: Flutter Web/Dart + Supabase + Vercel Serverless Functions + Gemini.

Este documento está pensado para migrar el trabajo a Claude Code, o para trabajar en paralelo entre Claude Code y Codex sin pisarse. La prioridad no es reescribir todo: la prioridad es estabilizar onboarding, selección de club/categoría, datos reales de Liga Universitaria, generación de sesiones y las pantallas del panel.

## Cómo usar este documento

Pegar a Claude Code el bloque "Prompt maestro para Claude Code" completo. Después, si se va a trabajar en paralelo con Codex, pedirle a Claude que antes de editar ejecute inspección de estado (`git status`, archivos tocados, rutas relevantes) y que mantenga cambios chicos, testeables y desplegables.

No copiar claves secretas en chats. Las variables reales están en entorno local/Vercel/Supabase. Este documento enumera nombres de variables y rutas, no valores secretos.

## Identidad actual del producto

Nombre comercial actual: `fobal`.

El nombre anterior aparece en código y docs como `CanteraOS`, `Cantera`, `DelClub` o `cantera_os`. Hay que tener cuidado: parte de la arquitectura conserva nombres viejos, pero la UI visible debe decir `fobal` en todas partes.

Objetivo del producto:

- Plataforma para DTs/profes de fútbol.
- Debe servir a dos perfiles:
  - DT/profe de Liga Universitaria/LUD: elige club real y categoría real, con datos importados.
  - Profe independiente/no LUD: crea su propio club/colegio, carga plantel manual, asistencia, calendario, tácticas, entrenamientos, alineaciones y citaciones.
- La plataforma debe ser simple para el usuario final, con IA y datos funcionando de forma implícita, no como jerga técnica.

## Estructura del proyecto

Raíz:

- `C:\Users\franc\delclub\pubspec.yaml`: dependencias Flutter.
- `C:\Users\franc\delclub\lib`: app Flutter.
- `C:\Users\franc\delclub\api`: Vercel Serverless Functions en Node.
- `C:\Users\franc\delclub\supabase\migrations`: SQL de Supabase.
- `C:\Users\franc\delclub\supabase\functions`: Supabase Edge Functions.
- `C:\Users\franc\delclub\web`: assets web/PWA.
- `C:\Users\franc\delclub\build\web`: build Flutter Web que Vercel publica.
- `C:\Users\franc\delclub\vercel.json`: configuración Vercel.
- `C:\Users\franc\delclub\tool\cantera_ai_server.js`: servidor Node auxiliar/histórico para IA.
- `C:\Users\franc\delclub\docs`: documentación técnica.

Archivos Flutter clave:

- `C:\Users\franc\delclub\lib\main.dart`
  - App root, tema visual `CX`, rutas, `AppScope`, shell principal, selector de categoría, logo/isotipo, navegación.
  - Maneja storage local de club/categoría.
  - Rutas importantes: `/login`, `/auth-lud`, `/auth-local`, `/access`, `/local-setup`, `/local-home`, `/home`, `/preview-home`.

- `C:\Users\franc\delclub\lib\data\cantera_data.dart`
  - Modelos de dominio: `CanteraClub`, `CategorySquad`, `Player`, `Methodology`, `TrainingSession`, etc.
  - Demo data y helpers de serialización.
  - Ojo: conserva naming `Cantera`.

- `C:\Users\franc\delclub\lib\screens\login_screen.dart`
  - Pantalla de login/sign-up.
  - Alterna entre perfil LUD y No LUD mediante `_ludMode`.
  - Maneja Google, email/password y creación de cuenta.
  - Debe evitar cualquier regreso a "solicitar acceso" o código de invitación.

- `C:\Users\franc\delclub\lib\screens\access_gate_screen.dart`
  - Selección de club LUD y luego categoría.
  - Hoy funciona como picker abierto de clubes. No debe pedir acceso por club.
  - Si `cantera_post_auth_mode == local`, debe mandar directo a `/local-setup`, no a clubes LUD.

- `C:\Users\franc\delclub\lib\screens\local_coach_setup_screen.dart`
  - Onboarding para profe independiente/no LUD.
  - Crea club manual en localStorage, categoría `Plantel`, agenda, jugadores y secciones visibles.

- `C:\Users\franc\delclub\lib\screens\home_screen.dart`
  - Inicio/dashboard del club.
  - Debe mostrar resultados reales recientes según club y categoría.

- `C:\Users\franc\delclub\lib\screens\tactica_screen.dart`
  - Sección Táctica.
  - Integra Plantel, Asistencia en LUD, Planificar e Impronta futbolística.
  - Para externos/no LUD actualmente no muestra asistencia dentro de Táctica porque Asistencia es sección propia.

- `C:\Users\franc\delclub\lib\screens\calendario_screen.dart`
  - Calendario manual con eventos persistidos en localStorage y mutation queue.
  - Hubo bug recurrente de pantalla/cuadrado gris. Tratarlo como error visual crítico.

- `C:\Users\franc\delclub\lib\screens\mi_equipo_screen.dart`
  - Sección Mi equipo para perfil independiente.
  - Carga logo, foto del equipo y plantel manual.

- `C:\Users\franc\delclub\lib\screens\asistencia_screen.dart`
  - Control de asistencia.

- `C:\Users\franc\delclub\lib\screens\alineacion_screen.dart`
  - Alineación y citaciones.
  - El usuario dijo que alineación está bastante bien, tocar con cuidado.

- `C:\Users\franc\delclub\lib\screens\estadisticas_screen.dart`
  - Estadísticas para clubes/categorías LUD.
  - Debe calcular últimos cinco resultados reales, no rellenar con 0-0.

Servicios clave:

- `C:\Users\franc\delclub\lib\services\supabase_auth_service.dart`
  - Inicializa Supabase desde `/api/public-config`.
  - Login Google y password.
  - Último arreglo importante: si `/api/public-config` no existe o falla, login se rompe.

- `C:\Users\franc\delclub\lib\services\club_access_service.dart`
  - Lista clubes LUD.
  - Carga contexto real del club, fixture, resultados, standings y datos tácticos.
  - Es una zona crítica para bugs de club/categoría mezclados.

- `C:\Users\franc\delclub\lib\services\training_ai_service.dart`
  - Construye payload para generación de entrenamiento/táctica.
  - Valida contexto, jugadores, rival, perfil de plantel y calidad de datos.

- `C:\Users\franc\delclub\lib\services\offline_mutation_service.dart`
  - Cola offline/mutation queue.

- `C:\Users\franc\delclub\lib\services\local_cache_service.dart`
  - Cache local.

- `C:\Users\franc\delclub\lib\repositories\training_session_repository.dart`
  - Repositorio de sesiones.

APIs Vercel:

- `C:\Users\franc\delclub\api\public-config.js`
  - Devuelve Supabase URL y anon key pública al cliente.
  - Debe estar desplegada como Function. Si devuelve 404, login falla.

- `C:\Users\franc\delclub\api\generate-training-session.js`
  - Orquesta Gemini para generar sesiones/tácticas.
  - Debe devolver JSON estructurado. Si Gemini falla, la UI muestra mensaje amarillo.

- `C:\Users\franc\delclub\api\lud-teams.js`
  - Lista clubes LUD.

- `C:\Users\franc\delclub\api\lud-team-context.js`
  - Contexto completo de club LUD: equipo, categorías, jugadores, escudo.

- `C:\Users\franc\delclub\api\lud-team-fixture.js`
  - Fixture y resultados. Crítico para forma reciente y próximo partido.

- `C:\Users\franc\delclub\api\lud-team-standings.js`
  - Tabla/estadísticas.

- `C:\Users\franc\delclub\api\lud-opponent-analysis.js`
  - Análisis del rival.

- `C:\Users\franc\delclub\api\club-crest.js`
  - Proxy de escudos.

- `C:\Users\franc\delclub\api\claim-category-access.js`
- `C:\Users\franc\delclub\api\review-club-membership.js`
- `C:\Users\franc\delclub\api\sync-lud-teams.js`
- `C:\Users\franc\delclub\api\_league-cache.js`

Supabase:

- `C:\Users\franc\delclub\supabase\migrations\20260728120000_cantera_access_foundation.sql`
- `C:\Users\franc\delclub\supabase\migrations\20260802050000_tactical_write_roles.sql`
- `C:\Users\franc\delclub\supabase\migrations\20260814010000_category_access_and_subscription.sql`
- `C:\Users\franc\delclub\supabase\migrations\20260825090000_offline_rag_rls_foundation.sql`
- `C:\Users\franc\delclub\supabase\migrations\20260827090000_rag_permissions_active_fix.sql`

Edge Function:

- `C:\Users\franc\delclub\supabase\functions\generate-training-session\index.ts`

## Comandos de trabajo

Desde `C:\Users\franc\delclub`:

```powershell
C:\flutter\bin\flutter.bat pub get
C:\flutter\bin\flutter.bat analyze
C:\flutter\bin\flutter.bat test
C:\flutter\bin\flutter.bat build web --release --no-tree-shake-icons --no-wasm-dry-run
```

Deploy actual:

```powershell
npx.cmd --yes vercel deploy --prod --yes --scope del-local
```

El proyecto usa `vercel.json` con:

- `outputDirectory: build/web`
- `buildCommand: echo Using prebuilt Flutter web`
- `functions: api/*.js`
- rewrites SPA hacia `/index.html`
- headers anti-cache para `index.html`, `main.dart.js`, bootstrap y service worker.

Importante: como Vercel usa build precompilado, siempre hacer `flutter build web` antes del deploy.

## Variables de entorno necesarias

En Vercel:

- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`
- `SUPABASE_SERVICE_ROLE_KEY` o equivalente si alguna API serverless necesita privilegios de servidor.
- `GEMINI_API_KEY`
- Variables internas de LUD si existen en el proyecto/entorno.

En Supabase:

- Google OAuth configurado.
- Redirect URLs deben incluir:
  - `https://web-tau-gules-52.vercel.app/#/auth-lud`
  - `https://web-tau-gules-52.vercel.app/#/auth-local`
  - URLs preview si se usan deployments temporales.

No hardcodear estas claves en Flutter ni en Git.

## Estado reciente verificado

Último problema grande resuelto:

- Login no funcionaba porque `https://web-tau-gules-52.vercel.app/api/public-config` devolvía 404.
- Se corrigió `vercel.json` para registrar `api/*.js` como Functions.
- Se mejoró `api/public-config.js`.
- Se robusteció `lib/services/supabase_auth_service.dart`.
- Se desplegó a producción y se verificó:
  - `/api/public-config` devuelve 200.
  - Pantalla login carga.
  - OAuth Google redirige a `/access`.
  - La selección de clubes aparece sin errores de consola.

## Bugs y pendientes prioritarios

Tratar estos como backlog vivo:

1. Categoría seleccionada no siempre se respeta.
   - El usuario reportó que elige una categoría y entra por defecto a Mayores.
   - Revisar `AppScope._selectedCategoryId`, `_effectiveCategoryId`, `_MembershipHydrator`, `AccessGateScreen._enterSelectedCategory`, `ClubAccessService.prewarmPrimaryLeagueData`.
   - Asegurar que cada query LUD use `categoryId` y `categoryName` correctos.

2. Estadísticas por club/categoría LUD pueden mostrarse mal.
   - Revisar `estadisticas_screen.dart`, `ClubAccessService.loadResults`, `api/lud-team-fixture.js`, `api/lud-team-standings.js`.
   - Forma reciente debe usar últimos cinco partidos reales de esa categoría, no un partido real + cuatro 0-0.
   - "Puntos obtenidos" debe mostrar el porcentaje real de puntos obtenidos según puntos disputados, no otra efectividad inventada.

3. Próximo partido/fixture no se actualiza de forma confiable.
   - Revisar cache en `_league-cache.js` y query params.
   - El botón de refresh debe invalidar o forzar actualización real.

4. Generación de sesión falla o queda demasiado estricta.
   - Mensaje visto: "Gemini no pudo construir una respuesta confiable..."
   - Para profe independiente debe permitir generar aunque haya pocos jugadores o datos manuales.
   - Para LUD debe permitir usar plantel cargado y no bloquear por "acceso activo al club".
   - Revisar `api/generate-training-session.js`, `training_ai_service.dart` y Supabase auth/RLS si la API consulta datos protegidos.

5. Animación generada de ejercicios es genérica.
   - Debe derivarse del ejercicio generado: objetivo, reglas, espacio, cantidad de jugadores, balón, carriles, movimientos.
   - Revisar dónde se renderiza la animación en Flutter dentro de planificación/sesión.
   - Exigir que el JSON de IA incluya `animation_scene` o equivalente: jugadores, trayectorias, balón, timing y zonas.

6. Pantallas grises en secciones.
   - Bug recurrente en Calendario, Alineación/Citaciones para profe independiente y otras secciones.
   - Sospecha: `Expanded`/`LayoutBuilder`/`IndexedStack`/`KeyedSubtree` con widgets que no pintan o quedan detrás de overlay/placeholder.
   - Revisar `MainShell` en `main.dart`, `_AnimatedShellStack`, `CalendarioScreen`, `TacticaScreen`.
   - Verificar con navegador real después de cada fix.

7. Onboarding independiente/no LUD.
   - Flujo correcto:
     - Login.
     - Elegir "No soy DT de Liga".
     - Iniciar con Google o credenciales.
     - Pedir datos propios: club/colegio y nombre del profe.
     - Elegir secciones del panel.
     - Abrir setup/panel local.
   - Nunca debe mostrar clubes LUD en este flujo.

8. Control de acceso por clubes LUD.
   - El usuario pidió desactivarlo como bloqueo.
   - Para DT LUD: después de login, que vea todos los equipos, elija club y categoría, y entre.
   - No debe aparecer "Solicitar acceso", "código de invitación" ni "tu cuenta no tiene acceso activo a este club".

9. Diseño login.
   - El usuario quiere conservar el hero visual premium tipo cancha/IA a la izquierda y el formulario a la derecha.
   - Debe mantener selector `DT de Liga` / `Otros usuarios`.
   - Branding visible: `fobal`, tipografía fina, moderna.

10. Mi equipo.
   - Logo y foto deben cargar y persistir correctamente.
   - El texto "Plantel | Temporada actual" debe reemplazarse por año/temporada real configurable.
   - El número/código visible que no aporta debe eliminarse si no tiene utilidad.

11. Táctica.
   - Cambiar tab "Forma de jugar" por "Impronta futbolística".
   - Eliminar bloques informativos sin valor como agenda actualizada, contadores de sesiones si no aportan, y "plantel perfilado".
   - Los chips de preparación deben ser clickeables/editables y llevar al lugar donde se completa cada dato.

12. Calendario.
   - Debe ser más chico, con hora al crear eventos.
   - Debe parecer una herramienta útil y no un bloque gigante.
   - Debe persistir eventos por club/categoría.

## Reglas funcionales que no se deben romper

- Profe independiente no debe ver clubes LUD.
- DT LUD no debe quedar bloqueado por permisos de club.
- Club, escudo, jugadores, tabla y categoría deben corresponder entre sí.
- No mezclar jugadores de J.M.L.M con tabla/categoría de Playa Honda u otro club.
- La categoría seleccionada debe mantenerse al recargar.
- La app no debe mostrar "CanteraOS" ni "DelClub" al usuario final.
- No mostrar mensajes técnicos como Supabase, Gemini, IA, API o sincronización salvo en errores internos de desarrollo.
- La UI visible debe hablar como herramienta para cuerpo técnico.

## Estrategia recomendada para Claude Code

Trabajar en iteraciones cortas:

1. Reproducir en local o producción con browser automation.
2. Identificar archivo exacto.
3. Hacer cambio mínimo.
4. Ejecutar `flutter analyze`.
5. Ejecutar build web.
6. Verificar flujo real en navegador.
7. Deploy solo cuando el cambio esté validado.

No hacer refactors grandes de arquitectura mientras haya bugs críticos de acceso, categoría, calendario o IA.

## Prompt maestro para Claude Code

Actúa como Staff Software Engineer experto en Flutter Web, Supabase, Vercel Serverless Functions y productos de IA para deporte. Vas a trabajar sobre el repositorio local `C:\Users\franc\delclub`, plataforma actualmente llamada `fobal`.

Antes de modificar nada, inspecciona:

- `C:\Users\franc\delclub\lib\main.dart`
- `C:\Users\franc\delclub\lib\screens\login_screen.dart`
- `C:\Users\franc\delclub\lib\screens\access_gate_screen.dart`
- `C:\Users\franc\delclub\lib\screens\local_coach_setup_screen.dart`
- `C:\Users\franc\delclub\lib\screens\tactica_screen.dart`
- `C:\Users\franc\delclub\lib\screens\calendario_screen.dart`
- `C:\Users\franc\delclub\lib\screens\estadisticas_screen.dart`
- `C:\Users\franc\delclub\lib\services\supabase_auth_service.dart`
- `C:\Users\franc\delclub\lib\services\club_access_service.dart`
- `C:\Users\franc\delclub\lib\services\training_ai_service.dart`
- `C:\Users\franc\delclub\api\public-config.js`
- `C:\Users\franc\delclub\api\generate-training-session.js`
- `C:\Users\franc\delclub\api\lud-team-fixture.js`
- `C:\Users\franc\delclub\api\lud-team-standings.js`
- `C:\Users\franc\delclub\api\lud-team-context.js`
- `C:\Users\franc\delclub\vercel.json`

Mandatos:

1. Estabiliza de raíz el onboarding:
   - Login debe funcionar con Google y email/password.
   - Crear cuenta debe permitir iniciar sesión después.
   - No debe existir solicitar acceso ni código de invitación.
   - Para `DT de Liga`, luego de login: elegir club LUD, luego categoría, luego panel.
   - Para `Otros usuarios`/No LUD, luego de login: cargar nombre del club/colegio y profe, elegir secciones, luego panel local. No mostrar clubes LUD.

2. Corrige selección de club/categoría:
   - Respetar categoría seleccionada, persistirla por club y no volver a Mayores por defecto.
   - Toda pantalla debe recibir datos consistentes del mismo club y categoría.
   - Nunca mezclar escudo/jugadores de un club con tabla/fixture de otro.

3. Corrige datos LUD:
   - Forma reciente debe ser últimos cinco partidos reales de la categoría seleccionada.
   - No rellenar partidos inexistentes con 0-0.
   - Estadísticas y porcentaje de puntos deben calcularse desde los datos reales disponibles.
   - Refresh debe actualizar realmente los datos o invalidar cache.

4. Corrige generación de entrenamientos:
   - Debe funcionar tanto para LUD como para profe independiente.
   - No bloquear por permisos de club si el producto está en modo abierto.
   - Si faltan datos, pedir menos o usar supuestos mínimos, pero generar una sesión aplicable.
   - La respuesta debe ser JSON estructurado y robusto.

5. Corrige animaciones de ejercicios:
   - La animación debe depender del ejercicio generado, no ser genérica.
   - Agregar al JSON campos de escena: jugadores, balón, trayectorias, espacio, tiempos, zonas y consignas.
   - Renderizar esos datos en Flutter.

6. Corrige pantalla gris:
   - Reproducir y corregir Calendario, Alineación/Citaciones y cualquier sección que quede gris.
   - Verificar con navegador real después del cambio.

7. Mejora UI sin romper flujos:
   - Branding visible `fobal`.
   - Login premium con hero visual a la izquierda y formulario a la derecha.
   - Táctica: tab "Impronta futbolística".
   - Calendario más compacto y con hora.
   - Mi equipo con logo/foto persistentes y temporada/año editable.

Validación obligatoria antes de dar por terminado:

```powershell
C:\flutter\bin\flutter.bat analyze
C:\flutter\bin\flutter.bat build web --release --no-tree-shake-icons --no-wasm-dry-run
```

Después probar en navegador:

- Login `DT de Liga` -> Google/credenciales -> elegir club -> elegir categoría -> home.
- Cambiar categoría y recargar: debe mantenerse.
- Estadísticas de dos clubes/categorías distintas: datos no mezclados.
- Login `Otros usuarios` -> setup local -> panel local -> calendario -> asistencia -> alineación/citaciones.
- Generar entrenamiento en LUD.
- Generar entrenamiento en No LUD.
- Abrir calendario y verificar que no aparece bloque gris.

Deploy:

```powershell
npx.cmd --yes vercel deploy --prod --yes --scope del-local
```

Al finalizar, entregar:

- Resumen breve de cambios.
- Archivos modificados.
- Resultado de `flutter analyze`.
- URL de producción.
- Qué flujos se probaron en navegador.

## Recomendación si se trabaja con Codex y Claude en paralelo

Usar una herramienta por tipo de tarea:

- Claude Code: refactors grandes, arquitectura, búsqueda profunda de bugs de flujo.
- Codex: fixes rápidos, deploys, verificación en navegador, documentación, patches chicos.

Regla práctica: no editar ambos el mismo archivo al mismo tiempo. Para evitar pisadas:

- Antes de cada tanda: `git status`.
- Coordinar archivos bloqueados por tarea.
- Cada tanda debe terminar con build o explicación clara de bloqueo.

## Notas de estilo del producto

El usuario final es un DT/profe. Evitar jerga técnica.

Mal:

- "Gemini no pudo construir..."
- "Supabase no configurado..."
- "0% listo para IA"
- "Sincronizado al ingresar"

Mejor:

- "No pudimos generar la sesión con estos datos. Ajustá el objetivo o probá otra vez."
- "Tu panel ya está listo."
- "Plantel cargado"
- "Agenda actualizada"

El producto debe sentirse profesional, directo y útil en cancha.
