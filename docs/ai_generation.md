# CanteraOS AI generation

## Frontend

The Flutter screen calls `TrainingAiService.generateSession`.

Order:

1. If `CANTERA_AI_ENDPOINT` is defined, call the backend endpoint.
2. If the endpoint is missing or fails, use a local dynamic generator.

Run with endpoint:

```bash
flutter run -d web-server --release --web-hostname 127.0.0.1 --web-port 5175 --dart-define=CANTERA_AI_ENDPOINT=https://web-tau-gules-52.vercel.app/api/generate-training-session
```

## Backend

Vercel serverless function:

`api/generate-training-session.js`

The old Supabase Edge Function was deleted.

Environment variables:

- `GEMINI_API_KEY`
- `GEMINI_MODEL` (optional override)
- `AI_USER_DAILY_LIMIT` (default `20`)
- `AI_GLOBAL_DAILY_LIMIT` (default `200`)
- `AI_GLOBAL_MINUTE_LIMIT` (default `6`)

Generation model order:

1. `GEMINI_MODEL`, when set
2. `gemini-3.6-flash`
3. `gemini-3.5-flash-lite`
4. `gemini-3.1-flash-lite`

Embeddings use `gemini-embedding-001` with 768 dimensions.

Usage limits are enforced through the Supabase RPC `ai_usage_consume`. When a user, global daily, or global minute limit is exceeded, the function returns HTTP 429.

## Why backend

The Gemini API key must not be shipped in Flutter/web/mobile clients. The app sends the sports context to the backend, the backend calls Gemini, and the app receives the generated session.
