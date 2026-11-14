# Order + Invoice, specified four ways

The same small domain written in four spec stacks, each with a spec checker and a conformance test against one shared TypeScript implementation. Every result below was produced by running the tools on 2026-11-13; nothing is taken from documentation.

## Result

| | Quint | IntentLang + Alloy | IntentLang + Quint | Allium + Quint |
|---|---|---|---|---|
| Spec you edit | `orders.qnt` (191 lines) | `orders.intent` (264) | `orders.intent` (264) | `orders.allium` (218) |
| Second artifact | none | `orders.als` (180) | `orders.qnt` (205) | `orders.qnt` (206) |
| Planted bug caught by the readable tier's own tools | n/a | No (`intent verify` prints VERIFIED) | No (same spec, same tools) | No (`allium analyse`: 0 findings) |
| Planted bug caught by the model checker | Yes, 4 to 5 step trace, about 1 s | Yes, 4-step trace, about 1.5 s | Yes, 4-step trace, about 1 s | Yes, 4-step trace, about 1 s |
| Full check of the correct spec | 806 states, exhaustive, about 1 s | 5 checks to 15 steps, about 60 s | same as Quint | same as Quint |
| Buggy implementation caught by conformance tests | Yes | Yes, after tuning the generator | Yes (same tests) | Yes |

The planted bug: `cancelOrder` no longer voids the order's issued invoice. It breaks "a cancelled order has no issued or paid invoice", and lets a customer pay for a cancelled order.

**The short version:** only the model checkers verified the spec itself. Neither IntentLang's nor Allium's own tooling noticed the bug. Those two languages are better at saying things (actors, surfaces, lifecycles); Quint and Alloy are the ones that check things.

## The four tools

| Tool | What it is | Made by | Version used | Checks invariants |
|---|---|---|---|---|
| [Quint](https://quint-lang.org) | An executable specification language based on TLA+, with TypeScript-like syntax. Ships a simulator and hands off to the TLC and Apalache model checkers. | Informal Systems | 0.33.1 | Yes, exhaustively |
| [Alloy](https://alloytools.org) | A relational modeling language: everything is sets and relations, analyzed by a bounded SAT-based solver. Version 6 added mutable state and temporal logic. | Daniel Jackson's group at MIT | 6.2.0 | Yes, within bounds |
| [Allium](https://juxt.github.io/allium/) | A behavioural specification language written for LLM coding agents: entities, rules, actors, surfaces, lifecycles. No runtime; a CLI validates structure and plans tests. | JUXT | CLI 3.6.1, language 3 | No |
| [IntentLang](https://krakenhavoc.github.io/IntentLang/) | A contract-style specification language for human and AI collaboration: entities, actions with `requires` / `ensures`, invariants, state machines. Has code generation and a spec-level test runner. | krakenhavoc (GitHub account) | 0.7.0-beta.1, built from source | No |

- **Quint** was the strongest here. It was the only tool that both read reasonably and verified the spec, and the only one whose traces could drive the conformance tests directly. Its weak spot is that actors and side effects are conventions, not language constructs.
- **Alloy** did what it promises, but it suits structure-heavy models. For this workflow-shaped problem it was slower than Quint, its result was bounded, and its command-line output is hard to read without the GUI.
- **Allium** was the most expressive and the most pleasant to read, and its CLI installed and behaved as documented. It checks lifecycle structure and nothing deeper, so it needs a checker underneath.
- **IntentLang** reads well and its contracts translate cleanly into a checkable model. Its tooling was the least mature: the published release rejects the project's own example, the test runner ignores quantified effects, and `verify` does not verify invariants.

## The domain

- **Order:** Draft → Confirmed → Fulfilled, or Cancelled from Draft or Confirmed.
- **Invoice:** belongs to one order. Issued → Paid, or Void.
- **Actions:** customer creates, confirms, pays, cancels; the system issues invoices; staff void invoices and fulfil orders.
- **Side effects:** an invoice email on issue, a receipt on payment.
- **Invariants:**
  1. Every invoice refers to an existing order.
  2. An order has at most one non-void invoice.
  3. A fulfilled order has a paid invoice.
  4. A cancelled order has no issued or paid invoice.
  5. A receipt exists only for a paid invoice.
- **Bounds for checking:** 2 orders, 3 invoices.

Two things were added to what we agreed, both to make an invariant non-trivial: `createOrder` (otherwise invariant 1 cannot fail) and `voidInvoice` by staff (otherwise an order never gets a second invoice and invariant 2 cannot fail).

## What is in each folder

| Folder | Files |
|---|---|
| `impl/` | `orders.ts`, the shared implementation, with a switch that reproduces the bug in code |
| `quint/` | `orders.qnt`, `conformance.test.ts` (replays Quint traces) |
| `intentlang-alloy/` | `orders.intent`, `orders.als`, `contracts.test.ts`, `generated/orders.ts` (IntentLang's TypeScript skeleton) |
| `intentlang-quint/` | `orders.intent` (identical to the one in `intentlang-alloy/`), `orders.qnt`, `sync-check.mjs` (drift guard), `ir.json`, `contracts.test.ts` |
| `allium-quint/` | `orders.allium`, `orders.qnt`, `sync-check.mjs` (drift guard), `plan.json`, `obligations.test.ts` |
| every stack folder | `orders_bug.*`, `planted-bug.diff`, `results/` (the checkers' raw output on the bug), `check.sh` |

## Running it

```bash
npm install                      # Quint 0.33.1 and fast-check
cargo install allium-cli         # allium 3.6.1
# IntentLang: build from source, see the note below
# Alloy: download org.alloytools.alloy.dist.jar (6.2.0) to tools/alloy.jar
# Java 17+ is needed for Alloy and for Quint's model checkers; Node 22.18+ runs the .ts tests directly

npm run check:quint              # about 45 s
npm run check:intentlang-alloy   # about 70 s
npm run check:intentlang-quint   # about 35 s
npm run check:allium-quint       # about 30 s
```

Each `check.sh` runs the correct spec (must pass), the reachability witnesses, the planted bug (must be reported), and the conformance tests against the correct and the buggy implementation.

## What each stack did with the planted bug

**Quint.** `quint typecheck` passes, as it should: the bug is well-typed. The simulator names the broken invariant (`cancelledHasNoLiveInvoice`) and prints the trace in Quint syntax. The TLC model checker finds it too. An ad hoc query, written on the command line, showed the consequence: a trace ending with a Paid invoice and a Receipt on a Cancelled order.

**IntentLang + Alloy.** `intent check` and `intent verify` both pass on the buggy spec. `intent test` fails one scenario, but only because I had written an example asserting `invoice.status == Void`; a second scenario that asserts nothing about the invoice passes, even though the resulting state breaks a declared invariant. Alloy finds the counterexample.

**IntentLang + Quint.** The readable tier behaves exactly as above, since it is the same file and the same tools. The difference is underneath: the Quint model finds the bug in about a second and names the broken invariant. The names line up one to one (`CancelOrder` and `cancelOrder`, `OneActiveInvoice` and `oneActiveInvoice`), so a drift guard built on `intent compile` was easy to write.

**Allium + Quint.** `allium check` and `allium analyse` report nothing. For contrast, when I changed a rule to produce an illegal transition (draft → fulfilled), `allium analyse` did flag it, along with the state that lost its only exit. So Allium checks lifecycle structure, and does not check cross-entity invariants. The derived Quint model finds the bug, provided someone mirrored the change into it.

## What each language says natively

| Primitive | Quint | IntentLang | Alloy | Allium |
|---|---|---|---|---|
| Entities and relationships | Records and maps, by hand | `entity`, typed fields | `sig` and relations (its core strength) | `entity`, relationships, projections, derived values |
| Lifecycle | Enum plus action guards | `state` block | Status sigs plus guards | `transitions` graph with terminal states |
| Actions | `action` | `action` with `requires` / `ensures` | `pred` with hand-written frame conditions | `rule` with `when` / `requires` / `ensures` |
| Invariants | `val`, checked | `invariant`, not checked | `assert` + `check`, checked | `invariant`, not checked |
| Actors | A value and a guard, by hand | `requires_role` property, metadata only | A sig and a guard, by hand | `actor`, plus `surface` for what each one sees and may do |
| Side effects | A state variable (outbox), by hand | An `exists` postcondition | A mutable set, by hand | Entity creation, or a chained rule |
| System reactions | A separate step with a guard | Not expressible | A separate step | `when: order: Order.awaiting_invoice`, first-class |
| Reachability | Yes | No | Yes | Lifecycle edges only |

## Things I had to work around

- **IntentLang's published release is behind its repository.** `cargo install intent-cli` installs 0.1.0. Asking for 0.7.0-beta.1 gives a build that rejects `state` blocks, including the project's own `task_states.intent` example. Building the repository from source (also labelled 0.7.0-beta.1) works. That is what `check:intentlang-alloy` uses.
- **IntentLang's test runner executes only simple postconditions.** It turns `param.field == value` into an assignment and ignores quantified effects, so "every issued invoice of this order becomes void" could not drive a test. I added an explicit optional `invoice` parameter to `CancelOrder` to give it something to assign. A scenario with no invoices at all fails with "no instances provided for type 'Invoice' in quantifier", so I could not write the "cancel a draft order" example.
- **IntentLang's test harness generator emits Rust only.** `contracts.test.ts` is transcribed by hand.
- **Quint's default simulator backend could not be downloaded here** (it is fetched from the GitHub API, which this sandbox blocks). The scripts use `--backend typescript`. On your machine the default should work and is faster.
- **Quint's default model checker (Apalache) did not finish.** A bounded check to 12 steps was still running after 10 minutes. The TLC backend (`--backend tlc`) explored the whole state space in about a second. For small finite models like this one, TLC is the right backend.
- **Random property tests missed the bug at first.** With short, uniformly random action sequences the buggy implementation passed 2,000 runs. It was caught only after I biased the generator toward the right actor and forced sequences of 20 to 40 steps. Quint's spec-generated traces caught it without tuning.
- **Alloy's default counterexample output is hard to read on the command line.** `-t text` is usable; the visualizer in the Alloy GUI is where its traces are meant to be read.

## Limits of this prototype

- **Drift in the two-tier stacks is only guarded by name.** `sync-check.mjs` fails if a rule or invariant exists in one file and not the other. It passes when the Allium file and the Quint model disagree about what a rule does. In `allium-quint` and `intentlang-quint`, the checker only caught the bug because I applied it to both files. `intentlang-alloy` has no drift guard at all.
- **Not everything in the readable tier reached the model.** Allium's surfaces, `Order.customer` and `Invoice.paid_at` are not in the Quint model, so nothing checks them.
- **No liveness.** Reachability ("an order can be fulfilled") is checked. "Every order eventually reaches a terminal state" is not.
- **Alloy's result is bounded** at 15 steps. TLC reported the full graph has depth 13, so the bound covers it for this model; that will not hold as the model grows.
- **The off-the-shelf TypeScript connector for Quint was not used.** `conformance.test.ts` is a 76-line hand-written trace replayer. I did not test `@firfi/quint-connect`.
- **Conformance is sampling.** 200 traces, 1,190 steps for Quint; 2,000 random sequences for both IntentLang stacks; 1,000 per invariant for Allium + Quint.
- **Language features not exercised:** Allium's temporal triggers, config and contracts; IntentLang's `serve` runtime, OpenAPI output and AI generation; Quint's temporal properties and inductive invariants.

## My read

- **If verifying the spec is the requirement, Quint alone is the cleanest.** One file, and the file you edit is the file that gets checked. The cost is that actors and side effects are conventions you maintain, not constructs.
- **Allium + Quint reads best and says the most.** The Allium file is the one I would hand to a product person or an agent. Its price is the second file and the fact that its correctness rests on the agent mirroring every change.
- **IntentLang + Quint is the better of the two IntentLang stacks.** Quint checks the whole state space in a second where Alloy took a minute for a bounded result, and the contract style (`requires` / `ensures`) translates into Quint guards and updates almost line for line. It still inherits IntentLang's immature tooling.
- **IntentLang + Alloy is the weakest today.** IntentLang's contracts read well, but its tooling is the least mature of the four, its "verify" does not verify invariants, and Alloy added a slower checker with less readable output for this workflow-shaped problem. Alloy would earn its place on a model that is mostly structure and few transitions.
- **A correction to what I told you earlier:** I described Allium's checks as lint-level. `allium analyse` does more than that (lifecycle reachability, dead ends, conflicting rules). It still does not check invariants.
