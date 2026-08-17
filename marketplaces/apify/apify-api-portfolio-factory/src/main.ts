import { Actor } from 'apify';
import { analyzeUrls } from './extractor.js';
import { parseActorInput } from './schema.js';

await Actor.init();

try {
  const input = parseActorInput(await Actor.getInput());
  const results = await analyzeUrls(input);
  await Actor.pushData(results);
  await Actor.setValue('OUTPUT', {
    count: results.length,
    ok: results.filter((result) => result.status === 'ok').length,
    errors: results.filter((result) => result.status === 'error').length,
    generatedAt: new Date().toISOString(),
  });
} finally {
  await Actor.exit();
}
