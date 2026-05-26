-- Creates the first company and administrator profile for a newly signed-up
-- Supabase Auth user. This is intentionally a security definer RPC because
-- new users do not have a profile yet and RLS would otherwise block bootstrap.

create or replace function public.registrar_empresa_admin(
  p_empresa_nombre text,
  p_admin_nombre text,
  p_usuario text default null,
  p_empresa_telefono text default null,
  p_empresa_identificacion text default null
)
returns table (
  empresa_id uuid,
  perfil_id uuid
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_email text;
  v_empresa_id uuid;
  v_plan_id uuid;
  v_suscripcion_id uuid;
begin
  if v_user_id is null then
    raise exception 'Debes iniciar sesion para registrar una empresa.';
  end if;

  if nullif(trim(p_empresa_nombre), '') is null then
    raise exception 'El nombre de empresa es obligatorio.';
  end if;

  if nullif(trim(p_admin_nombre), '') is null then
    raise exception 'El nombre del administrador es obligatorio.';
  end if;

  if exists (
    select 1
    from public.perfiles
    where id = v_user_id
  ) then
    raise exception 'Este usuario ya tiene un perfil asignado.';
  end if;

  select email
  into v_email
  from auth.users
  where id = v_user_id;

  insert into public.empresas (
    nombre,
    identificacion,
    email,
    telefono,
    estado
  ) values (
    trim(p_empresa_nombre),
    nullif(trim(p_empresa_identificacion), ''),
    v_email,
    nullif(trim(p_empresa_telefono), ''),
    'activa'
  )
  returning id into v_empresa_id;

  insert into public.perfiles (
    id,
    empresa_id,
    nombre,
    usuario,
    rol,
    estado
  ) values (
    v_user_id,
    v_empresa_id,
    trim(p_admin_nombre),
    nullif(trim(p_usuario), ''),
    'administrador',
    'activo'
  );

  select id
  into v_plan_id
  from public.planes
  where codigo = 'pro'
  limit 1;

  if v_plan_id is not null then
    insert into public.suscripciones (
      empresa_id,
      plan_id,
      estado,
      proveedor,
      referencia_pago,
      monto,
      fecha_inicio,
      fecha_fin,
      observacion
    ) values (
      v_empresa_id,
      v_plan_id,
      'prueba',
      'manual',
      'TRIAL-INICIAL',
      0,
      now(),
      now() + interval '15 days',
      'Prueba inicial creada durante registro SaaS'
    )
    returning id into v_suscripcion_id;
  end if;

  insert into public.auditoria (
    empresa_id,
    usuario_id,
    accion,
    modulo,
    descripcion,
    referencia_id,
    metadata
  ) values (
    v_empresa_id,
    v_user_id,
    'registrar_empresa',
    'auth',
    'Empresa y administrador inicial creados',
    v_empresa_id,
    jsonb_build_object('suscripcion_id', v_suscripcion_id)
  );

  return query select v_empresa_id, v_user_id;
end;
$$;

revoke all on function public.registrar_empresa_admin(
  text,
  text,
  text,
  text,
  text
) from public;

grant execute on function public.registrar_empresa_admin(
  text,
  text,
  text,
  text,
  text
) to authenticated;
