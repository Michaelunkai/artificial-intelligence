import { z } from 'zod';

const urlSchema = z.string().url().refine((value) => {
  const protocol = new URL(value).protocol;
  return protocol === 'http:' || protocol === 'https:';
}, 'Only http and https URLs are supported.');

export const actorInputSchema = z.object({
  urls: z.array(urlSchema).min(1).max(100),
  maxLinksPerUrl: z.number().int().min(0).max(100).default(25),
  timeoutMs: z.number().int().min(1000).max(30000).default(12000),
  includeTextSample: z.boolean().default(true),
});

export type ActorInput = z.infer<typeof actorInputSchema>;

export type LinkSummary = {
  href: string;
  text: string;
  internal: boolean;
};

export type UrlIntelligenceResult = {
  url: string;
  status: 'ok' | 'error';
  httpStatus?: number;
  title?: string;
  description?: string;
  canonicalUrl?: string;
  language?: string;
  wordCount?: number;
  linkCount?: number;
  emails?: string[];
  technologies?: string[];
  textSample?: string;
  links?: LinkSummary[];
  error?: string;
  fetchedAt: string;
};

export function parseActorInput(input: unknown): ActorInput {
  return actorInputSchema.parse(input);
}
