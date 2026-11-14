import * as esbuild from 'esbuild';
import * as fs from 'fs';
import * as path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const ROOT = __dirname;

const inputDir = path.join(ROOT, `sources`);
const outputDir = path.join(ROOT, `scripts`);

const inputFileName = `index.ts`;
const outputFileName = `index.js`;

const format = `esm`;
const target = `es2021`;

const external = [
  '@minecraft/common',
  '@minecraft/debug-utilities',
  '@minecraft/gameplay-utilities',
  '@minecraft/math',
  '@minecraft/server',
  '@minecraft/server-ui',
  '@minecraft/server-admin',
  '@minecraft/server-gametest',
  '@minecraft/server-net',
  '@minecraft/server-common',
  '@minecraft/server-editor',
  '@minecraft/debug-utilities',
];

fs.mkdirSync(outputDir, { recursive: true });

esbuild
  .build({
    entryPoints: [path.join(inputDir, inputFileName)],
    outfile: path.join(outputDir, outputFileName),
    bundle: true,
    minify: true,
    format,
    target,
    external,
  })
  .then(() => {
    console.log('Bundling finished!');
  })
  .catch(error => {
    console.error(`Bundling failed: ${error}`);
  });
