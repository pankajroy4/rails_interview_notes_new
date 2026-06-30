/*
===============================================================================================
                  ASYNCHRONOUS PATTERNS: Callbacks -> Promises -> Async/Await
===============================================================================================
The evolution of async JS. Interviewers love asking you to refactor callback hell into
async/await and to explain error handling at each stage.
*/

/*
-----------------------------------------------------------------------------------------------
Question 1: The three generations of async code
-----------------------------------------------------------------------------------------------
Answer ->
  1. CALLBACKS (the original) — pass a function to be called when the work finishes.
     Node convention: "error-first callbacks" -> callback(err, result).

  2. PROMISES (ES2015) — an object representing a future value. .then() / .catch() / .finally().
     Fixes "callback hell" by allowing chaining and centralized error handling.

  3. ASYNC / AWAIT (ES2017) — syntactic sugar over Promises. Lets you write async code that
     READS like synchronous code, with normal try/catch for errors. This is the modern default.

All three coexist; async/await is built on Promises, and Promises wrap callbacks under the hood.
*/

/*
-----------------------------------------------------------------------------------------------
Question 2: Error-first callbacks and "callback hell"
-----------------------------------------------------------------------------------------------
Answer -> Node's classic async style is the error-first callback: the FIRST argument is the
error (null if none), the rest is the result.

  const fs = require('fs');
  fs.readFile('a.txt', 'utf8', (err, data) => {
    if (err) return console.error(err);   // always handle err FIRST and return
    console.log(data);
  });

Callback hell ("pyramid of doom") happens when you nest dependent async calls:

  getUser(id, (err, user) => {
    if (err) return done(err);
    getOrders(user.id, (err, orders) => {
      if (err) return done(err);
      getPayments(orders[0].id, (err, payments) => {
        if (err) return done(err);
        // ...deeper and deeper, error handling repeated everywhere
      });
    });
  });

Problems: hard to read, error handling duplicated, hard to compose, hard to reason about flow.
Promises and async/await were invented to fix exactly this.
*/

/*
-----------------------------------------------------------------------------------------------
Question 3: Promises — states, creation, chaining
-----------------------------------------------------------------------------------------------
Answer -> A Promise has three states:
  - pending   -> initial, not yet settled
  - fulfilled -> resolved successfully with a value
  - rejected  -> failed with a reason (error)
  Once settled (fulfilled or rejected), it never changes again ("immutable" outcome).

  Creating one (usually you only do this to wrap a callback API):
    const wait = (ms) => new Promise((resolve, reject) => {
      setTimeout(() => resolve(`done after ${ms}ms`), ms);
    });

  Chaining flattens the pyramid:
    getUser(id)
      .then(user => getOrders(user.id))
      .then(orders => getPayments(orders[0].id))
      .then(payments => console.log(payments))
      .catch(err => console.error(err))   // ONE catch handles errors from ANY step
      .finally(() => console.log('always runs'));

  Key rules:
   - Returning a value from .then passes it to the next .then.
   - Returning a Promise from .then waits for it before continuing (flattening).
   - Throwing inside .then jumps to the nearest .catch.
   - A missing .catch on a rejected promise = "unhandledRejection" (can crash the process).
*/

/*
-----------------------------------------------------------------------------------------------
Question 4: Async/await — the modern way
-----------------------------------------------------------------------------------------------
Answer -> `async` marks a function that always returns a Promise. `await` pauses the function
until a Promise settles, giving you the resolved value (or throwing the rejection).

  async function getDashboard(id) {
    try {
      const user = await getUser(id);
      const orders = await getOrders(user.id);
      const payments = await getPayments(orders[0].id);
      return { user, orders, payments };
    } catch (err) {
      // catches a rejection from ANY of the awaits — clean, single handler
      logger.error('dashboard failed', err);
      throw err;   // re-throw so the caller knows (e.g. Express error middleware)
    }
  }

Why it's better: reads top-to-bottom like sync code, normal try/catch, easy to debug with
stack traces, no nesting. This is what I write 95% of the time.

GOTCHA: an async function ALWAYS returns a Promise. `const x = getDashboard(1)` gives a Promise,
not the value — you must await it or .then it.
*/

/*
-----------------------------------------------------------------------------------------------
Question 5: Sequential vs parallel awaits (a VERY common performance question)
-----------------------------------------------------------------------------------------------
Answer -> Independent async operations should run in PARALLEL, not sequentially. A naive
await-each is a classic performance bug.

  // SLOW — sequential: total time = a + b + c (each waits for the previous, though unrelated)
  const a = await getA();   // 100ms
  const b = await getB();   // 100ms
  const c = await getC();   // 100ms  => ~300ms total

  // FAST — parallel: total time = max(a, b, c) ≈ 100ms
  const [a, b, c] = await Promise.all([getA(), getB(), getC()]);

Use sequential await ONLY when later calls DEPEND on earlier results. Otherwise Promise.all.
This is the Node equivalent of fixing an N+1: you batch independent I/O so it overlaps.
*/

/*
-----------------------------------------------------------------------------------------------
Question 6: Promise combinators — all / allSettled / race / any
-----------------------------------------------------------------------------------------------
Answer ->
  Promise.all([...])
    -> resolves with an array of all results. REJECTS FAST: if ANY promise rejects, the whole
       thing rejects immediately (the others keep running but their results are discarded).
       Use when you need ALL to succeed.

  Promise.allSettled([...])
    -> NEVER rejects. Resolves with [{status:'fulfilled', value} | {status:'rejected', reason}].
       Use when you want ALL results regardless of individual failures (e.g. fan-out to N APIs
       and report which succeeded). Great for "send 100 notifications, tell me which failed."

  Promise.race([...])
    -> settles as soon as the FIRST promise settles (fulfilled OR rejected). Classic use:
       implement a timeout -> race the real call against a setTimeout that rejects.

  Promise.any([...])
    -> resolves with the first FULFILLED value; rejects only if ALL reject (AggregateError).
       Use for "try several mirrors, take whichever responds first successfully."

  // Timeout pattern with race:
  const withTimeout = (promise, ms) => Promise.race([
    promise,
    new Promise((_, reject) => setTimeout(() => reject(new Error('timeout')), ms)),
  ]);
*/

/*
-----------------------------------------------------------------------------------------------
Question 7: Common async mistakes (these are interview gold + real bugs)
-----------------------------------------------------------------------------------------------
Answer ->
  1. Forgetting `await` -> you get a pending Promise instead of the value, and thrown errors
     become unhandledRejections that bypass your try/catch.
        const user = getUser(id);          // BUG: user is a Promise
        const user = await getUser(id);     // correct

  2. await inside a forEach -> forEach does NOT wait for async callbacks.
        // BUG: forEach ignores the returned promises; "done" logs before any insert finishes
        items.forEach(async (item) => { await save(item); });
        console.log('done');
        // FIX (sequential): for...of
        for (const item of items) { await save(item); }
        // FIX (parallel):  await Promise.all(items.map(item => save(item)));

  3. Mixing callbacks and promises -> resolving/rejecting twice, or swallowing errors.
     Use util.promisify to convert a callback API to a promise instead.
        const { promisify } = require('util');
        const readFile = promisify(require('fs').readFile);
        const data = await readFile('a.txt', 'utf8');
     (Many core modules already offer promise versions: require('fs').promises / require('fs/promises').)

  4. Unhandled rejections -> always have a .catch or try/catch. In Express, wrap async handlers
     so rejections reach the error middleware (or use express-async-errors / Express 5).

  5. Creating Promises you never await -> "fire and forget" loses errors. If intentional,
     attach a .catch for logging.
*/

/*
-----------------------------------------------------------------------------------------------
Question 8: Refactor exercise — callback hell to async/await (be ready to do this live)
-----------------------------------------------------------------------------------------------
  // BEFORE (callbacks)
  function checkout(userId, cb) {
    getCart(userId, (err, cart) => {
      if (err) return cb(err);
      charge(cart.total, (err, payment) => {
        if (err) return cb(err);
        createOrder(userId, cart, payment, (err, order) => {
          if (err) return cb(err);
          cb(null, order);
        });
      });
    });
  }

  // AFTER (async/await) — assuming each function returns a Promise
  async function checkout(userId) {
    const cart = await getCart(userId);
    const payment = await charge(cart.total);
    const order = await createOrder(userId, cart, payment);
    return order;
  }
  // Errors propagate automatically; caller does try/catch. Flat, readable, testable.
*/

/*
-----------------------------------------------------------------------------------------------
Question 9: Concurrency control — don't fire 10,000 promises at once
-----------------------------------------------------------------------------------------------
Answer -> Promise.all on a huge array launches ALL of them simultaneously, which can exhaust
the DB connection pool, hit rate limits, or run the process out of memory. In production you
limit concurrency (a pool).

  // Simple batching:
  async function inBatches(items, size, worker) {
    for (let i = 0; i < items.length; i += size) {
      const batch = items.slice(i, i + size);
      await Promise.all(batch.map(worker));
    }
  }
  // Or use p-limit / p-map (popular libs), or BullMQ worker concurrency for real workloads.

This directly mirrors how I rate-limited the WhatsApp API and batched the 2M-record import in
Rails — same principle, batch + bounded concurrency, just different tools.
*/

module.exports = {};
