import { describe, expect, it } from 'vitest';
import { analyzeUrl, parseHtml } from '../src/extractor.js';
import type { ActorInput } from '../src/schema.js';

describe('parseHtml', () => {
  it('extracts API-ready metadata from HTML', () => {
    const result = parseHtml('https://example.com/path', `
      <!doctype html>
      <html lang="en">
        <head>
          <title>Example Title</title>
          <meta name="description" content="Example description">
          <link rel="canonical" href="/canonical">
          <script id="__NEXT_DATA__">{}</script>
        </head>
        <body>
          Contact sales@example.com.
          <a href="/pricing">Pricing</a>
          <a href="https://external.test">External</a>
        </body>
      </html>
    `, 10, true);

    expect(result.title).toBe('Example Title');
    expect(result.description).toBe('Example description');
    expect(result.canonicalUrl).toBe('https://example.com/canonical');
    expect(result.language).toBe('en');
    expect(result.emails).toEqual(['sales@example.com']);
    expect(result.technologies).toContain('Next.js');
    expect(result.links).toEqual([
      { href: 'https://example.com/pricing', text: 'Pricing', internal: true },
      { href: 'https://external.test/', text: 'External', internal: false },
    ]);
  });
});

describe('analyzeUrl', () => {
  it('returns a structured error row for failed HTTP responses', async () => {
    const input: ActorInput = {
      urls: ['https://example.com'],
      maxLinksPerUrl: 5,
      timeoutMs: 2000,
      includeTextSample: false,
    };

    const response = new Response('<html><title>Nope</title></html>', {
      status: 404,
      headers: { 'content-type': 'text/html' },
    });

    const result = await analyzeUrl('https://example.com/missing', input, async () => response);

    expect(result.status).toBe('error');
    expect(result.httpStatus).toBe(404);
    expect(result.title).toBe('Nope');
    expect(result.error).toBe('HTTP 404');
  });
});
