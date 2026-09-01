# CanteraOS AI generation

## Frontend

The Flutter screen calls `TrainingAiService.generateSession`.

Order:

1. If `CANTERA_AI_ENDPOINT` is defined, call the backend endpoint.
2. If the endpoint is missing or fails, use a local dynamic generator.

Run with endpoint:

```bash
flutter run -d web-server --release --web-hostname 127.0.0.1 --web-port 5175 --dart-define=CANTERA_AI_ENDPOINT=https://YOUR_SUPABASE.functions.supabase.co/generate-training-session
```

## Backend

Supabase Edge Function:

`supabase/functions/generate-training-session/index.ts`

Environment variables:

- `GEMINI_API_KEY`

The function uses Google Gemini Flash (`gemini-1.5-flash`).

## Why backend

The Gemini API key must not be shipped in Flutter/web/mobile clients. The app sends the sports context to the backend, the backend calls Gemini, and the app receives the generated session.
