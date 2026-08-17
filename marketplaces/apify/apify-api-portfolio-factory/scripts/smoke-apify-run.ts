import { apifyRequest } from './apify-api.js';

type SmokeResult = {
  url?: string;
  status?: string;
  httpStatus?: number;
  title?: string;
};

const actorRef = process.env.APIFY_ACTOR_REF ?? 'fluting_frostfield~url-intelligence-api';
const items = await apifyRequest<SmokeResult[]>(`/actors/${actorRef}/run-sync-get-dataset-items?memory=256&timeout=60`, {
  method: 'POST',
  body: JSON.stringify({
    urls: ['https://example.com'],
    maxLinksPerUrl: 5,
    timeoutMs: 12000,
    includeTextSample: false,
  }),
});

if (!Array.isArray(items) || items.length !== 1) {
  throw new Error(`Expected one dataset item, got ${Array.isArray(items) ? items.length : typeof items}.`);
}

const [item] = items;
if (item.url !== 'https://example.com' || item.status !== 'ok' || item.httpStatus !== 200 || item.title !== 'Example Domain') {
  throw new Error(`Unexpected smoke result: ${JSON.stringify(item)}`);
}

console.log(JSON.stringify({
  actorRef,
  itemCount: items.length,
  status: item.status,
  httpStatus: item.httpStatus,
  title: item.title,
}, null, 2));
