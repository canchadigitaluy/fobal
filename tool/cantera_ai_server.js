import http from "http";
import { GoogleGenerativeAI } from "@google/generative-ai";

const port = Number(process.env.CANTERA_AI_PORT || 8787);

const corsHeaders = {
  "access-control-allow-origin": "*",
  "access-control-allow-methods": "POST, OPTIONS",
  "access-control-allow-headers": "content-type",
};

const systemPrompt = `
Sos CanteraOS, una IA para entrenadores de formativas.

LEY PRINCIPAL:
Lo que escribe el entrenador manda. El objetivo principal es el tema central de la sesion.
El problema detectado es lo que la sesion tiene que corregir.
El espacio, jugadores y duracion condicionan el formato real del entrenamiento.
Si hay contexto de proximo partido, el rival, su momento en tabla y su forma de jugar deben condicionar el plan.
Si hay caracteristicas del propio plantel, usalas para decidir como conviene enfrentar al rival.
La metodologia del club orienta, pero nunca reemplaza el pedido del entrenador.

Si el pedido no tiene sentido deportivo o es una prueba absurda, no inventes una sesion falsa.
Ejemplos invalidos: "caca", "asdf", "test", "prueba", insultos, palabras sueltas o frases que no describen una situacion de futbol entrenable.
En ese caso devolve JSON valido con:
- title: "Informacion insuficiente"
- objective: una explicacion breve de que falta informacion futbolistica concreta
- blocks: dos bloques cortos para completar objetivo y problema
- coach_cues: pedidos concretos al entrenador
- success_indicators: criterios de que el pedido ya sirve para generar una sesion real

Si el pedido tiene sentido, genera una sesion completamente personalizada:
- cada bloque debe estar relacionado explicitamente con el objetivo escrito;
- cada bloque debe corregir el problema escrito;
- usa el espacio y la cantidad de jugadores;
- no cambies el tema por otro mas generico;
- no uses teoria, devolve ejercicios aplicables en cancha;
- si dice corners/pelota quieta, todo debe ser corners/pelota quieta;
- si dice defensa, todo debe ser defensa;
- si dice finalizacion, todo debe ser finalizacion;
- si el tema es raro pero entrenable, adaptalo sin escaparte del tema.

Si mode es "match_tactic", no generes una sesion de entrenamiento.
Genera una tactica de partido real basada en rival, momento, forma de jugar y plantel propio.
Los bloques deben ser: Plan principal, Con pelota, Sin pelota, Transiciones y Claves del DT.
Cada bloque debe explicar decisiones concretas para competir ese partido.
La tactica debe usar literalmente los datos cargados. Si el entrenador dice "rival flojo por bandas", el plan debe explotar bandas: superioridades por fuera, cambios de orientacion, centros atras, ataques a espalda del lateral y coberturas para no sufrir contras.
No devuelvas frases genericas como "adaptarse al rival". Cada bloque debe nombrar la debilidad/fortaleza escrita y convertirla en decisiones de juego.

Devolve solo JSON valido con el schema solicitado.
`;

function sendJson(res, status, body) {
  res.writeHead(status, {
    ...corsHeaders,
    "content-type": "application/json",
  });
  res.end(JSON.stringify(body));
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    let body = "";
    req.on("data", (chunk) => {
      body += chunk;
      if (body.length > 1_000_000) {
        req.destroy();
        reject(new Error("Body too large"));
      }
    });
    req.on("end", () => resolve(body));
    req.on("error", reject);
  });
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

async function generate(payload) {
  const prompt = `${systemPrompt}

Schema JSON obligatorio:
{
  "title": "string",
  "objective": "string",
  "blocks": [
    { "name": "string", "duration": "string", "description": "string" }
  ],
  "coach_cues": ["string"],
  "success_indicators": ["string"]
}

Contexto:
${JSON.stringify(payload)}
`;

  const genAI = new GoogleGenerativeAI(process.env.GEMINI_API_KEY);
  const model = genAI.getGenerativeModel({ model: "gemini-1.5-flash" });
  const result = await model.generateContent(prompt);
  const text = result.response.text();
  return parseJson(text);
}

http
  .createServer(async (req, res) => {
    if (req.method === "OPTIONS") {
      sendJson(res, 200, { ok: true });
      return;
    }

    if (req.url !== "/generate-training-session" || req.method !== "POST") {
      sendJson(res, 404, { error: "Not found" });
      return;
    }

    if (!process.env.GEMINI_API_KEY) {
      sendJson(res, 500, {
        error: "Missing GEMINI_API_KEY",
        title: "Gemini no conectado",
      });
      return;
    }

    try {
      const payload = JSON.parse(await readBody(req));
      const result = await generate(payload);
      sendJson(res, 200, result);
    } catch (error) {
      sendJson(res, 500, {
        error: "Gemini generation failed",
        details: String(error.message || error),
      });
    }
  })
  .listen(port, "127.0.0.1", () => {
    console.log(`CanteraOS Gemini server running at http://127.0.0.1:${port}`);
  });
