# Fase 3 - Bootstrap Flutter con Supabase

## Objetivo

Preparar la app Flutter para conectarse a Supabase sin romper la operacion local actual con SQLite.

## Avance realizado

Se agrego la dependencia:

```yaml
supabase_flutter
```

Se agrego el servicio:

```text
lib/core/services/supabase_service.dart
```

El servicio:

- Lee configuracion desde `EnvConfig`.
- Inicializa Supabase solo si existen `SUPABASE_URL` y `SUPABASE_ANON_KEY`.
- Mantiene la app en modo local SQLite si Supabase no esta configurado.
- Expone `isConfigured`, `isInitialized` y `client`.

`main.dart` ahora intenta inicializar Supabase antes de abrir SQLite.

## Ejecutar con Supabase

```bash
flutter run \
  --dart-define=APP_ENV=development \
  --dart-define=SUPABASE_URL=https://your-project.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=your-public-anon-key
```

## Ejecutar sin Supabase

```bash
flutter run --dart-define=APP_ENV=development
```

En este modo la app continua usando SQLite local.

## Nota Windows

Despues de agregar `supabase_flutter`, Flutter puede requerir Developer Mode en Windows porque algunos plugins usan symlinks.

Para habilitarlo manualmente:

```powershell
start ms-settings:developers
```

Luego activar "Developer Mode" en la configuracion de Windows.

## Siguiente paso

Crear una capa de autenticacion hibrida:

- `AuthRepository`.
- `LocalAuthDataSource`.
- `SupabaseAuthDataSource`.
- Fallback temporal a login SQLite.
- Login Supabase cuando exista configuracion online.
