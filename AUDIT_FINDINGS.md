### [home_screen] Dashboard de liga usa siempre la primera categoria
- Archivo: lib/screens/home_screen.dart:86
- Que hay hoy: `_ensureLeagueFutures()` toma `scope.club.categories.first` para tabla, fixture y resultados, aunque existe `scope.selectedCategoryId` y otras pantallas si lo respetan.
- Oportunidad: cargar standings/fixture/results de la categoria seleccionada y refrescar al cambiarla, para que el tablero del DT refleje el equipo que esta mirando.
- Impacto: alto
- Esfuerzo estimado: S

### [home_screen] Filtro por texto oculta planes de partido validos
- Archivo: lib/screens/home_screen.dart:251
- Que hay hoy: `_isWrongCategorySeminarioPlan()` descarta planes si el texto contiene `seminario`, sin validar categoria, rival, fecha ni origen.
- Oportunidad: reemplazar ese filtro por una validacion estructural usando `categoryId`/metadata del plan, o mostrarlo con alerta si hay duda.
- Impacto: medio
- Esfuerzo estimado: S

### [reservas_screen] El plan tactico generado no queda vinculado al partido preparado
- Archivo: lib/screens/reservas_screen.dart:338
- Que hay hoy: `_generateTactic()` guarda un `club_tactical_data` de tipo `match_plan` y lo agrega a `_matchPlans`, pero no actualiza `club.matchPreparations` ni `linkedSessionId`.
- Oportunidad: cuando el plan nace desde un handoff/calendario, vincularlo al `MatchPreparation` correspondiente para que Calendario, Home y Panel de partido lo consuman como preparacion real.
- Impacto: alto
- Esfuerzo estimado: M

### [reservas_screen] Analisis objetivo del rival no sobrevive al borrador local
- Archivo: lib/screens/reservas_screen.dart:3831
- Que hay hoy: `_FixtureMemory.fromDraftJson()` reconstruye `opponentAnalysis` como `null`, aunque `_loadOpponentAnalysis()` llena datos ricos del backend como peligro, forma, local/visitante y minutos de gol.
- Oportunidad: persistir el `OpponentAnalysis` completo en el draft o rehidratarlo automaticamente al volver a abrir la categoria.
- Impacto: alto
- Esfuerzo estimado: M

### [tactica_screen] El selector de categoria solo gobierna Planificar
- Archivo: lib/screens/tactica_screen.dart:109
- Que hay hoy: `_PlannerCategorySelector` aparece solo cuando la seccion activa es Planificar; Plantel, Asistencia e Impronta dependen de la categoria global o de su propia logica.
- Oportunidad: propagar un selector consistente a las subpantallas tacticas o sincronizar `scope.selectedCategoryId` al cambiar el selector del planner.
- Impacto: medio
- Esfuerzo estimado: M

### [cuota_screen] Jugadores sin categoria quedan en un callejon sin salida
- Archivo: lib/screens/cuota_screen.dart:298
- Que hay hoy: `_UncategorizedPlayersPanel` lista jugadores pendientes de categoria y dice revisar la vinculacion, pero no permite asignarlos, moverlos ni abrir una accion correctiva.
- Oportunidad: agregar una accion concreta para asignar categoria/plantel a cada jugador pendiente cuando el dato venga incompleto.
- Impacto: alto
- Esfuerzo estimado: M

### [cuota_screen] Edicion de perfil usa guardado remoto inmediato sin cola offline
- Archivo: lib/screens/cuota_screen.dart:99
- Que hay hoy: `_editPlayer()` actualiza el jugador local y luego llama `ClubAccessService.saveTacticalData()` directo; si falla, solo muestra "en este dispositivo" y no encola reintento.
- Oportunidad: usar `OfflineMutationService.saveTacticalDataOfflineFirst()` para perfiles de jugador, igual que sesiones/asistencia/alineaciones.
- Impacto: alto
- Esfuerzo estimado: S

### [asistencia_screen] Asistencia ignora la categoria seleccionada
- Archivo: lib/screens/asistencia_screen.dart:470
- Que hay hoy: `build()` toma `final category = club.categories.isEmpty ? null : club.categories.first;`, aunque el resto de la app maneja categoria activa.
- Oportunidad: resolver la categoria desde `AppScope.selectedCategoryId` con fallback a la primera, igual que Estadisticas/Semana.
- Impacto: alto
- Esfuerzo estimado: S

### [asistencia_screen] La asistencia que se sube a la nube no se puede reconstruir completa
- Archivo: lib/screens/asistencia_screen.dart:214
- Que hay hoy: el payload remoto de asistencia guarda solo `date`, `presentIds` y `absentIds`; omite `statusByPlayer`, `rosterIds`, `plantelIds` y `note`.
- Oportunidad: guardar el `AttendanceRecord.toJson()` completo y leer registros `attendance` desde `loadTacticalData()` para rehidratar `club.attendanceRecords`.
- Impacto: alto
- Esfuerzo estimado: M

### [week_screen] Semana no muestra sesiones planificadas ni calendario
- Archivo: lib/screens/week_screen.dart:60
- Que hay hoy: Semana calcula actividad solo desde `attendanceRecords` y `matchResults`; si hay sesiones creadas en Planificar o eventos en Calendario, puede mostrar "Semana sin actividad registrada".
- Oportunidad: sumar `club.sessions` por `scheduledDate` y eventos de calendario de la categoria a la agenda semanal.
- Impacto: alto
- Esfuerzo estimado: M

### [estadisticas_screen] Estadisticas de jugadores LUD dependen de campos locales
- Archivo: lib/screens/estadisticas_screen.dart:95
- Que hay hoy: `_playerStats()` usa `Player.matchesPlayed`, `minutesPlayed`, `goals`, `assists` locales; `_load()` solo trae tabla y resultados.
- Oportunidad: aprovechar los datos de jugadores que ya trae/cachea `/api/lud-team-context` para refrescar estadisticas individuales LUD dentro de Estadisticas.
- Impacto: alto
- Esfuerzo estimado: M

### [alineacion_screen] Alineacion arranca en la primera categoria, no en la activa
- Archivo: lib/screens/alineacion_screen.dart:156
- Que hay hoy: `_syncCategory()` conserva `_categoryId` o cae en `club.categories.first.id`; no consulta `AppScope.selectedCategoryId`.
- Oportunidad: inicializar y sincronizar la categoria de Alineacion con la categoria activa del shell.
- Impacto: alto
- Esfuerzo estimado: S

### [alineacion_screen] Citaciones no se comparten con el resto del cuerpo tecnico
- Archivo: lib/screens/alineacion_screen.dart:336
- Que hay hoy: `_saveCallUp()` guarda `club.callUps` localmente, pero no usa `OfflineMutationService`; en cambio `_save()` de alineacion si persiste `alignment` remoto.
- Oportunidad: persistir citaciones como tactical data/offline mutation para que colaborador, calendario y perfil de jugador lean la misma convocatoria.
- Impacto: alto
- Esfuerzo estimado: M

### [calendario_screen] Al cambiar de categoria puede mostrar eventos viejos
- Archivo: lib/screens/calendario_screen.dart:71
- Que hay hoy: `_load()` retorna si `_events.isNotEmpty`, pero `_storageKey` depende de la categoria activa.
- Oportunidad: trackear la storage key cargada, limpiar `_events` y recargar cuando cambie club/categoria.
- Impacto: alto
- Esfuerzo estimado: S

### [calendario_screen] Calendario se sube como tactical data pero ninguna pantalla lo rehidrata
- Archivo: lib/screens/calendario_screen.dart:112
- Que hay hoy: `_save()` encola un registro `type: 'calendar'`, pero las sincronizaciones vistas en Home/Cuota/Reservas solo consumen sesiones, planes, notas y perfiles.
- Oportunidad: leer registros `calendar` desde `loadTacticalData()` y fusionarlos con el calendario local por categoria.
- Impacto: alto
- Esfuerzo estimado: M

### [mi_equipo_screen] "Mi equipo" puede listar jugadores de todas las categorias
- Archivo: lib/screens/mi_equipo_screen.dart:170
- Que hay hoy: `playersForPlantel(scope.club.players, _plantelFilter)` filtra por plantel, pero no por `categoryId`; con "Todos" muestra todo el club aunque `categoryId` este resuelto arriba.
- Oportunidad: filtrar primero por categoria activa y luego por plantel.
- Impacto: alto
- Esfuerzo estimado: S

### [mi_equipo_screen] Disponibilidad editada no se guarda como dato colaborativo
- Archivo: lib/screens/mi_equipo_screen.dart:74
- Que hay hoy: `_editAvailability()` actualiza el jugador local y muestra snackbar, sin `saveTacticalData` ni cola offline.
- Oportunidad: persistir cambios de disponibilidad como perfil de jugador remoto/offline para que alineacion, match prep y otros usuarios vean las alertas.
- Impacto: alto
- Esfuerzo estimado: S

### [player_profile_screen] Objetivos y notas del jugador quedan solo locales
- Archivo: lib/screens/player_profile_screen.dart:98
- Que hay hoy: `_addOrEditGoal()` y `_editNote()` actualizan `club.players` localmente; no hay guardado remoto/offline para objetivos, notas ni disponibilidad.
- Oportunidad: guardar el perfil completo del jugador en tactical data con `relatedLudPlayerIds`, reutilizando `applyRemotePlayerProfiles()`.
- Impacto: alto
- Esfuerzo estimado: M

### [configuracion_club_screen] Metodologia se guarda distinto segun pantalla
- Archivo: lib/screens/configuracion_club_screen.dart:388
- Que hay hoy: `_saveMethodology()` solo actualiza el club local; `perfil_screen.dart` si llama `ClubAccessService.saveTacticalData()` al editar impronta/principios.
- Oportunidad: unificar el guardado para que Configuracion tambien persista metodologia en remoto/offline.
- Impacto: alto
- Esfuerzo estimado: S

### [perfil_screen] Seguimiento individual mezcla todas las categorias
- Archivo: lib/screens/perfil_screen.dart:69
- Que hay hoy: `_PlayerRadar(players: club.players)` y el contador de plantel usan todo el club, no la categoria activa.
- Oportunidad: filtrar por categoria seleccionada para que la impronta y el radar representen al equipo que el DT esta trabajando.
- Impacto: medio
- Esfuerzo estimado: S

### [exercise_library_screen] Biblioteca no tiene persistencia colaborativa explicita
- Archivo: lib/screens/exercise_library_screen.dart:98
- Que hay hoy: crear/editar/borrar ejercicios solo actualiza `club.savedExercises`; no hay `OfflineMutationService` especifico ni registro tactical data para ejercicios.
- Oportunidad: persistir ejercicios guardados como parte del flujo offline/remoto, o documentar y asegurar que el push del club document cubra estos cambios.
- Impacto: medio
- Esfuerzo estimado: M

### [session_builder_screen] Bloques nuevos no heredan contexto de partido ni plantel
- Archivo: lib/screens/session_builder_screen.dart:73
- Que hay hoy: `_addNew()` crea un bloque manual desde `ExerciseEditDialog` con categoria por defecto, pero no precarga objetivo, espacio, cantidad de jugadores ni contexto del match prep actual.
- Oportunidad: cuando el constructor viene desde un `calendarEventId`, prellenar datos desde el partido/preparacion y el plantel disponible de la categoria.
- Impacto: medio
- Esfuerzo estimado: S

### [match_preparation_screen] Panel de partido ignora categoria activa
- Archivo: lib/screens/match_preparation_screen.dart:432
- Que hay hoy: `build()` usa `final category = club.categories.first;`, aun cuando `openMatchPreparation()` puede venir desde calendario o shell con otra categoria activa.
- Oportunidad: resolver la categoria desde `AppScope.selectedCategoryId` y validar que el `calendarEventId` pertenezca a esa categoria.
- Impacto: alto
- Esfuerzo estimado: S

### [match_preparation_screen] Plan de partido local no se persiste remotamente
- Archivo: lib/screens/match_preparation_screen.dart:188
- Que hay hoy: `_persistPrep()` actualiza `club.matchPreparations`, pero no encola ni guarda tactical data; solo las sesiones vinculadas terminan en remoto.
- Oportunidad: guardar `MatchPreparation.toJson()` con `OfflineMutationService` para que Home/Calendario/Planificar puedan sincronizar el panel completo entre usuarios.
- Impacto: alto
- Esfuerzo estimado: M

### [services/api] Backend calcula datos de rival que el front usa parcialmente
- Archivo: api/lud-opponent-analysis.js:103
- Que hay hoy: el endpoint devuelve `homeAwaySplit`, `avgGoalsPerMatch`, `biggestWin`, `biggestLoss`, `currentStreak`, `cleanSheets` y `goalMinuteBuckets`; `reservas_screen.dart` los parsea, pero el flujo de Match Preparation solo busca al rival en standings.
- Oportunidad: usar `ClubAccessService.loadOpponentAnalysis()` tambien desde `match_preparation_screen.dart` para completar automaticamente notas, jugadores a observar y pelota quieta.
- Impacto: alto
- Esfuerzo estimado: M

### [services/offline_mutation_service] La cola offline solo cubre dos tipos de mutacion
- Archivo: lib/services/offline_mutation_service.dart:205
- Que hay hoy: `_sync()` solo sincroniza `club_tactical_data.upsert` y `club_document.push`; varias pantallas escriben datos locales sensibles sin entrar por ninguno de esos caminos.
- Oportunidad: conectar citaciones, match preparations, perfiles de jugador, ejercicios y calendario a uno de esos dos caminos de forma consistente.
- Impacto: alto
- Esfuerzo estimado: L
