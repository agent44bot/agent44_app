# Sketch: making the NYK Super Agent actually agentic

**Status:** design sketch / not wired up. Branch `agentic-super-agent-sketch`.

## What we have today

`KitchenAi::AskAgent` (`app/lib/kitchen_ai/ask_agent.rb`) is a single-turn RAG
wrapper: it stuffs the latest snapshot + a computed fleet-status summary into a
system prompt, calls Claude Haiku once, and returns the answer. It can *describe*
the fleet but can't *do* anything — no tools, no loop. By the strict definition
(LLM + tools + a loop that observes results and iterates), it isn't an agent.

## What "agentic" takes

Three things the current code lacks:

1. **A tool surface** — typed actions the model can call.
2. **A loop** — call the model; if it returned `tool_use`, execute the tool(s),
   append the `tool_result`(s), call again; repeat until `stop_reason == "end_turn"`.
3. **Data on demand, not pre-stuffed** — instead of baking the snapshot into the
   system prompt, expose *read tools* so the agent pulls only what it needs. This
   is what lets the system prompt stay frozen (and cacheable) and is the whole
   point of an agent: it decides what to look at.

The loop and tool shapes are scaffolded in
`app/lib/kitchen_ai/agentic_agent.rb`. This doc is the rationale + the parts that
need decisions before it ships.

## Tool surface

Split by blast radius — this split is the design, not an afterthought.

### Read tools (auto-run, safe, parallel-safe)
| Tool | Backed by | Notes |
|---|---|---|
| `get_fleet_status` | `AskAgent#format_fleet_status` (extract to shared) | the summary we used to pre-stuff |
| `list_classes` | `KitchenSnapshot.latest` | `filter: upcoming \| sold_out \| all` |
| `get_sales_summary` | `KitchenSnapshot.tickets_sold_*` | rolling tickets/day, this week |

### Write tools (gated — see below)
| Tool | Backed by | Reversible? |
|---|---|---|
| `trigger_scrape` | `ScrapeKitchenJob.perform_later` | yes (just refreshes a snapshot) |
| `trigger_smoke_test` | GitHub `repository_dispatch` (the pattern already in `Api::V1::TelegramWebhookController#handle_smoke_request`) | yes (read-only test run) |
| `draft_social_post` | `WorkspaceAi::Drafter#suggest` → creates a **draft**, never publishes | yes (a draft) |

Deliberately **not** a tool yet: publishing a post, rotating tokens, changing
Display settings. Those are irreversible/outward-facing; keep them human-driven
until the gated path below is proven.

## The decision that blocks shipping: how do write tools get authorized?

A chat request/response cycle has no natural place to pause for "are you sure?".
Three options, cheapest first:

1. **Role gate + audit log (scaffolded default).** Write tools only run if the
   caller is workspace `owner`/`admin`; every call writes an audit row. Simple,
   no UI work. Risk: the model can trigger a scrape/smoke/draft on its own say-so
   within a turn. Acceptable for *reversible* actions (all three above are), not
   for anything destructive.
2. **Two-phase confirm (recommended before adding any irreversible tool).** The
   write tool returns a *staged action* (`{staged: true, action: "...", token}`)
   instead of executing. The loop ends, the UI renders a Confirm button, a second
   request executes the staged action. This is the `tool_confirmation` pattern,
   done manually. More UI work; the only safe option for irreversible actions.
3. **`tool_choice` allowlist per role.** Non-admins get a read-only tool set
   (write tools simply absent from `tools`); admins get the full set. Compose
   with (1) or (2).

The scaffold ships (1) + (3): role decides which tools exist, write tools
role-gate again at execution and audit-log. **Recommendation:** keep it to
reversible tools under (1) for v1; add (2) the moment we want a publish/delete tool.

## Prompt caching

Render order is `tools → system → messages`; any byte change in the prefix busts
everything after it. So:

- **Frozen system prompt** — instructions only, no date, no snapshot, no fleet
  status (all of which change constantly and would bust the cache every call).
  `cache_control: {type: "ephemeral"}` on the last system block.
- **Stable tool list** — same tools every call, so the `tools` prefix caches too.
  Put the breakpoint on the last tool def.
- **Volatile data moves into tools.** The agent calls `get_fleet_status` /
  `list_classes` when it needs them; their results land in `messages` (after the
  cached prefix), so freshness never costs us a cache miss on the expensive part.

Verify with `usage.cache_read_input_tokens > 0` on the 2nd+ call. If it's zero,
something volatile leaked into the prefix.

## Model + cost

Scaffold defaults to **`claude-haiku-4-5`**, matching `nyk_ask`/`nyk_enhance` and
NYK's cost sensitivity (usage rolls into the existing AI-cost dashboard). An
agentic loop multiplies tokens (N round trips + tool results), so caching the
system/tools prefix matters more here than in the single-shot path.

If multi-step planning across several tools proves shaky on Haiku, bump to
`claude-sonnet-4-6` (adaptive thinking, better tool sequencing) — that's a
cost/quality call for whoever owns the budget, flagged here rather than silently
chosen.

## Testing

Per repo convention (never hit the Anthropic API in tests), `AgenticAgent` keeps
the `class.stub` seam `AskAgent` already uses. A test stub returns a scripted
sequence of `tool_use` → `end_turn` responses so we can assert the loop executes
tools, feeds results back, and terminates. Tool handlers are tested directly
against fixtures (no model involved). Write-tool tests assert the role gate and
that `draft_social_post` creates a draft and does **not** publish.

## Rollout

1. Land read tools only, behind the existing `/nykitchen/ask` UI, admin-gated.
2. Dogfood on the real NYK workspace; watch the cost dashboard + cache hit rate.
3. Add `trigger_scrape` / `trigger_smoke_test` (reversible) under the role gate.
4. Add the two-phase confirm UI before any publish/destructive tool.

## Open questions

- Loop guardrail: cap iterations (scaffold uses `MAX_STEPS = 6`) so a confused
  model can't spin. Right number?
- Audit: reuse `Notification`/`ImpersonationLog` style, or a new `AgentActionLog`?
- Should `trigger_smoke_test` block on the run, or fire-and-forget and let the
  user check the hub? (Scaffold fires and returns the run id.)
