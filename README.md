# CanteraOS

Inteligencia deportiva para clubes formativos.

Frase central:

> El entrenador habla. La IA estructura. El coordinador entiende.

## Estado actual

Demo Flutter con datos locales para mostrar:

- dashboard coordinador
- dashboard entrenador
- generador de entrenamientos con IA simulada
- registro post-entrenamiento desde texto/audio transcripto
- metodologia del club
- alertas inteligentes
- informes IA
- seguimiento simple de jugadores

## Desarrollo

```bash
flutter pub get
flutter analyze
flutter test
flutter run -d web-server --release --web-hostname 127.0.0.1 --web-port 5175 --no-web-resources-cdn
```

## Pendiente backend

Supabase debe volver en la etapa backend para autenticacion, base de datos,
storage, roles, RLS, Edge Functions e integracion real con IA.
