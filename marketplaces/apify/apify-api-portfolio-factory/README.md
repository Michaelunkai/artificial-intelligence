# Apify API Portfolio Factory

Live website: https://apify-api-portfolio-factory.netlify.app

This project is a complete starting point for selling small API-style Apify Actors. The first Actor, `url-intelligence-api`, accepts URLs and returns clean dataset rows with page metadata, links, text statistics, email hints, and technology hints.

## What is included

- A TypeScript Apify Actor with `.actor/actor.json`, input schema, dataset schema, output schema, and Dockerfile.
- Local build, type check, lint, tests, local run, secret scan, permission check, and deploy commands.
- GitHub Actions workflow using `apify/push-actor-action@v1` and `APIFY_TOKEN` as a repository secret.
- Operational docs for scaling the portfolio, publishing, pricing, and pruning.

## Commands

```powershell
npm install
npm run verify
npm run run:local
$env:APIFY_TOKEN = "your token only in this shell"
npm run permission:test
npm run deploy
Remove-Item Env:\APIFY_TOKEN
```

## Safety rules

- Never commit `.env` or real API tokens.
- Use `APIFY_TOKEN` only as a shell environment variable or GitHub Actions secret.
- Keep Actors private until schemas, tests, example runs, support text, and pricing are ready.
- Treat marketplace/payout/KYC prompts as account-owner steps if Apify requires them in Console.

## First sellable Actor

`url-intelligence-api` is useful for lead enrichment, competitive research, SEO triage, and AI-agent preprocessing. It returns structured output from public URLs without needing a custom backend.

## Deployment

The official Apify docs recommend deploying Actors with the Apify CLI from a directory containing `.actor/actor.json`, or via GitHub Actions with `apify/push-actor-action@v1`. This project supports both.

## Account-owner gates

The code can create, update, deploy, test, and run Actors using an unscoped Apify token. It cannot honestly complete legal, payout, tax, identity, store terms, or marketplace review gates if Apify requires a human account-owner confirmation in Console.
