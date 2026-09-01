# Migracion DelClub -> CanteraOS

## Decision

DelClub deja de ser una app de socios/club social. CanteraOS pasa a ser una plataforma de inteligencia deportiva para formativas.

## Reutilizable

- Flutter como base mobile/web responsive.
- Tema oscuro premium.
- Estructura simple de pantallas.
- Mock local para demo rapida.
- Experiencia mobile-first.

## Eliminar del foco

- Carnet digital.
- Cuotas.
- Reservas.
- Novedades institucionales.
- Tabla de posiciones.
- App white-label para socios.
- Modelo centrado en socio.

## Nuevo foco

- Coordinador deportivo.
- Entrenador.
- Categoria.
- Jugador.
- Metodologia.
- Entrenamiento.
- Registro post-entrenamiento.
- Informes IA.
- Alertas inteligentes.

## Tablas Supabase

- `clubs`
- `users`
- `categories`
- `players`
- `methodology`
- `training_sessions`
- `training_reports`
- `attendance`
- `alerts`
- `ai_reports`

## Roles

- `coordinator`
- `coach`
- `admin`

## Logica IA

- Generar entrenamientos desde formulario.
- Estructurar texto/audio transcripto post-entrenamiento.
- Generar alertas.
- Generar informes semanales/mensuales.
- Recomendar proxima sesion.
- Evaluar coherencia con metodologia.

## Flujo MVP

1. Coordinador entra.
2. Ve categorias, alertas, metodologia e informes.
3. Entrenador entra.
4. Ve su categoria.
5. Genera entrenamiento con IA.
6. Registra post-entrenamiento con texto/audio transcripto.
7. Coordinador ve alertas e informe.

## Primeras tareas ejecutadas

- Reemplazo visual de DelClub por CanteraOS.
- Nueva data demo deportiva.
- Nuevo login por rol.
- Nuevo dashboard coordinador.
- Nuevo dashboard entrenador.
- Nuevo generador IA simulado.
- Nuevo panel de inteligencia, metodologia, alertas e informes.

## Proximas tareas

1. Reincorporar Supabase con tablas nuevas y RLS.
2. Crear Edge Functions para IA.
3. Persistir sesiones generadas.
4. Persistir reportes post-entrenamiento.
5. Crear CRUD de categorias y jugadores.
6. Agregar carga real de audio/transcripcion.
7. Generar informes IA desde datos reales.
