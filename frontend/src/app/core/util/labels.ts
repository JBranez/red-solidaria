/** Etiquetas legibles y estilo (clases de Bootstrap 5.3 "subtle") de los estados que devuelve la API. */
export interface Etiqueta { texto: string; clase: string; icono?: string }
const e = (texto: string, color: string, icono?: string): Etiqueta => ({ texto, clase: `bg-${color}-subtle text-${color}-emphasis border border-${color}-subtle`, icono });

export const ETIQUETAS: Record<string, Etiqueta> = {
  // campañas
  Borrador: e('Borrador', 'secondary', 'pencil'), Activa: e('Activa', 'success', 'broadcast'), Pausada: e('Pausada', 'warning', 'pause-circle'),
  Finalizada: e('Finalizada', 'primary', 'flag'), Cancelada: e('Cancelada', 'danger', 'x-octagon'),
  // donaciones / gastos
  Pendiente: e('Pendiente', 'warning', 'hourglass-split'), Confirmada: e('Confirmada', 'success', 'check-circle'),
  Rechazada: e('Rechazada', 'danger', 'x-circle'), Anulada: e('Anulada', 'secondary', 'slash-circle'),
  Registrado: e('Por aprobar', 'warning', 'hourglass-split'), Aprobado: e('Aprobado', 'success', 'check-circle'), Anulado: e('Anulado', 'secondary', 'slash-circle'),
  // entregas
  Programada: e('Programada', 'info', 'calendar-event'), Entregada: e('Entregada', 'success', 'box-seam'), 'No realizada': e('No realizada', 'danger', 'x-circle'),
  // necesidades
  'En atencion': e('En atención', 'info', 'arrow-repeat'), Cubierta: e('Cubierta', 'success', 'check-circle'), Descartada: e('Descartada', 'secondary', 'slash-circle'),
  // urgencia
  Baja: e('Baja', 'secondary'), Media: e('Media', 'info'), Alta: e('Alta', 'warning'), Critica: e('Crítica', 'danger'),
  // feedback
  Abierta: e('Abierta', 'warning'), 'En revision': e('En revisión', 'info'), Resuelta: e('Resuelta', 'success'), Cerrada: e('Cerrada', 'secondary'),
  Consulta: e('Consulta', 'info', 'question-circle'), Sugerencia: e('Sugerencia', 'primary', 'lightbulb'), Queja: e('Queja', 'danger', 'exclamation-triangle'), Felicitacion: e('Felicitación', 'success', 'emoji-smile'),
  // donantes
  Persona: e('Persona', 'secondary', 'person'), Empresa: e('Empresa', 'primary', 'building'),
};
export const etiqueta = (valor: string): Etiqueta => ETIQUETAS[valor] ?? { texto: valor, clase: 'bg-light text-body border' };

export const TIPOS_GASTO = [
  { v: 'Bienes', t: 'Bienes' }, { v: 'Transporte', t: 'Transporte' }, { v: 'Logistica', t: 'Logística' },
  { v: 'Administrativo', t: 'Administrativo' }, { v: 'Otro', t: 'Otro' },
];
export const URGENCIAS = [{ v: 'Critica', t: 'Crítica' }, { v: 'Alta', t: 'Alta' }, { v: 'Media', t: 'Media' }, { v: 'Baja', t: 'Baja' }];
export const TIPOS_FEEDBACK = [{ v: 'Consulta', t: 'Consulta' }, { v: 'Sugerencia', t: 'Sugerencia' }, { v: 'Queja', t: 'Queja' }, { v: 'Felicitacion', t: 'Felicitación' }];

export const ACCIONES_AUDITORIA: Record<string, string> = {
  CREAR: 'Creó', EDITAR: 'Editó', CAMBIAR_ESTADO: 'Cambió estado', LOGIN: 'Inició sesión', LOGIN_FALLIDO: 'Intento fallido', LOGOUT: 'Cerró sesión',
  CAMBIAR_PASSWORD: 'Cambió contraseña', EXPORTAR: 'Exportó',
};
