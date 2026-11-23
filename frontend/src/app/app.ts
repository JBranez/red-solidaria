import { ChangeDetectionStrategy, Component } from '@angular/core';
import { RouterOutlet } from '@angular/router';
import { Avisos, Confirmacion } from './shared/ui';

@Component({
  selector: 'app-root',
  imports: [RouterOutlet, Avisos, Confirmacion],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `<router-outlet /><rs-avisos /><rs-confirmacion />`,
})
export class App {}
