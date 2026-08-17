import { describe, expect, it } from 'vitest';
import { parseActorInput } from '../src/schema.js';

describe('parseActorInput', () => {
  it('normalizes defaults', () => {
    const input = parseActorInput({
      urls: ['https://example.com'],
    });

    expect(input.maxLinksPerUrl).toBe(25);
    expect(input.timeoutMs).toBe(12000);
    expect(input.includeTextSample).toBe(true);
  });

  it('rejects unsupported protocols', () => {
    expect(() => parseActorInput({
      urls: ['file:///etc/passwd'],
    })).toThrow();
  });
});
