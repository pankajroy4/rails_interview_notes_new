Question: What is an EDI file?

Answer -> EDI stands for Electronic Data Interchange. It is a standardized format used for exchanging structured business documents between computer systems without human intervention.
Industries like automotive and retail use it heavily for things like purchase orders, invoices, and product catalogs.

In our case, we processed a large EDI Parts Master file from Volkswagen, which contained millions of fixed-width records representing spare parts and pricing information.

----------------------------------------------------------------------------------------------------------------

Question: You mentioned you optimized a job from 24 hours to 6 minutes. Can you explain exactly what you did?

Answer -> This optimization was part of a Parts Master import pipeline in a large-scale automotive claims system used by Volkswagen Group.

The system had to process 2 million fixed-width EDI records coming as a large file stored in S3. Each record represented a part with pricing, tax, and metadata.

Originally, the system was slow because it processed records sequentially, created ActiveRecord objects per line, and performed individual database writes with validations and callbacks. This resulted in millions of database round trips, which pushed execution time close to 24 hours.

I identified three main bottlenecks:
  Sequential processing of a massive file
  Per-record database inserts and updates
  Synchronous execution of heavy logic inside a single job

I redesigned the entire pipeline into a chunk-based, asynchronous, bulk-write architecture.

Instead of downloading the full file, I streamed it from S3 using byte-range reads, splitting it into predictable chunks, based on fixed-width line size.
  Each chunk processed ~20,000 lines, ensuring:
    Controlled memory usage
    Parallel execution
    Fault isolation

Each chunk was enqueued as a separate background job, allowing parallel processing across workers.
Redis was used to:
  Track total chunks
  Track processed chunks
  Trigger final aggregation once all chunks completed

Inside each chunk:
  Lines were parsed using String#unpack to avoid substring allocations
  Business validations were applied in memory
  Invalid records were skipped and logged
  Instead of saving records individually, I built a bulk write payload and used MongoDB bulk operations with upsert.

  This reduced millions of database writes to a small number of bulk operations.

  Since the file was fixed-width formatted, I used String#unpack with a template directive to extract fields efficiently in a single pass.
  It s implemented in C and avoids repeated substring allocations, which significantly improves performance when parsing millions of records.

  Tempalte Example: fields = line.unpack("x7A18A8A8x40A40A2x64A3x2A18")
            x7	-> Skip 7 bytes
            A18 -> 	Extract 18-character string

To avoid corrupting production data:
  New records were first written to a temporary collection
  Duplicate and invalid entries were tracked
  A summary report was generated before final promotion
  This ensured data safety and rollback capability.

The system also:
  Generated detailed error reports in CSV
  Aggregated per-chunk statistics
  Sent automated email notifications with processing summaries
  This made the pipeline production-ready and auditable.

As a result of:
  Chunk-based parallelism
  Bulk upsert operations
  Reduced DB round trips
  Async job processing

We reduced processing time from ~24 hours to approximately 6 minutes, while also improving reliability and observability.

 ============================= 60-SECOND VERSION =============================

We were importing around 2 million EDI part records, and the original implementation processed them sequentially with per-record database writes, which took nearly 24 hours.

I redesigned the pipeline to stream the file in chunks from S3, process each chunk asynchronously using background jobs, validate records in memory, and perform bulk upserts instead of individual inserts.

I also used a temporary collection strategy, Redis-based job tracking, and detailed error reporting.

This reduced database round trips dramatically and brought the total processing time down to around 6 minutes.

-------------------------------------------------------------------------------------------------------------
Question: If 5,000 dealers submit claims simultaneously, how would you prevent system bottlenecks?
Answer: If 5,000 dealers submit claims at the same time, my goal would be to prevent request blocking, database contention, and background job overload.

First, I would make sure the HTTP request cycle is lightweight. Any heavy validation logic, document processing, or external API calls would be offloaded to background jobs using Sidekiq. The controller should only validate essential fields and enqueue a job.

Second, I would use Redis-backed Sidekiq queues with priority separation. For example, I would have separate queues for critical claim processing and lower-priority tasks like email notifications. That prevents less important jobs from blocking business-critical ones.

Third, I would ensure proper database indexing, especially on claim reference IDs, dealer IDs, and status fields. Without indexes, concurrent inserts and lookups under heavy load would cause full table scans and lock contention.

For reporting or analytics queries, I would use read replicas so that heavy SELECT queries do not impact the primary database handling writes.

I would also apply rate limiting using Rack middleware like rack-attack, so if any dealer or IP starts sending excessive requests, we can throttle them and protect the system.

For static lookup data, such as claim types, tax percentages, or dealer configuration, I would use caching — either Redis or in-memory cache — to reduce repetitive database hits.

Additionally, I would implement optimistic locking using a lock_version column. This prevents two users from modifying the same claim simultaneously and overwriting each others changes.

So overall, my strategy would be:
  Keep requests lightweight, push heavy work to background jobs, optimize database access with indexing and replicas, protect with rate limiting, and ensure data consistency using optimistic locking.

---------------------------------- Whatsapp Bulk Messenger --------------------------------------------
Question: Suppose Meta rate limits your system. How do you handle that?
Answer: If Meta rate limits our system, I never rely on blind retries. Instead, I design the system to be rate-limit aware.

First, I implement exponential backoff retry logic. So instead of retrying immediately, the retry delay increases progressively — for example, 30 seconds, then 2 minutes, then 5 minutes. This prevents retry storms.

Second, I use dedicated Sidekiq queues specifically for WhatsApp delivery. That way, high-volume messaging does not block other critical background jobs in the system.

Third, I implement rate-limit-aware job scheduling. If the API responds with a 429 status or provides rate limit headers, I dynamically adjust job scheduling intervals based on that information.

I also use Redis-based counter throttling. For example, I maintain a per-minute or per-second counter in Redis to ensure we never exceed Metas allowed throughput. If the threshold is reached, new jobs are delayed automatically.

Additionally, I implemented a circuit breaker pattern. If the system detects repeated failures due to rate limiting, it temporarily pauses sending requests to avoid continuous API rejection.

For reliability, I store failed attempts along with retry metadata — including error codes, retry count, and last attempt timestamp.

If a job fails permanently after maximum retries, it is pushed into a dead-letter queue for manual inspection or automated alerting.

So overall, my strategy is:
  Control outbound traffic proactively, respect rate limits, retry intelligently, isolate failures, and ensure no message is silently dropped.

--------------------------------------------------------------------------------------------------------------
Question: In your CRM & ChatBot Architecture, How did you design it to be production-grade and scalable?
Answer: When designing the CRM + ChatBot system, my focus was to make it production-grade, scalable, and easy to maintain.
First, I followed the Service Object pattern. All business logic — like message processing, lead creation, conversation routing — was moved into service classes. This keeps controllers thin and prevents fat models.

Controllers were strictly responsible for request validation and response rendering. No heavy logic inside them.

I also structured the application using modular namespaces. For example, I separated CRM logic, ChatBot logic, and Webhook processing into their own namespaces. This improves clarity and prevents tight coupling between components.

Webhook controllers were completely isolated from the main application flow. Webhooks are unpredictable and must be idempotent, so I treated them as entry points that validate signatures, log payloads, and then push processing to background jobs instead of handling everything synchronously.

For asynchronous operations — like sending messages, processing replies, or triggering workflows — I used a background job pipeline with Sidekiq. This prevents blocking the request cycle and improves throughput under load.

From an observability perspective, I implemented structured logging. Each request and message had a correlation ID so we could trace flows across services. Errors were captured with proper context to make debugging easier.

Database Design
  On the database level, I ensured proper indexing, especially on phone number fields since they are heavily queried during inbound message lookup.

  I also used partial indexes for status-based queries. For example, if most queries fetch only 'active' leads, I created a partial index for records where status = 'active'. This reduces index size and improves query performance.

----------------------------------------------------------------------------------------------------------------
Question: What if Meta temporarily bans your number because of quality score drop — how would your system react automatically?

Answer: If Meta temporarily bans or restricts our WhatsApp number due to a quality score drop, my system should react automatically instead of continuing to send messages blindly.

First, I monitor delivery status webhooks and error codes very closely. If Meta returns specific restriction or quality-related error codes, I immediately flag that sender number as 'restricted' in the database.

At that point, I trigger a circuit breaker mechanism.

The circuit breaker automatically:
  Stops sending new outbound messages from that number
  Pauses related Sidekiq queues
  Marks the number as unhealthy in Redis cache

Instead of failing thousands of jobs, I redirect traffic to backup numbers if available. So I maintain a sender pool architecture. If one numbers quality drops, traffic is shifted to other healthy numbers.

For queued jobs that were about to use the banned number, I reschedule them with delayed retries instead of marking them failed immediately.

I also:
  Log the incident with structured metadata
  Send alerts via Slack or monitoring tools
  Store restriction timestamps and error payloads for auditing
  Additionally, I maintain a rate and quality monitoring service that periodically checks:
  Delivery rate
  Block rate
  User complaint rate

If quality score drops below a threshold, the system gradually reduces throughput automatically instead of waiting for a full ban.

For recovery:
  Once Meta restores the number, the circuit breaker closes automatically after a health check passes, and traffic resumes gradually — not instantly — to avoid another spike.

So overall, the strategy is: Detect early, stop damage automatically, shift traffic safely, monitor continuously, and resume gradually.

------------------------------------------------------------------------------------------------------------------------------------------------
Question: Tell me about a time you diagnosed and fixed a serious performance issue.

Answer: This was on a SaaS application — a LinkedIn outreach automation platform with a "Team Inbox" feature where users manage conversations(Incoming conversations ko review karna, prioritize karna, aur handle karn) from their assigned/connected LinkedIn accounts. 
The core query — fetch_all_conversation_ids — pulls the filtered, sorted list of conversation IDs a rep should see, and it is used both by the paginated list view and a "Focus Mode" (one-conversation-at-a-time) view.

For our larger organizations (1000+ LinkedIn profiles under one org), this query was intermittently taking 30 to over 170 seconds, causing request timeouts that surfaced to users as raw, unstyled Rails 500 error pages — both a generic "conversation failed to load" bug and a specific 500 when submitting a status change in Focus Mode.

Diagnosis: I used EXPLAIN (deliberately never EXPLAIN ANALYZE on production — that actually executes the query, which is unacceptable on a live, already-struggling query) to inspect the plan. I found Postgres was picking a catastrophic plan: instead of first filtering conversations down to the current organization (a cheap, indexed equality check) and then evaluating the correlated EXISTS subqueries (checking for messages, checking campaign_statuses), the planner was flattening one of those correlated EXISTS subqueries into a join and evaluating it globally — scanning the messages table across every organization in the system (33.7 million rows) — before ever applying the org filter. The estimated plan cost was 21–28 million cost-units, versus a healthy plan in the low hundred-thousands.

I ruled out two simpler explanations first: I ran ANALYZE messages to refresh planner statistics — no change, so it was not stale statistics. I tried the classic OFFSET 0 trick inside one EXISTS clause, which is a known (if hacky) way to force Postgres not to flatten a specific subquery — it fixed that clause, but the exact same pathology just shifted to a different EXISTS clause in the same query, and the total cost actually got worse (21M → 28M). That told me this was not a single-clause problem — it was structural: the planner was free to reorder the whole WHERE clause however it estimated was cheapest, and its estimate was wrong for our specific data skew.

Fix: I restructured the query using a WITH ... AS MATERIALIZED CTE — a Postgres 12+ feature that acts as an explicit optimization fence. Postgres is guaranteed to compute a MATERIALIZED CTE as a standalone step and can not flatten or reorder anything outside it back into it. I put every cheap, indexed, highly selective condition — organization_id, status, date range — inside the CTE, so Postgres narrows a multi-million-row table down to maybe a few hundred or low-thousand rows for that one org first. Then the correlated EXISTS/NOT EXISTS checks (messages, campaign_statuses) run only against that already-narrowed set, instead of the reverse.

In code, I split the query-building logic into two methods matching that structural boundary: apply_narrowing_conditions (everything that goes inside the CTE) and apply_existence_conditions (everything that must run outside it).

Result: EXPLAIN cost dropped from ~21–28 million to ~250K — roughly an 85–110x improvement in the planner's own cost estimate.' More importantly, I confirmed this against real production execution time, not just the estimate: across our largest orgs, the same filter scenarios that took 28 to 102+ seconds on the old query completed in 400ms to 3 seconds on the new one.

Verification, which I think is the most important part of this: A query rewrite on a core, high-traffic path is risky — "no SQL errors" isn't proof it's correct. So before deploying, I wrote a read-only comparison script and ran it against 4 real production organizations (small to our largest), across 7 different filter combinations each — 28 scenarios total — running both the old query and the new CTE query back-to-back and diffing the actual returned ID sets, not just checking for exceptions. Every single scenario returned the identical set of conversation IDs. A few scenarios showed the same set in a different order — I traced that to a pre-existing gap: the original ORDER BY had no deterministic tiebreaker on last_activity/followup_on, which are not unique columns. When many rows tie and you are at a LIMIT 2000 boundary, Postgres does not guarantee stable order among ties — so which rows land in vs. out of the top 2000 can differ purely based on the plan shape, independent of my change. I fixed that too, by appending , id to every ORDER BY clause, which made the result set fully deterministic regardless of query plan.

As a side finding during this investigation, I also discovered one of the actions this query fed into (#messages, loading a conversation's full thread) had zero exception handling — any transient failure surfaced as Rails' raw HTML 500 page straight into a JS alert(). I added proper rescue handling there too, matching the pattern already used elsewhere in the same controller (typed rescues → JSON error responses with correct status codes).'

-------------------------------------------------------------------------------------------------------------------------------------------------------------------------
Q: How do you know PostgreSQL flattened the EXISTS?
Answer: I inferred it from the execution plan. Although the SQL used correlated EXISTS subqueries, EXPLAIN showed a Hash Semi Join instead of a SubPlan. That indicates PostgreSQL had transformed the correlated EXISTS into a semi-join during optimization. In our case, that allowed it to reorder execution and scan the large messages table before applying the selective organization filter, which was the root cause of the poor plan.

-------------------------------------------------------------------------------------------------------------------------------------------------------------------------
Q: Why did Postgres's cost-based optimizer pick a bad plan in the first place — isn't that its whole job?

Answer: Cost-based optimizers estimate selectivity using table statistics (histograms, distinct-value counts) — they're heuristics, not guarantees. With correlated subqueries, Postgres has the freedom to flatten them into joins if it thinks that's cheaper, and that estimate can be wrong when data is skewed — e.g., if it estimates the EXISTS on messages will only match a handful of rows, it may prefer scanning messages first. For a single-tenant query that's often fine; in a large multi-tenant table where one EXISTS check touches millions of other orgs' rows before your org filter narrows anything, that estimate can be catastrophically wrong. This is a well-known class of Postgres planner issue — it's exactly why MATERIALIZED exists as an explicit escape hatch.

-------------------------------------------------------------------------------------------------------------------------------------------------------------------------
Q: Why not just add an index instead of restructuring the query?

Answer: I checked — the relevant columns (organization_id, conversation_id FKs) were already indexed. The problem wasn't a missing index; it was join/subquery ordering. An index makes a scan cheap once Postgres decides to do that scan in the right order — it doesn't fix the planner choosing to do the expensive scan before the cheap filter. That's a planning problem, not an access-path problem, so restructuring the query (forcing the order) was the correct fix, not indexing.

Q: What's the actual difference MATERIALIZED makes — walk me through it mechanically.

Answer: Without it, a CTE in modern Postgres (12+) is just syntactic sugar — the planner is free to inline it, meaning it treats the CTE's SELECT as if it were a subquery pasted directly into the outer query, and can reorder/merge conditions across that boundary however it wants. MATERIALIZED disables that inlining — Postgres computes the CTE fully, spools the result (like a temp table), and the outer query can only operate on that finished result. It's a hard fence the optimizer cannot cross.

-------------------------------------------------------------------------------------------------------------------------------------------------------------------------
Q: What's the downside of MATERIALIZED — when would you NOT want to force it?

Answer: Two costs: (1) if the CTE itself returns a genuinely large result set, materializing it means Postgres can't push outer filters down into it, so you lose out on cases where inlining would help; (2) it always fully computes the CTE even if the outer query only needs a few rows from it (no short-circuiting). In my case this was the right tradeoff because the CTE result — one org's conversations — is small and cheap to fully compute, and forcing that computation first was exactly the fix I needed.

-------------------------------------------------------------------------------------------------------------------------------------------------------------------------
Q: Could you have used a materialized VIEW instead?

Answer: No — a materialized view is a persisted, pre-computed object you refresh on a schedule; it'd be stale between refreshes, and this query's filters (org, status, date range, per-request params) change on every single request, so there's nothing fixed to pre-compute and cache at the DB level. MATERIALIZED on a CTE is a per-query execution hint, not a persisted object — a completely different mechanism that happens to share a name.

-------------------------------------------------------------------------------------------------------------------------------------------------------------------------
Q: How did you verify correctness beyond checking for SQL errors?

Answer: I explicitly didn't trust "it runs without errors" as proof — that only shows the syntax is valid, not that the result set is right. I wrote a script that executed both the old and new query for the exact same real filter params against real production data, across multiple orgs and filter combinations, and diffed the returned ID sets directly — not row counts, not spot checks, the actual sets. That's what caught the ordering-tiebreaker issue, which "no errors" would never have surfaced.

-------------------------------------------------------------------------------------------------------------------------------------------------------------------------
Q: Why not use EXPLAIN ANALYZE — wouldn't that give you real timing instead of just an estimate?

Answer: EXPLAIN ANALYZE actually executes the query — on a query already taking 30–170 seconds and already causing production issues, running it repeatedly just to diagnose would itself add load and risk. I stuck to plan-only EXPLAIN for diagnosis (safe, read-only, no execution) and only measured real timing later, via the actual application logs once I ran the verification comparison — which gave me real execution numbers without deliberately hammering a struggling query on production.

-------------------------------------------------------------------------------------------------------------------------------------------------------------------------
Q: You tested 4 organizations — how confident are you that generalizes to every org?

Answer: I deliberately picked orgs across the size spectrum, including our largest — the one most likely to expose the exact pathology I was fixing, since it's a data-skew-driven planner issue that shows up more as table sizes grow. The query logic itself is org-agnostic — no org-specific conditionals — so there's no reason to expect different orgs to hit different code paths. I called out that this wasn't literally exhaustive when I made the deploy decision — the fix is a plain controller change with no data migration, so if any org did misbehave, rollback is a single revert, not a data recovery problem.

-------------------------------------------------------------------------------------------------------------------------------------------------------------------------
Q: Explain the "same set, different order" bug in more detail — why does a missing tiebreaker cause a different result, not just different order, at a LIMIT boundary?

Answer: If you ORDER BY last_activity ASC LIMIT 2000 and, say, 50 rows all share the exact same last_activity value sitting right at the boundary — with only 1,980 slots left before hitting 2000 — Postgres has to pick which 30 of those 50 tied rows go in the top 2000. Without a tiebreaker, that choice depends on whatever order the scan happens to visit them in, which depends on the query plan. Two different plans (old flat query vs. new CTE) can visit tied rows in different orders, so they can each legitimately pick a different arbitrary 30 out of that tied group. It's not a bug in either plan individually — it's that the query never specified a deterministic result in the first place. Adding id as a final tiebreaker means there's only ever one correct ordering, so the result is the same no matter which plan runs it.

-------------------------------------------------------------------------------------------------------------------------------------------------------------------------
Q: What would you monitor after deploying this, and what's your rollback plan?

Answer: Post-deploy I'd watch error/exception tracking for a few minutes for any new SQL errors, and manually exercise the feature on our largest org to confirm load times and pagination behave correctly. Rollback is low-risk here specifically because this is a pure query-logic change in one controller — no schema migration, no data mutation — so a straight git revert and redeploy fully undoes it with no cleanup needed.

-------------------------------------------------------------------------------------------------------------------------------------------------------------------------
Q: Any performance cost to adding id to every ORDER BY clause?

Answer: Negligible — id is the primary key, always indexed, and it's only a tiebreaker (last sort key), so it only affects rows that are already tied on the primary sort column, which in practice is a small fraction of rows. It doesn't change which index or scan strategy Postgres picks for the dominant sort.


===========================
Question: Walk me through the AI conversation feature you built — how does it work end to end?
Answer → This was an AI-powered conversation-assistance feature inside a LinkedIn outreach automation platform (Castanet), used by outreach teams handling hundreds of prospect conversations daily across campaigns.

The problem: every incoming LinkedIn reply had to be read by a rep from scratch, with no visibility into how engaged or interested the prospect actually was. At volume, this meant slow response times and inconsistent messaging quality across the team.

I designed and built the full pipeline, end to end:

Entry point: A Unipile webhook handler receives every inbound LinkedIn message. When a message is from the prospect (not us), it enqueues a background job — this keeps the webhook itself fast and idempotent, and pushes the actual AI work off the request cycle.

Classification + generation, in one call: The background worker resolves the right "Conversation Agent" for that conversation (campaign-specific agent takes priority; falls back to the LinkedIn profile's default agent otherwise) and calls a service that builds a system prompt (the agent's own instructions plus a shared guardrail block) and sends it to GPT-4o in JSON mode. Critically, I designed this as one LLM call, not two — it returns both the suggested reply text and a 4-level interest classification (High/Medium/Neutral/Low) in the same structured response. That halves the API cost and latency versus running separate classification and generation calls, and avoids the two signals ever disagreeing with each other since they come from the same reasoning pass.

Prompt generation from business context: Rather than a human hand-writing a 100+ line system prompt per client, I built a service that takes structured business context (offering, ideal customer profile, primary goal, social proof, booking link, etc.) and merges it into a reusable meta-prompt template via an LLM call, producing a complete, ready-to-use agent prompt automatically.

Human-in-the-loop refinement: Reps or clients can improve an agent's behavior two ways — free-form instructions on the agent settings page, or by giving feedback on a specific rejected suggested reply. Either path goes through the same refinement service, which is deliberately instructed to generalize the feedback into a broad rule rather than hard-coding the example as a canned response, and returns a diff. That diff is shown for review — it's never auto-applied — before it's saved and starts influencing live conversations.

Display and workflow: The suggestion is shown to the rep inside a "Focus Mode" — a single-conversation review queue I also helped build for high-volume triage — with the interest level shown as a colored icon. Whenever a new suggestion is generated for a conversation, any previous active suggestion for it is automatically dismissed, so a rep is never looking at a stale one.

Safety, since this talks to real prospects: every generated prompt has a dedicated anti-hallucination instruction block appended at generation time — regardless of whatever the client's own edited prompt says — specifically forbidding fabricated case studies, statistics, or client names. And since the whole feature is advisory (never auto-sends anything), if the OpenAI call fails or times out for any reason, the worker just returns early — the rep sees no suggestion that cycle, but their normal manual workflow is completely unaffected. No error, no broken UI.

============================= 60-SECOND VERSION =============================

I built an AI suggested-reply feature for a LinkedIn outreach platform. Every inbound reply triggers a background job that calls GPT-4o once to both classify the prospect's interest level and draft a suggested reply, shown to the rep in a focused single-conversation review queue.

I also built a system that auto-generates each client's agent prompt from their business context via an LLM meta-prompt, plus a human-in-the-loop refinement flow where feedback on a rejected reply gets turned into a generalized prompt rule — reviewed as a diff before it's applied.

Because this talks directly to real prospects, I built in a hard anti-hallucination guardrail on every prompt and made the whole feature fail gracefully — if the AI call fails, the rep's normal workflow is unaffected, nothing breaks.



Likely Cross-Questions + Answers
Q: Why combine reply-generation and interest classification into a single LLM call instead of two separate calls?

Cost and latency — one GPT-4o call instead of two, using JSON-mode structured output so I get a typed {reply, interest_level} object back reliably. It also avoids a subtle consistency bug: if you classify and generate separately, you can end up with a reply that reads as enthusiastic while the classifier scores the prospect "Low" — because they're two independent reasoning passes over the same conversation. One call means one coherent read of the conversation drives both outputs.

Q: How do you stop the AI from hallucinating facts about the client's business — fake case studies, wrong pricing, invented results?

Every agent prompt gets a dedicated factual-accuracy guardrail block injected at generation time, on top of whatever the client's own prompt says — explicitly instructing the model to never invent statistics, testimonials, or client names, and to fall back to the closest real example provided instead of fabricating one. It's appended server-side every time a reply is generated, so it can't be accidentally stripped out even if a client's stored prompt gets edited or refined later.

Q: What happens if the OpenAI API call fails, times out, or returns something unparseable?

The service returns nil on any failure — HTTP error, blank API key, JSON parse error — and the worker just returns early without creating a suggestion. Because this feature is purely advisory and never auto-sends anything, a failure has zero blast radius: the rep just doesn't see a suggestion for that message and replies manually, exactly as they would if the feature didn't exist. I deliberately designed it so a bad AI response degrades to "no assistance," never to a broken or incorrect UI state.

Q: How do you let non-developers change the AI's behavior without touching code?

Two paths, both going through the same refinement service. One is free-form instructions on the agent settings page ("stop mentioning pricing in the first message"). The other is reacting to a specific rejected suggestion with feedback on why it was wrong. In both cases the LLM is explicitly instructed to extract the general principle behind the request and edit the relevant section of the existing prompt, rather than pasting the example back verbatim as a hardcoded canned response — that's what makes it generalize instead of just memorizing one correction.

Q: Why show a diff and require a review step instead of applying the refined prompt immediately?

Because an LLM-rewritten prompt can over-generalize or introduce behavior nobody asked for, and this prompt is about to start controlling live conversations with real prospects — that's not something I wanted auto-applied blind. Showing the diff lets a human sanity-check the actual before/after wording in one glance before it goes live. The refine endpoint and the apply endpoint are two separate actions specifically so nothing is saved until someone reviews it.

Q: How do you decide which agent's prompt to use, if a profile is running multiple campaigns?

Priority order: first, the specific campaign tied to the conversation's active, non-network/non-blacklist campaign status — so different active campaigns on the same profile can run different pitches or personas. If there's no campaign-specific agent, it falls back to the LinkedIn profile's most recently created agent, so there's always a sane default rather than silently generating nothing.

Q: How would this scale if inbound message volume grew 50x — where's the bottleneck?

Each inbound message is one Sidekiq job making one synchronous OpenAI HTTP call with a 60-second timeout. At real scale the bottleneck shifts to OpenAI's own rate limits and cost, and Sidekiq concurrency on that queue. I'd isolate this onto its own dedicated queue so a burst of AI jobs can't starve other background work, add rate-limit-aware backoff on 429s, and consider de-duplicating near-identical low-signal replies (like repeated "thanks!" messages) before spending an API call classifying something that's almost certainly benign.

Q: The interest level is a qualitative High/Medium/Neutral/Low label rather than a numeric confidence score — was that a deliberate choice?

Yes — this signal is meant for a human to glance at (shown as a colored icon next to the suggestion), not to drive an automated decision, so a coarse, human-readable label was the right fit. If this were feeding an automated action instead of a human's judgment — for example auto-continuing a sequence or auto-dismissing a conversation without review — I'd want a numeric confidence score with an explicit threshold, precisely because a wrong automated action is far more costly than a rep glancing past an imprecise label.


----------------------------------------------


Question: Walk me through the Decision Engine you built — how does it work end to end?

Answer → This was a follow-up project on the same LinkedIn outreach platform, building on top of the existing AI suggested-reply feature. The client's ask was: if incoming replies could be auto-classified and routed, roughly 75% of daily inbound messages (benign "thanks for connecting" replies, and clear "not interested" replies) could be handled without a human ever touching them — leaving Team Inbox for only the conversations that genuinely need judgment.

The key design constraint the client gave me: never risk the existing, live app. So I built it around three non-negotiable rules:

1.Additive-only — no existing method or endpoint gets edited. New behavior lives in new files/classes/columns that call existing, already-tested action endpoints (Resume Sequence, Not Interested) unchanged.
2.Off-by-default flag, checked inside the new code, not at the call site — the webhook handler that receives inbound messages gets exactly one new line added (enqueuing a new worker), never a branch that replaces the existing suggested-reply worker call. Both workers just run; the new one self-gates internally.
3.Shadow mode before any action — first ship classify-and-log-only, where nothing actually happens. Validate accuracy against real conversations. Only then enable real actions, one bucket at a time, lowest-risk first.

Pipeline: same inbound-webhook entry point as the suggested-reply feature enqueues a second worker. That worker resolves whether the triggering campaign has the feature flag on; if so, it calls a standalone classifier service — a separate GPT-4o call (JSON mode) from the suggested-reply one, because it's answering a fundamentally different question. The suggested-reply classifier scores a 4-level interest gradient for a human to read; this one sorts into 4 mutually-exclusive routing buckets: continue (benign, resume the sequence), not_interested (send the decline response and dismiss), dismiss (benign reply but the lead is already closed/resolved — no message, just close it), and needs_human (the default — leave it in Team Inbox, today's normal behavior).

For 2+ months this ran in pure shadow mode — every classification was written to a log table with action_taken: nil, visible to nobody except an internal report. I validated it against real dev conversations first, then against real production data once the client enabled it on a pilot campaign, before any action-taking code was even written.

Only after the client reviewed real report data and confirmed accuracy did I build the second phase: a decision_engine_actions_enabled flag that lets the same classification actually act — calling the exact same continue_sequence/not_interested endpoints a rep's manual click already calls — gated by a confidence threshold, rolled out lowest-risk action first.

============================= 60-SECOND VERSION =============================

I built a Decision Engine that auto-classifies every inbound LinkedIn reply into 4 outcomes — continue sequence, not interested, dismiss (already-closed lead), or needs human — and routes the first three to existing, already-tested action endpoints instead of a rep clicking them manually.

I shipped it shadow-mode first: for weeks it only classified and logged, took zero action, so we could validate accuracy against real production data with no risk. Only after the client confirmed accuracy did I add a second flag that lets it actually act, gated by a 90%+ confidence threshold, rolling out the lowest-risk actions first and the highest-risk one (Not Interested) last, after a dedicated refactor.

Every flag is off by default and is an instant kill switch — flipping it false makes the feature fully inert for that campaign with no deploy needed.

Likely Cross-Questions + Answers

Q: Why build a second classifier instead of reusing the existing 4-level interest classifier from the suggested-reply feature?

They answer different questions. The existing classifier scores an interest gradient (High/Medium/Neutral/Low) for a human to glance at — it's advisory, imprecise-by-design, never drives an action. The Decision Engine needs a routing decision — which of 4 mutually exclusive buckets, because a wrong bucket now triggers a real action (a real message sent, or a real conversation closed). Overloading one classifier to serve both purposes would mean any prompt tweak for one use case risks silently breaking the other. Keeping them fully independent — separate service, separate prompt, intentionally duplicated transcript-building logic rather than shared — meant I could iterate on one without any risk of regressing the other, which had already been live in production for months.

Q: Why shadow mode first instead of just launching with actions on and monitoring for problems?

Because the failure modes aren't symmetric. A false-positive "not interested" auto-dismiss can permanently lose a real, engaged lead — there's no undo once a decline message is sent and the conversation is closed out. Monitoring-after-launch only tells you about damage that already happened. Shadow mode gives you the same accuracy signal — real classifications against real conversations — with the cost of a wrong classification being literally zero, since nothing acts on it. I only greenlit real actions once I'd manually spot-checked shadow-mode output against the actual conversation text and the client had independently reviewed a report and confirmed it looked right.

Q: How did you land on 90% as the confidence threshold, and why not lower it to catch more cases automatically?

That number came directly from the client, not an arbitrary engineering choice — I asked how confident the engine should be before acting, and the answer was "very high, especially at the start; once the system's proven itself we can lower it." There was no exact number given, so 90% was my interpretation of "very high," documented explicitly as an interpretation rather than presented as their literal number — and it's a single constant in the worker, trivially adjustable later. The reasoning for starting high: the cost of a false positive (a lost lead) is much higher than the cost of a false negative (a message just sits in Team Inbox a little longer, which is today's default behavior anyway) — so an asymmetric, conservative threshold is the correct tradeoff until there's a track record to justify loosening it.

Q: You said "continue sequence" was zero-touch but "not interested" wasn't — what does that mean, and why the difference?

"Continue sequence" already had its logic sitting in a clean, reusable controller action, so the worker could call it directly with zero refactoring. "Not interested" was different — its logic lived inline inside the Team Inbox controller's manual-click action, mixed in with session-bound concerns like marking messages read and evicting a cache. Before the worker could safely call it, I had to extract the actual business logic (resolve the campaign status, decide whether to send a decline message or just dismiss) into a standalone service, while deliberately leaving the session-bound pieces in the controller since a background worker has no HTTP session to act on. I verified this extraction very carefully — including confirming, by reading the actual send-message method, that none of my test conversations could trigger a real outbound LinkedIn API call — because this is literally the highest-risk action in the whole feature.

Q: How do you tell the difference in your data between an action a human took and one the engine took automatically?

I added a source field to the existing lead-status-event logging — user_manual for a rep's click, automation for the engine — reusing a value that already existed in the codebase's enum but had never been wired up to anything. The human-click path passes the real user_id; the automated path passes user: nil with source: automation. I verified both paths produce distinguishable audit rows for the exact same underlying action, which matters both for debugging (was this a bad AI call or a rep mistake?) and for eventually answering the client's original "what % is actually automated" question with real numbers instead of an estimate.

Q: What happens if the classifier call fails or times out?

It fails safe, not silent. If the OpenAI call returns nothing after a retry, the worker treats that exactly like a needs_human classification — it logs the failure with an error field for later debugging, but takes no action and leaves the conversation for a rep, which is the same outcome as if the feature didn't exist at all for that message. I also added a single immediate retry inside the shared OpenAI service for transient network timeouts specifically because I hit one during manual testing — confirmed it was transient by retrying the identical call and having it succeed — and made that fix generically, since the existing suggested-reply feature shares the same underlying service and benefits from the same retry.

Q: The client only confirmed 3 specific statuses count as "already closed" — what happened with the ones they didn't confirm, like "Won"?

I was careful not to silently invent scope the client hadn't signed off on — the prompt's example list only contains the exact statuses they confirmed. But because this is an LLM classifying by meaning rather than string-matching a literal list, I found during verification that it still correctly classified a "Won" conversation as dismiss even though "Won" isn't in the prompt anywhere — it reasoned that a closed deal shouldn't get outreach messages either, the same way it did for the confirmed statuses. That's arguably correct behavior, but it's also model generalization the client didn't explicitly approve, so I flagged it back to them as an open question rather than treating it as a bug to suppress or a feature to quietly rely on.

Q: Given a single flag now controls all three actions together, what's the actual blast radius if the classifier is wrong on a campaign that has the flag on?

For continue and dismiss, the blast radius is low — worst case a sequence resumes a bit early, or a conversation gets tucked away that a rep would have tucked away themselves anyway. For not_interested, it's real — a wrong call could send an unwanted decline message or close out an engaged lead. That's exactly why the flag decision was explicit and documented as a risk tradeoff, not something I assumed silently: the client chose one combined flag over three separate ones for simplicity, which I implemented as asked, but I made sure the confidence threshold and shadow-mode validation happened before that flag existed at all, so by the time any campaign could reach that blast radius, the classifier already had a validated track record on real data.

Q: How would you actually measure whether this hits the client's ~75% target?

That's not something you get from a single test — it needs a real rollout period across live campaigns with the audit-trail source field I added, counting what fraction of inbound replies get an automation-sourced resolution versus landing in Team Inbox for a human. I was explicit with the client that 75% was their estimate going in, not a number I'd verified — proving it out is a longer-running rollout-and-measure phase, not something you can claim from dev testing.
