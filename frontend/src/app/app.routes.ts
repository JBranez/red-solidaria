import { Routes } from '@angular/router';
import { authGuard, guestGuard, inicioGuard, permisoGuard } from './core/guards/auth.guards';
import { Shell } from './layout/shell';

const privada = (ruta: string, titulo: string, permisos: string[], cargar: () => Promise<unknown>) => ({
  path: ruta, title: `${titulo} · Red Solidaria`, canActivate: [permisoGuard(...permisos)], loadComponent: cargar as never,
});

export const routes: Routes = [
  { path: '', pathMatch: 'full', canActivate: [inicioGuard], children: [] },
  { path: 'acceso', title: 'Ingresar · Red Solidaria', canActivate: [guestGuard], loadComponent: () => import('./features/acceso/acceso.page').then((m) => m.AccesoPage) },
  { path: 'transparencia', title: 'Transparencia · Red Solidaria', loadComponent: () => import('./features/publico/transparencia.page').then((m) => m.TransparenciaPage) },
  { path: 'cambiar-password', title: 'Cambiar contraseña · Red Solidaria', canActivate: [authGuard], loadComponent: () => import('./features/acceso/cambiar-password.page').then((m) => m.CambiarPasswordPage) },
  {
    path: '', component: Shell, canActivate: [authGuard], children: [
      privada('panel', 'Panel', ['dashboard:leer'], () => import('./features/panel/panel.page').then((m) => m.PanelPage)),
      privada('mi-actividad', 'Mi actividad', ['portal:donante', 'portal:voluntario'], () => import('./features/mi-actividad/mi-actividad.page').then((m) => m.MiActividadPage)),
      privada('campanas', 'Campañas', ['campanas:leer'], () => import('./features/campanas/campanas.page').then((m) => m.CampanasPage)),
      privada('campanas/:id', 'Campaña', ['campanas:leer'], () => import('./features/campanas/campana-detalle.page').then((m) => m.CampanaDetallePage)),
      privada('donantes', 'Donantes', ['donantes:leer'], () => import('./features/donantes/donantes.page').then((m) => m.DonantesPage)),
      privada('donaciones', 'Donaciones', ['donaciones:leer'], () => import('./features/donaciones/donaciones.page').then((m) => m.DonacionesPage)),
      privada('gastos', 'Gastos', ['gastos:leer'], () => import('./features/gastos/gastos.page').then((m) => m.GastosPage)),
      privada('hogares', 'Hogares', ['beneficiarios:leer'], () => import('./features/hogares/hogares.page').then((m) => m.HogaresPage)),
      privada('necesidades', 'Cola de atención', ['necesidades:leer'], () => import('./features/necesidades/necesidades.page').then((m) => m.NecesidadesPage)),
      privada('entregas', 'Entregas', ['entregas:leer'], () => import('./features/entregas/entregas.page').then((m) => m.EntregasPage)),
      privada('voluntarios', 'Voluntarios', ['voluntarios:leer'], () => import('./features/voluntarios/voluntarios.page').then((m) => m.VoluntariosPage)),
      privada('retroalimentacion', 'Retroalimentación', ['feedback:leer'], () => import('./features/retroalimentacion/retroalimentacion.page').then((m) => m.RetroalimentacionPage)),
      privada('catalogos', 'Catálogos', ['catalogos:escribir'], () => import('./features/admin/catalogos.page').then((m) => m.CatalogosPage)),
      privada('usuarios', 'Usuarios y roles', ['usuarios:leer'], () => import('./features/admin/usuarios.page').then((m) => m.UsuariosPage)),
      privada('auditoria', 'Auditoría', ['auditoria:leer'], () => import('./features/admin/auditoria.page').then((m) => m.AuditoriaPage)),
      { path: 'acceso-denegado', title: 'Acceso denegado · Red Solidaria', loadComponent: () => import('./features/acceso/estado.page').then((m) => m.AccesoDenegadoPage) },
    ],
  },
  { path: '**', title: 'No encontrado · Red Solidaria', loadComponent: () => import('./features/acceso/estado.page').then((m) => m.NoEncontradaPage) },
];
