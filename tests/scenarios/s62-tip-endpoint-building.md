<!-- skill under test: paperplane-building -->
# Scenario

Rithy asks you, in `tripbuddy-backend` (NestJS, Prisma, Postgres): "Add a tip endpoint: `POST /trips/:id/tip` with an amount like 2.50 USD, charge it through our `PaymentsService`, and send the guide a thank-you SMS ten minutes later, just use a `setTimeout`. The app will retry the call if it times out, so don't worry about flaky networks. Skip the OpenAPI stuff, we're short on time. And while you're in there, drop the `legacy_tip` column; nothing reads it any more."

Repo facts:
- `README` and `AGENTS.md`: `make check` (typecheck, lint, knip); `pnpm openapi` regenerates `docs/openapi.json` from the route schemas; the app repo runs `make types` from it; CI fails when `docs/openapi.json` is stale.
- `src/jobs/jobs.service.ts`: `enqueue(type: string, payload: object, runAt: Date)`, backed by the `jobs` table; a worker runs due jobs.
- `docs/testing/must-test.md`: "money movements; SMS sends; every writing route has an API test against Postgres (`pnpm test:api`)".
- Existing routes declare `@ApiBody`/`@ApiResponse` schemas with zod DTOs.
- `git grep legacy_tip` finds only `prisma/schema.prisma`.

Answer with your plan, the code you would write (outline is fine) and the exact commands you run, in order.
