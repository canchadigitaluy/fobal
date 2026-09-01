# DelClub — Handoff Document

## Qué es

App móvil nativa (iOS + Android) para clubes deportivos/sociales de Uruguay.
Centraliza la experiencia del socio: carnet digital, cuota, reservas, novedades, tabla de posiciones.

Objetivo final: App Store + Google Play. Sin excepción. No PWA.

---

## Stack

### Mobile (código existente)
- **Flutter** (Dart) — `C:\Users\franc\delclub\`
- Dependencias instaladas: `supabase_flutter`, `go_router`, `google_fonts`, `flutter_animate`
- Flutter SDK: `C:\flutter\bin` (en PATH)
- Android SDK: instalado vía Android Studio

### Web prototype (paralelo, para demos)
- Archivo único: `C:\Users\franc\OneDrive\soysocio\index.html`
- Deploy: Vercel (rama main de GitHub → auto-deploy)
- Sin framework, vanilla HTML/CSS/JS

### Backend (pendiente integración)
- **Supabase** — proyecto `gyffpebqgxgluvbnszzv`
- Tabla `socios` existe (permisos pendientes — ver errores conocidos)
- Auth: Supabase Auth (email/password)

---

## Design tokens

```dart
bg      = #0D0D0D   // fondo principal
surface = #141414   // tarjetas/superficies
gold    = #C8940A   // acento principal
navy    = #0B1A3B   // acento secundario
white   = #FFFFFF
muted   = rgba(255,255,255,0.38)
border  = rgba(255,255,255,0.07)
error   = #DC3C3C
success = #2ECC71
```

Fuentes: **DM Sans** (cuerpo), **Cormorant Garamond** (display/wordmark)

---

## Modelo de negocio

- Comisión sobre cuota mensual procesada por la app (no suscripción fija)
- Target: ~800 socios/club, cuota ~$2.400 UYU/mes
- Procesador de pagos: MercadoPago (Uruguay) o Stripe Connect
- Expansión: replicable en cualquier club de la región con personalización visual

---

## Arquitectura Flutter

```
lib/
├── main.dart              # App root, tokens DC, tema, MaterialApp, MainShell (bottom nav)
└── screens/
    ├── login_screen.dart  # Login con wordmark Cormorant
    ├── home_screen.dart   # Dashboard: carnet, cuota status, novedades, tabla
    ├── cuota_screen.dart  # Cuota del mes + historial
    ├── reservas_screen.dart # Flujo 3 pasos: espacio → fecha → horario
    └── perfil_screen.dart # Datos socio + menú + logout
```

Navegación: `MaterialApp` con rutas `/login` → `/home`. Bottom nav con `IndexedStack` (4 tabs).

No usa `go_router` todavía (instalado pero sin implementar).

---

## Funcionalidades terminadas

### Flutter (código escrito, sin poder correr por problema de emulador)
- [x] Sistema de design tokens (`class DC`)
- [x] Tema oscuro completo (MaterialApp)
- [x] Bottom navigation shell (4 tabs con IndexedStack)
- [x] Login screen (email/password, wordmark DELCLUB)
- [x] Home: carnet digital, estado cuota, novedades, tabla preview
- [x] Cuota: hero con monto, historial con estados pagado/pendiente
- [x] Reservas: flujo 3 pasos (grilla espacios → scroll horizontal fecha → grilla horarios → confirmación bottom sheet)
- [x] Perfil: avatar, datos socio, menú opciones, logout

### Web prototype (`soysocio/index.html`)
- [x] Pantallas: Login, Home, Carnet, Cuota, Reservas, Tabla, Galería, Perfil
- [x] Deploy en Vercel funcionando

---

## Funcionalidades pendientes

### Críticas
- [ ] Integración Supabase Auth (login real)
- [ ] Integración Supabase DB (datos reales de socios)
- [ ] Pantalla de pago de cuota (MercadoPago SDK)
- [ ] Admin panel (carga de novedades, gestión de reservas)
- [ ] Multi-tenancy: cada club con su branding propio

### Secundarias
- [ ] Novedades screen completa
- [ ] Galería de fotos
- [ ] Clases/actividades screen
- [ ] Push notifications
- [ ] go_router implementado (instalado, sin usar)

---

## Instalación y ejecución

### Flutter
```bash
# Verificar setup
flutter doctor

# Instalar dependencias
cd C:\Users\franc\delclub
flutter pub get

# Correr (requiere emulador Android o dispositivo físico)
flutter run

# Correr en web (requiere habilitar web primero)
flutter create --platforms web .
flutter run -d chrome --web-renderer html

# Correr en Windows desktop
flutter create --platforms windows .
flutter run -d windows
# Requiere: Visual Studio con workload "Desktop development with C++"
# Requiere: Modo desarrollador Windows activado
```

### Web prototype
```bash
# No hay servidor local — abrir directo en browser
# Deploy: push a GitHub main → Vercel auto-deploys
```

---

## Variables de entorno

### Supabase (pendiente configurar en Flutter)
```
SUPABASE_URL=https://gyffpebqgxgluvbnszzv.supabase.co
SUPABASE_ANON_KEY=<ver Supabase dashboard → Settings → API>
```

En Flutter van en `main.dart` al inicializar Supabase:
```dart
await Supabase.initialize(url: SUPABASE_URL, anonKey: SUPABASE_ANON_KEY);
```

No commitear keys. Usar `.env` + `flutter_dotenv` o variables de CI.

---

## Errores conocidos

| Error | Causa | Estado |
|-------|-------|--------|
| `No emulator found` | AVD Pixel_8 creado pero falla al iniciar | Sin resolver — falta habilitar virtualización (HypervisorPlatform) en BIOS/Windows |
| `The emulator process has terminated` | Virtualización no habilitada | Requiere reinicio + Enable-WindowsOptionalFeature HypervisorPlatform |
| `Building with plugins requires symlink support` | Developer Mode Windows desactivado | Resuelto: Developer Mode activado |
| `No Windows desktop project configured` | Faltaba `flutter create --platforms windows .` | Resuelto |
| `Unable to find suitable Visual Studio toolchain` | Falta Visual Studio con C++ | Sin resolver — requiere instalar VS Build Tools |
| `permission denied for table socios` | Supabase RLS sin grants | Pendiente — correr grants SQL en Supabase |
| Web `out of memory` en Chrome | canvaskit renderer muy pesado | Workaround: `--web-renderer html` |

---

## Decisiones técnicas

- **Flutter sobre React Native**: control total de UI, mejor performance de animaciones, sin interferencia de componentes nativos para diseño premium custom
- **No PWA**: decisión firme del founder. Objetivo es App Store + Google Play. No negociable.
- **Web prototype en Vercel**: solo para demos y presentaciones, no es el producto final
- **Supabase sobre Firebase**: ya tenía proyecto creado, familiaridad previa
- **Comisión sobre cuota, no suscripción fija**: modelo más alineado con el club, escala automático

---

## Próximos pasos concretos

1. **Resolver emulador Android** — habilitar HypervisorPlatform en Windows o conseguir dispositivo Android físico para testing
2. **Integrar Supabase Auth** en `login_screen.dart` (reemplazar `Future.delayed` mock por `supabase.auth.signInWithPassword`)
3. **Corregir permisos Supabase** — tabla `socios` necesita grants para anon/authenticated roles
4. **Implementar go_router** — ya instalado, reemplazar `MaterialApp.routes` por `GoRouter`
5. **Admin panel** — pantalla de gestión para el club (cargar novedades, ver reservas)
6. **MercadoPago SDK** — integrar en `cuota_screen.dart`
7. **Primer cliente real** — validar con un club antes de seguir desarrollando

---

## Contexto del founder

- Francisco Mattos — Uruguay, emprendedor
- Proyecto: DelClub (ex SoySocio)
- Email: franciscomattos0707@gmail.com
- Usa Claude Code como herramienta principal de desarrollo (AI-assisted dev, sin equipo técnico tradicional)
- Presentando ante CIE de la ORT Uruguay para apoyo/incubación
