/*
===============================================================================================
            MY REAL PROJECTS, RE-TOLD IN NODE.JS TERMS  (the most important file)
===============================================================================================
These are MY actual production stories (Horizon EDI import, WhatsApp bulk messenger/CRM),
translated from my real Rails/Resque/Mongoid implementation into how I'd build/explain the SAME
system in Node.js. For a 3.5-year interview, THIS is what gets me hired — I'm not reciting
theory, I'm describing systems I genuinely built, with the same engineering decisions.

The rule: keep the architecture and the reasoning identical (that's what's real); only swap the
tools (Resque->BullMQ, Mongoid->Mongoose, String#unpack->Buffer parsing, S3 ruby SDK->aws-sdk v3).
*/

/* =============================================================================================
   PROJECT 1 — HORIZON: the 24-hours -> 6-minutes EDI Parts Master import
   (Volkswagen Group UK / KIA Ireland claim-management platform)
   ============================================================================================= */

/*
-----------------------------------------------------------------------------------------------
Q1: Tell me about a performance optimization you're proud of. (THE flagship story)
-----------------------------------------------------------------------------------------------
Answer (full version) ->
  "On Horizon, a transit-damage claim platform for Volkswagen Group UK, we imported the EDI
   Parts Master file — about 2 million fixed-width records (606 bytes per line) representing
   spare parts with pricing, tax, and metadata, delivered as one large file in S3.

   The original implementation took ~24 hours because it (1) processed the file sequentially,
   (2) created one ORM object per line and did per-record DB writes with validations and
   callbacks — millions of round trips — and (3) ran all of that synchronously in a single job.

   I redesigned it into a chunked, asynchronous, bulk-write pipeline. Three levers did the work:
     1. STREAM the file from S3 in byte-range chunks (never download the whole 600MB+ file).
     2. Fan out each chunk as a separate background job so workers process them in PARALLEL.
     3. Replace per-record writes with BULK UPSERTS, collapsing millions of writes into a
        handful of bulk operations.
   I tracked progress in Redis (total vs processed chunks) to know when to run final
   aggregation, wrote to a TEMPORARY collection first for safety, and generated an error CSV +
   email summary so the import was auditable and production-ready. End result: ~24h -> ~6 min,
   plus far better reliability and observability."

  Same three levers I'd state in any language: STREAMING + PARALLELISM + BULK DB OPS.
*/

/*
-----------------------------------------------------------------------------------------------
Q2: How exactly did you stream a huge file from S3 without running out of memory? (Node version)
-----------------------------------------------------------------------------------------------
Answer -> In Rails I used S3 byte-range reads (get_object with range: "bytes=start-end") and
fixed-width line math. In Node it's the same idea with aws-sdk v3 — request explicit byte ranges
so I only ever hold one chunk (~20k lines) in memory at a time.

  const { S3Client, GetObjectCommand } = require('@aws-sdk/client-s3');
  const s3 = new S3Client({ region });

  const LINE_BYTESIZE = 606;          // bytes per fixed-width record (same constant as my Rails code)
  const LINES_PER_CHUNK = 20000;      // ~20k lines per chunk
  const CHUNK_BYTES = LINE_BYTESIZE * LINES_PER_CHUNK;

  async function* readChunks(bucket, key) {
    let startByte = 0;
    let remainder = '';                                  // carry an incomplete line across chunks
    while (true) {
      const endByte = startByte + CHUNK_BYTES - 1;
      const res = await s3.send(new GetObjectCommand({
        Bucket: bucket, Key: key, Range: `bytes=${startByte}-${endByte}`,
      }));
      const body = await streamToString(res.Body, 'latin1');  // res.Body is a Node stream
      const data = remainder + body;

      const lines = data.split(/\r?\n/);
      remainder = lines.pop();                            // last item may be a partial line
      yield lines;

      if (Number(res.ContentLength) < CHUNK_BYTES) break; // last chunk (short read)
      startByte += CHUNK_BYTES;
    }
    if (remainder) yield [remainder];                     // flush the final partial line
  }

  KEY POINTS to say:
   - I read EXACT byte ranges, so memory stays flat regardless of file size (constant ~12MB/chunk).
   - I carry a `remainder` across chunk boundaries because a 606-byte record can be split across
     two byte-range reads — exactly the `remaining_line` handling in my Rails code.
   - I detect the last chunk when the returned ContentLength is shorter than the requested range.
   - latin1/binary encoding avoids mangling the fixed-width byte offsets (the file isn't UTF-8 clean).
*/

/*
-----------------------------------------------------------------------------------------------
Q3: The records are FIXED-WIDTH. In Ruby you used String#unpack. How in Node?
-----------------------------------------------------------------------------------------------
Answer -> Ruby's String#unpack("x7A18A8...") parses fixed-width fields in one C-level pass with
no substring allocations. Node has no unpack, so I parse by BYTE OFFSETS off a Buffer (or fixed
substrings), which is the same single-pass, allocation-light idea.

  // a tiny declarative field map = the unpack template, but explicit
  // [name, offset, length]  (offsets/lengths in BYTES, matching the EDI spec)
  const FIELDS = [
    ['materialNumber', 7, 18],     // x7 then A18  -> ET2000_part_no
    ['creationDate',  25, 8],      // A8
    ['lastUpdated',   33, 8],      // A8
    ['description',   81, 40],     // A40
    ['division',     121, 2],
    ['dangerousGoods',187, 3],
    ['discountCode', 212, 2],
    ['hpgCode',      219, 18],
    ['retailPrice',  530, 15],
    ['taxCode',      584, 1],
  ];

  function parseFixedWidthLine(buf) {            // buf = a Buffer for one 606-byte line
    const out = {};
    for (const [name, offset, len] of FIELDS) {
      out[name] = buf.toString('latin1', offset, offset + len).trim();
    }
    return out;
  }

  WHY Buffer offsets (the senior detail): like unpack, slicing a Buffer by byte position avoids
  creating throwaway substrings for the whole line and reads each field in one pass — important
  when you're doing this 2 million times. I also clean non-ASCII bytes and skip records that
  don't start with the record marker "M" (and skip suppression types "M"/"O") — the exact same
  validation gating I had in Ruby.
*/

/*
-----------------------------------------------------------------------------------------------
Q4: How did you parallelize the chunks? (Resque -> BullMQ)
-----------------------------------------------------------------------------------------------
Answer -> In Rails each chunk was enqueued as a separate Resque job
(Resque.enqueue(VwgPartsPriceUploadFileChunkProcessor, ...)) so multiple workers processed chunks
concurrently. In Node that's BullMQ: the producer streams the file and enqueues one job per chunk;
a worker pool with concurrency processes many chunks at once.

  // producer: stream + fan out one job per chunk
  const { Queue } = require('bullmq');
  const chunkQueue = new Queue('edi-parts-chunks', { connection });

  async function importPartsFile({ bucket, key }) {
    const totalKey = `chunks:${key}:total`, processedKey = `chunks:${key}:processed`;
    await redis.mset(totalKey, 0, processedKey, 0);

    let chunkNo = 0, total = 0;
    for await (const lines of readChunks(bucket, key)) {
      chunkNo += 1; total += 1;
      await chunkQueue.add('process-chunk',
        { chunkNo, lines, fileKey: key },
        { attempts: 3, backoff: { type: 'exponential', delay: 2000 },
          removeOnComplete: true });
    }
    await redis.set(totalKey, total);   // now workers can detect "all done"
  }

  // worker: many chunks in parallel
  const { Worker } = require('bullmq');
  new Worker('edi-parts-chunks', processChunk, { connection, concurrency: 8 });

  Talking points: each chunk job is INDEPENDENT (fault isolation — one bad chunk doesn't fail the
  rest, and it retries on its own), and concurrency lets me use all worker capacity. This is the
  exact chunk-based parallelism from my Rails design, just BullMQ instead of Resque.
*/

/*
-----------------------------------------------------------------------------------------------
Q5: How did you turn millions of writes into a few? (bulk upsert + Redis tracking + temp collection)
-----------------------------------------------------------------------------------------------
Answer -> Inside each chunk worker: parse + validate in memory, build ONE bulkWrite payload of
upserts, write it to a TEMPORARY collection, then use Redis counters to detect the last chunk and
run final aggregation/promotion. This mirrors my Mongoid `bulk_write([{ replace_one: {...,
upsert: true } }])` to a PartTemporary collection.

  async function processChunk(job) {
    const { chunkNo, lines, fileKey } = job.data;
    const ops = [];
    const stats = { valid: 0, invalid: 0, skipped: 0, errors: [] };

    for (const rawLine of lines) {
      const buf = Buffer.from(rawLine, 'latin1');
      if (buf.length < LINE_BYTESIZE - 2) { stats.invalid++; continue; }     // length guard
      if (rawLine[0] !== 'M') continue;                                       // record marker
      const supp = rawLine.substr(191, 1);
      if (supp === 'M' || supp === 'O') { stats.skipped++; continue; }        // suppression types

      try {
        const part = validatePart(parseFixedWidthLine(buf));                  // in-memory validation
        if (!part.ok) { stats.invalid++; stats.errors.push(part.error); continue; }
        ops.push({
          replaceOne: {
            filter: { cardPartNumber: part.value.cardPartNumber },
            replacement: part.value,
            upsert: true,                                                      // upsert == insert-or-update
          },
        });
        stats.valid++;
      } catch (e) { stats.invalid++; stats.errors.push({ line: rawLine, msg: e.message }); }
    }

    // ONE round trip for the whole chunk instead of 20k writes; ordered:false => independent ops
    if (ops.length) await PartTemporary.bulkWrite(ops, { ordered: false });

    await persistChunkStats(chunkNo, stats);                                  // per-chunk summary (like my .json files)

    // Redis progress tracking -> final aggregation when the last chunk lands
    const processed = await redis.incr(`chunks:${fileKey}:processed`);
    const total = Number(await redis.get(`chunks:${fileKey}:total`));
    if (processed === total) await finalizeImport(fileKey);                   // aggregate + notify + promote
  }

  WHY this is the whole game (say all of this):
   - bulkWrite sends MANY ops in ONE network round trip -> millions of writes become a few
     thousand bulk calls. This single change is most of the 24h -> 6min.
   - ordered:false: independent docs, the server keeps going past a failing op and parallelizes better.
   - upsert: insert-or-update keyed on cardPartNumber — needs an INDEX on that field or every
     upsert is a collection scan (I create that index on the temp collection up front).
   - TEMPORARY collection first: I never mutate the live Part collection mid-import. I load into
     PartTemporary, verify counts + duplicates, then promote — so a bad file can't corrupt prod
     and I can roll back. (Same safety strategy as my Rails code.)
   - REDIS counters (incr processed, compare to total) are how distributed parallel workers agree
     on "everything's done" so exactly one of them runs the final aggregation + email.
*/

/*
-----------------------------------------------------------------------------------------------
Q6: How did you make it auditable / production-ready? (error report + notifications + recovery)
-----------------------------------------------------------------------------------------------
Answer -> Same operational polish as my Rails version:
   - Per-chunk stats persisted (counts: total lines, lines starting with M, skipped suppression
     types, unsupported encoding, validation failures, valid parts) then aggregated at the end.
   - DUPLICATE DETECTION during aggregation (a cardPartNumber seen twice across chunks is flagged).
   - An ERROR REPORT CSV of invalid records (part no, description, error message, line) generated
     with a csv writer and attached to the summary.
   - EMAIL NOTIFICATION to the uploader with the summary + the CSV (nodemailer instead of ActionMailer).
   - On failure: clean up enqueued chunk jobs and reset the Redis counters so a re-run starts clean
     (my clean_failed_jobs equivalent — BullMQ: drain/obliterate the queue + reset keys).
   - Structured logging per chunk with the chunk number for traceability.

  // CSV error report (the generate_error_report_csv equivalent)
  const { stringify } = require('csv-stringify/sync');
  function buildErrorCsv(invalidRecords) {
    return stringify(invalidRecords, { header: true,
      columns: ['ET2000PartNo', 'descriptionEnglish', 'errorMessage', 'line'] });
  }

  This is the part that signals real production experience: I didn't just make it fast, I made it
  SAFE (temp collection + verification) and OBSERVABLE (stats, error CSV, email, logs).
*/

/*
-----------------------------------------------------------------------------------------------
Q7: 60-second version (have this memorized)
-----------------------------------------------------------------------------------------------
Answer ->
  "We imported ~2 million fixed-width EDI part records from an S3 file. The original code processed
   them sequentially with per-record DB writes — about 24 hours. I redesigned it: stream the file
   from S3 in byte-range chunks of ~20k lines so memory stays flat, fan each chunk out as its own
   BullMQ job so workers process them in parallel, parse the fixed-width fields by byte offset, and
   replace per-record writes with a single bulk upsert per chunk into a temporary collection.
   Redis counters track chunk progress so the last worker triggers aggregation, duplicate
   detection, an error-report CSV, and an email summary, after which the verified data is promoted
   to the live collection. That cut it from ~24 hours to ~6 minutes and made it reliable and
   auditable. In Rails I built this with Resque and Mongoid; the Node version is the same
   architecture with BullMQ and Mongoose."
*/

/*
-----------------------------------------------------------------------------------------------
Q8: 5,000 dealers submit claims simultaneously — how do you prevent bottlenecks? (Node version)
-----------------------------------------------------------------------------------------------
Answer -> Same strategy I gave for the Rails system, mapped to Node:
   1. KEEP THE REQUEST LIGHTWEIGHT: the Express handler only validates essential fields and
      enqueues a job; all heavy validation, document processing, and external API calls go to a
      BullMQ worker. (In Node this matters double — heavy sync work would block the event loop for
      EVERY dealer, not just one request.)
   2. PRIORITY QUEUES: separate BullMQ queues for critical claim processing vs low-priority work
      (emails/notifications), so non-critical jobs never starve business-critical ones.
   3. DB INDEXING on claim reference id, dealer id, and status — without them, concurrent inserts
      + lookups cause scans and lock contention.
   4. READ REPLICAS for reporting/analytics SELECTs so heavy reads don't hit the write primary.
   5. RATE LIMITING (express-rate-limit with a Redis store) to throttle any dealer/IP flooding us.
   6. CACHING (Redis) for static lookup data — claim types, tax %, dealer config — to cut repeat DB hits.
   7. OPTIMISTIC LOCKING (a version column) so two users editing the same claim can't silently
      overwrite each other; a stale update returns 409 and retries.
   8. SCALE OUT: multiple stateless API instances (cluster/PM2/k8s) behind a load balancer +
      a separately-scaled worker tier, all sharing Redis/DB.
   "Keep requests thin, push heavy work to queues, index + replicate the DB, rate-limit, cache
    lookups, and protect consistency with optimistic locking."
*/

/* =============================================================================================
   PROJECT 2 — WHATSAPP BULK MESSENGER, CHATBOT & CRM (Meta WhatsApp Cloud API)
   ============================================================================================= */

/*
-----------------------------------------------------------------------------------------------
Q9: Walk me through the architecture of your WhatsApp platform in Node.
-----------------------------------------------------------------------------------------------
Answer -> Same production-grade design I built in Rails, expressed in Node:
   - SERVICE LAYER: all business logic (message processing, lead creation, conversation routing)
     lives in service modules; Express controllers only validate + respond. Thin controllers,
     no fat models. (file 19 layering.)
   - MODULAR STRUCTURE: CRM, ChatBot, and Webhook processing are separate modules/namespaces to
     avoid tight coupling.
   - WEBHOOK ISOLATION + IDEMPOTENCY: webhook endpoints are isolated entry points that VERIFY the
     signature, LOG the payload, ACK fast with 200 (Meta requires a quick response), then push the
     work to a BullMQ queue. Handlers are idempotent (keyed on the WhatsApp message id) because
     Meta can redeliver the same webhook.
   - ASYNC PIPELINE: sending messages, processing replies, triggering workflows all run in BullMQ
     workers so the request cycle never blocks and throughput stays high under load.
   - OBSERVABILITY: structured logging (pino) with a CORRELATION ID per message so I can trace a
     flow end-to-end; errors captured with context.
   - DB DESIGN: indexes on phone-number fields (heavily queried on inbound lookup), and PARTIAL
     indexes for status-based queries (e.g. index only where status='active') to keep the index
     small and fast.

  // webhook endpoint: verify -> ack fast -> enqueue (never process inline)
  app.post('/webhooks/whatsapp', verifyMetaSignature, async (req, res) => {
    res.sendStatus(200);                                  // ACK immediately
    for (const event of extractEvents(req.body)) {
      await inboundQueue.add('inbound', event, {
        jobId: `wa:${event.messageId}`,                   // idempotency: de-dupe redelivered webhooks
      });
    }
  });
*/

/*
-----------------------------------------------------------------------------------------------
Q10: Meta rate-limits your system. How do you handle it? (my real answer, Node tools)
-----------------------------------------------------------------------------------------------
Answer -> I make the sender rate-limit AWARE, never blind-retry:
   1. EXPONENTIAL BACKOFF on retries (e.g. 30s -> 2m -> 5m) so retries don't storm.
        outboundQueue.add('send', msg, { attempts: 6, backoff: { type: 'exponential', delay: 30000 } });
   2. DEDICATED OUTBOUND QUEUE for WhatsApp delivery so high-volume messaging doesn't block other jobs.
   3. RATE-LIMIT-AWARE SCHEDULING: BullMQ's limiter caps throughput to Meta's allowance, and if the
      API returns 429 / rate-limit headers, I dynamically delay (respect Retry-After).
        new Worker('wa-outbound', sendMessage, { connection, limiter: { max: 80, duration: 1000 } });
   4. REDIS COUNTER THROTTLING: a per-second/per-minute counter in Redis (INCR + EXPIRE) so I never
      exceed allowed throughput; when the threshold is hit, new jobs are delayed automatically.
   5. CIRCUIT BREAKER: on repeated rate-limit failures, trip open and pause sending to stop hammering
      a rejecting API; close again after a health check (opossum).
   6. FAILURE METADATA: store error code, retry count, last-attempt timestamp on each failed attempt.
   7. DEAD-LETTER QUEUE: jobs that exhaust retries go to a failed set for inspection/alerting — no
      message is ever silently dropped.
   "Control outbound traffic proactively, respect limits, retry intelligently, isolate failures,
    and guarantee nothing is dropped." (Word-for-word my Rails answer; BullMQ replaces Sidekiq.)
*/

/*
-----------------------------------------------------------------------------------------------
Q11: Meta temporarily bans your number on a quality-score drop. How does the system react
     automatically? (sender-pool + circuit breaker — a strong senior answer)
-----------------------------------------------------------------------------------------------
Answer -> It must react automatically instead of blindly sending:
   - MONITOR delivery-status webhooks + error codes closely. On a restriction/quality error code,
     immediately flag that sender number as 'restricted' in the DB and mark it 'unhealthy' in Redis.
   - TRIP A CIRCUIT BREAKER for that number: stop new outbound from it, PAUSE its BullMQ queue
     (queue.pause()), and cache the unhealthy state in Redis so all instances see it.
   - SENDER POOL ARCHITECTURE: I maintain a pool of sender numbers; if one number's quality drops,
     traffic SHIFTS to other healthy numbers instead of failing thousands of jobs.
   - RESCHEDULE, don't fail: queued jobs targeting the banned number get delayed retries (re-routed
     to a healthy number), not marked failed.
   - ALERT + AUDIT: log the incident with structured metadata, alert via Slack/monitoring, store
     restriction timestamps + error payloads for auditing.
   - PROACTIVE QUALITY MONITORING: a service periodically checks delivery rate, block rate, complaint
     rate; if quality dips below a threshold, it GRADUALLY REDUCES throughput rather than waiting
     for a full ban.
   - GRADUAL RECOVERY: once Meta restores the number, the breaker closes after a health check and
     traffic resumes GRADUALLY (ramp up, not instant) to avoid another spike.
   "Detect early, stop damage automatically, shift traffic safely, monitor continuously, resume
    gradually." Node implements this with BullMQ pause/resume per sender queue, opossum circuit
    breakers, and Redis for the shared health state — same design I built with Sidekiq + Redis.
*/

/*
-----------------------------------------------------------------------------------------------
Q12: Why is Node actually a GOOD fit for this WhatsApp system? (turn the switch into a strength)
-----------------------------------------------------------------------------------------------
Answer ->
  "This workload is almost entirely I/O-bound — receiving webhooks, calling the Meta API, reading/
   writing the DB — which is exactly where Node's single-threaded non-blocking event loop excels.
   Thousands of concurrent webhook deliveries and outbound calls are cheap because the loop juggles
   waiting I/O instead of needing a thread per request. The fault-tolerant pieces — rate-limited
   workers, retries with backoff, idempotent handlers, circuit breakers, sender pools — map directly
   onto BullMQ + Redis + opossum. So everything I built on Sidekiq translates cleanly, and the
   real-time/high-concurrency nature of messaging plays to Node's strengths."
*/

/*
-----------------------------------------------------------------------------------------------
Q13: How would you describe these projects on the spot, given you're moving from Rails?
-----------------------------------------------------------------------------------------------
Answer (the honest, confident framing) ->
  "I built these in Ruby on Rails, but they're architecture-and-fundamentals stories, not
   framework trivia. The EDI optimization is about streaming, parallelism, and bulk DB operations;
   the WhatsApp platform is about idempotent webhook processing, rate-limit-aware queues, and
   circuit breakers. None of that is Rails-specific — in Node I'd build the identical systems with
   BullMQ instead of Sidekiq/Resque, Mongoose instead of Mongoid, aws-sdk v3 for S3, and the event
   loop actually makes the I/O-heavy parts a better fit. I understand WHY each decision was made,
   which is what lets me rebuild them in a new stack rather than just having used a gem."
*/

module.exports = {};
