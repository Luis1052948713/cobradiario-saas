# Fase 4 - Registro de empresa y primer administrador

## Objetivo

Permitir que una empresa nueva se registre desde Flutter usando Supabase Auth, creando automaticamente:

- Usuario en Supabase Auth.
- Empresa en `public.empresas`.
- Perfil administrador en `public.perfiles`.
- Suscripcion inicial de prueba.

## Archivos agregados

- `supabase/migrations/202605260001_register_company_admin.sql`
- `lib/modules/auth/pages/register_company_page.dart`

## Archivos modificados

- `lib/modules/auth/services/auth_service.dart`
- `lib/modules/auth/pages/login_page.dart`

## Flujo

1. Usuario abre Login.
2. Toca `Crear empresa`.
3. Ingresa datos de empresa, administrador, email y contrasena.
4. Flutter ejecuta `supabase.auth.signUp`.
5. Si Supabase retorna sesion activa, Flutter llama el RPC:

```sql
public.registrar_empresa_admin(...)
```

6. El RPC crea empresa, perfil administrador y prueba inicial.
7. La app carga el perfil y entra al dashboard.

## Nota importante

Para que el registro cree el perfil inmediatamente, Supabase Auth debe permitir sesion despues de `signUp`.

En desarrollo puedes desactivar confirmacion de email en:

```text
Supabase Dashboard > Authentication > Providers > Email > Confirm email
```

Si la confirmacion de email esta activa, el usuario se crea pero debera confirmar su correo antes de ingresar.
