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

- Model substantial work as a tree: keep decomposition and cross-slice contracts with the orchestrator; give agents bounded leaves.
- Keep delegated slices narrow, self-contained, and non-overlapping. Batch independent work rather than serializing it.
- Record decisions that affect downstream work in shared, discoverable context.
- Keep unrelated work moving while reviews or dependencies are blocked.
- Use focused, decorrelated reviews at consequential boundaries. Bound their scope before dispatch, then let them run to completion.
