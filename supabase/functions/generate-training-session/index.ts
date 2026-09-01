import { GoogleGenerativeAI } from "npm:@google/generative-ai";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "access-control-allow-origin": "*",
  "access-control-allow-headers":
    "authorization, x-client-info, apikey, content-type",
  "access-control-allow-methods": "POST, OPTIONS",
};

type RagDocument = {
  id: string;
  content: string;
  metadata: Record<string, unknown>;
  similarity?: number;
};

const responseSchema = {
  title: "string",
  objective: "string",
  blocks: [
    {
      name: "string",
      duration: "string",
      intensity: "low | medium | high",
      description: "string",
      constraints: ["string"],
      coaching_points: ["string"],
      success_metric: "string",
    },
  ],
  coach_cues: ["string"],
  success_indicators: ["string"],
  context_used: ["string"],
  limitations: ["string"],
  confidence: "low | medium | high",
};

const systemPrompt = `
Sos fobal, un motor de planificacion deportiva para entrenadores de futbol.

MANDATO
No devolves texto libre. Devolves exclusivamente JSON valido con el schema indicado.
La respuesta debe ser deterministica, contextual y trazable: cada bloque debe derivar de datos concretos recibidos o del historial RAG inyectado.

REGLAS
- No inventes jugadores, lesiones, disponibilidad, rival ni metricas.
- Si falta informacion, baja confidence y explicalo en limitations.
- Si el pedido es absurdo o insuficiente, devolve JSON valido con title "Informacion insuficiente" y bloques para pedir mejores datos.
- Cada ejercicio debe incluir duracion, intensidad, descripcion aplicable, restricciones, correcciones del entrenador e indicador de exito.
- Para match_tactic, los bloques representan fases del partido; para training_session, ejercicios de entrenamiento.
- Usa los documentos RAG solo si aparecen en RAG_CONTEXT.
- No menciones RAG, embeddings, Supabase ni Gemini al usuario final.
`;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return json({ ok: true });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  try {
    const payload = await req.json();
    const access = await requireUser(req);
    const rag = await loadRagContext(payload, access.userId);
    const prompt = buildPrompt(payload, rag);
    const plan = await generateStructuredPlan(prompt);
    validatePlan(plan);
    return json(plan);
  } catch (error) {
    return json(
      {
        error: "generation_failed",
        message:
          error instanceof Error
            ? error.message
            : "No se pudo generar una respuesta confiable.",
      },
      error instanceof AuthError ? 401 : 500,
    );
  }
});

async function requireUser(req: Request) {
  const authHeader = req.headers.get("authorization") ?? "";
  const token = authHeader.replace(/^Bearer\s+/i, "").trim();
  if (!token) throw new AuthError("Inicia sesion para usar el asistente.");

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const supabaseAnon = Deno.env.get("SUPABASE_ANON_KEY");
  if (!supabaseUrl || !supabaseAnon) {
    throw new Error("Supabase no esta configurado.");
  }

  const supabase = createClient(supabaseUrl, supabaseAnon, {
    global: { headers: { Authorization: `Bearer ${token}` } },
  });
  const { data, error } = await supabase.auth.getUser(token);
  if (error || !data.user) throw new AuthError("Sesion invalida.");
  return { token, userId: data.user.id };
}

async function loadRagContext(
  payload: Record<string, unknown>,
  userId: string,
): Promise<RagDocument[]> {
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceKey) return [];

  const query = [
    payload["mode"],
    payload["club"],
    payload["category"],
    payload["session_request"],
    payload["match_context"],
  ]
    .map((item) => JSON.stringify(item ?? ""))
    .join("\n");

  const embedding = await embed(query);
  if (!embedding.length) return [];

  const supabase = createClient(supabaseUrl, serviceKey);
  const { data, error } = await supabase.rpc("match_training_context", {
    query_embedding: embedding,
    match_count: 8,
    filter_user_id: userId,
    filter_club_id: String(
      (payload["club"] as Record<string, unknown> | undefined)?.["id"] ?? "",
    ),
  });
  if (error || !Array.isArray(data)) return [];
  return data.map((row) => ({
    id: String(row.id ?? ""),
    content: String(row.content ?? ""),
    metadata: row.metadata ?? {},
    similarity: Number(row.similarity ?? 0),
  }));
}

async function embed(text: string): Promise<number[]> {
  const apiKey = Deno.env.get("GEMINI_API_KEY2") ?? Deno.env.get("GEMINI_API_KEY");
  if (!apiKey) return [];
  const genAI = new GoogleGenerativeAI(apiKey);
  const model = genAI.getGenerativeModel({ model: "text-embedding-004" });
  const result = await model.embedContent(text.slice(0, 6000));
  return result.embedding.values;
}

async function generateStructuredPlan(prompt: string) {
  const apiKey = Deno.env.get("GEMINI_API_KEY2") ?? Deno.env.get("GEMINI_API_KEY");
  if (!apiKey) throw new Error("Gemini no esta configurado.");

  const genAI = new GoogleGenerativeAI(apiKey);
  const model = genAI.getGenerativeModel({
    model: "gemini-1.5-flash",
    generationConfig: {
      temperature: 0.25,
      topP: 0.8,
      maxOutputTokens: 8192,
      responseMimeType: "application/json",
    },
  });
  const result = await model.generateContent(prompt);
  return parseJson(result.response.text());
}

function buildPrompt(payload: unknown, rag: RagDocument[]) {
  return `${systemPrompt}

SCHEMA JSON OBLIGATORIO:
${JSON.stringify(responseSchema, null, 2)}

RAG_CONTEXT:
${JSON.stringify(rag, null, 2)}

PAYLOAD:
${JSON.stringify(payload, null, 2)}
`;
}

function validatePlan(plan: Record<string, unknown>) {
  if (typeof plan.title !== "string" || typeof plan.objective !== "string") {
    throw new Error("La IA devolvio un plan sin titulo u objetivo.");
  }
  if (!Array.isArray(plan.blocks) || plan.blocks.length < 4) {
    throw new Error("La IA devolvio pocos bloques.");
  }
  if (!Array.isArray(plan.coach_cues) || plan.coach_cues.length < 3) {
    throw new Error("La IA devolvio pocas consignas.");
  }
  if (!Array.isArray(plan.success_indicators) || plan.success_indicators.length < 3) {
    throw new Error("La IA devolvio pocos indicadores.");
  }
}

function parseJson(text: string) {
  const cleaned = text
    .trim()
    .replace(/^```json\s*/i, "")
    .replace(/^```\s*/i, "")
    .replace(/```$/i, "")
    .trim();
  return JSON.parse(cleaned);
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "content-type": "application/json",
    },
  });
}

class AuthError extends Error {}
