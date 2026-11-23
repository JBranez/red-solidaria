// Prepara el tema visual a partir de Bootswatch "Zephyr" (Bootstrap 5.3.8 precompilado, MIT, Thomas Park).
// Se ejecuta en `postinstall`/`prestart`/`prebuild`. Quita el @import a Google Fonts: la tipografía (Inter)
// se sirve desde el propio paquete (@fontsource-variable/inter), sin peticiones a terceros.
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const raiz = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const origen = resolve(raiz, 'node_modules/bootswatch/dist/zephyr/bootstrap.min.css');
const destino = resolve(raiz, 'src/theme/zephyr.css');

const css = readFileSync(origen, 'utf8').replace(/@import url\([^)]*\);?/g, '');
mkdirSync(dirname(destino), { recursive: true });
writeFileSync(destino, css);
console.log(`[tema] ${destino.replace(raiz, '.')} generado (${(css.length / 1024).toFixed(0)} kB, sin @import externos)`);
