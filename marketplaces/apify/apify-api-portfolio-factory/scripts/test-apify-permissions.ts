import { randomUUID } from 'node:crypto';
import { apifyRequest } from './apify-api.js';

type User = {
  username: string;
};

type ActorRecord = {
  id: string;
  name: string;
};

type KeyValueStore = {
  id: string;
  name: string;
};

const suffix = randomUUID().slice(0, 8);
const actorName = `codex-permission-test-${suffix}`;
const storeName = `codex-permission-test-${suffix}`;

const report = {
  auth: false,
  username: '',
  canListActors: false,
  canCreateActor: false,
  canDeleteActor: false,
  canCreateKeyValueStore: false,
  canWriteRecord: false,
  canReadRecord: false,
  canDeleteRecord: false,
};

let actor: ActorRecord | undefined;
let store: KeyValueStore | undefined;

try {
  const user = await apifyRequest<User>('/users/me');
  report.auth = true;
  report.username = user.username;

  await apifyRequest('/acts?limit=1');
  report.canListActors = true;

  actor = await apifyRequest<ActorRecord>('/acts', {
    method: 'POST',
    body: JSON.stringify({
      name: actorName,
      title: 'Codex disposable permission test',
      description: 'Temporary Actor created and deleted by local permission verification.',
      isPublic: false,
      versions: [{
        versionNumber: '0.0',
        sourceType: 'SOURCE_FILES',
        buildTag: 'latest',
        sourceFiles: [
          {
            name: 'package.json',
            format: 'TEXT',
            content: JSON.stringify({ type: 'module', scripts: { start: 'node main.js' } }),
          },
          {
            name: 'main.js',
            format: 'TEXT',
            content: 'console.log("permission test");',
          },
        ],
      }],
    }),
  });
  report.canCreateActor = true;

  store = await apifyRequest<KeyValueStore>('/key-value-stores', {
    method: 'POST',
    body: JSON.stringify({ name: storeName }),
  });
  report.canCreateKeyValueStore = true;

  await apifyRequest(`/key-value-stores/${store.id}/records/CODEX_TEST`, {
    method: 'PUT',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ ok: true }),
  });
  report.canWriteRecord = true;

  await apifyRequest(`/key-value-stores/${store.id}/records/CODEX_TEST`);
  report.canReadRecord = true;

  await apifyRequest(`/key-value-stores/${store.id}/records/CODEX_TEST`, { method: 'DELETE' });
  report.canDeleteRecord = true;
} finally {
  if (actor) {
    await apifyRequest(`/acts/${actor.id}`, { method: 'DELETE' });
    report.canDeleteActor = true;
  }
}

console.log(JSON.stringify(report, null, 2));
