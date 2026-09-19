import { GoogleGenerativeAI } from "@google/generative-ai";
import { createClient } from "@supabase/supabase-js";
import { createHmac, timingSafeEqual } from "node:crypto";

const forbiddenInputs = new Set([
  "caca",
  "asdf",
  "test",
  "prueba",
  "hola",
  "nada",
  "no se",
  "nose",
  "xxx",
  "123",
  "qwerty",
]);

const systemPrompt = `
Sos el director metodologico y analista tactico de fobal, especializado en futbol formativo.

Tu trabajo no es completar una plantilla. Tu trabajo es interpretar el caso particular, relacionar todos los datos disponibles y convertirlos en decisiones aplicables en cancha.

PRINCIPIO INNEGOCIABLE
Cada recomendacion debe tener una causa reconocible en los datos recibidos. Si dos solicitudes tienen datos diferentes, sus resultados deben cambiar de manera sustancial. No repitas el texto del usuario como si eso fuera analisis. Explica que significa futbolisticamente y que decision provoca.

PROCESO INTERNO OBLIGATORIO
1. Extrae hechos concretos y separalos de opiniones o supuestos.
2. Detecta relaciones entre objetivo, problema, edad, espacio, jugadores, metodologia, rival y plantel.
3. Prioriza como maximo tres problemas determinantes.
4. Convierte cada prioridad en comportamientos, reglas, roles, espacios y correcciones observables.
5. Verifica que el resultado utilice todos los datos relevantes recibidos.
6. Elimina cualquier frase que pudiera copiarse sin cambios para otro equipo.
No muestres este razonamiento interno. Muestra una sintesis diagnostica breve y las decisiones resultantes.

REGLAS DE CALIDAD
- No inventes sistemas, jugadores, fortalezas, debilidades ni datos que no fueron informados.
- Cuando falte un dato secundario, declara el supuesto minimo dentro del diagnostico.
- Usa lenguaje profesional, claro y de cancha. Evita teoria vacia.
- Cada ejercicio o decision debe indicar organizacion, roles, dimensiones o zonas, reglas, progresion y correccion del DT.
- Las consignas deben ser cortas y comunicables a jugadores.
- Los indicadores deben poder observarse o contarse.
- La metodologia del club orienta el plan, pero no reemplaza el pedido concreto.
- Usa data_quality para nombrar faltantes relevantes y ajustar la confianza del plan. No completes esos faltantes con datos inventados.
- Trata unavailable_players como bajas reales: no les asignes roles, no los cuentes en formatos y explica cualquier ajuste provocado por su ausencia.
- Usa recent_field_reports para dar continuidad: conserva lo que funciono, corrige lo que fallo y prioriza nextRecommendation cuando sea compatible con el pedido actual.
- Usa rival_memory_from_staff, rival_danger_players_and_patterns y previous_match_notes como cuaderno tactico del cuerpo tecnico: si existen, deben cambiar el plan de partido, los riesgos, los roles y los ajustes. No los conviertas en texto decorativo.
- Usa scheduled_date para ubicar la carga y la especificidad del plan. No inventes dias de recuperacion ni calendario adicional.
- Usa fixture_context_from_lud como fuente prioritaria cuando exista: fecha, rival, localia, competencia y categoria deben aparecer en context_used y condicionar el plan de partido.
- Usa match_day_context.periodization_label como regla dura de carga cuando exista; context_used puede citar esa etiqueta si condiciono el plan.
- Si match_day_context.periodization_label es MD: no planifiques cargas de desarrollo; solo activacion prepartido, estrategia puntual o recuperacion segun el momento del dia.
- Si match_day_context.periodization_label es MD-1: prohibido volumen alto, carga neuromuscular explosiva o excentrica alta y duelos de alta intensidad prolongados. Prioridad: activacion, reaccion corta, patrones tacticos especificos del rival y volumen bajo.
- Si match_day_context.periodization_label es MD-2: volumen medio-bajo, evitar fatiga residual y priorizar tactica especifica con bloques cortos de alta velocidad sin acumulacion.
- Si match_day_context.periodization_label es MD-3 o mas o sin_referencia: puede haber mayor volumen, fuerza o resistencia segun el objetivo, sin restriccion especial por proximidad a partido.
- Si match_day_context.periodization_label es MD+1: sesion regenerativa, volumen bajo, foco en jugadores con mas minutos si ese dato existe y sin trabajo de intensidad.
- Usa category.position_map para asignar roles por linea. No inventes posiciones para jugadores sin perfil posicional; si faltan, baja la confianza y declaralo en limitations.
- Usa data_quality.ai_ready_player_profiles e incomplete_ai_player_profiles para calibrar roles individuales: si hay perfiles incompletos, evita instrucciones nominales finas sobre esos jugadores, baja confidence como minimo a medium cuando afecte a mas del 25% del plantel y repite el faltante en limitations.
- Respeta las capacidades cognitivas y fisicas de la categoria/edad.
- No uses frases como "trabajar el objetivo", "adaptarse al rival", "jugar con intensidad" o "aprovechar los espacios" sin explicar exactamente como.
- Escribe en espanol rioplatense claro, sin markdown y sin texto fuera del JSON.
- context_used debe enumerar hechos concretos realmente recibidos que determinaron el plan.
- Usa generation_quality.evidence_contract como contrato de trazabilidad: context_used debe incluir al menos tres evidencias de esa lista cuando existan.
- Si generation_quality.context_score es menor a 70, confidence no puede ser high y limitations debe explicar que faltan evidencias para elevar precision.
- limitations debe repetir faltantes relevantes de data_quality y nunca convertirlos en supuestos.
- confidence debe ser high, medium o low segun completitud y trazabilidad de los datos.

MODO training_session
Genera una sesion megapersonalizada. El diagnostico debe relacionar objetivo y problema con categoria, plantel, espacio y metodologia. La suma de minutos de todos los bloques debe coincidir exactamente con la duracion solicitada.
Incluye como minimo estos bloques diferenciados:
1. Diagnostico aplicado y objetivo medible.
2. Activacion especifica.
3. Ejercicio de adquisicion o correccion.
4. Ejercicio con oposicion y toma de decision.
5. Juego condicionado con transferencia real.
6. Cierre y evaluacion.
En las descripciones incluye organizacion exacta, cantidad de jugadores por equipo o estacion, dimensiones adaptadas al espacio, reglas de puntuacion, progresion, variante, intervenciones del DT y errores esperables. No propongas filas largas ni formatos incompatibles con la cantidad de jugadores.

MODO match_tactic
No generes una sesion de entrenamiento. Genera un plan de partido completamente ligado al rival y al plantel propio.
Incluye como minimo estos bloques diferenciados:
1. Lectura razonada del enfrentamiento.
2. Prioridades y sistema/estructura recomendada con justificacion.
3. Plan con pelota y salida desde el fondo.
4. Progresion y ataque por zonas.
5. Plan sin pelota, altura y direccion de la presion.
6. Transicion ataque-defensa.
7. Transicion defensa-ataque.
8. Pelota quieta ofensiva y defensiva.
9. Roles concretos por linea o posicion.
10. Ajustes durante el partido y plan alternativo.
Relaciona nuestras fortalezas con sus debilidades y nuestras limitaciones con sus amenazas. Si el rival es flojo por bandas, no alcanza con decir "atacar por bandas": define como crear la superioridad, quien fija, quien desdobla, quien ocupa el area, donde va el pase final y como queda la cobertura tras perdida.
Si hay memoria de cruces anteriores, notas post partido o jugadores rivales señalados, el plan debe explicar que se aprendio, que se repite, que se corrige y que alarma observar durante el partido.

ANIMATION_SCENE (OBLIGATORIO EN CADA BLOQUE)
Cada bloque incluye "animation_scene": una representacion espacial del ejercicio de ESE bloque. No es decorativa: debe coincidir con la descripcion del bloque (mismo espacio, misma cantidad de jugadores, mismos movimientos, mismas zonas y misma idea de balon). Si dos bloques o dos sesiones tienen ejercicios distintos, sus animation_scene deben ser claramente distintas.
Coordenadas normalizadas 0..1: x = ancho (0 izquierda, 1 derecha); y = largo (0 arco propio, 1 arco rival).
- pitch_area: uno de "full", "half", "attacking_third", "middle_third", "defensive_third", "small_grid", "wide_channels", elegido segun el espacio descripto.
- players: lista de {id, label (numero o rol corto), team ("own" | "rival" | "neutral"), start {x,y}, end {x,y}, role}. La cantidad debe coincidir con el formato (ej. 4v2 => 6 jugadores; 7v7 => 14).
- ball_path: 2 a 6 puntos {x,y} que trazan el recorrido real del balon en la accion descripta.
- movements: por cada jugador que se desplaza => {player (id), from {x,y}, to {x,y}, start_s, end_s, type ("pase" | "conduccion" | "desmarque" | "presion" | "cobertura" | "apoyo")}.
- zones: {type ("target" | "forbidden" | "lane"), label, x, y, width, height} (0..1). Usalas para zonas objetivo, prohibidas o carriles reales del ejercicio.
- coaching_cues: 1 a 3 consignas cortas propias de esa accion.
- duration_seconds: entre 4 y 14.

SALIDA
Devuelve exclusivamente JSON valido siguiendo el schema solicitado. Cada bloque debe ser sustancial, especifico y distinto.
`;

function normalize(value) {
  return String(value || "")
    .toLowerCase()
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/[^a-z0-9\s]/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function meaningful(value, minimumLength = 8) {
  const text = normalize(value);
  if (text.length < minimumLength || forbiddenInputs.has(text)) return false;
  const words = text.split(" ").filter(Boolean);
  if (words.length === 1) return false;
  return new Set(words).size > 1;
}

function simpleValue(value, minimumLength = 3) {
  const text = normalize(value);
  return text.length >= minimumLength && !forbiddenInputs.has(text);
}

function parseDateOnly(value) {
  if (!value) return null;
  if (value instanceof Date && !Number.isNaN(value.getTime())) {
    return new Date(value.getFullYear(), value.getMonth(), value.getDate());
  }
  const text = String(value).trim();
  let match = text.match(/\b(\d{4})-(\d{2})-(\d{2})\b/);
  if (match) {
    const [, year, month, day] = match;
    const date = new Date(Number(year), Number(month) - 1, Number(day));
    return isSameDateParts(date, Number(year), Number(month), Number(day)) ? date : null;
  }
  match = text.match(/\b(\d{1,2})\/(\d{1,2})\/(\d{4})\b/);
  if (match) {
    const [, day, month, year] = match;
    const date = new Date(Number(year), Number(month) - 1, Number(day));
    return isSameDateParts(date, Number(year), Number(month), Number(day)) ? date : null;
  }
  return null;
}

function isSameDateParts(date, year, month, day) {
  return (
    date instanceof Date &&
    !Number.isNaN(date.getTime()) &&
    date.getFullYear() === year &&
    date.getMonth() === month - 1 &&
    date.getDate() === day
  );
}

function buildMatchDayContext(payload) {
  const sessionDate = parseDateOnly(payload?.session_request?.scheduled_date);
  const fixtureText = payload?.match_context?.fixture_context_from_lud;
  const fixtureDate = parseDateOnly(fixtureText);
  if (!sessionDate || !fixtureDate) return null;

  const dayMs = 24 * 60 * 60 * 1000;
  const daysUntilMatch = Math.round((fixtureDate - sessionDate) / dayMs);
  let periodizationLabel = "sin_referencia";
  if (daysUntilMatch === 0) periodizationLabel = "MD";
  else if (daysUntilMatch === 1) periodizationLabel = "MD-1";
  else if (daysUntilMatch === 2) periodizationLabel = "MD-2";
  else if (daysUntilMatch >= 3) periodizationLabel = "MD-3 o mas";
  else if (daysUntilMatch === -1) periodizationLabel = "MD+1";

  return {
    periodization_label: periodizationLabel,
    days_until_match: daysUntilMatch,
    session_date: formatDateOnly(sessionDate),
    match_date: formatDateOnly(fixtureDate),
    source: "scheduled_date + fixture_context_from_lud",
  };
}

function formatDateOnly(date) {
  const two = (value) => String(value).padStart(2, "0");
  return `${date.getFullYear()}-${two(date.getMonth() + 1)}-${two(date.getDate())}`;
}

function validatePayload(payload) {
  const mode = payload?.mode;
  const session = payload?.session_request || {};
  const match = payload?.match_context || {};
  const missing = [];

  if (!payload?.category?.name || normalize(payload.category.name).includes("sin cargar")) {
    missing.push("una categoria real");
  }
  const isManualClub =
    payload?.club?.league === "Trabajo independiente" ||
    payload?.club?.data_source === "manual";

  if (mode === "match_tactic") {
    // A match plan without a squad is not useful; keep this gate for LUD.
    if (!isManualClub && (payload?.data_quality?.category_players_loaded ?? 0) === 0) {
      missing.push("jugadores reales vinculados a esa categoria");
    }
    if (!simpleValue(match.rival_name, 3)) missing.push("el nombre del rival");
    if (!meaningful(match.rival_game_model_strengths_and_weaknesses, 18)) {
      missing.push("como juega el rival, con fortalezas o debilidades concretas");
    }
    if (!meaningful(match.own_squad_individual_and_collective_profile, 18)) {
      missing.push("caracteristicas concretas del plantel propio");
    }
  } else {
    // Training sessions can be generated with sparse input: the model (and the
    // contextual fallback) fill space, duration and player count with sane
    // defaults. Only an objective is genuinely required.
    if (!simpleValue(session.objective, 4)) {
      missing.push("un objetivo para la sesion");
    }
  }

  return missing;
}

function parseJson(text) {
  const cleaned = text
    .trim()
    .replace(/^```json\s*/i, "")
    .replace(/^```\s*/i, "")
    .replace(/```$/i, "")
    .trim();
  return JSON.parse(cleaned);
}

export default async function handler(req, res) {
  res.setHeader("access-control-allow-origin", "*");
  res.setHeader("access-control-allow-methods", "POST, OPTIONS");
  res.setHeader(
    "access-control-allow-headers",
    "authorization, content-type, x-cantera-preview-token",
  );

  if (req.method === "OPTIONS") {
    res.status(200).json({ ok: true });
    return;
  }

  if (req.method !== "POST") {
    res.status(405).json({ error: "Method not allowed" });
    return;
  }

  let payload;
  let mode = "training_session";
  try {
    payload = typeof req.body === "string" ? JSON.parse(req.body) : req.body;
    const access = await authenticateClubRequest(req, payload);
    if (!access.ok) {
      res.status(access.status).json({
        error: access.error,
        message: access.message,
      });
      return;
    }
    const missing = validatePayload(payload);
    if (missing.length > 0) {
      res.status(422).json({
        error: "insufficient_context",
        message: `Para armar la sesión necesitamos ${missing.join(", ")}.`,
      });
      return;
    }

    mode = payload.mode === "match_tactic" ? "match_tactic" : "training_session";
    if (mode === "training_session") {
      // Fill sparse training input with sane defaults so both the model and
      // the fallback always have something concrete to work with.
      const sr = (payload.session_request = payload.session_request || {});
      const loaded = Number(payload?.data_quality?.category_players_loaded) || 0;
      if (!simpleValue(sr.space, 3)) sr.space = "media cancha";
      if (!Number.isInteger(sr.duration_minutes) || sr.duration_minutes < 20) {
        sr.duration_minutes = 60;
      }
      if (
        !Number.isInteger(sr.available_players) ||
        sr.available_players < 1
      ) {
        sr.available_players = loaded > 0 ? loaded : 12;
      }
      if (!simpleValue(sr.problem, 4)) {
        sr.problem = "mejorar la ejecucion del objetivo planteado";
      }
    }
    const matchDayContext = buildMatchDayContext(payload);
    if (matchDayContext) {
      payload.match_day_context = matchDayContext;
    }
    const schema = {
      title: "Titulo especifico del caso",
      objective: "Diagnostico breve que conecta explicitamente los datos y justifica las prioridades",
      blocks: [
        {
          name: "Nombre concreto del bloque",
          duration: mode === "training_session" ? "Cantidad exacta en min" : "Momento o fase del partido",
          intensity: "low, medium o high",
          description: "Desarrollo detallado, aplicable y trazable a los datos recibidos",
          constraints: ["Reglas, limites o condiciones especificas del bloque"],
          coaching_points: ["Correcciones concretas que debe hacer el entrenador"],
          success_metric: "Indicador observable especifico del bloque",
          animation_scene: {
            pitch_area: "full | half | attacking_third | middle_third | defensive_third | small_grid | wide_channels",
            players: [
              {
                id: "o1",
                label: "5",
                team: "own | rival | neutral",
                start: { x: 0.3, y: 0.4 },
                end: { x: 0.45, y: 0.6 },
                role: "rol corto",
              },
            ],
            ball_path: [{ x: 0.3, y: 0.4 }, { x: 0.55, y: 0.6 }],
            movements: [
              {
                player: "o1",
                from: { x: 0.3, y: 0.4 },
                to: { x: 0.45, y: 0.6 },
                start_s: 0,
                end_s: 3,
                type: "pase | conduccion | desmarque | presion | cobertura | apoyo",
              },
            ],
            zones: [
              {
                type: "target | forbidden | lane",
                label: "nombre de la zona",
                x: 0.2,
                y: 0.6,
                width: 0.6,
                height: 0.3,
              },
            ],
            coaching_cues: ["consigna corta"],
            duration_seconds: 8,
          },
        },
      ],
      coach_cues: ["Minimo 5 consignas breves, especificas y observables"],
      success_indicators: ["Minimo 5 indicadores medibles u observables"],
      context_used: ["Minimo 3 hechos concretos recibidos que cambiaron el plan"],
      limitations: ["Faltantes reales que limitan esta recomendacion, o lista vacia"],
      confidence: "high, medium o low",
    };

    const geminiApiKey =
      process.env.GEMINI_API_KEY2 || process.env.GEMINI_API_KEY;
    if (!geminiApiKey) {
      res.status(503).json({
        error: "missing_configuration",
        message: "El asistente no esta configurado en produccion.",
      });
      return;
    }

    const quota = await consumeAiQuota(access);
    if (!quota.ok) {
      if (quota.retryAfter) res.setHeader("retry-after", String(quota.retryAfter));
      res.status(429).json({ error: "ai_quota_exceeded", message: quota.message });
      return;
    }

    const genAI = new GoogleGenerativeAI(geminiApiKey);
    const ragContext = await loadRagContext({
      payload,
      access,
      apiKey: geminiApiKey,
    });
    const prompt = `${systemPrompt}\n\nMODO ACTIVO: ${mode}\n\nSCHEMA JSON OBLIGATORIO:\n${JSON.stringify(schema, null, 2)}\n\nCONTEXTO HISTORICO DISPONIBLE:\n${JSON.stringify(ragContext, null, 2)}\n\nDATOS COMPLETOS DEL CASO:\n${JSON.stringify(payload, null, 2)}`;

    const result = await generateWithModelFallback(genAI, prompt);
    const data = parseJson(result.response.text());

    normalizeGeneratedPlanShape(data, payload, mode);
    validateGeneratedPlan(data, payload, mode);
    normalizeGeneratedPlanQuality(data, payload);
    await persistGeneratedContext({
      payload,
      access,
      data,
      mode,
      apiKey: geminiApiKey,
    });

    res.status(200).json(data);
  } catch (error) {
    // Sin este log, un modelo retirado o una clave revocada quedan escondidos
    // detras del plan de respaldo (responde 200) y nadie se entera.
    console.error("generate-training-session failed:", error?.status, error?.message);
    const safePayload = payload || {};
    const fallback = buildFallbackPlan(safePayload, mode);
    normalizeGeneratedPlanShape(fallback, safePayload, mode);
    normalizeGeneratedPlanQuality(fallback, safePayload);
    fallback.limitations = [
      ...fallback.limitations,
      "Gemini no devolvio una estructura estable; fobal genero un plan contextual de respaldo con los datos ingresados.",
    ];
    res.status(200).json(fallback);
  }
}

function rawText(value, fallback = "") {
  const text = String(value || "").trim();
  return text || fallback;
}

function buildFallbackPlan(payload, mode) {
  return mode === "match_tactic"
    ? buildFallbackTactic(payload)
    : buildFallbackTraining(payload);
}

function buildFallbackTraining(payload) {
  const session = payload.session_request || {};
  const category = payload.category || {};
  const club = payload.club || {};
  const objective = rawText(session.objective, "mejorar el funcionamiento colectivo");
  const problem = rawText(session.problem, "darle mas claridad a la ejecucion");
  const space = rawText(session.space, "media cancha");
  const players = Number(session.available_players) || Number(payload.data_quality?.category_players_loaded) || 14;
  const duration = Math.max(40, Number(session.duration_minutes) || 60);
  const warm = Math.min(12, Math.max(8, Math.round(duration * 0.18)));
  const correction = Math.min(18, Math.max(12, Math.round(duration * 0.28)));
  const opposition = Math.min(20, Math.max(12, Math.round(duration * 0.30)));
  const close = 6;
  const game = Math.max(10, duration - warm - correction - opposition - close);
  const groups = players >= 18 ? "3 grupos de 6" : players >= 12 ? "2 grupos equilibrados" : "grupos cortos con rotacion";
  const title = `${rawText(category.name, "Plantel")}: ${objective}`;

  return {
    title,
    objective: `La prioridad es convertir "${objective}" en conductas visibles, atacando el problema "${problem}" en ${space}. Para ${players} jugadores se propone una progresion de baja a alta oposicion, evitando tareas largas y usando ${groups}.`,
    blocks: [
      {
        name: "Activacion orientada al objetivo",
        duration: `${warm} min`,
        description: `Rondo o posesion corta en ${space}, con ${groups}. La regla principal es que cada punto solo vale si aparece una accion vinculada a "${objective}". El DT corrige perfil corporal, distancia de apoyo y primer control. Si el problema aparece como "${problem}", se pausa cinco segundos, se muestra la solucion y se reinicia desde esa situacion.`,
      },
      {
        name: "Correccion guiada del problema",
        duration: `${correction} min`,
        description: `Ejercicio principal con inicio controlado. Se recrea la situacion donde aparece "${problem}" y se obliga a resolverla antes de sumar velocidad. Puntua doble cuando el equipo ejecuta la respuesta esperada al objetivo. Progresion: primero sin oposicion real, luego con rival condicionado y finalmente con presion libre.`,
      },
      {
        name: "Oposicion y toma de decision",
        duration: `${opposition} min`,
        description: `Formato competitivo adaptado a ${players} jugadores. El espacio se divide en zonas para que la solucion no sea casual: debe aparecer la decision que mejora "${objective}". El entrenador interviene solo cuando la accion se parece al problema detectado, preguntando que opcion faltaba, quien debia dar apoyo y que referencia habia que mirar.`,
      },
      {
        name: "Juego condicionado de transferencia",
        duration: `${game} min`,
        description: `Partido reducido o juego real segun espacio disponible. La condicion de puntuacion premia las jugadas que resuelven el objetivo y penaliza repetir "${problem}". Se agrega una variante final: si el equipo logra tres acciones correctas seguidas, se libera una regla para comprobar si el aprendizaje se sostiene sin ayuda.`,
      },
      {
        name: "Cierre y evaluacion",
        duration: `${close} min`,
        description: `Vuelta a la calma breve y charla concreta. Cada jugador debe nombrar una decision que ayudo a cumplir "${objective}" y una correccion para evitar "${problem}" en el proximo entrenamiento o partido.`,
      },
    ],
    coach_cues: [
      `La accion vale si mejora ${objective}.`,
      `Antes de acelerar, corregimos ${problem}.`,
      "Perfilado antes de recibir.",
      "Apoyo cercano y opcion lejana visibles.",
      "Si perdemos claridad, paramos y repetimos la situacion.",
    ],
    success_indicators: [
      `Aumentan las acciones correctas vinculadas a ${objective}.`,
      `Baja la repeticion del problema: ${problem}.`,
      "El equipo resuelve sin que el DT frene cada repeticion.",
      "Los jugadores nombran la consigna principal sin ayuda.",
      `El formato funciona con ${players} jugadores en ${space}.`,
    ],
    context_used: [
      `Objetivo pedido: ${objective}.`,
      `Problema detectado: ${problem}.`,
      `Espacio disponible: ${space}.`,
      `Jugadores disponibles: ${players}.`,
      ...(payload.match_day_context?.periodization_label
        ? [`Etiqueta de carga: ${payload.match_day_context.periodization_label}.`]
        : []),
      `Club/equipo: ${rawText(club.name, "equipo manual")}.`,
    ],
    limitations: [
      "Plan de respaldo generado cuando el motor principal no devolvio JSON confiable.",
    ],
    confidence: "medium",
  };
}

function buildFallbackTactic(payload) {
  const match = payload.match_context || {};
  const category = payload.category || {};
  const rival = rawText(match.rival_name, "rival a definir");
  const rivalModel = rawText(match.rival_game_model_strengths_and_weaknesses, "sin descripcion completa del rival");
  const own = rawText(match.own_squad_individual_and_collective_profile, "sin perfil completo del plantel propio");
  return {
    title: `${rawText(category.name, "Plantel")} vs ${rival}`,
    objective: `Plan armado desde dos datos centrales: lo que se sabe del rival (${rivalModel}) y lo que sabemos del plantel propio (${own}).`,
    blocks: [
      {
        name: "Lectura del partido",
        duration: "Antes del partido",
        description: `El plan no inventa informacion: toma como base que el rival presenta "${rivalModel}" y que nuestro plantel tiene "${own}". La prioridad es elegir zonas de ventaja y no exponerse donde no tenemos datos suficientes.`,
      },
      {
        name: "Con pelota",
        duration: "Ataque",
        description: `Buscar progresar hacia la debilidad concreta descrita del rival. Si aparece una banda o sector flojo, cargar ahi con lateral/extremo/interior, ocupar area con dos referencias y dejar una cobertura por detras de la pelota.`,
      },
      {
        name: "Sin pelota",
        duration: "Defensa",
        description: `Bloque compacto y presion orientada para llevar al rival hacia zonas menos peligrosas. No perseguir individualmente si eso rompe la estructura del equipo.`,
      },
      {
        name: "Ajustes",
        duration: "Durante el partido",
        description: `Si el rival supera nuestra primera idea, bajar diez metros el bloque y atacar con transiciones mas simples. Si la ventaja prevista aparece, insistir con cambios de orientacion hacia ese sector.`,
      },
      {
        name: "Pelota quieta",
        duration: "ABP",
        description: `Diseñar dos acciones simples ligadas al perfil propio y a lo observado del rival. En ataque, cargar la zona donde el rival defiende peor; en defensa, asignar marcas por amenaza y dejar una referencia para segunda pelota.`,
      },
      {
        name: "Roles por linea",
        duration: "Durante el partido",
        description: `Defensas: sostener coberturas y no quedar largos. Medios: orientar la presion y elegir cuando acelerar. Atacantes: fijar referencias y atacar la zona marcada como mas vulnerable del rival.`,
      },
      {
        name: "Plan alternativo",
        duration: "Si no funciona",
        description: `Si el equipo no consigue progresar, simplificar: salida mas directa hacia la zona debil detectada, segunda pelota preparada y bloque mas corto para no partirse tras perdida.`,
      },
      {
        name: "Indicadores en vivo",
        duration: "Control del DT",
        description: `Revisar cada quince minutos si las llegadas nacen desde la zona planificada, si el rival juega incomodo y si las perdidas quedan protegidas. Si no ocurre, cambiar altura o lado de inicio.`,
      },
    ],
    coach_cues: [
      "Atacamos donde el rival concede.",
      "Perdida: primer pase hacia afuera bloqueado.",
      "El equipo no queda largo.",
      "Dos llegan al area, uno queda cubriendo.",
      "Si no hay ventaja, cambiamos de lado.",
    ],
    success_indicators: [
      "Llegadas generadas desde la zona elegida.",
      "Recuperaciones sin quedar partidos.",
      "Rival obligado a jugar incomodo.",
      "Menos perdidas con el equipo abierto.",
      "Ajuste aplicado antes de que el partido se rompa.",
    ],
    context_used: [
      `Rival: ${rival}.`,
      `Modelo/debilidades del rival: ${rivalModel}.`,
      `Plantel propio: ${own}.`,
    ],
    limitations: [
      "Plan de respaldo generado cuando el motor principal no devolvio JSON confiable.",
    ],
    confidence: "medium",
  };
}

function normalizeGeneratedPlanShape(data, payload, mode) {
  data.title = String(data.title || "").trim();
  data.objective = String(data.objective || "").trim();
  data.confidence = String(data.confidence || "").trim().toLowerCase();
  data.blocks = Array.isArray(data.blocks)
    ? data.blocks
        .map((block) => ({
          name: String(block?.name || "").trim(),
          duration: String(block?.duration || "").trim(),
          intensity: String(block?.intensity || "").trim(),
          description: String(block?.description || "").trim(),
          constraints: cleanList(block?.constraints),
          coaching_points: cleanList(block?.coaching_points),
          success_metric: String(block?.success_metric || "").trim(),
          animation_scene: block?.animation_scene ?? null,
        }))
        .filter((block) => block.name && block.description)
    : [];
  data.coach_cues = cleanList(data.coach_cues);
  data.success_indicators = cleanList(data.success_indicators);
  data.context_used = cleanList(data.context_used);
  data.limitations = cleanList(data.limitations);

  const evidence = Array.isArray(payload?.generation_quality?.evidence_contract)
    ? payload.generation_quality.evidence_contract
    : [];
  for (const item of evidence) {
    if (data.context_used.length >= 5) break;
    const normalized = normalize(item);
    const alreadyUsed = data.context_used.some((used) => normalize(used).includes(normalized.slice(0, 18)));
    if (!alreadyUsed && normalized.length > 8) data.context_used.push(String(item).trim());
  }

  if (mode === "training_session") {
    data.blocks = data.blocks.map((block) => ({
      ...block,
      duration: normalizeDuration(block.duration),
    }));
  }

  const session = payload?.session_request || {};
  const sessionSpace = String(session.space || "").trim();
  const sessionPlayers = Number(session.available_players) ||
    Number(payload?.data_quality?.category_players_loaded) || 12;
  data.blocks = data.blocks.map((block) => ({
    ...block,
    animation_scene: normalizeAnimationScene(block.animation_scene, {
      text: `${block.name} ${block.description} ${block.constraints.join(" ")}`,
      space: sessionSpace,
      players: sessionPlayers,
      cues: block.coaching_points,
    }),
  }));

  if (hasGenericPlanningLanguage(data)) {
    data.limitations.push(
      "Se detectaron formulaciones genericas en parte del plan; revisar consignas y adaptar al cuerpo tecnico antes de ejecutar."
    );
    if (data.confidence === "high") data.confidence = "medium";
  }
}

function cleanList(value) {
  if (!Array.isArray(value)) return [];
  const seen = new Set();
  const result = [];
  for (const item of value) {
    const text = String(item || "").trim();
    const key = normalize(text);
    if (!key || seen.has(key)) continue;
    seen.add(key);
    result.push(text);
  }
  return result;
}

function normalizeDuration(value) {
  const minutes = Number.parseInt(String(value || ""), 10);
  return Number.isFinite(minutes) && minutes > 0 ? `${minutes} min` : String(value || "").trim();
}

const PITCH_AREAS = new Set([
  "full",
  "half",
  "attacking_third",
  "middle_third",
  "defensive_third",
  "small_grid",
  "wide_channels",
]);

function clamp01(v) {
  const n = Number(v);
  if (!Number.isFinite(n)) return 0.5;
  return Math.min(1, Math.max(0, n));
}

function normPoint(p) {
  if (Array.isArray(p) && p.length >= 2) return { x: clamp01(p[0]), y: clamp01(p[1]) };
  if (p && typeof p === "object") return { x: clamp01(p.x), y: clamp01(p.y) };
  return { x: 0.5, y: 0.5 };
}

function normPitchArea(value) {
  const t = String(value || "full").toLowerCase().trim().replace(/[\s-]+/g, "_");
  if (PITCH_AREAS.has(t)) return t;
  if (/(cuadr|reduc|grid|rombo|rond)/.test(t)) return "small_grid";
  if (/(ofens|attack|final)/.test(t)) return "attacking_third";
  if (/(fondo|salida|propi|defensiv)/.test(t)) return "defensive_third";
  if (/(banda|ancho|wide|amplitud|carril)/.test(t)) return "wide_channels";
  if (/(medio|middle|central)/.test(t)) return "middle_third";
  if (/(media|mitad|half)/.test(t)) return "half";
  return "full";
}

// Deterministic scene from a block's text + session context. Mirrors the
// Flutter fallback so both paths stay consistent. Distinct objectives /
// spaces / player counts produce visibly distinct scenes.
function buildSceneFromText({ text, space, players, cues = [] }) {
  const t = `${text || ""} ${space || ""}`.toLowerCase();
  const area = normPitchArea(`${space || ""} ${text || ""}`);
  const total = Math.min(12, Math.max(4, Math.round(Number(players) || 12)));
  const perSide = Math.min(6, Math.max(2, Math.round(total / 2)));
  const has = (re) => re.test(t);
  const p = (x, y) => ({ x: clamp01(x), y: clamp01(y) });

  const scene = {
    pitch_area: area,
    players: [],
    ball_path: [],
    movements: [],
    zones: [],
    coaching_cues: (cues || [])
      .map((c) => String(c || "").trim())
      .filter(Boolean)
      .slice(0, 3),
    duration_seconds: 9,
  };

  if (has(/(presion|presi[oó]n|recuper|tras p[eé]rdida|robar|marca)/)) {
    scene.players.push({ id: "r1", label: "R", team: "rival", start: p(0.5, 0.32), end: p(0.42, 0.24), role: "con balon" });
    for (let i = 1; i < perSide; i++) {
      const rx = 0.25 + (i / perSide) * 0.5;
      scene.players.push({ id: `r${i + 1}`, label: "r", team: "rival", start: p(rx, 0.18), end: p(rx, 0.14), role: "apoyo rival" });
    }
    for (let i = 0; i < perSide; i++) {
      const sx = 0.2 + (i / perSide) * 0.6;
      const start = p(sx, 0.62 + (i % 2 === 0 ? 0.06 : 0));
      const end = p(0.5 + (sx - 0.5) * 0.35, 0.42);
      scene.players.push({ id: `o${i + 1}`, label: `${i + 1}`, team: "own", start, end, role: i === 0 ? "presiona al balon" : "cierra linea de pase" });
      scene.movements.push({ player: `o${i + 1}`, from: start, to: end, start_s: 0, end_s: 4 + i, type: i === 0 ? "presion" : "cobertura" });
    }
    scene.ball_path = [p(0.5, 0.32), p(0.6, 0.28), p(0.55, 0.2), p(0.4, 0.16)];
    scene.zones.push({ type: "target", label: "zona de recuperacion", x: 0.28, y: 0.1, width: 0.44, height: 0.34 });
  } else if (has(/(salida|construcci|desde el fondo|amplitud|circulaci|posesi)/)) {
    scene.players.push({ id: "gk", label: "PO", team: "own", start: p(0.5, 0.06), end: p(0.5, 0.1), role: "inicia" });
    const laneXs = [0.12, 0.38, 0.62, 0.88];
    for (let i = 0; i < perSide; i++) {
      const lane = laneXs[i % laneXs.length];
      const start = p(lane, 0.2 + (i % 2 === 0 ? 0 : 0.08));
      const end = p(lane, 0.44 + i * 0.05);
      scene.players.push({ id: `o${i + 1}`, label: `${i + 1}`, team: "own", start, end, role: i === 0 ? "recibe y orienta" : "ofrece amplitud" });
      scene.movements.push({ player: `o${i + 1}`, from: start, to: end, start_s: 1 + i, end_s: 5 + i, type: i === 0 ? "conduccion" : "apoyo" });
    }
    for (let i = 0; i < Math.min(4, Math.max(1, perSide - 1)); i++) {
      const rx = 0.32 + (i / 3) * 0.36;
      scene.players.push({ id: `r${i + 1}`, label: "r", team: "rival", start: p(rx, 0.5), end: p(rx, 0.42), role: "presiona salida" });
    }
    scene.ball_path = [p(0.5, 0.08), p(0.14, 0.24), p(0.4, 0.4), p(0.82, 0.5), p(0.7, 0.68)];
    scene.zones.push({ type: "lane", label: "carril izquierdo", x: 0, y: 0, width: 0.28, height: 1 });
    scene.zones.push({ type: "lane", label: "carril derecho", x: 0.72, y: 0, width: 0.28, height: 1 });
    scene.zones.push({ type: "target", label: "zona de progresion", x: 0.2, y: 0.6, width: 0.6, height: 0.3 });
  } else if (has(/(finaliz|defin|remate|gol|llegada al [aá]rea|centro)/)) {
    for (let i = 0; i < perSide; i++) {
      const sx = 0.2 + (i / perSide) * 0.6;
      const start = p(sx, 0.55 - i * 0.03);
      const end = p(0.35 + (i / perSide) * 0.3, 0.86);
      scene.players.push({ id: `o${i + 1}`, label: `${i + 1}`, team: "own", start, end, role: i === 0 ? "asiste" : "ataca el area" });
      scene.movements.push({ player: `o${i + 1}`, from: start, to: end, start_s: i, end_s: 4 + i, type: i === 0 ? "pase" : "desmarque" });
    }
    for (let i = 0; i < Math.min(4, Math.max(1, perSide - 1)); i++) {
      scene.players.push({ id: `r${i + 1}`, label: "r", team: "rival", start: p(0.35 + i * 0.12, 0.82), end: p(0.35 + i * 0.12, 0.82), role: "defiende area" });
    }
    scene.ball_path = [p(0.2, 0.55), p(0.5, 0.7), p(0.62, 0.88)];
    scene.zones.push({ type: "target", label: "area rival", x: 0.28, y: 0.78, width: 0.44, height: 0.22 });
  } else {
    for (let i = 0; i < perSide; i++) {
      const sx = 0.18 + (i / perSide) * 0.64;
      const start = p(sx, 0.3);
      const end = p(sx + 0.05, 0.7);
      scene.players.push({ id: `o${i + 1}`, label: `${i + 1}`, team: "own", start, end, role: "progresa" });
      scene.movements.push({ player: `o${i + 1}`, from: start, to: end, start_s: i, end_s: 5 + i, type: "apoyo" });
    }
    for (let i = 0; i < Math.min(4, Math.max(1, perSide - 1)); i++) {
      const rx = 0.3 + (i / 3) * 0.4;
      scene.players.push({ id: `r${i + 1}`, label: "r", team: "rival", start: p(rx, 0.55), end: p(rx, 0.5), role: "defiende" });
    }
    scene.ball_path = [p(0.2, 0.3), p(0.45, 0.45), p(0.7, 0.62), p(0.55, 0.8)];
    scene.zones.push({ type: "target", label: "zona objetivo", x: 0.25, y: 0.62, width: 0.5, height: 0.3 });
  }
  return scene;
}

// Clean an AI-provided animation_scene; fall back to buildSceneFromText when
// it is missing or unusable so the client always gets a structured scene.
function normalizeAnimationScene(raw, ctx) {
  if (!raw || typeof raw !== "object") return buildSceneFromText(ctx);
  const players = (Array.isArray(raw.players) ? raw.players : [])
    .filter((pl) => pl && typeof pl === "object")
    .map((pl, i) => {
      const start = normPoint(pl.start || pl.start_position || pl.from);
      return {
        id: String(pl.id || pl.label || `p${i + 1}`).trim(),
        label: String(pl.label || pl.id || `${i + 1}`).trim(),
        team: /^riv|opp|contra/i.test(String(pl.team || ""))
          ? "rival"
          : /neut|comod|joker/i.test(String(pl.team || ""))
            ? "neutral"
            : "own",
        start,
        end: normPoint(pl.end || pl.end_position || pl.to || start),
        role: String(pl.role || "").trim(),
      };
    })
    .slice(0, 22);
  const ballPath = (Array.isArray(raw.ball_path) ? raw.ball_path : [])
    .map(normPoint)
    .slice(0, 8);
  if (players.length === 0 || ballPath.length < 2) return buildSceneFromText(ctx);
  const movements = (Array.isArray(raw.movements) ? raw.movements : [])
    .filter((m) => m && typeof m === "object")
    .map((m) => {
      const s = Math.max(0, Number(m.start_s ?? m.start ?? m.timing) || 0);
      const e = Number(m.end_s ?? m.end) || s + 2;
      return {
        player: String(m.player || m.player_id || m.id || "").trim(),
        from: normPoint(m.from),
        to: normPoint(m.to),
        start_s: s,
        end_s: e <= s ? s + 2 : e,
        type: String(m.type || m.movement_type || "movimiento").trim(),
      };
    })
    .slice(0, 30);
  const zones = (Array.isArray(raw.zones) ? raw.zones : [])
    .filter((z) => z && typeof z === "object")
    .map((z) => ({
      type: /prohib|forbid|no-go/i.test(String(z.type || ""))
        ? "forbidden"
        : /carril|lane|pasillo/i.test(String(z.type || ""))
          ? "lane"
          : "target",
      label: String(z.label || "").trim(),
      x: clamp01(z.x),
      y: clamp01(z.y),
      width: clamp01(z.width ?? z.w ?? 0.3),
      height: clamp01(z.height ?? z.h ?? 0.3),
    }))
    .slice(0, 8);
  let dur = Number(raw.duration_seconds ?? raw.durationSeconds) || 8;
  dur = Math.min(20, Math.max(3, dur));
  return {
    pitch_area: normPitchArea(raw.pitch_area ?? raw.pitchArea),
    players,
    ball_path: ballPath,
    movements,
    zones,
    coaching_cues: (Array.isArray(raw.coaching_cues) ? raw.coaching_cues : [])
      .map((c) => String(c || "").trim())
      .filter(Boolean)
      .slice(0, 3),
    duration_seconds: dur,
  };
}

function hasGenericPlanningLanguage(data) {
  const genericPatterns = [
    "trabajar el objetivo",
    "adaptarse al rival",
    "jugar con intensidad",
    "aprovechar los espacios",
    "mejorar la tecnica",
    "mantener concentracion",
  ];
  const text = normalize([
    data.objective,
    ...data.blocks.map((block) => `${block.name} ${block.description}`),
    ...data.coach_cues,
    ...data.success_indicators,
  ].join(" "));
  return genericPatterns.some((pattern) => text.includes(normalize(pattern)));
}

function normalizeGeneratedPlanQuality(data, payload) {
  const loadedPlayers = payload?.data_quality?.category_players_loaded ?? 0;
  const incompleteProfiles = payload?.data_quality?.incomplete_ai_player_profiles ?? 0;
  const contextScore = Number(payload?.generation_quality?.context_score ?? 100);
  const missingFields = payload?.data_quality?.missing_profile_fields ?? [];

  if (Number.isFinite(contextScore) && contextScore < 70) {
    const limitation = `Contexto de generacion incompleto (${contextScore}/100); completar ${missingFields.slice(0, 3).join(", ") || "mas evidencias del club"} para elevar precision.`;
    if (!data.limitations.some((item) => normalize(item).includes("contexto de generacion"))) {
      data.limitations.push(limitation);
    }
    if (data.confidence === "high") data.confidence = "medium";
    if (contextScore < 45) data.confidence = "low";
  }

  const evidence = payload?.generation_quality?.evidence_contract ?? [];
  if (Array.isArray(evidence) && evidence.length >= 3) {
    const used = data.context_used.map(normalize).join(" ");
    const evidenceHits = evidence.filter((item) => {
      const normalized = normalize(item);
      const key = normalized.split(" ").slice(0, 3).join(" ");
      return key && used.includes(key);
    }).length;
    if (evidenceHits < 2) {
      data.limitations.push("La respuesta uso pocas evidencias auditables del contrato de datos; revisar antes de compartir.");
      if (data.confidence === "high") data.confidence = "medium";
    }
  }

  if (!loadedPlayers || !incompleteProfiles) return;

  const ratio = incompleteProfiles / loadedPlayers;
  const limitation = `${incompleteProfiles} perfiles de jugador incompletos para IA; faltan posicion, rol alternativo, pie habil, estado o nota tecnica en parte del plantel.`;
  const alreadyMentioned = data.limitations.some((item) =>
    normalize(item).includes("perfil") || normalize(item).includes("jugador")
  );
  if (!alreadyMentioned) data.limitations.push(limitation);
  if (ratio > 0.25 && data.confidence === "high") data.confidence = "medium";
  if (ratio > 0.55) data.confidence = "low";
}

async function authenticateClubRequest(req, payload) {
  const previewToken = String(
    req.headers["x-cantera-preview-token"] || "",
  ).trim();
  if (previewToken && verifyPreviewToken(previewToken)) {
    return { ok: true, preview: true };
  }
  if (!process.env.SUPABASE_URL || !process.env.SUPABASE_ANON_KEY) {
    return {
      ok: false,
      status: 503,
      error: "auth_not_configured",
      message: "El acceso seguro al asistente no esta configurado.",
    };
  }
  const authorization = String(req.headers.authorization || "");
  const token = authorization.startsWith("Bearer ")
    ? authorization.slice(7).trim()
    : "";
  if (!token) {
    return {
      ok: false,
      status: 401,
      error: "not_authenticated",
      message: "Iniciá sesión para usar el asistente.",
    };
  }
  const clubId = String(payload?.club?.id || "");
  if (!clubId) {
    return {
      ok: false,
      status: 400,
      error: "club_required",
      message: "No se pudo identificar el club activo.",
    };
  }
  const club = payload?.club || {};
  const dataSource = String(
    club.data_source || club.dataSource || "",
  ).trim().toLowerCase();
  const league = String(club.league || "").trim().toLowerCase();
  const isIndependentClub =
    dataSource === "manual" ||
    league === "trabajo independiente" ||
    clubId.startsWith("externo-");
  const supabase = createClient(
    process.env.SUPABASE_URL,
    process.env.SUPABASE_ANON_KEY,
    {
      auth: { persistSession: false },
      global: { headers: { Authorization: `Bearer ${token}` } },
    },
  );
  const { data: userData, error: userError } = await supabase.auth.getUser(token);
  if (userError || !userData.user) {
    return {
      ok: false,
      status: 401,
      error: "invalid_session",
      message: "Tu sesion vencio. Vuelve a ingresar para usar el asistente.",
    };
  }
  if (isIndependentClub) {
    // isIndependentClub is derived from fields the CLIENT sends in the
    // request body (club.data_source/league, or a clubId prefix), so it
    // must not be trusted on its own. Verify the caller actually owns or
    // collaborates on this manual club before granting access, otherwise
    // anyone can claim an arbitrary clubId as "manual" and both read the
    // generation endpoint and, via persistGeneratedContext(), write RAG
    // memory under a club_id they have no real relationship to.
    const [{ data: ownedDoc }, { data: collaboration }] = await Promise.all([
      supabase
        .from("club_documents")
        .select("club_id")
        .eq("club_id", clubId)
        .eq("user_id", userData.user.id)
        .maybeSingle(),
      supabase
        .from("club_collaborators")
        .select("club_id")
        .eq("club_id", clubId)
        .eq("user_id", userData.user.id)
        .eq("status", "active")
        .maybeSingle(),
    ]);
    if (!ownedDoc && !collaboration) {
      return {
        ok: false,
        status: 403,
        error: "club_access_denied",
        message: "No tenes acceso a este club.",
      };
    }
    return {
      ok: true,
      role: "independent_coach",
      userId: userData.user.id,
      clubId,
      isMember: true,
    };
  }
  const { data: membership, error: membershipError } = await supabase
    .from("club_memberships")
    .select("role,status,category_ids")
    .eq("club_id", clubId)
    .eq("user_id", userData.user.id)
    .eq("status", "active")
    .maybeSingle();
  if (!membershipError && membership) {
    const writerRoles = new Set([
      "platform_admin",
      "club_admin",
      "coach",
      "assistant",
      "physical_trainer",
    ]);
    if (!writerRoles.has(membership.role)) {
      return {
        ok: false,
        status: 403,
        error: "read_only_role",
        message: "Tu rol es de solo lectura y no puede generar planes.",
      };
    }
    // Same category-scoping rule claim-category-access.js enforces: an
    // empty category_ids means unrestricted (admins and clubs that never
    // assigned categories), a populated one restricts assistants/PFs to
    // just their categories. Without this, a coach limited to one category
    // could still generate and persist AI memory under a sibling category
    // of the same club.
    const assignedCategoryIds = Array.isArray(membership.category_ids)
      ? membership.category_ids
      : [];
    const adminRoles = new Set(["platform_admin", "club_admin"]);
    const requestedCategoryId = String(payload?.category?.id || "");
    if (
      !adminRoles.has(membership.role) &&
      assignedCategoryIds.length > 0 &&
      !assignedCategoryIds.includes(requestedCategoryId)
    ) {
      return {
        ok: false,
        status: 403,
        error: "category_denied",
        message: "Esa categoria no esta asignada a tu cuenta.",
      };
    }
    return {
      ok: true,
      role: membership.role,
      userId: userData.user.id,
      clubId,
      isMember: true,
    };
  }
  // No membership row: this is normal for the "explorar clubes de la liga"
  // preview flow, where a coach browses any public LUD club's data without
  // formally joining it. Public LUD clubs stay usable for generation, but
  // isMember stays false so loadRagContext/persistGeneratedContext never
  // read or write that club's shared memory under an id the caller doesn't
  // actually belong to — only their own user-scoped memory.
  const { data: ludClub } = await supabase
    .from("cantera_clubs")
    .select("id,lud_team_id,status")
    .eq("id", clubId)
    .eq("status", "active")
    .not("lud_team_id", "is", null)
    .maybeSingle();
  if (!ludClub) {
    return {
      ok: false,
      status: 403,
      error: "club_access_denied",
      message: "No tenes acceso a este club.",
    };
  }
  return {
    ok: true,
    role: "lud_preview",
    userId: userData.user.id,
    clubId,
    isMember: false,
  };
}

// Gemini free tier es POR PROYECTO y Google lo recorta sin aviso; estos topes
// van por debajo del piso conocido (10 RPM / 250 RPD de 2.5 Flash). Ajustables
// por env sin redeploy de codigo.
function envInt(name, fallback) {
  const value = Number.parseInt(process.env[name] || "", 10);
  return Number.isFinite(value) && value > 0 ? value : fallback;
}

async function consumeAiQuota(access) {
  if (!process.env.SUPABASE_URL || !process.env.SUPABASE_SERVICE_ROLE_KEY) {
    return { ok: true };
  }
  try {
    const supabase = createClient(
      process.env.SUPABASE_URL,
      process.env.SUPABASE_SERVICE_ROLE_KEY,
      { auth: { persistSession: false } },
    );
    const { data, error } = await supabase.rpc("ai_usage_consume", {
      p_user: access?.userId || "preview",
      p_user_day: envInt("AI_USER_DAILY_LIMIT", 20),
      p_global_day: envInt("AI_GLOBAL_DAILY_LIMIT", 200),
      p_global_minute: envInt("AI_GLOBAL_MINUTE_LIMIT", 6),
    });
    // Falla de infraestructura: no bloquear al DT; el 429 de Gemini es el
    // respaldo (sin billing activo, exceder la cuota nunca genera cobro).
    if (error) return { ok: true };
    if (data === "user_day") {
      return {
        ok: false,
        message:
          "Llegaste al limite diario de generaciones con IA. Se renueva mañana.",
      };
    }
    if (data === "global_day") {
      return {
        ok: false,
        message:
          "El asistente alcanzo su limite diario de uso. Volve a intentar mañana.",
      };
    }
    if (data === "global_minute") {
      return {
        ok: false,
        retryAfter: 60,
        message:
          "El asistente esta con mucha demanda. Proba de nuevo en un minuto.",
      };
    }
    return { ok: true };
  } catch (_) {
    return { ok: true };
  }
}

// gemini-1.5-flash y text-embedding-004 ya fueron retirados por Google; se
// prueba primero un modelo vigente y se cae al siguiente solo si el actual no
// existe (404), agoto cuota (429) o esta caido (5xx). GEMINI_MODEL fuerza uno.
const GENERATION_MODELS = [
  ...new Set(
    [
      process.env.GEMINI_MODEL,
      "gemini-2.5-flash",
      "gemini-2.5-flash-lite",
      "gemini-1.5-flash",
    ].filter(Boolean),
  ),
];

async function generateWithModelFallback(genAI, prompt) {
  let lastError;
  for (const modelName of GENERATION_MODELS) {
    try {
      const generationConfig = {
        maxOutputTokens: 8192,
        responseMimeType: "application/json",
      };
      // 2.5 "piensa" por defecto y ese razonamiento se come los tokens de
      // salida: el JSON llegaria cortado.
      if (modelName.startsWith("gemini-2.5")) {
        generationConfig.thinkingConfig = { thinkingBudget: 0 };
      }
      return await genAI
        .getGenerativeModel({ model: modelName, generationConfig })
        .generateContent(prompt);
    } catch (error) {
      lastError = error;
      if (![404, 429, 500, 503].includes(error?.status)) throw error;
    }
  }
  throw lastError;
}

async function embedText(apiKey, text) {
  const response = await fetch(
    "https://generativelanguage.googleapis.com/v1beta/models/gemini-embedding-001:embedContent",
    {
      method: "POST",
      headers: { "content-type": "application/json", "x-goog-api-key": apiKey },
      // La columna training_context_documents.embedding es vector(768).
      body: JSON.stringify({
        content: { parts: [{ text }] },
        outputDimensionality: 768,
      }),
    },
  );
  if (!response.ok) throw new Error(`embedding_failed_${response.status}`);
  const json = await response.json();
  const values = json?.embedding?.values;
  if (!Array.isArray(values) || values.length !== 768) {
    throw new Error("embedding_bad_shape");
  }
  return values;
}

async function loadRagContext({ payload, access, apiKey }) {
  if (!process.env.SUPABASE_URL || !process.env.SUPABASE_SERVICE_ROLE_KEY) {
    return [];
  }
  if (!access?.userId) return [];
  try {
    const text = [
      payload?.mode,
      payload?.club?.name,
      payload?.category?.name,
      payload?.session_request?.objective,
      payload?.session_request?.problem,
      payload?.match_context?.rival_name,
      payload?.match_context?.rival_game_model_strengths_and_weaknesses,
      payload?.match_context?.own_squad_individual_and_collective_profile,
    ]
      .filter(Boolean)
      .join("\n")
      .slice(0, 6000);
    if (!text.trim()) return [];

    const embedding = await embedText(apiKey, text);
    const supabase = createClient(
      process.env.SUPABASE_URL,
      process.env.SUPABASE_SERVICE_ROLE_KEY,
      { auth: { persistSession: false } },
    );
    const { data, error } = await supabase.rpc("match_training_context", {
      query_embedding: embedding,
      match_count: 8,
      filter_user_id: access.userId,
      filter_club_id: access.isMember ? access.clubId : null,
      filter_category_id: String(payload?.category?.id || ""),
    });
    if (error || !Array.isArray(data)) return [];
    return data.map((item) => ({
      content: String(item.content || ""),
      metadata: item.metadata || {},
      similarity: Number(item.similarity || 0),
    }));
  } catch (_) {
    return [];
  }
}

async function persistGeneratedContext({ payload, access, data, mode, apiKey }) {
  if (!process.env.SUPABASE_URL || !process.env.SUPABASE_SERVICE_ROLE_KEY) {
    return;
  }
  if (!access?.userId) return;
  const memoryClubId = access.isMember && isUuid(access.clubId) ? access.clubId : null;
  try {
    const content = [
      `Tipo: ${mode}`,
      `Club: ${payload?.club?.name || ""}`,
      `Categoria: ${payload?.category?.name || ""}`,
      `Titulo: ${data?.title || ""}`,
      `Diagnostico: ${data?.objective || ""}`,
      `Bloques: ${Array.isArray(data?.blocks) ? data.blocks.map((block) => `${block.name}: ${block.description}`).join(" | ") : ""}`,
      `Consignas: ${Array.isArray(data?.coach_cues) ? data.coach_cues.join(" | ") : ""}`,
      `Indicadores: ${Array.isArray(data?.success_indicators) ? data.success_indicators.join(" | ") : ""}`,
    ]
      .filter((line) => line.replace(/^[^:]+:\s*/, "").trim())
      .join("\n")
      .slice(0, 9000);
    if (!content.trim()) return;

    const embedding = await embedText(apiKey, content);
    const supabase = createClient(
      process.env.SUPABASE_URL,
      process.env.SUPABASE_SERVICE_ROLE_KEY,
      { auth: { persistSession: false } },
    );
    const { error: insertError } = await supabase
      .from("training_context_documents")
      .insert({
        club_id: memoryClubId,
        user_id: access.userId,
        category_id: String(payload?.category?.id || ""),
        source_type: mode,
        content,
        metadata: {
          title: data?.title || "",
          confidence: data?.confidence || "",
          generated_at: new Date().toISOString(),
        },
        embedding,
      });
    // The Supabase client does not throw on a rejected insert (bad
    // constraint, RLS denial, etc) — it returns { error }. Not checking it
    // let every failed RAG write look like a success: the plan generated
    // fine, but the memory silently never saved. Logging at least makes a
    // recurring failure visible in Vercel logs instead of invisible.
    if (insertError) {
      console.error("persistGeneratedContext insert failed:", insertError.message);
    }
  } catch (error) {
    console.error("persistGeneratedContext failed:", error?.message || error);
  }
}

function isUuid(value) {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(
    String(value || ""),
  );
}

function verifyPreviewToken(token) {
  const signingKey = process.env.CANTERA_PREVIEW_SIGNING_KEY;
  if (!signingKey) return false;
  const [encodedPayload, signature] = token.split('.');
  if (!encodedPayload || !signature) return false;
  const expected = createHmac('sha256', signingKey)
    .update(encodedPayload)
    .digest('base64url');
  const actualBuffer = Buffer.from(signature);
  const expectedBuffer = Buffer.from(expected);
  if (actualBuffer.length !== expectedBuffer.length) return false;
  if (!timingSafeEqual(actualBuffer, expectedBuffer)) return false;
  try {
    const payload = JSON.parse(
      Buffer.from(encodedPayload, 'base64url').toString('utf8'),
    );
    return payload.scope === 'preview_ai' && Number(payload.exp) > Date.now();
  } catch (_) {
    return false;
  }
}

function validateGeneratedPlan(data, payload, mode) {
  if (
    !Array.isArray(data.blocks) ||
    !Array.isArray(data.coach_cues) ||
    !Array.isArray(data.success_indicators) ||
    !Array.isArray(data.context_used) ||
    !Array.isArray(data.limitations)
  ) {
    throw new Error("Gemini returned an incomplete schema");
  }
  if (data.context_used.length < 2 || !["high", "medium", "low"].includes(data.confidence)) {
    throw new Error("Gemini returned an untraceable plan");
  }
  if (data.coach_cues.length < 3 || data.success_indicators.length < 3) {
    throw new Error("Gemini returned insufficient operational detail");
  }
  if (mode === "training_session") {
    const total = data.blocks.reduce((sum, block) => {
      const minutes = Number.parseInt(String(block?.duration ?? ""), 10);
      return sum + (Number.isFinite(minutes) ? minutes : 0);
    }, 0);
    const expected = Number(payload.session_request.duration_minutes);
    if (Math.abs(total - expected) > 5) {
      throw new Error(`Session duration mismatch: expected ${expected}, got ${total}`);
    }
  }
}
