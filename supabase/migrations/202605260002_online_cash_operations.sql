alter table public.cajas
  add column if not exists dinero_reportado numeric(14, 2),
  add column if not exists dinero_entregado numeric(14, 2),
  add column if not exists diferencia numeric(14, 2),
  add column if not exists observacion_admin text,
  add column if not exists fecha_revision timestamptz;

create table if not exists public.solicitudes_saldo (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas (id) on delete restrict,
  cobrador_id uuid not null references public.perfiles (id) on delete restrict,
  admin_id uuid references public.perfiles (id) on delete set null,
  monto_solicitado numeric(14, 2) not null,
  monto_aprobado numeric(14, 2),
  observacion text,
  observacion_admin text,
  estado text not null default 'pendiente'
    check (estado in ('pendiente', 'aprobada', 'rechazada')),
  fecha_respuesta timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.solicitudes_saldo enable row level security;

drop policy if exists "same empresa solicitudes_saldo access"
  on public.solicitudes_saldo;

create policy "same empresa solicitudes_saldo access"
  on public.solicitudes_saldo
  for all
  using (public.same_empresa(empresa_id))
  with check (public.same_empresa(empresa_id));

create index if not exists idx_solicitudes_saldo_empresa_estado
  on public.solicitudes_saldo (empresa_id, estado, created_at desc);
