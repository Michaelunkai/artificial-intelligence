# Security

## Token handling

- `APIFY_TOKEN` must never be written into tracked files.
- Use a temporary shell variable for local runs.
- Use a GitHub Actions repository secret named `APIFY_TOKEN` for CI deployment.
- Rotate any token that was pasted into an untrusted place or committed by mistake.

## Scraping and API conduct

- Respect target-site terms, robots guidance where applicable, rate limits, and privacy laws.
- Do not collect credentials, private data, or content behind authentication unless you have permission.
- Keep inputs constrained and fail with structured errors instead of retry storms.

## Built-in checks

Run:

```powershell
npm run scan:secrets
npm run verify
```
