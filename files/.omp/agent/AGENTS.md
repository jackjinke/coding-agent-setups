# Development Preferences

Personal defaults for every project. A project's own AGENTS.md carries project facts and overrides these where they conflict.

## Resolving Ambiguity

- Prefer resolving unclear requirements from repository context — existing code, tests, and docs usually decide.
- Ask only when the remaining options carry materially different tradeoffs (data loss, public API shape, security posture). Otherwise take the most conservative interpretation and state the assumption.

## Architecture & Design

- Prefer the simplest, most direct design that solves the stated problem — no speculative flags, options, or abstractions (YAGNI). Abstract at the second concrete use, not the first.
- Keep modules focused and single-purpose, with explicit boundaries expressed in types.
- Centralize domain types, states, and enums rather than scattering parallel definitions.
- Architectural designs should get reviewed before implementation starts.

## Naming

- Names express domain meaning, not implementation history. Reject names like `phase1`, `v2`, `newThing`, `foo2`, `temp`, `legacy`, or `handleStuff` unless the term marks a lasting domain distinction (e.g. a real protocol version).

## Code Quality

- Value readability and maintainability; clarity beats cleverness.
- Comments explain why, not what.
- Validate external input at trust boundaries; fail loudly on impossible states instead of papering over them.

## Dependencies

- Prefer the stdlib and dependencies already in the project. A new dependency needs a benefit that outweighs its maintenance cost.

## Verification

- Verification should fit the change: reserve automated tests for durable behavioral contracts, and don't mechanically add tests to experiments or purely visual work.
- Tests assert observable behavior and side effects — including failure paths (missing dependencies, unavailable services, empty or partial input) — not internal plumbing.

## Orchestration

- In large changes, each phase or milestone passes review before the next begins.
- Scope every review before dispatching it, sized to the change under review. Avoid long and shallow reviews.
- Once dispatched, a review runs to completion. Don't interrupt or cancel it just for taking long. If reviews chronically overrun, adjust their scope on the next dispatch instead.
- No two delegated slices may decide the same question.
- Record design decisions where downstream work will encounter them.
- Prefer multiple decorrelated review lenses (transcript, output only, codebase only) over one deep pass.
