class AppRoles {
  const AppRoles._();

  static const String superadmin = 'superadmin';
  static const String administrador = 'administrador';
  static const String cobrador = 'cobrador';
}

class AppEstados {
  const AppEstados._();

  static const String activo = 'activo';
  static const String inactivo = 'inactivo';
  static const String pagado = 'pagado';
  static const String atrasado = 'atrasado';
  static const String cancelado = 'cancelado';
  static const String refinanciado = 'refinanciado';
}

class AppConfigKeys {
  const AppConfigKeys._();

  static const String moneda = 'moneda';
  static const String interesDefecto = 'interes_defecto';
  static const String temaOscuro = 'tema_oscuro';
  static const String empresaNombre = 'empresa_nombre';
  static const String empresaTelefono = 'empresa_telefono';
  static const String empresaDireccion = 'empresa_direccion';
  static const String frecuenciaPagoDefecto = 'frecuencia_pago_defecto';
  static const String interesesPermitidos = 'intereses_permitidos';
  static const String montoMaximoCobrador = 'monto_maximo_cobrador';
  static const String backupAutomatico = 'backup_automatico';
  static const String ultimoBackup = 'ultimo_backup';
  static const String licenciaApiUrl = 'licencia_api_url';
  static const String licenciaClave = 'licencia_clave';
  static const String pasarelaPagoNombre = 'pasarela_pago_nombre';
  static const String pasarelaPagoUrl = 'pasarela_pago_url';
  static const String nequiTitular = 'nequi_titular';
  static const String nequiTelefono = 'nequi_telefono';
}

class SuscripcionPlanes {
  const SuscripcionPlanes._();

  static const String basico = 'basico';
  static const String pro = 'pro';
  static const String empresa = 'empresa';

  static const List<String> todos = [basico, pro, empresa];
}

class SuscripcionEstados {
  const SuscripcionEstados._();

  static const String prueba = 'prueba';
  static const String activa = 'activa';
  static const String vencida = 'vencida';
  static const String cancelada = 'cancelada';
}

class SuscripcionProveedores {
  const SuscripcionProveedores._();

  static const String manual = 'manual';
  static const String pasarela = 'pasarela';
  static const String stripe = 'stripe';
  static const String revenueCat = 'revenuecat';
}

class RutaEstados {
  const RutaEstados._();

  static const String activa = 'activa';
  static const String inactiva = 'inactiva';
}

class RutaClienteEstados {
  const RutaClienteEstados._();

  static const String activo = 'activo';
  static const String removido = 'removido';
}

class RutaVisitaEstados {
  const RutaVisitaEstados._();

  static const String pago = 'pago';
  static const String pendiente = 'pendiente';
  static const String noEncontrado = 'no_encontrado';
  static const String negocioCerrado = 'negocio_cerrado';
  static const String prometePagar = 'promete_pagar';
  static const String noQuisoPagar = 'no_quiso_pagar';

  static const List<String> todos = [
    pago,
    pendiente,
    noEncontrado,
    negocioCerrado,
    prometePagar,
    noQuisoPagar,
  ];
}

class GastoTipos {
  const GastoTipos._();

  static const String transporte = 'transporte';
  static const String gasolina = 'gasolina';
  static const String alimentacion = 'alimentacion';
  static const String papeleria = 'papeleria';
  static const String otros = 'otros';

  static const List<String> todos = [
    transporte,
    gasolina,
    alimentacion,
    papeleria,
    otros,
  ];
}

class SolicitudSaldoEstados {
  const SolicitudSaldoEstados._();

  static const String pendiente = 'pendiente';
  static const String aprobada = 'aprobada';
  static const String rechazada = 'rechazada';
}

class CierreCajaEstados {
  const CierreCajaEstados._();

  static const String abierta = 'abierta';
  static const String cerrada = 'cerrada';
  static const String pendienteRevision = 'pendiente_revision';
  static const String aprobado = 'aprobado';
  static const String rechazado = 'rechazado';
  static const String bloqueada = 'bloqueada';
}

class CajaEstados {
  const CajaEstados._();

  static const String abierta = 'abierta';
  static const String cerrada = 'cerrada';
  static const String pendienteRevision = 'pendiente_revision';
  static const String bloqueada = 'bloqueada';
}

class MovimientoFinancieroTipos {
  const MovimientoFinancieroTipos._();

  static const String asignacionSaldo = 'asignacion_saldo';
  static const String prestamo = 'prestamo';
  static const String cobro = 'cobro';
  static const String gasto = 'gasto';
  static const String cierreCaja = 'cierre_caja';
  static const String solicitudSaldo = 'solicitud_saldo';
}

class CapitalMovimientoTipos {
  const CapitalMovimientoTipos._();

  static const String capitalInicial = 'capital_inicial';
  static const String asignacionCobrador = 'asignacion_cobrador';
  static const String ingresoAdicional = 'ingreso_adicional';
  static const String retiroAdministrativo = 'retiro_administrativo';
  static const String entregaDinero = 'entrega_dinero';
  static const String cierreFinanciero = 'cierre_financiero';
}

class NotificacionTipos {
  const NotificacionTipos._();

  static const String informativa = 'informativa';
  static const String advertencia = 'advertencia';
  static const String critica = 'critica';
  static const String exito = 'exito';
}

class NotificacionEstados {
  const NotificacionEstados._();

  static const String pendiente = 'pendiente';
  static const String leida = 'leida';
}
