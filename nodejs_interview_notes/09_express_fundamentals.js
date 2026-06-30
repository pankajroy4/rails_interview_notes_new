/*
===============================================================================================
                          EXPRESS FUNDAMENTALS (the "Rails" of Node, sort of)
===============================================================================================
Express is the most common Node web framework. Unlike Rails it is MINIMAL — it gives you
routing + middleware and nothing else (no ORM, no structure, no conventions). That freedom is
the #1 thing to discuss: "how do you add the structure Rails gives you for free?"
*/

/*
-----------------------------------------------------------------------------------------------
Question 1: What is Express and how does it compare to Rails?
-----------------------------------------------------------------------------------------------
Answer -> Express is a minimal, unopinionated web framework for Node built around two ideas:
routing (map HTTP method + path -> handler) and middleware (a chain of functions each request
passes through). It's a thin layer over Node's http module.

  RAILS                          EXPRESS
  ----------------------------   -----------------------------------------------
  Full framework, opinionated    Minimal, you assemble your own stack
  ActiveRecord built in          Bring your own ORM (Sequelize/Prisma/Mongoose)
  Convention over configuration  Almost no conventions — you decide everything
  Generators, scaffolding        None
  Rack middleware                Express middleware (very similar concept)
  routes.rb                      app.get/post + Router
  before_action                  middleware that calls next()
  rescue_from                    error-handling middleware (err,req,res,next)

  If I want Rails-like structure/opinions in Node, the answer is NestJS (see 22_nestjs.js).
*/

/*
-----------------------------------------------------------------------------------------------
Question 2: A minimal Express app
-----------------------------------------------------------------------------------------------
Answer ->
  const express = require('express');
  const app = express();

  app.use(express.json());                 // built-in middleware: parse JSON request bodies

  app.get('/health', (req, res) => {
    res.json({ status: 'ok' });
  });

  app.get('/users/:id', (req, res) => {
    res.json({ id: req.params.id });       // route params
  });

  app.post('/users', (req, res) => {
    const { name, email } = req.body;       // populated by express.json()
    res.status(201).json({ name, email });
  });

  const PORT = process.env.PORT || 3000;
  app.listen(PORT, () => console.log(`listening on ${PORT}`));
*/

/*
-----------------------------------------------------------------------------------------------
Question 3: The request (req) and response (res) objects
-----------------------------------------------------------------------------------------------
Answer ->
  REQUEST (req):
    req.params      -> route params  (/users/:id -> req.params.id)
    req.query       -> query string  (?page=2&limit=10 -> req.query.page)
    req.body        -> parsed body   (needs express.json()/urlencoded middleware)
    req.headers     -> request headers (req.get('Authorization'))
    req.method      -> 'GET', 'POST', ...
    req.path / req.originalUrl
    req.cookies     -> needs cookie-parser
    req.ip
    req.<custom>    -> middleware attaches stuff here (e.g. req.user after auth)

  RESPONSE (res):
    res.status(201)               -> set status code (chainable)
    res.json(obj)                 -> send JSON (sets Content-Type, stringifies)
    res.send(body)                -> send string/buffer/object
    res.sendStatus(204)           -> status + default body
    res.set('X-Foo', 'bar')       -> set a header
    res.redirect('/login')
    res.cookie('token', t, opts)
    res.end()                     -> end without a body
    IMPORTANT: send a response exactly ONCE per request, or you get
    "Cannot set headers after they are sent" errors.
*/

/*
-----------------------------------------------------------------------------------------------
Question 4: The Express request lifecycle (the Rails request-cycle equivalent)
-----------------------------------------------------------------------------------------------
Answer (the story to tell) ->
  1. Request hits Node's http server, Express wraps it as (req, res).
  2. The request flows through the MIDDLEWARE STACK in order (app.use(...)): body parsing,
     logging, CORS, auth, etc. Each middleware either responds, or calls next() to pass on.
  3. The ROUTER matches the method + path to a route handler.
  4. Route-level middleware runs (e.g. auth guard, validation) then the final handler.
  5. The handler does its work (calls services / ORM) and sends a response (res.json).
  6. If any step calls next(err) or throws (in sync code), the request jumps to the
     ERROR-HANDLING middleware at the end.
  7. If nothing matches, a 404 handler (a catch-all middleware) responds.

  In one line: Request -> middleware chain -> router -> route middleware -> handler -> response
  (errors -> error middleware). It's a pipeline, exactly like Rack/Rails middleware + filters.
*/

/*
-----------------------------------------------------------------------------------------------
Question 5: Routing — methods, params, and the Router
-----------------------------------------------------------------------------------------------
Answer ->
  app.get / app.post / app.put / app.patch / app.delete / app.all

  Route params:        app.get('/users/:id/posts/:postId', ...)  -> req.params.id, req.params.postId
  Optional / patterns: '/files/:name?'  , regex routes are supported.

  The Router lets you modularize routes (like Rails' resources / namespaces):

  // routes/users.js
  const router = require('express').Router();
  router.get('/', listUsers);
  router.get('/:id', getUser);
  router.post('/', createUser);
  module.exports = router;

  // app.js
  app.use('/api/v1/users', require('./routes/users'));   // mounts at a prefix

  This is how you keep app.js clean and group routes by resource — the manual version of Rails'
  `resources :users`.
*/

/*
-----------------------------------------------------------------------------------------------
Question 6: app.use vs app.get — and middleware ordering
-----------------------------------------------------------------------------------------------
Answer ->
  - app.use(fn) registers MIDDLEWARE that runs for every request (optionally scoped to a path
    prefix: app.use('/api', fn)). Used for cross-cutting concerns (logging, auth, body parse).
  - app.get/post/... registers a route HANDLER for a specific method + path.

  ORDER MATTERS — middleware/routes run top to bottom in the order registered. Consequences:
   - express.json() must come BEFORE routes that read req.body.
   - auth middleware must come BEFORE the protected routes.
   - the 404 handler and error handler must come LAST.

  // typical ordering
  app.use(helmet());
  app.use(cors());
  app.use(express.json());
  app.use(requestLogger);
  app.use('/api/v1/users', usersRouter);     // routes
  app.use(notFoundHandler);                   // 404 (no route matched)
  app.use(errorHandler);                      // errors (4-arg)
*/

/*
-----------------------------------------------------------------------------------------------
Question 7: Recommended project structure (since Express gives you none)
-----------------------------------------------------------------------------------------------
Answer -> A clean layered structure (this is a frequent question — "how do you organize a big
Express app?"):

  src/
    app.js              <- create express app, wire middleware (no listen here)
    server.js           <- import app, app.listen, graceful shutdown
    config/             <- env config, db connection setup
    routes/             <- route definitions (thin) -> point to controllers
    controllers/        <- parse req, call service, shape response (no business logic)
    services/           <- business logic (the "fat model"/service-object layer)
    repositories/       <- data access (ORM queries) — optional but clean
    models/             <- ORM models / schemas
    middlewares/        <- auth, validation, error handler, rate limit
    validators/         <- Joi/Zod schemas
    utils/              <- helpers, custom errors, logger
    jobs/               <- BullMQ workers/queues
    tests/

  The layering (controller -> service -> repository) recreates Rails' separation of concerns
  that you otherwise lose in bare Express. See 19_architecture_patterns.js for the deep version.
*/

/*
-----------------------------------------------------------------------------------------------
Question 8: Express alternatives (good to name-drop)
-----------------------------------------------------------------------------------------------
Answer ->
  - Fastify   -> faster than Express, schema-based validation + serialization built in,
                 first-class async/await, plugin system. Increasingly popular.
  - Koa       -> by the Express team, minimal, async/await-native middleware (ctx object).
  - NestJS    -> opinionated, structured, TypeScript-first, DI + modules + decorators. The most
                 "Rails-like" — best pick when you want convention and structure on a big team.
  - Hapi      -> configuration-centric, enterprise-y.

  What I'd say: "Express for its ubiquity and simplicity, Fastify when I want performance and
  built-in validation, and NestJS when I want Rails-style structure and TypeScript on a large
  codebase."
*/

module.exports = {};
