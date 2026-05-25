# Supabase - Cobra Diario SaaS

Esta carpeta contiene la estructura inicial para migrar Cobra Diario a Supabase/PostgreSQL.

## Migracion inicial

Archivo:

- `migrations/202605250001_initial_saas_schema.sql`

Incluye:

- Modelo multiempresa.
- Perfiles conectados a `auth.users`.
- Planes SaaS.
- Suscripciones.
- Clientes.
- Prestamos.
- Cobros.
- Rutas.
- Visitas.
- Cajas.
- Gastos.
- Notificaciones.
- Auditoria.
- Cola de sincronizacion.
- Logs de sincronizacion.
- Versiones de app.
- Logs de errores.
- Row Level Security inicial.

## Pendientes antes de produccion

- Revisar las politicas RLS con pruebas reales.
- Completar tablas financieras avanzadas que ya existen en SQLite local.
- Crear Edge Functions para Stripe webhooks.
- Crear seeds seguros para superadmin global.
- Agregar pruebas SQL de permisos por empresa y rol.
