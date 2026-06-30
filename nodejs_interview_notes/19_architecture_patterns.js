/*
===============================================================================================
                       ARCHITECTURE & DESIGN PATTERNS (structuring a Node app)
===============================================================================================
"Express gives you no structure — how do you organize a large app?" is one of THE most common
senior Node questions. My Rails experience (MVC, service objects, SOLID) is a big asset; I just
have to impose that structure myself. My solid_principle.rb notes apply directly.
*/

/*
-----------------------------------------------------------------------------------------------
Question 1: The layered architecture (controller -> service -> repository)
-----------------------------------------------------------------------------------------------
Answer -> The standard way to bring Rails-like separation of concerns to Express is a layered
architecture. Each layer has ONE job and depends only on the layer below it.

  ROUTE        -> declares the endpoint + attaches middleware (thin; no logic).
  CONTROLLER   -> HTTP glue: read req (params/body/query), call a service, shape the response.
                  NO business logic, NO DB queries here.
  SERVICE      -> business logic / use-cases (the "fat" layer). Orchestrates repositories,
                  enforces rules, runs transactions. Framework-agnostic (no req/res).
  REPOSITORY   -> data access only (ORM/DB queries). Hides the ORM behind an interface.
  MODEL        -> the ORM schema/entity.

  // controller (thin)
  async function createUser(req, res, next) {
    try {
      const user = await userService.register(req.body);   // delegate to service
      res.status(201).json({ data: user });
    } catch (err) { next(err); }
  }

  // service (business logic, no HTTP)
  async function register(dto) {
    if (await userRepo.findByEmail(dto.email)) throw new ConflictError('email taken');
    const passwordHash = await bcrypt.hash(dto.password, 12);
    const user = await userRepo.create({ ...dto, passwordHash });
    await emailQueue.add('welcome', { userId: user.id });   // side effect via queue
    return sanitize(user);
  }

  // repository (data access only)
  const userRepo = {
    findByEmail: (email) => User.findOne({ where: { email } }),
    create: (data) => User.create(data),
  };

  WHY: testability (mock the repo in service tests), swappable ORM, controllers stay trivial,
  business logic lives in one place. This is Rails' "skinny controller, service objects, models"
  philosophy, made explicit because Express won't do it for me.
*/

/*
-----------------------------------------------------------------------------------------------
Question 2: Folder structure — by-layer vs by-feature
-----------------------------------------------------------------------------------------------
Answer ->
  BY LAYER (technical, fine for small/medium apps):
    src/ controllers/  services/  repositories/  models/  routes/  middlewares/  utils/

  BY FEATURE / MODULE (scales better for large apps — what NestJS encourages):
    src/
      modules/
        users/   users.controller.js  users.service.js  users.repository.js  users.routes.js
        orders/  orders.controller.js orders.service.js ...
        auth/    ...
      shared/    middlewares/ utils/ errors/ config/

  By-feature keeps everything about a domain together (high cohesion), which is easier to
  navigate and own as the codebase grows. I'd default to by-feature for anything non-trivial.
*/

/*
-----------------------------------------------------------------------------------------------
Question 3: SOLID in Node/JS (my solid_principle notes, translated)
-----------------------------------------------------------------------------------------------
Answer -> SOLID is language-agnostic; here's the Node flavor:
  - S (Single Responsibility): a controller handles HTTP, a service handles logic, a repo
    handles data. Don't put DB queries in controllers.
  - O (Open/Closed): extend via new strategies/middleware, not by editing existing code (e.g.
    add a new payment provider class implementing a common interface).
  - L (Liskov): any implementation of an interface (e.g. a StorageProvider) must be substitutable
    (S3 vs local disk) without breaking callers.
  - I (Interface Segregation): keep modules/contracts small + focused; don't force a consumer to
    depend on methods it doesn't use.
  - D (Dependency Inversion): high-level code depends on ABSTRACTIONS, not concretions. Inject
    the repo/logger/email-sender into the service rather than importing a concrete one — this
    is dependency injection, and it's what makes services unit-testable.
*/

/*
-----------------------------------------------------------------------------------------------
Question 4: Dependency Injection (DI)
-----------------------------------------------------------------------------------------------
Answer -> DI = pass a component's dependencies IN rather than hard-importing them inside. Makes
code testable (inject mocks) and swappable.

  // hard to test: depends on the concrete module
  // function UserService() { const db = require('./db'); ... }

  // DI: dependencies passed in (constructor injection)
  function makeUserService({ userRepo, emailQueue, logger }) {
    return {
      register: async (dto) => { /* use userRepo, emailQueue, logger */ },
    };
  }
  // wire it up in a composition root (index.js); in tests pass fakes.

  NestJS has a full DI container with decorators (@Injectable) — Rails-like magic. In plain
  Express you do it manually (factory functions) or with awilix/tsyringe. The PRINCIPLE matters
  more than the tool.
*/

/*
-----------------------------------------------------------------------------------------------
Question 5: Common design patterns you'll cite
-----------------------------------------------------------------------------------------------
Answer ->
  - Repository:   abstract data access behind an interface (above).
  - Service/Use-case: encapsulate business operations.
  - Factory:      functions that build configured objects (makeUserService).
  - Singleton:    a single shared instance — Node modules are cached, so a module exporting an
                  instance (DB client, Redis client, logger) IS effectively a singleton.
  - Strategy:     swap algorithms/providers behind a common interface (payment gateways).
  - Middleware/Chain of Responsibility: Express middleware IS this pattern.
  - Observer/Pub-Sub: EventEmitter / message queues (decoupled events).
  - Adapter:      wrap a third-party SDK behind your own interface so it's swappable + testable.
  - DTO:          typed data objects crossing layer boundaries (validated input).
*/

/*
-----------------------------------------------------------------------------------------------
Question 6: Config & environments (the credentials.yml.enc / ENV equivalent)
-----------------------------------------------------------------------------------------------
Answer ->
  - Use process.env, loaded from a .env file in dev via dotenv (NEVER commit .env).
  - VALIDATE env at startup with a schema (Zod/envalid) so a missing var fails fast, loudly,
    at boot — not at 2am in a request.
      const env = z.object({ DATABASE_URL: z.string().url(), JWT_SECRET: z.string().min(32),
                             PORT: z.coerce.number().default(3000) }).parse(process.env);
  - Centralize config in one module (config/index.js) that reads env once and exports typed
    values; the rest of the app imports config, never raw process.env.
  - In production use a secrets manager (AWS Secrets Manager / SSM / Vault), not .env files.
  - NODE_ENV ('development' | 'test' | 'production') gates behavior (logging, error detail).
*/

/*
-----------------------------------------------------------------------------------------------
Question 7: Logging & observability (production maturity)
-----------------------------------------------------------------------------------------------
Answer ->
  - Use a STRUCTURED logger (pino — fast, JSON; or winston), not console.log, in production.
    JSON logs are searchable/aggregatable (ELK, Datadog, CloudWatch).
  - Add a correlation/request ID per request (a middleware that sets req.id and a child logger)
    so you can trace one request across logs and services. AsyncLocalStorage can carry it
    implicitly (the CurrentAttributes/request-store idea from Rails).
  - Log levels (debug/info/warn/error/fatal), never log secrets/PII.
  - Metrics (prom-client -> Prometheus) + distributed tracing (OpenTelemetry) for real systems.
  - Health/readiness endpoints for the load balancer + k8s probes.
*/

/*
-----------------------------------------------------------------------------------------------
Question 8: The clean one-liner for "how do you structure a big Express app?"
-----------------------------------------------------------------------------------------------
Answer ->
  "I impose the structure Express doesn't give me, using the layering I learned in Rails:
   thin routes -> thin controllers (HTTP only) -> services (business logic) -> repositories
   (data access). I organize by feature/module for cohesion, inject dependencies so services
   are unit-testable, validate config and input at the boundaries, and centralize errors and
   logging. If the team wants this enforced by convention out of the box, I'd reach for NestJS,
   which basically brings Rails-style structure and DI to Node."
*/

module.exports = {};
