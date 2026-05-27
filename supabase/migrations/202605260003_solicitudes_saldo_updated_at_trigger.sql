drop trigger if exists set_solicitudes_saldo_updated_at
  on public.solicitudes_saldo;

create trigger set_solicitudes_saldo_updated_at
  before update on public.solicitudes_saldo
  for each row execute function public.set_updated_at();
