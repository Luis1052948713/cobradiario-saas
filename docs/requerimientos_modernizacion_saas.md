# Requerimientos de Mejora y Modernizacion - Cobra Diario SaaS

## 1. Objetivo general

Convertir Cobra Diario en una plataforma SaaS profesional, multiempresa, segura, escalable y lista para comercializacion, migrando el sistema actual basado principalmente en SQLite local hacia una arquitectura hibrida moderna.

Tecnologias objetivo:

- Frontend movil y web: Flutter
- Backend: Supabase
- Base de datos online: PostgreSQL
- Base de datos local offline: SQLite
- Hosting web: Vercel
- Pagos y suscripciones: Stripe
- Versionado y CI/CD: GitHub
- Asistencia de desarrollo: GitHub Copilot / Codex

El sistema debe mantener operacion offline en la app movil y sincronizar automaticamente con Supabase cuando exista conexion.

## 2. Arquitectura general objetivo

La arquitectura debe ser hibrida:

- SQLite local para operacion offline en Android.
- Supabase/PostgreSQL para operacion centralizada online.
- Flutter Web para panel administrativo.
- Supabase Realtime para actualizaciones en vivo.
- Supabase Auth para autenticacion y sesiones.
- Supabase Storage para archivos.
- Supabase Edge Functions para procesos seguros de backend.
- Stripe para pagos recurrentes.
- Vercel para despliegue del panel web.
- GitHub para versionado, ramas y despliegues automaticos.

El sistema debe soportar:

- Operacion offline.
- Sincronizacion automatica y manual.
- Multiempresa.
- Roles y permisos.
- Tiempo real.
- Suscripciones SaaS.
- Despliegue automatico.
- Panel administrativo web.
- App movil Android.

## 3. Integracion con GitHub

El proyecto debe integrarse completamente con GitHub.

Requerimientos:

- Crear repositorio privado principal.
- Inicializar control de versiones.
- Mantener ramas principales:
  - `main`
  - `develop`
  - `testing`
- Organizar commits por modulo o funcionalidad.
- Mantener historial de cambios.
- Integrar flujo de trabajo con VS Code, Copilot y Codex.
- Preparar estructura para CI/CD.
- Configurar `.gitignore` adecuado para Flutter.
- Evitar subir secretos, `.env` reales, llaves privadas o credenciales.
- Crear archivos `.env.example` para documentar variables requeridas.
- Automatizar despliegues desde GitHub hacia Vercel.

Flujo esperado:

- Push a `develop`: despliegue staging.
- Push a `main`: despliegue produccion.
- Rama `testing`: validacion previa y pruebas QA.

## 4. Integracion con Supabase

Supabase sera el backend principal del sistema.

Debe utilizarse para:

- Base de datos PostgreSQL.
- Autenticacion.
- API REST automatica.
- Realtime.
- Storage.
- Edge Functions.
- Sincronizacion online.
- Multiempresa.
- Gestion de sesiones.
- Logs tecnicos.
- Seguridad y Row Level Security.

## 5. Base de datos PostgreSQL

Todas las tablas actuales de SQLite deben tener su equivalente en PostgreSQL.

Cada tabla SaaS debe incluir como minimo:

- `id UUID PRIMARY KEY`
- `empresa_id UUID`
- `created_at TIMESTAMPTZ`
- `updated_at TIMESTAMPTZ`
- Campos de sincronizacion cuando aplique:
  - `local_id`
  - `sync_status`
  - `last_synced_at`
  - `deleted_at`
  - `version`

Las operaciones deben estar aisladas por empresa.

Debe implementarse:

- Row Level Security.
- Politicas por rol.
- Restriccion por `empresa_id`.
- Indices para consultas frecuentes.
- Migraciones versionadas.
- Backups automaticos.

Tablas principales a migrar:

- empresas
- usuarios/perfiles
- clientes
- prestamos
- cobros
- rutas
- ruta_clientes
- ruta_visitas
- cajas
- cierres_caja
- gastos
- solicitudes_saldo
- movimientos_financieros
- capital_general
- movimientos_capital
- asignaciones_saldo
- cierres_financieros
- configuraciones
- notificaciones
- auditoria
- suscripciones
- licencia_eventos
- planes
- sync_queue
- sync_logs
- app_versions
- error_logs

## 6. Autenticacion y seguridad

La autenticacion local debe migrarse a Supabase Auth.

Debe incluir:

- Login.
- Logout.
- Recuperacion de contrasena.
- Persistencia real de sesion.
- Validacion de tokens.
- Refresh tokens.
- Sesiones activas.
- Cierre remoto de sesiones.
- Validacion por roles.
- Perfiles de usuario vinculados a `auth.users`.

Roles requeridos:

- `superadmin`: administra el SaaS global.
- `administrador`: administra una empresa.
- `cobrador`: opera cartera asignada.

Reglas:

- Las contrasenas no deben almacenarse en tablas propias.
- Las claves privadas no deben existir en Flutter.
- La app solo debe usar llaves publicas seguras.
- Operaciones sensibles deben ejecutarse en Edge Functions o backend seguro.
- Cada usuario debe acceder solo a datos permitidos por empresa y rol.

## 7. Seguridad avanzada

Debe implementarse:

- RLS en todas las tablas multiempresa.
- Politicas por `empresa_id`.
- Politicas por rol.
- Auditoria de seguridad.
- Proteccion de endpoints.
- Variables sensibles mediante `.env`, variables de entorno o secretos protegidos.
- Validacion de permisos en cliente y backend.
- Control de intentos fallidos de login.
- Logs de cambios criticos.
- Prevencion de acceso cruzado entre empresas.

## 8. Sincronizacion offline/online

La app movil debe continuar funcionando offline con SQLite local.

Debe existir:

- Cola de sincronizacion.
- Sincronizacion automatica.
- Sincronizacion manual.
- Control de conflictos.
- Reintentos automaticos.
- Estado online/offline.
- Almacenamiento temporal.
- Recuperacion ante fallos.
- Historial de sincronizacion.
- Resolucion de registros eliminados o modificados.

Modulos offline obligatorios:

- Clientes.
- Prestamos.
- Cobros.
- Rutas.
- Caja.
- Gastos.
- Visitas.

Cuando vuelva internet:

- La app debe enviar cambios pendientes.
- Debe descargar cambios remotos.
- Debe resolver conflictos.
- Debe actualizar estado de sincronizacion local.
- Debe registrar errores si falla algun lote.

Estados sugeridos de sincronizacion:

- `pending`
- `synced`
- `failed`
- `conflict`
- `deleted`

## 9. Supabase Realtime

Debe implementarse Supabase Realtime para:

- Notificaciones en tiempo real.
- Cobros en vivo.
- Cierres de caja en tiempo real.
- Alertas financieras.
- Actualizacion automatica de dashboards.
- Sincronizacion entre dispositivos.
- Cambios de estado de suscripcion.

Eventos importantes:

- Nuevo cobro.
- Prestamo creado.
- Caja abierta/cerrada.
- Cierre pendiente de revision.
- Solicitud de saldo.
- Capital bajo.
- Suscripcion vencida.
- Empresa suspendida.

## 10. Panel web administrativo

Debe crearse un panel administrativo web usando Flutter Web y desplegarse en Vercel.

Debe incluir:

- Dashboard administrativo.
- Metricas generales.
- Reportes.
- Auditoria.
- Usuarios.
- Cobradores.
- Clientes.
- Prestamos.
- Cobros.
- Capital.
- Caja.
- Alertas.
- Configuracion.
- Suscripciones.

El panel debe actualizarse automaticamente con cada despliegue.

El panel debe diferenciar vistas:

- Superadmin global.
- Administrador de empresa.
- Cobrador, si se habilita acceso web operativo.

## 11. Integracion con Vercel

Vercel sera utilizado para:

- Hosting del panel Flutter Web.
- Despliegue automatico.
- Dominio online.
- Preview deployments.
- Staging.
- Produccion.

Configuracion requerida:

- Conexion automatica con GitHub.
- Variables de entorno por ambiente.
- Build command para Flutter Web.
- Output directory configurado.
- Entorno staging desde `develop`.
- Entorno produccion desde `main`.

## 12. Suscripciones con Stripe

Stripe sera utilizado para:

- Pagos mensuales.
- Suscripciones recurrentes.
- Renovaciones automaticas.
- Facturacion.
- Bloqueo por mora.
- Control de planes.
- Webhooks de pago.

Flujo esperado:

1. Empresa registra cuenta.
2. Selecciona plan.
3. Stripe procesa pago.
4. Webhook confirma pago.
5. Supabase registra suscripcion.
6. Sistema habilita modulos.
7. Si no paga, se bloquean modulos segun reglas.

Los webhooks de Stripe deben procesarse en backend seguro, preferiblemente mediante Supabase Edge Functions.

## 13. Planes SaaS

Deben existir al menos tres planes:

- Basico.
- Pro.
- Empresa.

Cada plan debe definir:

- Precio mensual.
- Limite de cobradores.
- Limite de clientes.
- Limite de prestamos.
- Modulos habilitados.
- Acceso a reportes.
- Acceso a panel web.
- Acceso a exportaciones.
- Soporte incluido.

El sistema debe validar limites antes de:

- Crear cobradores.
- Crear clientes.
- Crear prestamos.
- Activar modulos premium.

## 14. Superadmin global

Debe existir un superadmin global del SaaS.

El superadmin podra:

- Ver todas las empresas.
- Suspender empresas.
- Activar empresas.
- Cancelar empresas.
- Ver pagos.
- Ver suscripciones.
- Gestionar planes.
- Acceder a cualquier empresa bajo reglas auditadas.
- Enviar notificaciones globales.
- Ver actividad global.
- Ver metricas generales.
- Gestionar licencias.
- Gestionar limites.
- Monitorear errores.
- Revisar logs tecnicos.

Toda accion del superadmin debe quedar auditada.

## 15. Monitoreo y soporte

Debe implementarse:

- Logs globales.
- Monitoreo de errores.
- Historial de sincronizacion.
- Errores de conexion.
- Auditoria tecnica.
- Alertas administrativas.
- Registro de eventos criticos.
- Trazabilidad por usuario, empresa y modulo.

Eventos a monitorear:

- Fallos de login.
- Fallos de sincronizacion.
- Errores de Stripe.
- Errores de Edge Functions.
- Suscripciones vencidas.
- Intentos de acceso no autorizado.
- Conflictos de datos.

## 16. Backups

Debe implementarse:

- Backup automatico.
- Backup manual.
- Exportacion SQLite.
- Exportacion PostgreSQL.
- Restauracion completa.
- Registro de fecha de ultimo backup.
- Auditoria de restauraciones.

Reglas:

- Los backups deben estar separados por empresa.
- Solo usuarios autorizados pueden descargar o restaurar datos.
- Restaurar datos debe requerir confirmacion y auditoria.

## 17. Sistema de versiones

Debe existir control de versiones de aplicacion.

La app debe validar:

- Version actual instalada.
- Version minima permitida.
- Version recomendada.
- Actualizacion obligatoria.

Debe permitir:

- Mostrar aviso de actualizacion.
- Bloquear versiones obsoletas.
- Definir mensajes por plataforma.
- Configurar URL de descarga o tienda.

## 18. Arquitectura tecnica Flutter

El proyecto debe migrarse progresivamente a Clean Architecture.

Separar capas:

- `presentation`
- `domain`
- `data`
- `services`
- `repositories`
- `models`
- `providers`

Debe utilizarse uno de estos gestores de estado:

- Riverpod, recomendado.
- Bloc, alternativa valida.

Patrones requeridos:

- Repository Pattern.
- Services Layer.
- DTOs para Supabase.
- Mappers entre SQLite, PostgreSQL y dominio.
- Casos de uso para reglas criticas.
- Manejo centralizado de errores.
- Manejo centralizado de permisos.
- Configuracion por ambiente.

Estructura sugerida:

```text
lib/
  core/
    config/
    database/
    errors/
    network/
    permissions/
    realtime/
    sync/
    theme/
  modules/
    clientes/
      data/
      domain/
      presentation/
    prestamos/
      data/
      domain/
      presentation/
    cobros/
      data/
      domain/
      presentation/
    caja/
      data/
      domain/
      presentation/
    rutas/
      data/
      domain/
      presentation/
    suscripcion/
      data/
      domain/
      presentation/
```

## 19. Pruebas

Deben implementarse:

- Unit tests.
- Widget tests.
- Integration tests.
- Tests de repositorios.
- Tests de sincronizacion.
- Tests de permisos.

Modulos criticos:

- Login.
- Prestamos.
- Cobros.
- Cierres.
- Caja.
- Sincronizacion.
- Permisos.
- Suscripciones.
- Stripe webhooks.

## 20. Fases recomendadas de implementacion

### Fase 1: Preparacion del proyecto

- Inicializar Git.
- Crear repositorio privado en GitHub.
- Crear ramas `main`, `develop`, `testing`.
- Ajustar `.gitignore`.
- Crear `.env.example`.
- Documentar ambientes.
- Agregar dependencias base para Supabase y manejo de estado.

### Fase 2: Modelo SaaS multiempresa

- Disenar esquema PostgreSQL.
- Crear migraciones Supabase.
- Crear tabla `empresas`.
- Crear perfiles vinculados a Supabase Auth.
- Agregar `empresa_id` a las entidades.
- Crear politicas RLS.

### Fase 3: Autenticacion Supabase

- Migrar login a Supabase Auth.
- Implementar persistencia real de sesion.
- Implementar recuperacion de contrasena.
- Crear perfiles y roles.
- Proteger rutas por rol.

### Fase 4: Sincronizacion hibrida

- Crear cola local `sync_queue`.
- Crear servicio de conectividad.
- Crear motor de sincronizacion.
- Sincronizar clientes, prestamos, cobros, rutas, caja, gastos y visitas.
- Manejar conflictos.
- Registrar logs de sincronizacion.

### Fase 5: Realtime y notificaciones

- Suscribirse a eventos Supabase Realtime.
- Actualizar dashboards automaticamente.
- Sincronizar notificaciones.
- Emitir alertas financieras.

### Fase 6: Panel web

- Adaptar Flutter Web.
- Crear vistas administrativas.
- Configurar build web.
- Preparar despliegue Vercel.

### Fase 7: Stripe y planes

- Crear planes SaaS.
- Integrar Stripe Checkout o Customer Portal.
- Crear Edge Functions para webhooks.
- Actualizar suscripciones en Supabase.
- Bloquear empresas vencidas.

### Fase 8: Produccion

- Configurar CI/CD.
- Configurar staging y produccion.
- Agregar monitoreo.
- Agregar backups.
- Agregar sistema de versiones.
- Ejecutar pruebas completas.
- Preparar primera version comercial.

## 21. Objetivo final

Cobra Diario debe quedar convertido en una plataforma SaaS profesional:

- Multiempresa.
- Online/offline.
- Movil y web.
- Sincronizada en tiempo real.
- Escalable.
- Segura.
- Automatizada.
- Lista para comercializacion.
