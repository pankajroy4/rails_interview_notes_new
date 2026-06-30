/*
===============================================================================================
                       REST API DESIGN (status codes, versioning, pagination)
===============================================================================================
This is mostly framework-agnostic and overlaps heavily with my Rails API experience. The
principles are identical; only the Express syntax is new.
*/

/*
-----------------------------------------------------------------------------------------------
Question 1: REST principles in one breath
-----------------------------------------------------------------------------------------------
Answer -> REST models the API around RESOURCES (nouns) addressed by URLs, manipulated with
HTTP METHODS (verbs), using standard status codes, and is STATELESS (each request carries all
the info needed; the server keeps no per-client session state — auth travels in a token/header).

  Resource:   /users, /users/123, /users/123/orders
  Verbs:      GET (read), POST (create), PUT (replace), PATCH (partial update), DELETE (remove)
  Stateless:  no server session affinity -> easy to scale horizontally
  Use NOUNS, not verbs, in paths:  GET /users   (not /getUsers)
*/

/*
-----------------------------------------------------------------------------------------------
Question 2: HTTP methods and idempotency/safety
-----------------------------------------------------------------------------------------------
Answer ->
  METHOD   PURPOSE              SAFE?  IDEMPOTENT?   Typical Express route
  ------   ------------------   -----  -----------   ---------------------------
  GET      read                 yes    yes           app.get('/users/:id')
  POST     create               no     no            app.post('/users')
  PUT      replace whole        no     yes           app.put('/users/:id')
  PATCH    partial update       no     no*           app.patch('/users/:id')
  DELETE   remove               no     yes           app.delete('/users/:id')

  SAFE = doesn't modify state. IDEMPOTENT = doing it N times == doing it once.
  Why it matters: idempotent methods are safe to RETRY (e.g. on a network timeout). POST is not
  idempotent, which is why "create payment" needs an idempotency key to avoid double charges
  (super relevant to my payment-integration experience).
*/

/*
-----------------------------------------------------------------------------------------------
Question 3: Status codes (use the right one — a real signal of API maturity)
-----------------------------------------------------------------------------------------------
Answer ->
  2xx success
    200 OK              -> GET/PUT/PATCH success with body
    201 Created         -> POST created a resource (return it + Location header)
    202 Accepted        -> accepted for async processing (e.g. queued a BullMQ job)
    204 No Content      -> success, no body (typical for DELETE)

  3xx redirect
    301/302 redirects, 304 Not Modified (caching/ETag)

  4xx client error
    400 Bad Request     -> malformed request / generic client error
    401 Unauthorized    -> not authenticated (no/invalid credentials)
    403 Forbidden       -> authenticated but not allowed (authorization)
    404 Not Found       -> resource doesn't exist
    409 Conflict        -> e.g. duplicate, version conflict
    422 Unprocessable   -> validation failed (well-formed but semantically invalid)
    429 Too Many Reqs   -> rate limited

  5xx server error
    500 Internal Server Error -> unhandled bug
    502 Bad Gateway / 503 Service Unavailable / 504 Gateway Timeout

  401 vs 403 is a classic gotcha: 401 = "who are you?", 403 = "I know you, you can't do this."
*/

/*
-----------------------------------------------------------------------------------------------
Question 4: API versioning
-----------------------------------------------------------------------------------------------
Answer -> Version so you can evolve without breaking existing clients. Options:
  - URL path:    /api/v1/users   (most common, explicit, easy to route in Express)
  - Header:      Accept: application/vnd.myapp.v2+json   (cleaner URLs, harder to test)
  - Query param: /users?version=2   (least preferred)

  Practical: mount versioned routers -> app.use('/api/v1', v1Router); app.use('/api/v2', v2Router).
  Keep v1 alive while clients migrate; deprecate with a sunset header + comms.
*/

/*
-----------------------------------------------------------------------------------------------
Question 5: Pagination, filtering, sorting (always asked for list endpoints)
-----------------------------------------------------------------------------------------------
Answer ->
  OFFSET pagination (simple, fine for small/medium data):
    GET /users?page=2&limit=20
    -> SQL: LIMIT 20 OFFSET 20 ; return { data, meta: { page, limit, total, totalPages } }
    -> Downside: slow on deep pages (large OFFSET scans + skips many rows), and items can
       shift if data changes between pages.

  CURSOR / keyset pagination (scales, stable):
    GET /users?limit=20&after=<lastId-or-encoded-cursor>
    -> SQL: WHERE id > :cursor ORDER BY id LIMIT 20
    -> Fast at any depth, stable under inserts. Best for infinite scroll / large tables.

  Filtering & sorting via query params:
    GET /users?status=active&sort=-createdAt&fields=id,name
    -> Whitelist allowed filter/sort fields (never interpolate raw input into queries).

  This maps directly to how I'd paginate in Rails with Kaminari/`.limit.offset` — same trade-
  offs (offset vs keyset), different syntax.
*/

/*
-----------------------------------------------------------------------------------------------
Question 6: Consistent response & error shapes
-----------------------------------------------------------------------------------------------
Answer -> Pick ONE shape and use it everywhere so clients can rely on it.

  // success
  { "data": { ... }, "meta": { "page": 1, "total": 137 } }

  // error
  { "error": { "code": "VALIDATION", "message": "email is invalid", "details": [ ... ] } }

  Centralize this in helpers + the error-handling middleware so controllers stay thin and
  responses stay uniform. Never leak stack traces or SQL to clients in production.
*/

/*
-----------------------------------------------------------------------------------------------
Question 7: Other production concerns for an API
-----------------------------------------------------------------------------------------------
Answer ->
  - Validation at the edge (Joi/Zod) -> 422 on bad input (see 13_validation.js).
  - Rate limiting (express-rate-limit, Redis store) -> 429.
  - Auth (JWT/sessions) + authorization (RBAC) -> 401/403 (see 12_auth_and_security.js).
  - Pagination limits (cap `limit` so a client can't request 1,000,000 rows).
  - Idempotency keys for POST that must not double-execute (payments).
  - Caching: ETag/Cache-Control for GETs; Redis for hot data.
  - Compression (gzip), CORS config, request size limits.
  - OpenAPI/Swagger docs (swagger-jsdoc / @nestjs/swagger) — the API contract.
  - Correlation/request IDs + structured logging for tracing.
  - Health endpoints (/health, /ready) for load balancers and k8s probes.
*/

/*
-----------------------------------------------------------------------------------------------
Question 8: REST vs GraphQL (I have GraphQL experience — frame it well)
-----------------------------------------------------------------------------------------------
Answer ->
  REST: multiple endpoints, server defines the response shape, simple + cacheable via HTTP,
        can over-/under-fetch (you get whatever the endpoint returns).
  GraphQL: one endpoint, the CLIENT specifies exactly which fields it wants (no over/under
        fetch), strongly typed schema, great for complex/nested data and many client types.
        Trade-offs: HTTP caching is harder, you must guard against expensive nested queries
        (depth/complexity limits), and N+1 needs DataLoader batching.

  "I built GraphQL APIs in PurePani with type-safe resolvers, so I'm comfortable choosing REST
   for simple resource CRUD and GraphQL when clients need flexible, nested data." (See
   23_graphql_nodejs.js.)
*/

module.exports = {};
