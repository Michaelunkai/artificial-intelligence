import { analyzeUrls } from '../src/extractor.js';
import { parseActorInput } from '../src/schema.js';

const input = parseActorInput({
  urls: ['https://example.com'],
  maxLinksPerUrl: 10,
  timeoutMs: 12000,
  includeTextSample: true,
});

const results = await analyzeUrls(input);
console.log(JSON.stringify(results, null, 2));
