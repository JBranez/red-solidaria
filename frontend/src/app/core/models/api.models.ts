/** Modelos que reflejan los esquemas de la API (backend/app/schemas). Fechas: 'YYYY-MM-DD'; marcas de tiempo: ISO UTC. */
export interface Pagina<T> { items: T[]; total: number; pagina: number; tamano: number }

export type EstadoCampana = 'Borrador' | 'Activa' | 'Pausada' | 'Finalizada' | 'Cancelada';
export type EstadoDonacion = 'Pendiente' | 'Confirmada' | 'Rechazada' | 'Anulada';
export type EstadoGasto = 'Registrado' | 'Aprobado' | 'Anulado';
export type EstadoEntrega = 'Programada' | 'Entregada' | 'No realizada' | 'Anulada';
export type EstadoNecesidad = 'Pendiente' | 'En atencion' | 'Cubierta' | 'Descartada';
export type Urgencia = 'Baja' | 'Media' | 'Alta' | 'Critica';
export type TipoDonante = 'Persona' | 'Empresa';
export type TipoGasto = 'Bienes' | 'Transporte' | 'Logistica' | 'Administrativo' | 'Otro';
export type TipoFeedback = 'Consulta' | 'Sugerencia' | 'Queja' | 'Felicitacion';
export type EstadoFeedback = 'Abierta' | 'En revision' | 'Resuelta' | 'Cerrada';

export interface Usuario {
  id_usuario: number; username: string; nombre_completo: string; correo: string;
  id_rol: number; rol_codigo: string; rol_nombre: string;
  id_donante: number | null; id_voluntario: number | null;
  debe_cambiar_password: boolean; permisos: string[];
}
export interface Token { access_token: string; token_type: string; expires_in: number; usuario: Usuario }

export interface UsuarioAdmin {
  id_usuario: number; username: string; nombre_completo: string; correo: string; id_rol: number; rol_codigo: string; rol_nombre: string;
  id_donante: number | null; donante: string | null; id_voluntario: number | null; voluntario: string | null;
  activo: boolean; debe_cambiar_password: boolean; ultimo_acceso: string | null; bloqueado_hasta: string | null; creado_en: string;
}
export interface Rol { id_rol: number; codigo: string; nombre: string; descripcion: string; permisos: number; usuarios_activos: number }
export interface Permiso { codigo: string; modulo: string; descripcion: string }
export interface MatrizRoles { roles: Rol[]; permisos: Permiso[]; asignaciones: Record<string, string[]> }
export interface Auditoria { id_evento: number; fecha: string; id_usuario: number | null; username: string | null; accion: string; entidad: string; id_entidad: number | null; detalle: string | null; ip: string | null }

export interface Categoria { id_categoria: number; nombre: string; descripcion: string; activo: boolean; creado_en: string; campanas: number; campanas_vigentes: number }
export interface Sector { id_sector: number; nombre: string; activo: boolean; creado_en: string; hogares: number }
export interface MetodoPago { id_metodo_pago: number; nombre: string; requiere_referencia: boolean; activo: boolean }

export interface Campana {
  id_campana: number; nombre: string; descripcion: string | null; objetivo_social: string | null; id_categoria: number; categoria: string;
  fecha_inicio: string; fecha_fin: string; estado: EstadoCampana; moneda: string;
  meta_recaudacion: number; meta_hogares: number | null; meta_unidades: number | null; id_responsable: number | null; responsable: string | null;
  cerrada_en: string | null; motivo_cierre: string | null; creado_en: string;
  recaudado_confirmado: number; recaudado_pendiente: number; donaciones_confirmadas: number; donaciones_pendientes: number; donantes: number;
  gastado_aprobado: number; saldo_disponible: number; entregas_realizadas: number; hogares_atendidos: number; unidades_entregadas: number;
  voluntarios_participantes: number; entregas_programadas: number; pct_meta_recaudacion: number; pct_meta_hogares: number | null; pct_meta_unidades: number | null;
  dias_restantes: number;
}
export interface CierreCampana {
  resumen: Campana;
  donaciones_por_metodo: { metodo: string; cantidad: number; total: number }[];
  gastos_por_tipo: { tipo: string; cantidad: number; total: number }[];
  entregas_por_sector: { sector: string; hogares: number; entregas: number; unidades: number }[];
  retroalimentacion: { total: number; satisfaccion_promedio: number | null; quejas: number; quejas_abiertas: number };
}
export interface Donante {
  id_donante: number; nombre: string; tipo: TipoDonante; correo: string; fecha_registro: string; activo: boolean; creado_en: string;
  total_donado: number; donaciones_confirmadas: number; donaciones_pendientes: number; campanas_apoyadas: number; ultima_donacion: string | null;
}
export interface Donacion {
  id_donacion: number; fecha: string; monto: number; moneda: string; estado: EstadoDonacion; referencia: string | null; observacion: string | null;
  motivo_estado: string | null; id_donante: number; donante: string; donante_tipo: TipoDonante; id_campana: number; campana: string;
  id_metodo_pago: number; metodo_pago: string; confirmado_en: string | null; confirmado_por: string | null; creado_en: string;
}
export interface Gasto {
  id_gasto: number; id_campana: number; campana: string; moneda: string; fecha: string; concepto: string; tipo: TipoGasto; proveedor: string | null;
  monto: number; comprobante: string | null; estado: EstadoGasto; motivo_estado: string | null; id_usuario_registra: number | null;
  registrado_por: string | null; id_aprobador: number | null; aprobado_por: string | null; aprobado_en: string | null; creado_en: string;
}
export interface Beneficiario {
  id_beneficiario: number; nombres: string; apellidos: string; nombre_completo: string; id_sector: number; sector: string; integrantes_hogar: number;
  fecha_registro: string; consentimiento_datos: boolean; fecha_consentimiento: string | null; activo: boolean; creado_en: string;
  entregas_recibidas: number; unidades_recibidas: number; ultima_entrega: string | null; necesidades_abiertas: number;
}
export interface Necesidad {
  id_necesidad: number; id_beneficiario: number; hogar: string; id_sector: number; sector: string; integrantes_hogar: number;
  id_categoria: number; categoria: string; urgencia: Urgencia; estado: EstadoNecesidad; descripcion: string | null; fecha_registro: string;
  fecha_cobertura: string | null; motivo_estado: string | null; prioridad: number; dias_espera: number; registrado_por: string | null; creado_en: string;
}
export interface Voluntario {
  id_voluntario: number; nombres: string; apellidos: string; nombre_completo: string; correo: string; fecha_ingreso: string; activo: boolean; creado_en: string;
  entregas_realizadas: number; unidades_entregadas: number; campanas_participadas: number; entregas_programadas: number; ultima_entrega: string | null;
}
export interface Entrega {
  id_entrega: number; fecha: string; cantidad: number; detalle: string | null; estado: EstadoEntrega; motivo_estado: string | null;
  id_campana: number; campana: string; categoria: string; id_beneficiario: number; hogar: string; id_sector: number; sector: string;
  integrantes_hogar: number; id_voluntario: number; voluntario: string; id_necesidad: number | null; creado_en: string;
}
export interface Feedback {
  id_retroalimentacion: number; tipo: TipoFeedback; mensaje: string; calificacion: number | null; estado: EstadoFeedback; confidencial: boolean;
  id_beneficiario: number | null; hogar: string | null; id_entrega: number | null; id_campana: number | null; campana: string | null;
  id_responsable: number | null; responsable: string | null; respuesta: string | null; fecha_limite: string; vencida: boolean;
  dias_para_vencer: number; resuelta_en: string | null; creado_en: string;
}

export interface Kpis {
  financiero: { recaudado_confirmado: number; recaudado_pendiente: number; donaciones_confirmadas: number; donaciones_pendientes: number; gastado_aprobado: number; saldo_disponible: number; meta_recaudacion: number; pct_meta: number | null; ticket_promedio: number | null; donantes_activos: number; moneda: string };
  cobertura: { hogares_registrados: number; hogares_atendidos: number; hogares_sin_atender: number; pct_cobertura: number | null; personas_estimadas: number; entregas_realizadas: number; unidades_entregadas: number; entregas_programadas: number; hogares_sin_consentimiento: number };
  operacion: { campanas_activas: number; campanas_borrador: number; campanas_pausadas: number; campanas_finalizadas: number; campanas_por_vencer: number; campanas_vencidas_sin_cerrar: number; voluntarios_activos: number; voluntarios_participantes: number; entregas_programadas_vencidas: number; donaciones_por_verificar: number; gastos_por_aprobar: number };
  resultados: { necesidades_abiertas: number; necesidades_cubiertas: number; necesidades_urgentes: number; pct_necesidades_cubiertas: number | null; dias_promedio_cobertura: number | null; satisfaccion_promedio: number | null; feedback_abierto: number; feedback_vencido: number; pct_quejas_en_plazo: number | null };
}
export interface SerieMensual { mes: string; donaciones: number; n_donaciones: number; entregas: number; unidades: number }
export interface PorCategoria { id_categoria: number; categoria: string; campanas: number; recaudado: number; gastado: number; entregas: number; unidades: number; hogares: number }
export interface PorSector { id_sector: number; sector: string; hogares_registrados: number; hogares_atendidos: number; personas_estimadas: number; entregas: number; unidades: number; pct_cobertura: number | null; necesidades_abiertas: number }
export interface TopDonante { id_donante: number; nombre: string; tipo: string; donaciones: number; total_donado: number; campanas: number }

export interface PublicoResumen {
  totales: { campanas_activas: number; campanas_finalizadas: number; recaudado_confirmado: number; gastado_aprobado: number; hogares_atendidos: number; entregas_realizadas: number; voluntarios_participantes: number; donantes: number; moneda: string };
  por_sector: { sector: string; hogares_atendidos: number | null; publicable: boolean }[];
  por_categoria: { categoria: string; recaudado: number; entregas: number; unidades: number }[];
}
export interface PublicoCampana {
  id_campana: number; nombre: string; categoria: string; descripcion: string | null; objetivo_social: string | null; fecha_inicio: string; fecha_fin: string;
  estado: string; moneda: string; meta_recaudacion: number; recaudado_confirmado: number; pct_meta_recaudacion: number; gastado_aprobado: number;
  saldo_disponible: number; meta_hogares: number | null; hogares_atendidos: number; pct_meta_hogares: number | null; unidades_entregadas: number; dias_restantes: number;
}
