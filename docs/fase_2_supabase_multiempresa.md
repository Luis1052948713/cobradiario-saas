# Fase 2 - Supabase y modelo multiempresa

## Objetivo

Crear la base PostgreSQL para operar Cobra Diario como SaaS multiempresa usando Supabase.

## Avance realizado

Se agrego la primera migracion:

```text
supabase/migrations/202605250001_initial_saas_schema.sql
```

La migracion define:

- Empresas.
- Perfiles vinculados a Supabase Auth.
- Planes SaaS.
- Suscripciones.
- Clientes.
- Prestamos.
- Cobros.
- Rutas.
- Ruta-clientes.
- Visitas.
- Cajas.
- Gastos.
- Notificaciones.
- Auditoria.
- Cola de sincronizacion.
- Logs de sincronizacion.
- Versiones de app.
- Logs de errores.

## Reglas base incluidas

- Todas las tablas de negocio tienen `empresa_id`.
- Las entidades principales usan `UUID`.
- Se incluyen `created_at` y `updated_at`.
- Se agregan campos de sincronizacion para entidades offline.
- Se habilita Row Level Security.
- Se crean politicas iniciales por empresa y rol.
- Se crean funciones auxiliares:
  - `current_profile()`
  - `current_empresa_id()`
  - `current_role()`
  - `is_superadmin()`
  - `same_empresa(uuid)`

## Advertencia tecnica

Esta migracion es una base inicial. Antes de usarla en produccion se deben probar las politicas RLS con usuarios reales y completar tablas financieras avanzadas que ya existen en SQLite local, como cierres de caja, movimientos financieros, capital general y asignaciones de saldo.

## Siguiente paso

Conectar Flutter con Supabase:

- Agregar dependencia `supabase_flutter`.
- Crear servicio `SupabaseClient`.
- Inicializar Supabase en `main.dart`.
- Mantener fallback local mientras la configuracion Supabase no exista.
- Migrar autenticacion desde SQLite hacia Supabase Auth de forma progresiva.
