import { readdir, readFile } from 'node:fs/promises';
import { join, relative, sep } from 'node:path';
import { apifyRequest, tryApifyRequest } from './apify-api.js';

type User = {
  username: string;
};

type ActorRecord = {
  id: string;
  name: string;
  username: string;
};

type VersionRecord = {
  versionNumber: string;
};

type BuildRecord = {
  id: string;
  status: string;
  actId: string;
  buildNumber?: string;
  startedAt?: string;
  finishedAt?: string;
};

type SourceFile = {
  name: string;
  format: 'TEXT';
  content: string;
};

const actorName = 'url-intelligence-api';
const actorTitle = 'URL Intelligence API';
const actorDescription = 'Turns public URLs into clean metadata, links, text statistics, email hints, and technology hints.';
const sourceRoots = ['dist', '.actor'];
const sourceFiles = await collectSourceFiles();
const user = await apifyRequest<User>('/users/me');
const actorRef = `${user.username}~${actorName}`;
let actor = await tryApifyRequest<ActorRecord>(`/acts/${actorRef}`);
let versionNumber = '0.1';

if (!actor) {
  actor = await apifyRequest<ActorRecord>('/acts', {
    method: 'POST',
    body: JSON.stringify({
      name: actorName,
      title: actorTitle,
      description: actorDescription,
      isPublic: false,
      versions: [makeVersion(versionNumber, sourceFiles)],
    }),
  });
} else {
  const versions = await apifyRequest<{ items?: VersionRecord[] } | VersionRecord[]>(`/actors/${actor.id}/versions`);
  const items = Array.isArray(versions) ? versions : versions.items ?? [];
  versionNumber = nextVersion(items.map((version) => version.versionNumber));
  await apifyRequest(`/actors/${actor.id}/versions`, {
    method: 'POST',
    body: JSON.stringify(makeVersion(versionNumber, sourceFiles)),
  });
}

const build = await apifyRequest<BuildRecord>(`/actors/${actor.id}/builds?version=${versionNumber}&tag=latest&waitForFinish=60`, {
  method: 'POST',
});

if (build.status !== 'SUCCEEDED') {
  throw new Error(`Actor build did not succeed within the wait window. Build ${build.id} status: ${build.status}`);
}

console.log(JSON.stringify({
  actorId: actor.id,
  actorRef,
  versionNumber,
  buildId: build.id,
  buildStatus: build.status,
}, null, 2));

function makeVersion(versionNumberValue: string, files: SourceFile[]) {
  return {
    versionNumber: versionNumberValue,
    sourceType: 'SOURCE_FILES',
    buildTag: 'latest',
    sourceFiles: files,
  };
}

async function collectSourceFiles(): Promise<SourceFile[]> {
  const root = process.cwd();
  const files: SourceFile[] = [];
  for (const sourceRoot of sourceRoots) {
    await walk(join(root, sourceRoot), root, files);
  }
  for (const fileName of ['Dockerfile', 'package.json', 'package-lock.json', 'README.md']) {
    const content = await readFile(join(root, fileName), 'utf8');
    files.push({ name: fileName, format: 'TEXT', content });
  }
  return files.sort((a, b) => a.name.localeCompare(b.name));
}

async function walk(dir: string, root: string, files: SourceFile[]): Promise<void> {
  const entries = await readdir(dir, { withFileTypes: true });
  for (const entry of entries) {
    const fullPath = join(dir, entry.name);
    if (entry.isDirectory()) {
      await walk(fullPath, root, files);
      continue;
    }
    if (!entry.isFile()) continue;
    const name = relative(root, fullPath).split(sep).join('/');
    const content = await readFile(fullPath, 'utf8');
    files.push({ name, format: 'TEXT', content });
  }
}

function nextVersion(existingVersions: string[]): string {
  const minors = existingVersions
    .map((version) => /^0\.(\d+)$/.exec(version)?.[1])
    .filter((value): value is string => Boolean(value))
    .map((value) => Number.parseInt(value, 10));
  const nextMinor = minors.length === 0 ? 1 : Math.max(...minors) + 1;
  return `0.${nextMinor}`;
}
