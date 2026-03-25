# Contributing to AgentFlow

Thank you for your interest in AgentFlow! This is currently a personal portfolio project by Till Thelet, but suggestions and feedback are welcome.

## Reporting Issues

Found a bug or have a feature request? Open an issue on GitHub:
- **Bug Report:** Describe the problem, steps to reproduce, and expected behavior
- **Feature Request:** Explain the use case and how it would improve AgentFlow

## Development Setup

1. **Clone the repository:**
   ```bash
   git clone https://github.com/Michaelunkai/agentflow.git
   cd agentflow
   ```

2. **Install dependencies:**
   ```bash
   npm install
   ```

3. **Install to OpenClaw:**
   ```bash
   powershell .\install.ps1
   ```

4. **Make changes and test:**
   ```bash
   # Hot-reload after changes
   curl -X POST http://localhost:18789/agentflow/api/admin/reload \
        -H "X-Admin-Token: agentflow-dev-token"
   ```

## Code Style

- **JavaScript:** ES6+ syntax, async/await preferred
- **Indentation:** 2 spaces
- **Naming:** camelCase for variables/functions, PascalCase for classes
- **Comments:** JSDoc for functions, inline comments for complex logic

## Project Structure

```
agentflow/
├── index.js              # Main extension entry
├── api/                  # API modules (tasks, bots, analytics)
├── lib/                  # Core libraries (BotManager)
├── web/                  # Frontend (HTML, CSS, JS)
├── docs/                 # Documentation
└── tests/                # Unit tests (TODO)
```

## Adding New Features

1. **Design first:** Think through the API, data model, and UX
2. **Write code:** Follow existing patterns in `api/` and `lib/`
3. **Update docs:** Add to README or ARCHITECTURE.md
4. **Test locally:** Ensure no regressions
5. **Submit PR:** (If external contributions are accepted in the future)

## Testing

Currently manual testing only. Automated tests are on the roadmap:
- Unit tests: `npm test` (TODO: Jest setup)
- Integration tests: Test API endpoints with supertest
- E2E tests: Playwright for frontend testing

## Questions?

Contact Till Thelet:
- **Email:** michaelovsky22@gmail.com
- **GitHub:** @Michaelunkai
- **Telegram:** @TillThelet

---

**Note:** This is a personal portfolio project. External contributions may not be accepted at this time, but feedback and suggestions are always welcome!
