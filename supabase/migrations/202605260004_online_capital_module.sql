create table if not exists public.capital_general (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas (id) on delete restrict,
  monto_inicial numeric(14, 2) not null,
  capital_disponible numeric(14, 2) not null,
  observacion text,
  usuario_id uuid references public.perfiles (id) on delete set null,
  estado text not null default 'activo' check (estado in ('activo', 'cerrado')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.movimientos_capital (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas (id) on delete restrict,
  capital_id uuid references public.capital_general (id) on delete set null,
  usuario_id uuid references public.perfiles (id) on delete set null,
  tipo text not null,
  monto numeric(14, 2) not null,
  saldo_antes numeric(14, 2) not null,
  saldo_despues numeric(14, 2) not null,
  observacion text,
  referencia_tabla text,
  referencia_id uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.cierres_financieros (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas (id) on delete restrict,
  capital_id uuid references public.capital_general (id) on delete set null,
  admin_id uuid references public.perfiles (id) on delete set null,
  fecha date not null,
  capital_inicial numeric(14, 2) not null,
  saldo_distribuido numeric(14, 2) not null default 0,
  total_prestado numeric(14, 2) not null default 0,
  total_recaudado numeric(14, 2) not null default 0,
  gastos numeric(14, 2) not null default 0,
  ganancias numeric(14, 2) not null default 0,
  capital_final numeric(14, 2) not null,
  observacion text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (empresa_id, fecha)
);

alter table public.capital_general enable row level security;
alter table public.movimientos_capital enable row level security;
alter table public.cierres_financieros enable row level security;

drop policy if exists "same empresa capital_general access"
  on public.capital_general;
drop policy if exists "same empresa movimientos_capital access"
  on public.movimientos_capital;
drop policy if exists "same empresa cierres_financieros access"
  on public.cierres_financieros;

create policy "same empresa capital_general access"
  on public.capital_general
  for all
  using (public.same_empresa(empresa_id))
  with check (public.same_empresa(empresa_id));

create policy "same empresa movimientos_capital access"
  on public.movimientos_capital
  for all
  using (public.same_empresa(empresa_id))
  with check (public.same_empresa(empresa_id));

create policy "same empresa cierres_financieros access"
  on public.cierres_financieros
  for all
  using (public.same_empresa(empresa_id))
  with check (public.same_empresa(empresa_id));

drop trigger if exists set_capital_general_updated_at
  on public.capital_general;
drop trigger if exists set_movimientos_capital_updated_at
  on public.movimientos_capital;
drop trigger if exists set_cierres_financieros_updated_at
  on public.cierres_financieros;

create trigger set_capital_general_updated_at
  before update on public.capital_general
  for each row execute function public.set_updated_at();

create trigger set_movimientos_capital_updated_at
  before update on public.movimientos_capital
  for each row execute function public.set_updated_at();

create trigger set_cierres_financieros_updated_at
  before update on public.cierres_financieros
  for each row execute function public.set_updated_at();
