# Alcance funcional

Derivado de `Analisis_Funcional_Red_Solidaria_para_Claude.md`. Prioridad: **P0** = núcleo, **P1** = valor alto con poco costo, **P2** = futuro.

## Matriz de implementación
| Módulo del análisis | Prioridad | Estado | Dónde |
|---|---|---|---|
| Autenticación, roles/permisos, auditoría | P0 | ✅ | `/acceso`, `/usuarios`, `/auditoria` |
| Categorías (catálogos) | P0 | ✅ | `/catalogos` |
| Campañas con ciclo de vida, metas económica/social/física, cierre | P0 | ✅ | `/campanas`, informe de cierre imprimible |
| Donantes (perfil, historial, duplicados) | P0 | ✅ | `/donantes` |
| Donaciones con verificación, referencia única, exportación | P0 | ✅ | `/donaciones` |
| Hogares con consentimiento y búsqueda | P0 | ✅ | `/hogares` |
| Voluntarios y participación | P0 | ✅ | `/voluntarios` |
| Entregas: programación, confirmación, anulación, constancia | P0 | ✅ | `/entregas`, `/mi-actividad` |
| Dashboard por niveles (recursos · cobertura · operación · resultados) | P0 | ✅ | `/panel` |
| Búsqueda, filtros, paginación, exportación CSV | P0 | ✅ | todos los listados |
| Evaluación de necesidades y cola de atención explicable | P1 | ✅ | `/necesidades` |
| Gastos separados de donaciones, con aprobación | P1 | ✅ | `/gastos` |
| Retroalimentación y quejas con plazo | P1 | ✅ | `/retroalimentacion` |
| Portal público de transparencia (solo agregados) | P1 | ✅ | `/transparencia` |
| Portales de donante y de voluntario | P1 | ✅ | `/mi-actividad` |
| Inventario / catálogo de artículos y unidades | P1 | ⏳ | `entrega.detalle` por ahora |
| Presupuesto por partidas; aliados; ODS; geolocalización | P2 | ⏳ | — |
| Notificaciones por correo, recuperación de clave por correo, MFA | P2 | ⏳ | restablecimiento por administrador |

## Catálogo de indicadores (`/panel`)
| Nivel | Indicador | Definición | Advertencia |
|---|---|---|---|
| Recursos | Recaudado y verificado | Σ donaciones **Confirmadas** | Lo pendiente se muestra aparte |
| Recursos | Gasto aprobado / saldo | Σ gastos **Aprobados** / recaudado − gastado | El saldo nunca puede ser negativo (lo impide el procedimiento) |
| Cobertura | Hogares atendidos | Hogares distintos con ≥ 1 entrega **Entregada** | — |
| Cobertura | Personas estimadas | Σ `integrantes_hogar` de hogares atendidos | **Estimación**, no personas únicas |
| Cobertura | Unidades entregadas | Σ `cantidad` | Operativo: unidades heterogéneas |
| Operación | Pendientes | Donaciones por verificar, gastos por aprobar, entregas vencidas | — |
| Resultados | Necesidades cubiertas / días de cobertura | Cubiertas ÷ (cubiertas + abiertas) | Sin datos ⇒ «—», nunca 0 |
| Calidad | Satisfacción, quejas en plazo | Promedio 1–5; resueltas ≤ plazo ÷ resueltas | Excluye casos confidenciales |

> **Las entregas y unidades son *productos*, no *resultados*:** no miden por sí solas una mejora en la vida de las familias. Para medir resultados se requiere seguimiento posterior (ver teoría del cambio en el análisis funcional).

## Matriz de permisos por rol (● = concedido)
| Permiso | Coordinador | Finanzas | Trabajo Social | Voluntario | Auditor | Donante | Admin |
|---|---|---|---|---|---|---|---|
| `campanas:leer` | ● | ● | ● | ● | ● |  | ● |
| `campanas:escribir` | ● |  |  |  |  |  | ● |
| `campanas:estado` | ● |  |  |  |  |  | ● |
| `catalogos:leer` | ● | ● | ● | ● | ● |  | ● |
| `catalogos:escribir` | ● |  |  |  |  |  | ● |
| `donantes:leer` | ● | ● |  |  | ● |  | ● |
| `donantes:escribir` |  | ● |  |  |  |  | ● |
| `donaciones:leer` | ● | ● |  |  | ● |  | ● |
| `donaciones:registrar` |  | ● |  |  |  |  | ● |
| `donaciones:verificar` |  | ● |  |  |  |  | ● |
| `donaciones:exportar` |  | ● |  |  |  |  | ● |
| `gastos:leer` | ● | ● |  |  | ● |  | ● |
| `gastos:registrar` |  | ● |  |  |  |  | ● |
| `gastos:aprobar` | ● |  |  |  |  |  | ● |
| `beneficiarios:leer` | ● |  | ● |  | ● |  | ● |
| `beneficiarios:escribir` |  |  | ● |  |  |  | ● |
| `necesidades:leer` | ● |  | ● |  | ● |  | ● |
| `necesidades:escribir` | ● |  | ● |  |  |  | ● |
| `voluntarios:leer` | ● |  | ● |  | ● |  | ● |
| `voluntarios:escribir` | ● |  |  |  |  |  | ● |
| `entregas:leer` | ● |  | ● |  | ● |  | ● |
| `entregas:registrar` | ● |  | ● |  |  |  | ● |
| `entregas:gestionar` | ● |  |  |  |  |  | ● |
| `entregas:propias` |  |  |  | ● |  |  | ● |
| `feedback:leer` | ● |  | ● |  | ● |  | ● |
| `feedback:registrar` | ● |  | ● | ● |  |  | ● |
| `feedback:gestionar` | ● |  | ● |  |  |  | ● |
| `feedback:confidencial` |  |  | ● |  |  |  | ● |
| `dashboard:leer` | ● | ● | ● |  | ● |  | ● |
| `reportes:leer` | ● | ● |  |  | ● |  | ● |
| `reportes:exportar` |  | ● |  |  |  |  | ● |
| `usuarios:leer` |  |  |  |  | ● |  | ● |
| `usuarios:escribir` |  |  |  |  |  |  | ● |
| `auditoria:leer` |  |  |  |  | ● |  | ● |
| `portal:donante` |  |  |  |  |  | ● | ● |
| `portal:voluntario` |  |  |  | ● |  |  | ● |

## Riesgos conocidos y mitigaciones
| Riesgo | Mitigación implementada |
|---|---|
| Datos personales de familias vulnerables | Aislamiento por rol, consentimiento visible, bitácora, exportación auditada, portal público con supresión de celdas pequeñas |
| Fraude interno | Separación de funciones en gastos, bitácora inmutable, referencias de pago únicas |
| Confundir «prometido» con «recibido» | Estados de donación; solo lo confirmado suma |
| Doble atención / exclusión | Alertas de repetición; cola de necesidades; «hogares sin ninguna entrega» como filtro |
| Casos de abuso o riesgo | Aviso explícito de escalar por el protocolo de salvaguarda (esta herramienta no lo reemplaza) |
