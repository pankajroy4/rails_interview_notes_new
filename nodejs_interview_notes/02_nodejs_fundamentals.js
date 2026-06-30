/*
===============================================================================================
                              NODE.JS FUNDAMENTALS / ARCHITECTURE
===============================================================================================
*/

/*
-----------------------------------------------------------------------------------------------
Question 1: What is Node.js? (the answer that shows you actually understand it)
-----------------------------------------------------------------------------------------------
Answer -> Node.js is a JavaScript runtime built on Chrome's V8 engine that lets you run
JavaScript OUTSIDE the browser, typically on a server. It is NOT a language and NOT a
framework — it's a runtime environment.

The key design idea: Node uses an event-driven, non-blocking I/O model on a single main
thread. That makes it lightweight and efficient for I/O-heavy workloads (APIs, real-time
apps, proxies) where the program spends most of its time waiting on the network or disk.

Two pieces make Node what it is:
  1. V8       -> Google's engine that compiles JavaScript to fast machine code (JIT).
  2. libuv    -> a C library that gives Node its event loop, async I/O, and a thread pool.

INTERVIEW SOUNDBITE:
  "Node is V8 plus libuv plus a standard library. V8 executes the JavaScript, and libuv
   provides the event loop and asynchronous I/O so a single thread can handle thousands of
   concurrent connections without a thread per request."

(Coming from Rails: Node is to JavaScript what MRI/CRuby is to Ruby — the runtime. Express
 is the framework on top, like Rails is on top of Ruby.)
*/

/*
-----------------------------------------------------------------------------------------------
Question 2: What is V8?
-----------------------------------------------------------------------------------------------
Answer -> V8 is Google's open-source JavaScript engine, written in C++, originally for Chrome.
It does NOT interpret JS line by line forever — it Just-In-Time (JIT) compiles JavaScript into
optimized machine code.

How V8 runs code (high level):
  - Parser turns source into an AST (abstract syntax tree).
  - Ignition (interpreter) generates and runs bytecode quickly.
  - TurboFan (optimizing compiler) watches "hot" code (run many times) and recompiles it to
    highly optimized machine code, making assumptions about types ("this is always a number").
  - If those assumptions break (you suddenly pass a string), V8 "deoptimizes" back to bytecode.

Practical takeaway: keep object shapes / types consistent (don't keep mutating an object's
structure or mixing types in an array) so V8 can stay in optimized code. This is the JS
equivalent of "don't fight the optimizer."

Node embeds V8 and adds APIs V8 doesn't have on its own — like file system, networking,
buffers, and the event loop (those come from Node + libuv, not from V8 or the language).
*/

/*
-----------------------------------------------------------------------------------------------
Question 3: What is libuv? (almost always a follow-up)
-----------------------------------------------------------------------------------------------
Answer -> libuv is the C library that powers Node's asynchronous, non-blocking behavior.
V8 only knows how to run JavaScript; it has no idea how to read a file or open a socket.
libuv provides:
  - The EVENT LOOP (the heart of Node — see 03_event_loop.js).
  - Asynchronous I/O using the OS's best mechanism (epoll on Linux, kqueue on macOS,
    IOCP on Windows) for network sockets.
  - A THREAD POOL (default 4 threads) for operations the OS can't do async natively —
    file system operations, DNS lookups (getaddrinfo), and some crypto (pbkdf2, bcrypt).

This is the crucial nuance that trips people up:
  - Network I/O is handled by the OS kernel asynchronously, NOT by the thread pool.
  - File I/O and CPU-ish crypto are handled by the libuv THREAD POOL (because most OSes
    don't offer truly async file APIs).

You can change the pool size: process.env.UV_THREADPOOL_SIZE = '8' (set BEFORE Node starts).

INTERVIEW SOUNDBITE:
  "People say Node is single-threaded, and the JavaScript IS single-threaded, but libuv keeps
   a small thread pool — 4 by default — for file system and some crypto work. So Node is
   single-threaded for your code, but multi-threaded under the hood for certain I/O."
*/

/*
-----------------------------------------------------------------------------------------------
Question 4: "Is Node single-threaded?" — the precise answer
-----------------------------------------------------------------------------------------------
Answer -> The right answer is "yes and no, and here's the distinction":

  - YES, single-threaded for JavaScript execution. There is ONE event loop thread that runs
    all your JS callbacks. Your code never runs on two threads at once (no data races in JS).

  - NO, not single-threaded overall. libuv has a thread pool (default 4) for file I/O, DNS,
    and some crypto. Network I/O is offloaded to the OS kernel. And modern Node also gives you
    worker_threads if you explicitly want to run JS on other threads for CPU-bound work.

Why this matters: because JS is single-threaded, a CPU-heavy synchronous operation (a big
loop, sync hashing, huge JSON.parse) BLOCKS the event loop, freezing every connection. The
fix is to make work async (I/O), offload to worker_threads, or push it to a background job.

THIS is the question I must nail. Coming from Rails: in Rails, a slow request ties up one
Puma worker; in Node, a slow SYNCHRONOUS operation ties up the whole server.
*/

/*
-----------------------------------------------------------------------------------------------
Question 5: Blocking vs non-blocking — show it in code
-----------------------------------------------------------------------------------------------
Answer -> Blocking = the next line can't run until this finishes. Non-blocking = the call
returns immediately and you get the result later via a callback/promise.

  const fs = require('fs');

  // BLOCKING (synchronous) — freezes the event loop until the file is fully read.
  const data = fs.readFileSync('/big-file.txt');   // nothing else runs meanwhile
  console.log(data.length);

  // NON-BLOCKING (asynchronous) — returns instantly; loop keeps serving others.
  fs.readFile('/big-file.txt', (err, data) => {
    if (err) throw err;
    console.log(data.length);
  });
  console.log('this prints BEFORE the file is read');

Rule of thumb: anything ending in `...Sync` (readFileSync, execSync) blocks the loop. Avoid
them in request-handling code. They're fine at startup (loading config once) or in CLI scripts.
*/

/*
-----------------------------------------------------------------------------------------------
Question 6: Why is Node good for some things and bad for others?
-----------------------------------------------------------------------------------------------
Answer ->
GOOD FOR (I/O-bound, high-concurrency):
  - REST/GraphQL APIs, BFFs (backend-for-frontend)
  - Real-time apps: chat, notifications, live dashboards (WebSockets) — fits my WhatsApp project
  - Streaming (video, file uploads), proxies, API gateways
  - Microservices that mostly forward/aggregate I/O
  Reason: most time is spent waiting on network/DB, and the event loop juggles thousands of
  waiting connections cheaply.

BAD FOR (CPU-bound):
  - Heavy computation: image/video processing, ML, big cryptography, complex math, giant
    in-memory sorts. A single CPU-heavy task blocks the loop and kills throughput.
  Mitigation: worker_threads, child processes, native addons, or offload to a job queue /
  a different service.

INTERVIEW SOUNDBITE:
  "Node shines for I/O-bound, high-concurrency workloads and struggles with CPU-bound work
   on the main thread. For CPU-heavy tasks I reach for worker_threads or push the job to a
   queue, the same separation of concerns I used with Sidekiq in Rails."
*/

/*
-----------------------------------------------------------------------------------------------
Question 7: What are globals in Node? (process, __dirname, etc.)
-----------------------------------------------------------------------------------------------
Answer -> Node provides globals you don't `require`:

  - process       -> info + control of the current process: process.env, process.argv,
                     process.cwd(), process.pid, process.exit(), process.on('SIGTERM', ...),
                     process.nextTick(), process.memoryUsage().
  - console       -> logging (console.log/error/warn).
  - Buffer        -> raw binary data (pre-dates Uint8Array typed arrays).
  - __dirname     -> absolute path of the current module's directory (CommonJS only).
  - __filename    -> absolute path of the current file (CommonJS only).
  - require       -> import modules (CommonJS).
  - module, exports -> the current module + its exports (CommonJS).
  - global        -> the global object (like window in the browser); avoid polluting it.
  - setTimeout / setInterval / setImmediate / queueMicrotask -> timing primitives.

  In ES Modules, __dirname/__filename don't exist; you derive them from import.meta.url.

  process.env is how you read config (like ENV in Rails). dotenv loads a .env file into it.
*/

/*
-----------------------------------------------------------------------------------------------
Question 8: The Node process model — how a server stays alive
-----------------------------------------------------------------------------------------------
Answer -> A Node program runs its top-level code, then keeps running as long as there is
something keeping the event loop alive — an open server socket, a pending timer, an open
file handle, etc. When there's nothing left to do, Node exits.

  const http = require('http');
  const server = http.createServer((req, res) => {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ ok: true }));
  });
  server.listen(3000, () => console.log('listening on 3000'));
  // The open listening socket keeps the process alive — it doesn't exit after this line.

This is why a script with a setInterval never exits, and a script that just defines a function
exits immediately. Understanding "what keeps the loop alive" explains a lot of Node behavior.
*/

/*
-----------------------------------------------------------------------------------------------
Question 9: How does Node differ from a browser JS environment?
-----------------------------------------------------------------------------------------------
Answer -> Same language (JavaScript), same engine family (V8), but different host APIs:

  BROWSER                                NODE
  ------------------------------------   --------------------------------------
  window / document / DOM                no DOM; `global` / `globalThis`
  fetch (native), XHR                    fetch (native since v18) / http module
  localStorage / cookies                 file system, process.env
  Web APIs (alert, navigator)            OS APIs (fs, net, os, child_process)
  modules: ESM (import)                  CommonJS (require) AND ESM
  security sandboxed                     full OS access (read files, open sockets)

Both share the event loop concept, Promises, async/await, and core JS. The skills transfer;
the host objects differ.
*/

/*
-----------------------------------------------------------------------------------------------
Question 10: What's in the Node standard library I should know?
-----------------------------------------------------------------------------------------------
Answer -> Core modules (no install needed, prefix with `node:` is the modern style):

  http / https   -> create servers and clients
  fs             -> file system (fs.promises for async/await style)
  path           -> cross-platform path joining (path.join, path.resolve)
  os             -> CPU count (os.cpus().length — used for clustering), memory, platform
  crypto         -> hashing, encryption, random bytes, uuid (crypto.randomUUID())
  events         -> EventEmitter (the base class lots of Node is built on)
  stream         -> Readable/Writable/Transform streams
  url            -> URL parsing
  util           -> util.promisify, util.inspect
  cluster        -> fork the process across CPU cores
  worker_threads -> real threads for CPU-bound JS
  child_process  -> spawn external processes (exec, spawn, fork)
  zlib           -> gzip/deflate compression

  Knowing these signals seniority — you reach for built-ins before npm packages when possible.
*/

module.exports = {};
