# Orchestration

- Model substantial work as tree: decomposition and cross-slice contracts stay with orchestrator; agents get narrow, bounded, self-contained leaves.
- Record downstream-impacting decisions in shared, discoverable context.
- While delegated work runs, keep parallelizable work moving. None left → one long wait, sized to next review mark when review runs; NEVER spin short-timeout poll loops — results deliver themselves.
- Open phase never justifies early cancel; phase closes when work returns or review timeline says cancel.

# Review Dispatch

- Review at consequential boundaries: public contract, data model, security surface, cross-slice seams after fan-out. Skip with stated reason.
- Scope before dispatch: named files or fixed diff, one axis, acceptance criteria. Vague "relevant code" makes reviewer redo that work.
- Timeline while no return: 10min nudge to converge; 15min request immediate return; 25min cancel. Marks are floors — NEVER escalate before mark; pre-mark silence is patience, not stall.
- Blocking findings close before phase advances; rest recorded, never dropped silently.
