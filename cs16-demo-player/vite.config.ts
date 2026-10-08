import { createReadStream } from 'node:fs';
import { open, readdir, stat } from 'node:fs/promises';
import { extname, relative, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';
import { defineConfig, type Connect, type Plugin } from 'vite';

const demosDir = resolve(fileURLToPath(new URL('./demos/', import.meta.url)));

interface DemoFile {
  name: string;
  path: string;
  url: string;
  map: string;
  size: number;
}

async function readDemoMap(file: string): Promise<string> {
  const header = Buffer.alloc(276);
  const handle = await open(file, 'r');
  try {
    await handle.read(header, 0, header.length, 0);
  } finally {
    await handle.close();
  }
  // HLDEMO header: magic[8], demo protocol, network protocol, map name[260].
  return header.subarray(16, 276).toString('utf8').split('\0', 1)[0].trim();
}

async function listDemos(directory = demosDir): Promise<DemoFile[]> {
  const files: DemoFile[] = [];
  for (const entry of await readdir(directory, { withFileTypes: true })) {
    if (entry.name.startsWith('.') || entry.name === 'known-bad') continue;
    const absolute = resolve(directory, entry.name);
    if (entry.isDirectory()) {
      files.push(...await listDemos(absolute));
    } else if (entry.isFile() && extname(entry.name).toLowerCase() === '.dem') {
      const path = relative(demosDir, absolute).split(sep).join('/');
      const info = await stat(absolute);
      const headerMap = await readDemoMap(absolute);
      const filenameMap = entry.name.match(/de_[a-z0-9_]+/i)?.[0] ?? '';
      files.push({
        name: entry.name,
        path,
        url: `/demos/${path.split('/').map(encodeURIComponent).join('/')}`,
        map: headerMap || filenameMap.toLowerCase() || 'unknown',
        size: info.size,
      });
    }
  }
  return files;
}

function demoLibraryPlugin(): Plugin {
  const middleware: Connect.NextHandleFunction = (request, response, next) => {
      void (async () => {
        const url = new URL(request.url ?? '/', 'http://localhost');
        if (url.pathname === '/api/demos') {
          const demos = await listDemos();
          demos.sort((a, b) => {
            const aCorpus = a.path.startsWith('corpus/') ? 1 : 0;
            const bCorpus = b.path.startsWith('corpus/') ? 1 : 0;
            return aCorpus - bCorpus || a.name.localeCompare(b.name);
          });
          const seen = new Set<string>();
          const uniqueDemos = demos.filter((demo) => {
            const key = `${demo.name.toLowerCase()}:${demo.size}`;
            if (seen.has(key)) return false;
            seen.add(key);
            return true;
          });
          response.setHeader('Content-Type', 'application/json');
          response.setHeader('Cache-Control', 'no-store');
          response.end(JSON.stringify(uniqueDemos));
          return;
        }
        if (!url.pathname.startsWith('/demos/')) {
          next();
          return;
        }

        const requested = decodeURIComponent(url.pathname.slice('/demos/'.length));
        const absolute = resolve(demosDir, requested);
        if (!absolute.startsWith(`${demosDir}${sep}`) || extname(absolute).toLowerCase() !== '.dem') {
          response.statusCode = 403;
          response.end('Forbidden');
          return;
        }
        try {
          const info = await stat(absolute);
          response.setHeader('Content-Type', 'application/octet-stream');
          response.setHeader('Content-Length', info.size);
          response.setHeader('Cache-Control', 'no-store');
          createReadStream(absolute).pipe(response);
        } catch {
          response.statusCode = 404;
          response.end('Demo not found');
        }
      })().catch(next);
    };

  return {
    name: 'local-demo-library',
    configureServer(server) {
      server.middlewares.use(middleware);
    },
    configurePreviewServer(server) {
      server.middlewares.use(middleware);
    },
  };
}

export default defineConfig({
  base: './',
  plugins: [demoLibraryPlugin()],
  // The WASM parser is built into the shared crate, outside this project root.
  server: { fs: { allow: ['.', '../shared/goldsrc-crate/pkg'] } },
});
