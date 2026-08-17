import * as cheerio from 'cheerio';
import type { ActorInput, LinkSummary, UrlIntelligenceResult } from './schema.js';

const EMAIL_PATTERN = /[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/giu;

export type FetchLike = (url: string, init?: RequestInit) => Promise<Response>;

export async function analyzeUrls(input: ActorInput, fetcher: FetchLike = fetch): Promise<UrlIntelligenceResult[]> {
  const results: UrlIntelligenceResult[] = [];

  for (const url of input.urls) {
    results.push(await analyzeUrl(url, input, fetcher));
  }

  return results;
}

export async function analyzeUrl(url: string, input: ActorInput, fetcher: FetchLike = fetch): Promise<UrlIntelligenceResult> {
  const fetchedAt = new Date().toISOString();
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), input.timeoutMs);

  try {
    const response = await fetcher(url, {
      redirect: 'follow',
      signal: controller.signal,
      headers: {
        'user-agent': 'Apify URL Intelligence API/0.1 (+https://apify.com)',
        accept: 'text/html,application/xhtml+xml,application/xml;q=0.9,text/plain;q=0.8,*/*;q=0.7',
      },
    });

    const contentType = response.headers.get('content-type') ?? '';
    const body = await response.text();
    const isHtml = contentType.includes('html') || looksLikeHtml(body);
    const parsed = isHtml ? parseHtml(url, body, input.maxLinksPerUrl, input.includeTextSample) : parseText(body, input.includeTextSample);

    return {
      url,
      status: response.ok ? 'ok' : 'error',
      httpStatus: response.status,
      ...parsed,
      error: response.ok ? undefined : `HTTP ${response.status}`,
      fetchedAt,
    };
  } catch (error) {
    return {
      url,
      status: 'error',
      error: error instanceof Error ? error.message : String(error),
      fetchedAt,
    };
  } finally {
    clearTimeout(timer);
  }
}

export function parseHtml(sourceUrl: string, html: string, maxLinks: number, includeTextSample: boolean): Partial<UrlIntelligenceResult> {
  const $ = cheerio.load(html);
  const pageUrl = new URL(sourceUrl);
  const title = cleanText($('title').first().text());
  const description = cleanText(
    $('meta[name="description"]').attr('content')
      ?? $('meta[property="og:description"]').attr('content')
      ?? '',
  );
  const canonicalUrl = absolutize($('link[rel="canonical"]').attr('href'), sourceUrl);
  const language = cleanText($('html').attr('lang') ?? '');
  const text = cleanText($('body').text());
  const links = extractLinks($, sourceUrl, pageUrl.hostname, maxLinks);
  const technologies = detectTechnologies($, html);

  return {
    title: title || undefined,
    description: description || undefined,
    canonicalUrl,
    language: language || undefined,
    wordCount: countWords(text),
    linkCount: $('a[href]').length,
    emails: extractEmails(text),
    technologies,
    textSample: includeTextSample ? text.slice(0, 500) : undefined,
    links,
  };
}

export function parseText(text: string, includeTextSample: boolean): Partial<UrlIntelligenceResult> {
  const cleaned = cleanText(text);
  return {
    wordCount: countWords(cleaned),
    linkCount: 0,
    emails: extractEmails(cleaned),
    technologies: [],
    textSample: includeTextSample ? cleaned.slice(0, 500) : undefined,
    links: [],
  };
}

function extractLinks($: cheerio.CheerioAPI, sourceUrl: string, hostname: string, maxLinks: number): LinkSummary[] {
  const seen = new Set<string>();
  const links: LinkSummary[] = [];

  $('a[href]').each((_, element) => {
    if (links.length >= maxLinks) return;
    const rawHref = $(element).attr('href');
    const href = absolutize(rawHref, sourceUrl);
    if (!href || seen.has(href)) return;
    seen.add(href);
    const targetHostname = new URL(href).hostname;
    links.push({
      href,
      text: cleanText($(element).text()).slice(0, 120),
      internal: targetHostname === hostname || targetHostname.endsWith(`.${hostname}`),
    });
  });

  return links;
}

function detectTechnologies($: cheerio.CheerioAPI, html: string): string[] {
  const technologies = new Set<string>();
  const generator = $('meta[name="generator"]').attr('content') ?? '';
  if (generator) technologies.add(generator);
  if (html.includes('wp-content') || html.includes('wp-includes')) technologies.add('WordPress');
  if (html.includes('Shopify.theme') || html.includes('cdn.shopify.com')) technologies.add('Shopify');
  if (html.includes('__NEXT_DATA__')) technologies.add('Next.js');
  if (html.includes('data-reactroot') || html.includes('react-dom')) technologies.add('React');
  if (html.includes('gtag(') || html.includes('googletagmanager.com')) technologies.add('Google Analytics/Tag Manager');
  return [...technologies].sort();
}

function absolutize(rawHref: string | undefined, sourceUrl: string): string | undefined {
  if (!rawHref) return undefined;
  try {
    const url = new URL(rawHref, sourceUrl);
    if (url.protocol !== 'http:' && url.protocol !== 'https:') return undefined;
    url.hash = '';
    return url.toString();
  } catch {
    return undefined;
  }
}

function cleanText(value: string): string {
  return value.replace(/\s+/g, ' ').trim();
}

function countWords(value: string): number {
  if (!value) return 0;
  return value.split(/\s+/).filter(Boolean).length;
}

function extractEmails(value: string): string[] {
  return [...new Set(value.match(EMAIL_PATTERN) ?? [])].sort();
}

function looksLikeHtml(value: string): boolean {
  return /<html|<!doctype html|<body|<title/i.test(value.slice(0, 2000));
}
