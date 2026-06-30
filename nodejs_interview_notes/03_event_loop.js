/*
===============================================================================================
                       THE EVENT LOOP  (the single most-asked Node topic)
===============================================================================================
If I can explain the event loop clearly, I look senior. If I fumble it, I look junior.
Memorize the phases AND the microtask rule. This file is worth re-reading the night before.
*/

/*
-----------------------------------------------------------------------------------------------
Question 1: What is the event loop?
-----------------------------------------------------------------------------------------------
Answer -> The event loop is the mechanism (provided by libuv) that lets single-threaded Node
perform non-blocking I/O. It continuously checks queues of pending callbacks and runs them
when the call stack is empty, so the one JS thread can juggle thousands of operations that are
"waiting" (on the DB, network, disk) without blocking.

Mental model:
  - JS has ONE call stack. Functions run one at a time.
  - When you start an async operation (setTimeout, DB query, file read), Node hands it off to
    libuv / the OS / the thread pool and your code keeps going.
  - When that operation finishes, its callback is placed into a queue.
  - The event loop's job: whenever the call stack is empty, pull the next ready callback from
    the appropriate queue and push it onto the stack to run.

(This is the SAME event loop concept from my browser JavaScript notes — Node just has more
 phases and adds process.nextTick + setImmediate.)
*/

/*
-----------------------------------------------------------------------------------------------
Question 2: The phases of the event loop (MEMORIZE THIS ORDER)
-----------------------------------------------------------------------------------------------
Answer -> Each full iteration of the loop is a "tick" and goes through these phases in order:

  ┌───────────────────────────┐
  │           timers          │  <- runs callbacks from setTimeout() and setInterval()
  ├───────────────────────────┤
  │     pending callbacks     │  <- runs some system/OS callbacks (e.g. certain TCP errors)
  ├───────────────────────────┤
  │       idle, prepare       │  <- internal use only
  ├───────────────────────────┤      ┌───────────────┐
  │           poll            │ <----│  incoming I/O │  <- retrieves new I/O events; runs I/O
  ├───────────────────────────┤      └───────────────┘     callbacks (file read done, socket data)
  │           check           │  <- runs setImmediate() callbacks
  ├───────────────────────────┤
  │      close callbacks      │  <- runs 'close' events (e.g. socket.on('close'))
  └───────────────────────────┘

The 3 you actually talk about in interviews: TIMERS, POLL, CHECK.
  - timers: setTimeout / setInterval callbacks whose time has elapsed.
  - poll:   the heart — waits for and processes I/O (your DB/file/HTTP callbacks happen here).
  - check:  setImmediate callbacks run right after poll.

CRUCIAL RULE: between EACH phase (and after each individual callback in modern Node), the loop
DRAINS the microtask queues — first process.nextTick queue, then the Promise microtask queue.
That's why Promises/nextTick always run before the next timer or I/O callback.
*/

/*
-----------------------------------------------------------------------------------------------
Question 3: Microtasks vs macrotasks (the rule that explains all the tricky outputs)
-----------------------------------------------------------------------------------------------
Answer ->
  MACROTASKS (a.k.a. tasks): setTimeout, setInterval, setImmediate, I/O callbacks. Each event
  loop phase processes macrotasks of its type.

  MICROTASKS: process.nextTick callbacks and Promise .then/.catch/.finally (and await
  continuations) and queueMicrotask. These run BETWEEN macrotasks / between phases, and the
  loop fully DRAINS the microtask queue before moving on.

  PRIORITY within microtasks: process.nextTick queue is drained BEFORE the Promise microtask
  queue. nextTick is "even more urgent" than a resolved Promise.

So the ordering priority, highest first:
  1. Currently running synchronous code (the call stack)
  2. process.nextTick queue        (microtask, highest)
  3. Promise microtask queue        (microtask)
  4. macrotasks by phase: timers -> poll(I/O) -> check(setImmediate) -> close
*/

/*
-----------------------------------------------------------------------------------------------
Question 4: The classic output-ordering puzzle
-----------------------------------------------------------------------------------------------
Answer -> Predict the output:

  console.log('1: sync start');

  setTimeout(() => console.log('2: setTimeout'), 0);
  setImmediate(() => console.log('3: setImmediate'));

  Promise.resolve().then(() => console.log('4: promise'));
  process.nextTick(() => console.log('5: nextTick'));

  console.log('6: sync end');

  OUTPUT:
    1: sync start
    6: sync end
    5: nextTick        <- microtask, nextTick drained first
    4: promise         <- microtask, promise queue next
    2: setTimeout      <- timers phase (usually before immediate at top level... see note)
    3: setImmediate    <- check phase

  Explanation:
   - All synchronous code runs first: "1" then "6".
   - Call stack empties -> drain microtasks: nextTick ("5") before Promise ("4").
   - Then macrotasks: setTimeout(0) in timers phase, setImmediate in check phase.

  NOTE / GOTCHA: setTimeout(0) vs setImmediate ordering at the TOP LEVEL is NON-deterministic
  — it depends on how fast the process started relative to the 1ms timer floor. But INSIDE an
  I/O callback, setImmediate ALWAYS runs before setTimeout(0), because after poll you go
  straight to the check phase. This is a favorite trick question.
*/

/*
-----------------------------------------------------------------------------------------------
Question 5: setTimeout vs setImmediate vs process.nextTick — when to use which
-----------------------------------------------------------------------------------------------
Answer ->
  setTimeout(fn, 0)   -> "run in the timers phase of a FUTURE tick." Has a minimum ~1ms delay.
  setImmediate(fn)    -> "run in the check phase, right after the current poll phase completes."
                         Use it to run AFTER I/O callbacks in the same iteration.
  process.nextTick(fn)-> "run BEFORE the loop continues, as soon as the current operation ends,
                         before any I/O or timers." It's a microtask with the HIGHEST priority.

  Inside an I/O callback, the deterministic ordering is:
    process.nextTick  >  Promise.then  >  setImmediate  >  setTimeout

DANGER: process.nextTick can STARVE the event loop. Because nextTick callbacks are drained
completely before the loop proceeds, a recursive nextTick will never let I/O run:

  function loop() { process.nextTick(loop); }  // BAD: starves the loop forever, no I/O ever runs
  function loop() { setImmediate(loop); }       // OK: yields to the loop each iteration

Rule of thumb: prefer setImmediate over process.nextTick unless you specifically need to run
something before any I/O (e.g. deferring an error callback to keep APIs consistently async).
*/

/*
-----------------------------------------------------------------------------------------------
Question 6: "Don't block the event loop" — concrete examples
-----------------------------------------------------------------------------------------------
Answer -> Blocking the loop means running synchronous code that takes a long time, so no other
callbacks (no other requests!) can run. Common culprits:

  - A long for/while loop doing computation.
  - JSON.parse / JSON.stringify on a HUGE object (it's synchronous).
  - fs.readFileSync, crypto.pbkdf2Sync, bcrypt sync variants, zlib sync.
  - Catastrophic-backtracking regexes (ReDoS) on attacker-controlled input.
  - A big array .sort() / .map() over millions of items.

  // BAD: blocks every other request for the duration of this loop
  app.get('/sum', (req, res) => {
    let total = 0;
    for (let i = 0; i < 1e10; i++) total += i;   // freezes the whole server
    res.json({ total });
  });

  FIXES:
  - Make it async I/O if possible (it usually is — it's the CPU work that's the problem).
  - Offload CPU work to worker_threads (see 18_performance_and_scaling.js).
  - Break the work into chunks with setImmediate so the loop can breathe between chunks.
  - Push it to a background job (BullMQ) if it doesn't need an immediate response.
  - Use streaming for large data instead of buffering it all in memory.

How to detect blocking in prod: monitor "event loop lag/delay" (perf_hooks.monitorEventLoopDelay,
or clinic.js / 0x). Rising loop lag = something is blocking.
*/

/*
-----------------------------------------------------------------------------------------------
Question 7: How does async/await interact with the event loop?
-----------------------------------------------------------------------------------------------
Answer -> `await` does NOT block the thread. When you `await` a Promise, the function pauses,
returns control to the event loop, and the rest of the function (the "continuation" after the
await) is scheduled as a MICROTASK once the Promise resolves.

  async function handler() {
    console.log('A');                 // sync
    await Promise.resolve();          // yields here
    console.log('B');                 // runs as a microtask after A's sync code
  }
  handler();
  console.log('C');
  // Output: A, C, B   (B is the continuation, scheduled as a microtask)

So `await someDbCall()` lets the single thread go serve other requests while the DB works,
then resumes your function when the data is ready. This is exactly why Node handles high
concurrency on one thread: awaiting frees the loop.
*/

/*
-----------------------------------------------------------------------------------------------
Question 8: Putting it all together — the whole-server mental model
-----------------------------------------------------------------------------------------------
Answer (the story I tell in an interview) ->

  "Node runs my JavaScript on a single thread driven by the libuv event loop. When a request
   comes in and I `await` a database call, Node hands that I/O to the OS or the libuv thread
   pool and immediately frees the loop to handle other requests. When the DB responds, the
   callback is queued; the event loop, once the stack is clear, drains microtasks
   (nextTick then Promises) and then processes the phase queues — timers, poll for I/O, check
   for setImmediate. Because the thread is never blocked on I/O, one process serves thousands
   of concurrent connections. The only thing that breaks this is synchronous CPU-heavy work,
   which I keep off the main thread using worker_threads or a job queue."
*/

module.exports = {};
