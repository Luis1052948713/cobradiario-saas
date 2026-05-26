do $$
declare
  v_user_id uuid := 'eb981916-9c1e-441d-833a-77a12f01f56d';
  v_email text := 'luisfernandobarbosaorozco7@gmail.com';
  v_empresa_id uuid;
  v_plan_id uuid;
begin
  select empresa_id
  into v_empresa_id
  from public.perfiles
  where id = v_user_id;

  if v_empresa_id is null then
    select id
    into v_empresa_id
    from public.empresas
    where email = v_email
    order by created_at asc
    limit 1;
  end if;

  if v_empresa_id is null then
    insert into public.empresas (
      nombre,
      email,
      estado
    ) values (
      'Empresa Demo',
      v_email,
      'activa'
    )
    returning id into v_empresa_id;
  end if;

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
    'Luis Fernando',
    v_email,
    'administrador',
    'activo'
  )
  on conflict (id) do update set
    empresa_id = excluded.empresa_id,
    nombre = excluded.nombre,
    usuario = excluded.usuario,
    rol = excluded.rol,
    estado = excluded.estado,
    updated_at = now();

  select id
  into v_plan_id
  from public.planes
  where codigo = 'pro'
  limit 1;

  if v_plan_id is not null and not exists (
    select 1
    from public.suscripciones
    where empresa_id = v_empresa_id
  ) then
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
      'TRIAL-INICIAL-MANUAL',
      0,
      now(),
      now() + interval '15 days',
      'Perfil administrador creado manualmente para usuario existente'
    );
  end if;
end $$;
