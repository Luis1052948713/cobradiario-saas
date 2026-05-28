alter table public.prestamos
  add column if not exists frecuencia_pago text not null default 'diario';

alter table public.prestamos
  drop constraint if exists prestamos_frecuencia_pago_check;

alter table public.prestamos
  add constraint prestamos_frecuencia_pago_check
  check (frecuencia_pago in ('diario', 'semanal', 'mensual'));
