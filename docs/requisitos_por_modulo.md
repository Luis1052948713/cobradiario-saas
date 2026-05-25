# Requisitos por modulo - Sistema Cobra Diario

## 1. Vision general

Cobra Diario es una aplicacion Flutter con base de datos local SQLite para administrar prestamos, clientes y cobros diarios. El sistema tendra dos roles principales:

- Administrador: acceso total a usuarios, clientes, prestamos, cobros, reportes y configuracion.
- Cobrador: acceso limitado a clientes asignados, prestamos asignados y registro de cobros.

La aplicacion debe funcionar inicialmente sin internet, usando SQLite como almacenamiento principal. Los modulos de notificaciones y sincronizacion quedan preparados para fases futuras.

## 2. Reglas generales del sistema

- Todo usuario debe iniciar sesion para acceder al sistema.
- Un usuario inactivo no puede iniciar sesion.
- Un cobrador solo puede ver clientes y prestamos asignados.
- Un administrador puede ver y administrar toda la informacion.
- Un cliente puede tener varios prestamos.
- Un prestamo puede tener varios cobros.
- Un cobro siempre debe pertenecer a un prestamo.
- El saldo de un prestamo debe disminuir cuando se registra un cobro.
- Un prestamo se marca como pagado cuando su saldo llega a cero.
- Los datos no deben eliminarse fisicamente si ya tienen historial; debe preferirse cambiar estado a inactivo, cancelado o anulado.

## 3. Roles y permisos

| Modulo | Administrador | Cobrador |
| --- | --- | --- |
| Auth | Login, logout, recuperar contrasena | Login, logout, recuperar contrasena |
| Dashboard | Ve resumen global | Ve resumen de su cartera |
| Clientes | Crear, editar, desactivar, asignar cobrador, ver todos | Ver asignados, registrar novedades |
| Prestamos | Crear, editar, refinanciar, cancelar, ver todos | Ver asignados |
| Cobros | Crear, editar segun regla, ver todos | Registrar cobros de asignados |
| Usuarios | Crear, editar, activar, desactivar, asignar roles | Sin acceso |
| Reportes | Todos los reportes | Reportes propios |
| Configuracion | Acceso total | Sin acceso |
| Notificaciones | Configurar y recibir | Recibir |
| Sincronizacion | Configurar y ejecutar | Ejecutar si esta permitido |

## 4. Modulo Auth

### Objetivo

Permitir acceso seguro al sistema segun el rol del usuario.

### Funcionalidades

- Login con usuario y contrasena.
- Logout.
- Validacion de credenciales.
- Mantener sesion activa.
- Recordar sesion.
- Recuperacion de contrasena.
- Control de acceso por rol.
- Bloqueo de usuarios inactivos.

### Flujo principal

1. El usuario abre la app.
2. Si existe sesion activa, entra al dashboard.
3. Si no existe sesion, se muestra login.
4. El usuario ingresa usuario y contrasena.
5. El sistema valida credenciales contra SQLite.
6. Si el usuario esta activo, entra al dashboard segun su rol.
7. Si las credenciales son invalidas, se muestra error.

### Tabla relacionada

Tabla: `usuarios`

Campos requeridos:

- `id`
- `nombre`
- `usuario`
- `contrasena`
- `rol`
- `estado`
- `fecha_creacion`

### Reglas tecnicas

- La contrasena no debe guardarse en texto plano en produccion.
- Para la primera version local se puede iniciar con validacion simple, pero debe quedar aislada en un repositorio o servicio de autenticacion.
- Los roles validos son `administrador` y `cobrador`.
- Los estados validos son `activo` e `inactivo`.

## 5. Modulo Dashboard

### Objetivo

Mostrar un resumen general y accionable del sistema.

### Funcionalidades

- Total cobrado hoy.
- Clientes activos.
- Prestamos activos.
- Cobros pendientes.
- Clientes atrasados.
- Accesos rapidos a clientes, prestamos, cobros y reportes.
- Indicadores por rol.
- Graficas basicas de cobros y prestamos.

### Widgets recomendados

- Cards de indicadores.
- Lista de cobros pendientes del dia.
- Accesos rapidos.
- Chart de cobros por dia.
- Chart de prestamos activos vs pagados.

### Reglas por rol

- Administrador: ve estadisticas globales.
- Cobrador: ve solo informacion de su cartera asignada.

### Consultas necesarias

- Total cobrado en la fecha actual.
- Conteo de clientes activos.
- Conteo de prestamos activos.
- Conteo de cobros pendientes.
- Conteo de clientes atrasados.

## 6. Modulo Clientes

### Objetivo

Administrar clientes del sistema y su historial de prestamos/cobros.

### Funcionalidades

- Crear cliente.
- Editar cliente.
- Desactivar cliente.
- Buscar cliente por nombre, cedula, telefono o barrio.
- Ver historial del cliente.
- Ver prestamos del cliente.
- Asignar cobrador.
- Registrar datos de ubicacion y referencia.
- Guardar foto del cliente.

### Datos del cliente

- Nombre.
- Cedula.
- Telefono.
- Direccion.
- Barrio.
- Referencia.
- Foto.
- Cobrador asignado.
- Estado.
- Fecha de registro.

### Tabla relacionada

Tabla: `clientes`

Campos requeridos:

- `id`
- `nombre`
- `cedula`
- `telefono`
- `direccion`
- `barrio`
- `referencia`
- `foto`
- `cobrador_id`
- `estado`
- `fecha_registro`

### Reglas de negocio

- No debe registrarse un cliente sin nombre.
- La cedula puede ser opcional al inicio, pero si se captura debe evitar duplicados.
- Un cliente desactivado no debe recibir nuevos prestamos.
- Si el cliente tiene prestamos activos, no debe eliminarse fisicamente.

## 7. Modulo Prestamos

### Objetivo

Registrar y controlar prestamos realizados a clientes.

### Funcionalidades

- Crear prestamo.
- Calcular intereses.
- Calcular total a pagar.
- Generar cuota diaria.
- Ver saldo pendiente.
- Ver historial de pagos.
- Refinanciar.
- Cancelar prestamo.
- Marcar prestamo como pagado.

### Datos del prestamo

- Cliente.
- Monto.
- Interes.
- Numero de cuotas.
- Cuota diaria.
- Fecha inicio.
- Fecha fin.
- Saldo.
- Estado.

### Tabla relacionada

Tabla: `prestamos`

Campos requeridos:

- `id`
- `cliente_id`
- `monto`
- `interes`
- `total_pagar`
- `cuotas`
- `cuota_diaria`
- `saldo`
- `fecha_inicio`
- `fecha_fin`
- `estado`

### Reglas de negocio

- No se debe crear prestamo para un cliente inactivo.
- El total a pagar se calcula con monto e interes.
- La cuota diaria se calcula segun total a pagar y numero de cuotas.
- El saldo inicial debe ser igual al total a pagar.
- Cada cobro reduce el saldo.
- El prestamo se marca como `pagado` cuando saldo es cero.
- Estados recomendados: `activo`, `pagado`, `atrasado`, `cancelado`, `refinanciado`.

## 8. Modulo Cobros

### Objetivo

Registrar pagos diarios de prestamos.

### Funcionalidades

- Registrar cobro.
- Registrar cobro parcial.
- Ver historial de cobros.
- Ver cobros atrasados.
- Marcar visita sin pago.
- Agregar observaciones.
- Asociar cobro a cobrador.

### Datos del cobro

- Cliente.
- Prestamo.
- Monto pagado.
- Fecha.
- Cobrador.
- Observacion.

### Tabla relacionada

Tabla: `cobros`

Campos requeridos:

- `id`
- `prestamo_id`
- `cobrador_id`
- `monto`
- `observacion`
- `fecha_pago`

### Reglas de negocio

- No se puede registrar un cobro mayor al saldo pendiente.
- Un cobro debe pertenecer a un prestamo activo o atrasado.
- Un cobrador solo puede cobrar prestamos asignados a su cartera.
- Una visita sin pago debe guardar observacion.
- Si el cobro deja saldo en cero, el prestamo pasa a estado `pagado`.

## 9. Modulo Usuarios

### Objetivo

Administrar usuarios del sistema.

### Funcionalidades

- Crear usuarios.
- Editar usuarios.
- Desactivar usuarios.
- Activar usuarios.
- Asignar roles.
- Asignar clientes a cobradores.
- Ver rendimiento de cobrador.

### Roles

- `administrador`
- `cobrador`

### Tabla relacionada

Tabla: `usuarios`

### Reglas de negocio

- Solo un administrador puede administrar usuarios.
- No se debe eliminar un usuario con cobros o prestamos asociados.
- Un cobrador inactivo no puede iniciar sesion.
- Al desactivar un cobrador, sus clientes deben reasignarse antes de seguir operando.

## 10. Modulo Reportes

### Objetivo

Generar estadisticas y reportes financieros del sistema.

### Funcionalidades

- Reporte diario.
- Reporte semanal.
- Reporte mensual.
- Ganancias.
- Clientes morosos.
- Prestamos activos.
- Saldo pendiente.
- Rendimiento por cobrador.
- Exportar PDF.
- Exportar Excel.

### Reportes importantes

- Total cobrado.
- Total prestado.
- Total por cobrar.
- Ganancia estimada por intereses.
- Clientes con atraso.
- Cobros por cobrador.
- Prestamos activos, pagados y cancelados.

### Reglas por rol

- Administrador: puede ver reportes globales.
- Cobrador: puede ver reportes de sus cobros y clientes asignados.

## 11. Modulo Configuracion

### Objetivo

Configurar parametros generales del sistema.

### Funcionalidades

- Porcentaje de interes por defecto.
- Moneda.
- Backup local.
- Restaurar datos.
- Tema oscuro.
- Datos de empresa.
- Parametros de cuotas.

### Datos recomendados

- Nombre de empresa.
- Telefono.
- Direccion.
- Moneda.
- Interes por defecto.
- Tema.
- Fecha de ultimo backup.

### Tabla futura sugerida

Tabla: `configuraciones`

Campos sugeridos:

- `id`
- `clave`
- `valor`
- `tipo`
- `fecha_actualizacion`

## 12. Modulo Notificaciones - futuro

### Objetivo

Enviar recordatorios automaticos sobre pagos y atrasos.

### Funcionalidades

- Notificar clientes atrasados.
- Notificar pagos pendientes.
- Recordatorios diarios para cobradores.
- Alertas para administrador.

### Reglas

- Las notificaciones deben poder activarse o desactivarse.
- Las notificaciones deben respetar el rol del usuario.
- Un cobrador solo recibe alertas de su cartera.

## 13. Modulo Sincronizacion - futuro

### Objetivo

Sincronizar datos locales con un servidor online.

### Funcionalidades

- Backup en la nube.
- Sincronizacion en tiempo real.
- Soporte multi dispositivo.
- Resolucion de conflictos.
- Control de ultima sincronizacion.

### Reglas

- SQLite seguira siendo la base local.
- La app debe poder operar sin internet.
- Los cambios locales se sincronizan cuando vuelva la conexion.
- Cada registro debe tener campos de auditoria para facilitar sincronizacion.

## 14. Modelo de base de datos recomendado

### Tabla usuarios

```sql
CREATE TABLE usuarios (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  nombre TEXT NOT NULL,
  usuario TEXT NOT NULL UNIQUE,
  contrasena TEXT NOT NULL,
  rol TEXT NOT NULL CHECK (rol IN ('administrador', 'cobrador')),
  estado TEXT NOT NULL DEFAULT 'activo' CHECK (estado IN ('activo', 'inactivo')),
  fecha_creacion TEXT NOT NULL
);
```

### Tabla clientes

```sql
CREATE TABLE clientes (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  nombre TEXT NOT NULL,
  cedula TEXT UNIQUE,
  telefono TEXT,
  direccion TEXT,
  barrio TEXT,
  referencia TEXT,
  foto TEXT,
  cobrador_id INTEGER,
  estado TEXT NOT NULL DEFAULT 'activo' CHECK (estado IN ('activo', 'inactivo')),
  fecha_registro TEXT NOT NULL,
  FOREIGN KEY (cobrador_id) REFERENCES usuarios (id)
    ON DELETE RESTRICT ON UPDATE CASCADE
);
```

### Tabla prestamos

```sql
CREATE TABLE prestamos (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  cliente_id INTEGER NOT NULL,
  monto REAL NOT NULL,
  interes REAL NOT NULL DEFAULT 0,
  total_pagar REAL NOT NULL,
  cuotas INTEGER NOT NULL,
  cuota_diaria REAL NOT NULL,
  saldo REAL NOT NULL,
  fecha_inicio TEXT NOT NULL,
  fecha_fin TEXT,
  estado TEXT NOT NULL DEFAULT 'activo'
    CHECK (estado IN ('activo', 'pagado', 'atrasado', 'cancelado', 'refinanciado')),
  FOREIGN KEY (cliente_id) REFERENCES clientes (id)
    ON DELETE RESTRICT ON UPDATE CASCADE
);
```

### Tabla cobros

```sql
CREATE TABLE cobros (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  prestamo_id INTEGER NOT NULL,
  cobrador_id INTEGER NOT NULL,
  monto REAL NOT NULL,
  observacion TEXT,
  fecha_pago TEXT NOT NULL,
  FOREIGN KEY (prestamo_id) REFERENCES prestamos (id)
    ON DELETE RESTRICT ON UPDATE CASCADE,
  FOREIGN KEY (cobrador_id) REFERENCES usuarios (id)
    ON DELETE RESTRICT ON UPDATE CASCADE
);
```

## 15. Arquitectura Flutter recomendada por modulo

Cada modulo debe mantener su propia responsabilidad:

```text
lib/
├── core/
│   ├── database/
│   ├── session/
│   ├── permissions/
│   └── utils/
└── modules/
    ├── auth/
    │   ├── data/
    │   ├── models/
    │   ├── pages/
    │   └── services/
    ├── clientes/
    │   ├── data/
    │   ├── models/
    │   ├── pages/
    │   └── widgets/
    ├── prestamos/
    │   ├── data/
    │   ├── models/
    │   ├── pages/
    │   └── services/
    ├── cobros/
    │   ├── data/
    │   ├── models/
    │   ├── pages/
    │   └── services/
    ├── usuarios/
    │   ├── data/
    │   ├── models/
    │   └── pages/
    ├── reportes/
    │   ├── pages/
    │   └── services/
    └── configuracion/
        ├── pages/
        └── services/
```

## 16. Orden recomendado de desarrollo

1. Ajustar esquema SQLite definitivo.
2. Crear repositorios para usuarios, clientes, prestamos y cobros.
3. Implementar Auth real con SQLite.
4. Implementar sesion activa y recordar sesion.
5. Crear CRUD de clientes.
6. Crear CRUD de prestamos con calculos.
7. Crear registro de cobros con actualizacion de saldo.
8. Construir dashboard con consultas reales.
9. Construir reportes basicos.
10. Agregar configuracion.
11. Preparar notificaciones.
12. Preparar sincronizacion.

## 17. Proxima tarea tecnica recomendada

El siguiente paso debe ser alinear el codigo SQLite actual con este documento:

- Cambiar campos de `usuarios` para usar `usuario`, `contrasena`, `estado`, `fecha_creacion`.
- Cambiar campos de `clientes` para usar `cedula`, `barrio`, `referencia`, `foto`, `cobrador_id`, `fecha_registro`.
- Cambiar campos de `prestamos` para usar `total_pagar`, `cuota_diaria`, `saldo`.
- Cambiar campos de `cobros` para usar `cobrador_id` y `fecha_pago`.
- Actualizar los modelos Dart para que coincidan exactamente con SQLite.
- Crear repositorios por modulo para no consultar la base de datos desde las pantallas.
