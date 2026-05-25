# Fase 1 - GitHub, ambientes y despliegue base

## Objetivo

Preparar el proyecto Cobra Diario para trabajo profesional con GitHub, manejo seguro de variables, CI basico y despliegue web en Vercel.

## Ramas objetivo

- `main`: produccion.
- `develop`: staging.
- `testing`: pruebas QA.

## Variables de entorno

El proyecto incluye `.env.example` como plantilla. Los valores reales no deben subirse al repositorio.

Para Flutter se recomienda inyectar configuracion con `--dart-define`:

```bash
flutter run --dart-define=APP_ENV=development
```

Ejemplo para web staging:

```bash
flutter build web --release \
  --dart-define=APP_ENV=staging \
  --dart-define=SUPABASE_URL=https://your-project.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=your-public-anon-key
```

## GitHub

Pasos manuales pendientes:

1. Crear un repositorio privado en GitHub.
2. Conectar el remoto local:

```bash
git remote add origin https://github.com/USUARIO/REPOSITORIO.git
```

3. Subir ramas:

```bash
git push -u origin main
git push -u origin develop
git push -u origin testing
```

## Vercel

El archivo `vercel.json` usa `scripts/vercel_build.sh` para preparar Flutter Web en el entorno de Vercel y compilar `build/web`.

Configuracion esperada:

- `develop` despliega a staging.
- `main` despliega a produccion.
- Variables sensibles se configuran en el panel de Vercel, no en Git.
- `APP_ENV` debe configurarse como `staging` o `production` segun el ambiente.

## CI

El workflow `.github/workflows/flutter_ci.yml` ejecuta:

- `flutter pub get`
- `flutter analyze`
- `flutter test`

Se ejecuta en push y pull request hacia:

- `main`
- `develop`
- `testing`
