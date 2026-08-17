import { readdir, readFile } from 'node:fs/promises';
import { join } from 'node:path';

const root = process.cwd();
const ignoredDirs = new Set(['node_modules', '.git', 'dist', 'storage', 'apify_storage', 'coverage']);
const secretPatterns = [
  /apify_api_[A-Za-z0-9_-]{20,}/g,
  /sk-proj-[A-Za-z0-9_-]{20,}/g,
  /sk-[A-Za-z0-9_-]{20,}/g,
];

const hits: string[] = [];

async function walk(dir: string): Promise<void> {
  const entries = await readdir(dir, { withFileTypes: true });
  for (const entry of entries) {
    if (ignoredDirs.has(entry.name)) continue;
    const fullPath = join(dir, entry.name);
    if (entry.isDirectory()) {
      await walk(fullPath);
      continue;
    }
    if (entry.isFile()) {
      const content = await readFile(fullPath, 'utf8').catch(() => '');
      for (const pattern of secretPatterns) {
        if (pattern.test(content)) hits.push(fullPath);
        pattern.lastIndex = 0;
      }
    }
  }
}

await walk(root);

if (hits.length > 0) {
  console.error(`Potential secrets found:\n${hits.join('\n')}`);
  process.exit(1);
}

console.log('Secret scan passed.');
