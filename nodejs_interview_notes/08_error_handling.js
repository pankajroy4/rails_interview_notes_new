/*
===============================================================================================
                       ERROR HANDLING (production-grade) & GRACEFUL SHUTDOWN
===============================================================================================
Error handling in async, single-threaded Node is genuinely different from Rails' rescue_from.
This is a strong place to show production maturity (my resume claims prod systems + reliability).
*/

/*
-----------------------------------------------------------------------------------------------
Question 1: The categories of errors in Node
-----------------------------------------------------------------------------------------------
Answer ->
  1. Operational errors  -> expected runtime problems you should HANDLE gracefully:
     failed DB connection, 404, invalid user input, request timeout, third-party API down.
     These are normal; the app recovers (return a 4xx/5xx, retry, fallback).

  2. Programmer errors (bugs) -> defects in code: calling undefined, passing wrong types,
     forgetting await. You can't "handle" these meaningfully — you FIX them. The right response
     is often to log, alert, and let the process restart clean (crash-only design).

Knowing this distinction is itself a senior signal: "I handle operational errors; I let
programmer errors crash and rely on a process manager to restart, rather than catching
everything and limping along in a corrupt state."
*/

/*
-----------------------------------------------------------------------------------------------
Question 2: The four ways errors propagate in Node
-----------------------------------------------------------------------------------------------
Answer ->
  1. throw / try-catch        -> synchronous code AND inside async/await.
  2. error-first callbacks    -> callback(err, result); check err first.
  3. Promise rejection        -> .catch() or try/catch around await.
  4. 'error' events           -> on EventEmitters/streams; unhandled 'error' crashes the process.

  The big trap: a try/catch does NOT catch errors thrown in a callback that runs LATER on a
  different tick. The catch has already exited by then.

  try {
    setTimeout(() => { throw new Error('boom'); }, 0);  // NOT caught by this try/catch
  } catch (e) { /* never runs */ }

  But try/catch DOES catch awaited rejections, because await keeps you "inside" the function:
  try { await mightReject(); } catch (e) { /* caught */ }
*/

/*
-----------------------------------------------------------------------------------------------
Question 3: try/catch with async/await — the modern default
-----------------------------------------------------------------------------------------------
Answer ->
  async function getUser(id) {
    try {
      const user = await db.users.findById(id);
      if (!user) throw new NotFoundError('user not found');   // operational error
      return user;
    } catch (err) {
      // log with context, then decide: rethrow, return fallback, or map to HTTP status
      logger.error({ id, err }, 'getUser failed');
      throw err;
    }
  }

  Best practice: create custom error classes that carry an HTTP status + code, so the layer
  that maps errors to responses (Express error middleware) can stay generic.

  class AppError extends Error {
    constructor(message, statusCode = 500, code = 'INTERNAL') {
      super(message);
      this.name = this.constructor.name;
      this.statusCode = statusCode;
      this.code = code;
      this.isOperational = true;     // distinguishes expected errors from bugs
      Error.captureStackTrace(this, this.constructor);
    }
  }
  class NotFoundError extends AppError { constructor(m='Not found'){ super(m,404,'NOT_FOUND'); } }
  class ValidationError extends AppError { constructor(m){ super(m,422,'VALIDATION'); } }
*/

/*
-----------------------------------------------------------------------------------------------
Question 4: Centralized error handling in Express (the rescue_from equivalent)
-----------------------------------------------------------------------------------------------
Answer -> Express error-handling middleware has a special FOUR-argument signature (err first).
It must be registered LAST, after all routes. All errors funnel here for consistent responses.

  // error middleware — note the 4 args; Express identifies it by arity
  function errorHandler(err, req, res, next) {
    const status = err.statusCode || 500;
    const body = {
      error: {
        code: err.code || 'INTERNAL',
        message: err.isOperational ? err.message : 'Something went wrong',  // hide internals
      },
    };
    if (status >= 500) logger.error({ err, path: req.path }, 'request failed');
    res.status(status).json(body);
  }
  app.use(errorHandler);   // MUST be after routes

  GOTCHA: in Express 4, a thrown error inside an ASYNC route handler does NOT automatically
  reach this middleware — you must catch it and call next(err), or wrap handlers:

  const asyncHandler = (fn) => (req, res, next) => Promise.resolve(fn(req, res, next)).catch(next);
  app.get('/users/:id', asyncHandler(async (req, res) => {
    const user = await getUser(req.params.id);   // if this rejects, next(err) is called
    res.json(user);
  }));
  // Express 5 forwards rejected promises to error middleware automatically.
*/

/*
-----------------------------------------------------------------------------------------------
Question 5: uncaughtException and unhandledRejection (the process-level safety nets)
-----------------------------------------------------------------------------------------------
Answer ->
  process.on('uncaughtException', (err) => {
    // a synchronous error escaped all try/catch. The app state may now be CORRUPT.
    logger.fatal(err, 'uncaughtException');
    // Best practice: log, then EXIT and let the process manager restart a clean process.
    process.exit(1);
  });

  process.on('unhandledRejection', (reason) => {
    // a Promise rejected with no .catch. In modern Node this also terminates by default.
    logger.fatal(reason, 'unhandledRejection');
    process.exit(1);
  });

  CRITICAL PHILOSOPHY: these handlers are for LOGGING and crashing cleanly, NOT for "keep
  running no matter what." After an uncaughtException the process is in an unknown state;
  continuing risks serving corrupt data or leaking resources. Let it die and restart (PM2,
  Docker/k8s, systemd will bring up a fresh process). This is the "crash-only / let it crash"
  philosophy (also Erlang's idea).
*/

/*
-----------------------------------------------------------------------------------------------
Question 6: Graceful shutdown (zero-downtime deploys + not dropping requests)
-----------------------------------------------------------------------------------------------
Answer -> On SIGTERM (what Docker/k8s/PM2 send to stop a process), don't just die — finish
in-flight work, then close connections. This prevents dropped requests and corrupted jobs
during deploys.

  const server = app.listen(3000);

  async function shutdown(signal) {
    logger.info(`${signal} received, shutting down gracefully`);
    server.close(async () => {            // 1. stop accepting NEW connections
      try {
        await db.close();                 // 2. close DB pool
        await redis.quit();               // 3. close Redis
        await worker.close();             // 4. let BullMQ finish current job, stop taking new
        logger.info('clean shutdown complete');
        process.exit(0);
      } catch (err) {
        logger.error(err, 'error during shutdown');
        process.exit(1);
      }
    });
    // 5. failsafe: force-exit if cleanup hangs
    setTimeout(() => { logger.error('forced shutdown'); process.exit(1); }, 10000).unref();
  }

  process.on('SIGTERM', () => shutdown('SIGTERM'));
  process.on('SIGINT', () => shutdown('SIGINT'));   // Ctrl-C in dev

  This is a great thing to volunteer — it shows I think about deploys and reliability, which
  ties to my "fault-tolerant pipelines / 99.9% uptime" resume claims.
*/

/*
-----------------------------------------------------------------------------------------------
Question 7: Practical rules / checklist
-----------------------------------------------------------------------------------------------
Answer ->
  - Always handle the 'error' event on streams and emitters.
  - Always await (or .catch) every Promise; never fire-and-forget without a .catch.
  - Wrap async Express handlers so rejections reach error middleware.
  - Use custom error classes with statusCode + isOperational; map them centrally.
  - Don't leak internals (stack traces, SQL) to clients in production responses.
  - Log with context (request id, user id) using a structured logger (pino/winston), not
    console.log, in production. Add a correlation/request id per request.
  - Let programmer errors crash; rely on a process manager to restart.
  - Implement graceful shutdown on SIGTERM/SIGINT.
  - Validate input at the edge so bad data becomes a clean 4xx, not a deep crash.
*/

module.exports = {};
