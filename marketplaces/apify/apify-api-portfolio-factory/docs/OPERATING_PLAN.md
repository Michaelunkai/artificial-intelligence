# Operating Plan

## Goal

Build a portfolio of low-maintenance paid Apify Actors that behave like APIs: narrow inputs, predictable outputs, clean schemas, examples, automated tests, and repeatable deployment.

## Factory loop

1. Choose one narrow data transformation or scraping niche.
2. Write the Actor from the existing TypeScript template.
3. Add input schema, dataset schema, output schema, and README examples.
4. Add fixture tests and one live smoke test if target-site terms allow it.
5. Deploy private.
6. Run with 3-5 example inputs and inspect outputs.
7. Add pricing and marketplace listing only after output quality is stable.
8. Watch usage, errors, and support load for two weeks.
9. Keep winners, improve borderline Actors, and delete dead Actors.

## Portfolio candidates

- URL Intelligence API: metadata, links, text stats, contacts, technology hints.
- SERP Result Normalizer: normalize imported search-result HTML or APIs into a common schema.
- Product Page Extractor: title, price, variants, availability, and offer metadata.
- Job Post Enrichment API: company, role, location, seniority, skills, and apply links.
- Local Business Page Auditor: phone, address, schema.org, socials, hours, and broken links.

## Monetization checklist

- Actor is private while being tested.
- Input schema uses clear limits and defaults.
- Dataset output is stable and documented.
- Example runs are clean.
- Store listing says exactly what is collected and what is not.
- Pricing starts low enough to earn first usage, then increases only after proof.
- Account-owner billing, tax, payout, and terms prompts are completed in Apify Console.

## Maintenance checklist

- Weekly: inspect failed runs and support messages.
- Monthly: run `npm run verify`, update dependencies, and re-run sample jobs.
- Quarterly: remove low-usage Actors and clone winning patterns into adjacent niches.
