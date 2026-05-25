-- Cobra Diario SaaS - initial Supabase/PostgreSQL schema
-- This migration prepares the multi-company foundation for Supabase Auth,
-- Row Level Security, subscriptions, sync, audit, and core business modules.

create extension if not exists pgcrypto;

create table public.empresas (
  id uuid primary key default gen_random_uuid(),
  nombre text not null,
  identificacion text,
  email text,
  telefono text,
  estado text not null default 'activa'
    check (estado in ('activa', 'inactiva', 'suspendida', 'cancelada')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.perfiles (
  id uuid primary key references auth.users (id) on delete cascade,
  empresa_id uuid references public.empresas (id) on delete restrict,
  nombre text not null,
  usuario text,
  rol text not null check (rol in ('superadmin', 'administrador', 'cobrador')),
  estado text not null default 'activo' check (estado in ('activo', 'inactivo')),
  saldo_disponible numeric(14, 2) not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (empresa_id, usuario)
);

create table public.planes (
  id uuid primary key default gen_random_uuid(),
  codigo text not null unique,
  nombre text not null,
  precio_mensual numeric(14, 2) not null default 0,
  limite_cobradores integer not null,
  limite_clientes integer not null,
  limite_prestamos integer not null,
  modulos jsonb not null default '{}'::jsonb,
  estado text not null default 'activo' check (estado in ('activo', 'inactivo')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.suscripciones (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas (id) on delete restrict,
  plan_id uuid references public.planes (id) on delete set null,
  estado text not null check (estado in ('prueba', 'activa', 'vencida', 'cancelada')),
  proveedor text not null default 'stripe',
  stripe_customer_id text,
  stripe_subscription_id text,
  referencia_pago text,
  monto numeric(14, 2) not null default 0,
  fecha_inicio timestamptz not null,
  fecha_fin timestamptz not null,
  fecha_ultimo_pago timestamptz,
  observacion text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.clientes (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas (id) on delete restrict,
  local_id text,
  nombre text not null,
  cedula text,
  telefono text,
  direccion text,
  barrio text,
  referencia text,
  foto_url text,
  cobrador_id uuid references public.perfiles (id) on delete set null,
  latitud numeric(12, 8),
  longitud numeric(12, 8),
  estado text not null default 'activo' check (estado in ('activo', 'inactivo')),
  sync_status text not null default 'synced'
    check (sync_status in ('pending', 'synced', 'failed', 'conflict', 'deleted')),
  last_synced_at timestamptz,
  deleted_at timestamptz,
  version integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (empresa_id, cedula)
);

create table public.prestamos (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas (id) on delete restrict,
  local_id text,
  cliente_id uuid not null references public.clientes (id) on delete restrict,
  monto numeric(14, 2) not null,
  interes numeric(8, 2) not null default 0,
  total_pagar numeric(14, 2) not null,
  cuotas integer not null,
  cuota_diaria numeric(14, 2) not null,
  saldo numeric(14, 2) not null,
  fecha_inicio date not null,
  fecha_fin date,
  estado text not null default 'activo'
    check (estado in ('activo', 'pagado', 'atrasado', 'cancelado', 'refinanciado')),
  sync_status text not null default 'synced'
    check (sync_status in ('pending', 'synced', 'failed', 'conflict', 'deleted')),
  last_synced_at timestamptz,
  deleted_at timestamptz,
  version integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.cobros (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas (id) on delete restrict,
  local_id text,
  prestamo_id uuid not null references public.prestamos (id) on delete restrict,
  cobrador_id uuid not null references public.perfiles (id) on delete restrict,
  monto numeric(14, 2) not null,
  saldo_anterior numeric(14, 2),
  saldo_actual numeric(14, 2),
  observacion text,
  fecha_pago timestamptz not null,
  estado text not null default 'registrado' check (estado in ('registrado', 'anulado')),
  sync_status text not null default 'synced'
    check (sync_status in ('pending', 'synced', 'failed', 'conflict', 'deleted')),
  last_synced_at timestamptz,
  deleted_at timestamptz,
  version integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.rutas (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas (id) on delete restrict,
  local_id text,
  nombre text not null,
  zona text not null,
  cobrador_id uuid not null references public.perfiles (id) on delete restrict,
  estado text not null default 'activa' check (estado in ('activa', 'inactiva')),
  sync_status text not null default 'synced'
    check (sync_status in ('pending', 'synced', 'failed', 'conflict', 'deleted')),
  last_synced_at timestamptz,
  deleted_at timestamptz,
  version integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.ruta_clientes (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas (id) on delete restrict,
  ruta_id uuid not null references public.rutas (id) on delete restrict,
  cliente_id uuid not null references public.clientes (id) on delete restrict,
  orden integer not null,
  estado text not null default 'activo' check (estado in ('activo', 'removido')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index idx_ruta_cliente_activo
  on public.ruta_clientes (empresa_id, cliente_id)
  where estado = 'activo';

create table public.ruta_visitas (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas (id) on delete restrict,
  local_id text,
  ruta_id uuid not null references public.rutas (id) on delete restrict,
  cliente_id uuid not null references public.clientes (id) on delete restrict,
  cobrador_id uuid not null references public.perfiles (id) on delete restrict,
  prestamo_id uuid references public.prestamos (id) on delete set null,
  cobro_id uuid references public.cobros (id) on delete set null,
  estado_visita text not null check (estado_visita in (
    'pago',
    'pendiente',
    'no_encontrado',
    'negocio_cerrado',
    'promete_pagar',
    'no_quiso_pagar'
  )),
  monto_cobrado numeric(14, 2) not null default 0,
  observacion text,
  fecha_hora timestamptz not null,
  sync_status text not null default 'synced'
    check (sync_status in ('pending', 'synced', 'failed', 'conflict', 'deleted')),
  last_synced_at timestamptz,
  deleted_at timestamptz,
  version integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.cajas (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas (id) on delete restrict,
  local_id text,
  cobrador_id uuid not null references public.perfiles (id) on delete restrict,
  admin_id uuid references public.perfiles (id) on delete set null,
  fecha date not null,
  hora_apertura time not null,
  hora_cierre time,
  saldo_inicial numeric(14, 2) not null default 0,
  saldo_actual numeric(14, 2) not null default 0,
  observacion_apertura text,
  observacion_cierre text,
  estado text not null default 'abierta'
    check (estado in ('abierta', 'cerrada', 'pendiente_revision', 'bloqueada')),
  sync_status text not null default 'synced'
    check (sync_status in ('pending', 'synced', 'failed', 'conflict', 'deleted')),
  last_synced_at timestamptz,
  deleted_at timestamptz,
  version integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.gastos (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas (id) on delete restrict,
  local_id text,
  cobrador_id uuid not null references public.perfiles (id) on delete restrict,
  tipo text not null,
  valor numeric(14, 2) not null,
  descripcion text,
  fecha_hora timestamptz not null,
  sync_status text not null default 'synced'
    check (sync_status in ('pending', 'synced', 'failed', 'conflict', 'deleted')),
  last_synced_at timestamptz,
  deleted_at timestamptz,
  version integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.notificaciones (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid references public.empresas (id) on delete cascade,
  usuario_id uuid references public.perfiles (id) on delete cascade,
  titulo text not null,
  mensaje text not null,
  tipo text not null check (tipo in ('informativa', 'advertencia', 'critica', 'exito')),
  modulo text,
  referencia_id uuid,
  estado text not null default 'pendiente' check (estado in ('pendiente', 'leida')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.auditoria (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid references public.empresas (id) on delete cascade,
  usuario_id uuid references public.perfiles (id) on delete set null,
  accion text not null,
  modulo text not null,
  descripcion text not null,
  referencia_id uuid,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table public.sync_queue (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas (id) on delete cascade,
  usuario_id uuid references public.perfiles (id) on delete set null,
  device_id text not null,
  tabla text not null,
  operacion text not null check (operacion in ('insert', 'update', 'delete')),
  local_id text,
  remote_id uuid,
  payload jsonb not null default '{}'::jsonb,
  estado text not null default 'pending'
    check (estado in ('pending', 'synced', 'failed', 'conflict')),
  intentos integer not null default 0,
  error text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.sync_logs (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid references public.empresas (id) on delete cascade,
  usuario_id uuid references public.perfiles (id) on delete set null,
  device_id text,
  estado text not null check (estado in ('started', 'finished', 'failed')),
  mensaje text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table public.app_versions (
  id uuid primary key default gen_random_uuid(),
  plataforma text not null check (plataforma in ('android', 'ios', 'web', 'desktop')),
  version_minima text not null,
  version_recomendada text not null,
  obligatoria boolean not null default false,
  mensaje text,
  url_actualizacion text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.error_logs (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid references public.empresas (id) on delete cascade,
  usuario_id uuid references public.perfiles (id) on delete set null,
  origen text not null,
  severidad text not null default 'error' check (severidad in ('info', 'warning', 'error', 'critical')),
  mensaje text not null,
  stacktrace text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create or replace function public.current_profile()
returns public.perfiles
language sql
stable
security definer
set search_path = public
as $$
  select *
  from public.perfiles
  where id = auth.uid()
  limit 1
$$;

create or replace function public.current_empresa_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select empresa_id
  from public.perfiles
  where id = auth.uid()
  limit 1
$$;

create or replace function public.current_role()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select rol
  from public.perfiles
  where id = auth.uid()
  limit 1
$$;

create or replace function public.is_superadmin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(public.current_role() = 'superadmin', false)
$$;

create or replace function public.same_empresa(target_empresa_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.is_superadmin()
    or target_empresa_id = public.current_empresa_id()
$$;

do $$
declare
  table_name text;
begin
  foreach table_name in array array[
    'empresas',
    'perfiles',
    'planes',
    'suscripciones',
    'clientes',
    'prestamos',
    'cobros',
    'rutas',
    'ruta_clientes',
    'ruta_visitas',
    'cajas',
    'gastos',
    'notificaciones',
    'sync_queue',
    'app_versions'
  ]
  loop
    execute format(
      'create trigger set_%I_updated_at before update on public.%I for each row execute function public.set_updated_at()',
      table_name,
      table_name
    );
  end loop;
end $$;

alter table public.empresas enable row level security;
alter table public.perfiles enable row level security;
alter table public.planes enable row level security;
alter table public.suscripciones enable row level security;
alter table public.clientes enable row level security;
alter table public.prestamos enable row level security;
alter table public.cobros enable row level security;
alter table public.rutas enable row level security;
alter table public.ruta_clientes enable row level security;
alter table public.ruta_visitas enable row level security;
alter table public.cajas enable row level security;
alter table public.gastos enable row level security;
alter table public.notificaciones enable row level security;
alter table public.auditoria enable row level security;
alter table public.sync_queue enable row level security;
alter table public.sync_logs enable row level security;
alter table public.app_versions enable row level security;
alter table public.error_logs enable row level security;

create policy "superadmin can manage empresas"
  on public.empresas
  for all
  using (public.is_superadmin())
  with check (public.is_superadmin());

create policy "users can read own empresa"
  on public.empresas
  for select
  using (id = public.current_empresa_id());

create policy "superadmin can manage perfiles"
  on public.perfiles
  for all
  using (public.is_superadmin())
  with check (public.is_superadmin());

create policy "users can read same empresa perfiles"
  on public.perfiles
  for select
  using (public.same_empresa(empresa_id) or id = auth.uid());

create policy "admins can manage same empresa perfiles"
  on public.perfiles
  for all
  using (
    public.current_role() = 'administrador'
    and empresa_id = public.current_empresa_id()
  )
  with check (
    public.current_role() = 'administrador'
    and empresa_id = public.current_empresa_id()
  );

create policy "authenticated can read active plans"
  on public.planes
  for select
  using (auth.uid() is not null and estado = 'activo');

create policy "superadmin can manage plans"
  on public.planes
  for all
  using (public.is_superadmin())
  with check (public.is_superadmin());

create policy "same empresa suscripciones read"
  on public.suscripciones
  for select
  using (public.same_empresa(empresa_id));

create policy "superadmin can manage suscripciones"
  on public.suscripciones
  for all
  using (public.is_superadmin())
  with check (public.is_superadmin());

create policy "same empresa clientes access"
  on public.clientes
  for all
  using (public.same_empresa(empresa_id))
  with check (public.same_empresa(empresa_id));

create policy "same empresa prestamos access"
  on public.prestamos
  for all
  using (public.same_empresa(empresa_id))
  with check (public.same_empresa(empresa_id));

create policy "same empresa cobros access"
  on public.cobros
  for all
  using (public.same_empresa(empresa_id))
  with check (public.same_empresa(empresa_id));

create policy "same empresa rutas access"
  on public.rutas
  for all
  using (public.same_empresa(empresa_id))
  with check (public.same_empresa(empresa_id));

create policy "same empresa ruta_clientes access"
  on public.ruta_clientes
  for all
  using (public.same_empresa(empresa_id))
  with check (public.same_empresa(empresa_id));

create policy "same empresa ruta_visitas access"
  on public.ruta_visitas
  for all
  using (public.same_empresa(empresa_id))
  with check (public.same_empresa(empresa_id));

create policy "same empresa cajas access"
  on public.cajas
  for all
  using (public.same_empresa(empresa_id))
  with check (public.same_empresa(empresa_id));

create policy "same empresa gastos access"
  on public.gastos
  for all
  using (public.same_empresa(empresa_id))
  with check (public.same_empresa(empresa_id));

create policy "same empresa notificaciones access"
  on public.notificaciones
  for all
  using (
    public.is_superadmin()
    or empresa_id = public.current_empresa_id()
    or usuario_id = auth.uid()
  )
  with check (
    public.is_superadmin()
    or empresa_id = public.current_empresa_id()
    or usuario_id = auth.uid()
  );

create policy "same empresa auditoria read"
  on public.auditoria
  for select
  using (public.same_empresa(empresa_id) or usuario_id = auth.uid());

create policy "same empresa auditoria insert"
  on public.auditoria
  for insert
  with check (public.same_empresa(empresa_id) or usuario_id = auth.uid());

create policy "same empresa sync_queue access"
  on public.sync_queue
  for all
  using (public.same_empresa(empresa_id))
  with check (public.same_empresa(empresa_id));

create policy "same empresa sync_logs access"
  on public.sync_logs
  for all
  using (public.same_empresa(empresa_id))
  with check (public.same_empresa(empresa_id));

create policy "authenticated can read app versions"
  on public.app_versions
  for select
  using (auth.uid() is not null);

create policy "superadmin can manage app versions"
  on public.app_versions
  for all
  using (public.is_superadmin())
  with check (public.is_superadmin());

create policy "same empresa error logs insert"
  on public.error_logs
  for insert
  with check (public.same_empresa(empresa_id) or usuario_id = auth.uid());

create policy "admins can read same empresa error logs"
  on public.error_logs
  for select
  using (
    public.is_superadmin()
    or (
      public.current_role() = 'administrador'
      and empresa_id = public.current_empresa_id()
    )
  );

create index idx_perfiles_empresa_rol on public.perfiles (empresa_id, rol);
create index idx_clientes_empresa_cobrador on public.clientes (empresa_id, cobrador_id);
create index idx_prestamos_empresa_estado on public.prestamos (empresa_id, estado);
create index idx_cobros_empresa_fecha on public.cobros (empresa_id, fecha_pago desc);
create index idx_rutas_empresa_cobrador on public.rutas (empresa_id, cobrador_id);
create index idx_cajas_empresa_fecha on public.cajas (empresa_id, fecha desc);
create index idx_gastos_empresa_fecha on public.gastos (empresa_id, fecha_hora desc);
create index idx_auditoria_empresa_fecha on public.auditoria (empresa_id, created_at desc);
create index idx_sync_queue_empresa_estado on public.sync_queue (empresa_id, estado, created_at);

insert into public.planes (
  codigo,
  nombre,
  precio_mensual,
  limite_cobradores,
  limite_clientes,
  limite_prestamos,
  modulos
) values
  (
    'basico',
    'Basico',
    49000,
    2,
    300,
    500,
    '{"reportes": true, "rutas": true, "panel_web": false, "exportaciones": false}'::jsonb
  ),
  (
    'pro',
    'Pro',
    99000,
    8,
    1500,
    3000,
    '{"reportes": true, "rutas": true, "panel_web": true, "exportaciones": true}'::jsonb
  ),
  (
    'empresa',
    'Empresa',
    199000,
    50,
    10000,
    25000,
    '{"reportes": true, "rutas": true, "panel_web": true, "exportaciones": true, "soporte_prioritario": true}'::jsonb
  );
