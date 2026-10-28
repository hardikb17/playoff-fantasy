<!-- BEGIN:nextjs-agent-rules -->

## This is NOT the Next.js you know

This version has breaking changes — APIs, conventions, and file structure may all differ from your training data. Read the relevant guide in `node_modules/next/dist/docs/` (resolved from this file's directory; in monorepos the `next` package may not be visible from the repo root) before writing any code. Heed deprecation notices.

This block is written and re-added by `next dev` — verify at `node_modules/next/dist/server/lib/generate-agent-files.js`. Removing it from a diff only re-creates the uncommitted change; committing it with your work keeps the tree clean.

<!-- END:nextjs-agent-rules -->

## Project guidance

- Read [docs/SPEC.md](docs/SPEC.md) for confirmed NFL playoff fantasy rules and unresolved choices, [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for proposals, and [docs/PLAN.md](docs/PLAN.md) for status and the next bounded task. Recommendations are not approved requirements.
- Use explicit season labeling: 2026 NFL season, playoffs concluding in 2027. Do not invent product features or silently resolve open decisions.
- Build one milestone at a time. Explain focused changes and how to verify them; update docs when accepted decisions change.
- Preserve server/database authorization, league isolation, atomic draft correctness, exact scoring, and safe reimports. Never present simulated security, persistence, or multiplayer as complete. Label synthetic data.
- Add meaningful tests for turn order, exact scoring, authorization, concurrency, idempotency, undo, and safe reimports as those capabilities are implemented.
- Use existing package scripts; currently dev/build/start/lint/test. `npm test` runs pure TypeScript tests using Node’s test runner with `tsx`. Typecheck with `npx tsc --noEmit`. Read relevant installed Next.js guides before coding and preserve the generated guidance above.
- Version schema changes as SQL migrations. Keep secrets server-side where required and out of Git; prevent local/preview writes to production. Avoid extra infrastructure without demonstrated need.
- Do not install third-party skills or execute their scripts without review. Future tasks are governed by their explicitly authorized scope.
