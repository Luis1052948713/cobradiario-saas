import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

type CreateUserBody = {
  nombre?: string;
  email?: string;
  usuario?: string;
  password?: string;
  rol?: string;
  estado?: string;
};

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return jsonResponse({ error: "Metodo no permitido." }, 405);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

  if (!supabaseUrl || !anonKey || !serviceRoleKey) {
    return jsonResponse({ error: "Secrets de Supabase incompletos." }, 500);
  }

  const authorization = req.headers.get("Authorization");
  if (!authorization) {
    return jsonResponse({ error: "Sesion requerida." }, 401);
  }

  const authClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authorization } },
  });
  const adminClient = createClient(supabaseUrl, serviceRoleKey);

  const {
    data: { user },
    error: userError,
  } = await authClient.auth.getUser();

  if (userError || !user) {
    return jsonResponse({ error: "Sesion invalida." }, 401);
  }

  const { data: actor, error: actorError } = await adminClient
    .from("perfiles")
    .select("id, empresa_id, rol, estado")
    .eq("id", user.id)
    .maybeSingle();

  if (actorError || !actor) {
    return jsonResponse({ error: "Perfil administrador no encontrado." }, 403);
  }

  const puedeCrear =
    actor.estado === "activo" &&
    (actor.rol === "administrador" || actor.rol === "superadmin");
  if (!puedeCrear) {
    return jsonResponse({ error: "No tienes permiso para crear usuarios." }, 403);
  }

  const body = (await req.json()) as CreateUserBody;
  const nombre = body.nombre?.trim();
  const email = body.email?.trim().toLowerCase();
  const usuario = body.usuario?.trim();
  const password = body.password ?? "";
  const rol = body.rol === "administrador" ? "administrador" : "cobrador";
  const estado = body.estado === "inactivo" ? "inactivo" : "activo";

  if (!nombre) {
    return jsonResponse({ error: "El nombre es obligatorio." }, 400);
  }
  if (!email || !email.includes("@")) {
    return jsonResponse({ error: "Correo electronico invalido." }, 400);
  }
  if (password.length < 6) {
    return jsonResponse({ error: "La contrasena debe tener minimo 6 caracteres." }, 400);
  }
  if (!actor.empresa_id && actor.rol !== "superadmin") {
    return jsonResponse({ error: "El administrador no tiene empresa asignada." }, 400);
  }

  const { data: created, error: createError } =
    await adminClient.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
      user_metadata: { nombre, rol },
    });

  if (createError || !created.user) {
    return jsonResponse(
      { error: createError?.message ?? "No se pudo crear el usuario Auth." },
      400,
    );
  }

  const { data: profile, error: profileError } = await adminClient
    .from("perfiles")
    .insert({
      id: created.user.id,
      empresa_id: actor.empresa_id,
      nombre,
      usuario: usuario && usuario.length > 0 ? usuario : email,
      rol,
      estado,
    })
    .select()
    .single();

  if (profileError) {
    await adminClient.auth.admin.deleteUser(created.user.id);
    return jsonResponse({ error: profileError.message }, 400);
  }

  await adminClient.from("auditoria").insert({
    empresa_id: actor.empresa_id,
    usuario_id: actor.id,
    accion: "crear_usuario",
    modulo: "usuarios",
    descripcion: `Usuario creado: ${email} rol=${rol}`,
    referencia_id: created.user.id,
  });

  return jsonResponse({ profile });
});
