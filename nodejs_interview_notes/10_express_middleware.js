/*
===============================================================================================
                            EXPRESS MIDDLEWARE (deep dive)
===============================================================================================
Middleware is THE core concept of Express. If I understand middleware deeply, most of Express
falls out of it. This is the Rack-middleware / before_action equivalent from Rails.
*/

/*
-----------------------------------------------------------------------------------------------
Question 1: What is middleware, precisely?
-----------------------------------------------------------------------------------------------
Answer -> Middleware is a function with access to the request (req), the response (res), and
the `next` function. It runs during the request-response cycle and can:
  - run any code (logging, timing),
  - MODIFY req/res (attach req.user, set headers),
  - END the cycle (send a response),
  - or call next() to pass control to the NEXT middleware/handler.

  function middleware(req, res, next) {
    // do something
    next();        // pass control onward; OR res.send(...) to end here
  }

If a middleware neither responds nor calls next(), the request HANGS forever (a common bug).
*/

/*
-----------------------------------------------------------------------------------------------
Question 2: What does next() do? (the heart of the question)
-----------------------------------------------------------------------------------------------
Answer -> next() hands control to the next function in the chain. Three forms:
  - next()           -> proceed to the next middleware/route.
  - next(err)        -> SKIP all remaining normal middleware and jump straight to the
                        error-handling middleware (the 4-arg one).
  - next('route')    -> skip the rest of THIS route's handlers, go to the next matching route
                        (used with router.param / multiple handlers).

  Think of the middleware stack as a chain; next() is "yield to the next link." It's why
  ordering matters and why a missing next() stalls the request.
*/

/*
-----------------------------------------------------------------------------------------------
Question 3: The five types of middleware
-----------------------------------------------------------------------------------------------
Answer ->
  1. Application-level   -> app.use(fn) / app.get(path, fn). Runs for the app (or a path).
  2. Router-level        -> router.use(fn). Same, but scoped to a Router instance.
  3. Built-in            -> express.json(), express.urlencoded(), express.static().
  4. Third-party         -> morgan (logging), cors, helmet, cookie-parser, multer (uploads).
  5. Error-handling      -> 4 args (err, req, res, next). Registered LAST.
*/

/*
-----------------------------------------------------------------------------------------------
Question 4: Writing custom middleware — practical examples
-----------------------------------------------------------------------------------------------
Answer ->

  // (a) Request logger (a tiny morgan)
  function requestLogger(req, res, next) {
    const start = Date.now();
    res.on('finish', () => {
      console.log(`${req.method} ${req.originalUrl} ${res.statusCode} ${Date.now() - start}ms`);
    });
    next();
  }

  // (b) Auth guard (the before_action :authenticate equivalent)
  function requireAuth(req, res, next) {
    const token = req.get('Authorization')?.replace('Bearer ', '');
    if (!token) return res.status(401).json({ error: 'missing token' });
    try {
      req.user = jwt.verify(token, process.env.JWT_SECRET);   // attach user for handlers
      next();
    } catch {
      return res.status(401).json({ error: 'invalid token' });
    }
  }

  // (c) Role guard (parameterized middleware via a factory)
  function requireRole(...roles) {
    return (req, res, next) => {
      if (!roles.includes(req.user?.role)) return res.status(403).json({ error: 'forbidden' });
      next();
    };
  }

  // Usage: chain middleware before the handler (run left to right)
  app.delete('/users/:id', requireAuth, requireRole('admin'), deleteUserHandler);
*/

/*
-----------------------------------------------------------------------------------------------
Question 5: Error-handling middleware (the special 4-arg one)
-----------------------------------------------------------------------------------------------
Answer -> Express recognizes error middleware purely by its FOUR parameters. It only runs when
something calls next(err) or throws synchronously. Register it LAST.

  app.use((err, req, res, next) => {
    const status = err.statusCode || 500;
    if (status >= 500) logger.error({ err, path: req.path }, 'unhandled');
    res.status(status).json({ error: err.message || 'Internal Server Error' });
  });

  You can have multiple error middlewares (e.g. one to log, one to respond) — chain via next(err).
*/

/*
-----------------------------------------------------------------------------------------------
Question 6: The async middleware trap (Express 4) — and the fix
-----------------------------------------------------------------------------------------------
Answer -> In Express 4, if an ASYNC handler/middleware rejects, Express does NOT catch it -> it
becomes an unhandledRejection and the error middleware never runs. You must catch and next(err).

  // BROKEN in Express 4: rejection escapes, error middleware not reached
  app.get('/x', async (req, res) => { const u = await mayThrow(); res.json(u); });

  // FIX 1: wrapper
  const asyncHandler = (fn) => (req, res, next) =>
    Promise.resolve(fn(req, res, next)).catch(next);
  app.get('/x', asyncHandler(async (req, res) => { res.json(await mayThrow()); }));

  // FIX 2: the 'express-async-errors' package (monkey-patches it globally)
  // FIX 3: upgrade to Express 5, which forwards rejected promises to next() automatically.
*/

/*
-----------------------------------------------------------------------------------------------
Question 7: Essential third-party / built-in middleware to know by name
-----------------------------------------------------------------------------------------------
Answer ->
  express.json()              -> parse application/json bodies (set a size limit!)
  express.urlencoded()        -> parse form-encoded bodies
  express.static('public')    -> serve static files
  helmet()                    -> security HTTP headers (CSP, HSTS, X-Frame-Options...)
  cors()                      -> CORS headers / preflight handling
  morgan('combined')          -> HTTP request logging
  cookie-parser               -> populate req.cookies
  express-rate-limit          -> rate limiting (Rack::Attack equivalent)
  multer                      -> multipart/form-data (file uploads)
  compression                 -> gzip responses
  express-session             -> server-side sessions

  Knowing these by name lets me assemble a production-grade stack quickly — the "batteries"
  Rails includes that you bolt on yourself in Express.
*/

/*
-----------------------------------------------------------------------------------------------
Question 8: Middleware ordering — a correct production stack
-----------------------------------------------------------------------------------------------
Answer ->
  app.use(helmet());                       // 1. security headers first
  app.use(cors(corsOptions));              // 2. CORS
  app.use(express.json({ limit: '1mb' })); // 3. body parsing (limit to prevent DoS)
  app.use(express.urlencoded({ extended: true }));
  app.use(cookieParser());
  app.use(requestLogger);                  // 4. logging
  app.use(rateLimiter);                    // 5. rate limiting
  app.use('/api/v1', apiRouter);           // 6. application routes
  app.use(notFoundHandler);                // 7. 404 catch-all
  app.use(errorHandler);                   // 8. error handler (LAST, 4 args)

  Rationale: cross-cutting/security concerns first, routes in the middle, fallthrough handlers
  last. Getting this order right (and explaining WHY) is a common interview discriminator.
*/

module.exports = {};
