class DatabaseTables {
  const DatabaseTables._();

  static const String usuarios = 'usuarios';
  static const String clientes = 'clientes';
  static const String prestamos = 'prestamos';
  static const String cobros = 'cobros';

  static const String configuraciones = 'configuraciones';

  static const String auditoria = 'auditoria';

  static const String rutas = 'rutas';

  static const String rutaClientes = 'ruta_clientes';

  static const String rutaVisitas = 'ruta_visitas';

  static const String cajas = 'cajas';

  static const String cierresCaja = 'cierres_caja';

  static const String movimientosCaja = 'movimientos_caja';

  static const String gastos = 'gastos';
  static const String solicitudesSaldo = 'solicitudes_saldo';

  static const String movimientosFinancieros = 'movimientos_financieros';

  static const String notificaciones = 'notificaciones';

  static const String capitalGeneral = 'capital_general';

  static const String movimientosCapital = 'movimientos_capital';

  static const String asignacionesSaldo = 'asignaciones_saldo';

  static const String cierresFinancieros = 'cierres_financieros';

  static const String empresas = 'empresas';
  static const String suscripciones = 'suscripciones';

  static const String licenciaEventos = 'licencia_eventos';

  static const String syncQueue = 'sync_queue';

  /// Guarda la última sesión válida autenticada online,
  /// para permitir restauración local cuando no haya internet.
  static const String localAuthSession = 'local_auth_session';

  /// Guarda la relación entre IDs locales SQLite y UUIDs de Supabase.
  /// Esto evita perder la referencia al cerrar/reabrir la app.
  static const String onlineIdMap = 'online_id_map';
}
