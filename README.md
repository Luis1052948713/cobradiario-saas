# Cobra Diario

Cobra Diario es una aplicacion Flutter para gestionar prestamos diarios, clientes, cobradores, rutas, cobros, caja, reportes, auditoria y suscripciones.

El objetivo de modernizacion es convertir el sistema en una plataforma SaaS hibrida:

- SQLite local para operacion offline.
- Supabase/PostgreSQL para operacion online y sincronizacion.
- Flutter Web para panel administrativo.
- Vercel para hosting web.
- Stripe para pagos y suscripciones.
- GitHub para versionado y CI/CD.

## Estado actual

La aplicacion ya cuenta con modulos locales para:

- Autenticacion local.
- Dashboard por rol.
- Usuarios.
- Clientes.
- Prestamos.
- Cobros.
- Rutas.
- Caja y control financiero.
- Gastos.
- Reportes PDF/Excel.
- Auditoria.
- Notificaciones internas.
- Suscripciones/licencia local.

## Ambientes

La configuracion se inyecta con `--dart-define`.

Ejemplo local:

```bash
flutter run --dart-define=APP_ENV=development
```

Ejemplo web:

```bash
flutter build web --release --dart-define=APP_ENV=staging
```

Las variables requeridas estan documentadas en `.env.example`.

## Seguridad

No se deben commitear:

- Archivos `.env` reales.
- Llaves privadas.
- Service role keys de Supabase.
- Secret keys de Stripe.
- Backups o bases de datos locales.

Flutter solo debe usar llaves publicas, como `SUPABASE_ANON_KEY` y `STRIPE_PUBLISHABLE_KEY`.

## Ramas

Flujo esperado:

- `main`: produccion.
- `develop`: staging.
- `testing`: pruebas QA.

## CI

El workflow de GitHub Actions ejecuta:

- `flutter pub get`
- `flutter analyze`
- `flutter test`

## Documentacion

- Requerimientos actuales por modulo: `docs/requisitos_por_modulo.md`
- Modernizacion SaaS: `docs/requerimientos_modernizacion_saas.md`
- Fase 1 GitHub/ambientes: `docs/fase_1_setup_github_ambientes.md`
