# Node.js Interview Preparation Notes

These notes are written for an experienced **Ruby on Rails developer (3.6+ yrs)** moving to
**Node.js / Express / TypeScript**. The depth, tone, and "how I'd say it out loud in an
interview" style mirror my Rails notes. Every topic tries to connect a *new* Node concept
back to something I already know from Rails so the mental model transfers fast.

Files are kept as `.js` (and a couple `.md`) so they highlight nicely and code examples run
as-is.

---------------------------------------------------------------------------------------------

## Suggested study order

1. `01_rails_to_nodejs_mapping.js`   <- READ FIRST. Translates every Rails concept to Node.
2. `02_nodejs_fundamentals.js`       <- What Node actually is (V8 + libuv), architecture.
3. `03_event_loop.js`                <- The single most asked Node topic. Master this.
4. `04_async_patterns.js`            <- callbacks -> promises -> async/await, error handling.
5. `05_modules_and_npm.js`           <- CommonJS vs ESM, package.json, semver, npm internals.
6. `06_streams_and_buffers.js`       <- streams, backpressure, buffers (the "Ruby IO" of Node).
7. `07_events_and_emitters.js`       <- EventEmitter, the pattern Node is built on.
8. `08_error_handling.js`            <- prod-grade error handling, crashes, graceful shutdown.
9. `09_express_fundamentals.js`      <- the Rails of Node (sort of). Routing + request cycle.
10. `10_express_middleware.js`       <- middleware deep dive (Rack/before_action equivalent).
11. `11_rest_api_design.js`          <- RESTful design, status codes, versioning, pagination.
12. `12_auth_and_security.js`        <- JWT, sessions, bcrypt, Passport, OWASP, helmet, CORS.
13. `13_validation.js`               <- Joi / Zod / express-validator (Rails validations).
14. `14_databases_sql_orm.js`        <- Sequelize / Prisma / Knex, migrations, N+1, tx.
15. `15_mongodb_mongoose.js`         <- MongoDB + Mongoose (I already used Mongoid in Horizon).
16. `16_background_jobs.js`          <- BullMQ / Bull / Agenda (Sidekiq/Resque equivalent).
17. `17_caching_redis.js`            <- Redis caching patterns.
18. `18_performance_and_scaling.js`  <- cluster, worker_threads, PM2, load balancing, profiling.
19. `19_architecture_patterns.js`    <- folder structure, service/repository, SOLID, DI.
20. `20_testing.js`                  <- Jest, Supertest, mocking (RSpec equivalent).
21. `21_typescript_nodejs.js`        <- TypeScript with Node, types, generics, config.
22. `22_nestjs.js`                   <- NestJS = the most "Rails-like" Node framework.
23. `23_graphql_nodejs.js`           <- Apollo Server / GraphQL (I have GraphQL exp in PurePani).
24. `24_websockets_realtime.js`      <- Socket.io / WebSockets (relevant to my WhatsApp project).
25. `25_microservices.js`            <- microservices, message queues, API gateway.
26. `26_scenario_interview_questions.js` <- real production scenario Q&A (set 1).
27. `27_my_projects_in_nodejs.js`    <- MY real projects (Horizon EDI import, WhatsApp/CRM) re-told
                                        in Node terms, with actual implementation detail. HIGH VALUE.
28. `28_more_scenario_questions.js`  <- 14 more production scenarios (set 2).

### Infra / DevOps / breadth (added to match every topic in my Rails notes)
29. `29_elasticsearch_nodejs.js`     <- Elasticsearch + the multi-model "global search" scenario.
30. `30_aws_for_node.js`             <- IAM, EC2, S3 (aws-sdk v3), presigned URLs, ECS/Lambda deploy.
31. `31_docker_for_node.js`          <- multi-stage Dockerfile, compose, signals/PID-1 gotchas.
32. `32_cicd_for_node.js`            <- GitHub Actions (npm ci/lint/tsc/jest), deploy, secrets, gates.
33. `33_database_scaling.js`         <- vertical/horizontal, read replicas, partitioning, sharding.
34. `34_system_design_basics.js`     <- e-commerce schema, OMS/WMS, a repeatable design framework.
35. `35_dsa_in_javascript.js`        <- DSA patterns + REAL JS solutions (my dsa.rb, re-solved in JS).
36. `36_agile_and_process.js`        <- Scrum/Agile (language-agnostic; for behavioral rounds).
37. `37_unix_and_dev_environment.js` <- Linux commands + Node tooling (nvm, npm scripts, pm2, signals).

---------------------------------------------------------------------------------------------

## The 10 questions I MUST be able to answer cold

1. Is Node single-threaded? (Answer: JS execution is, I/O is not — explain libuv thread pool.)
2. Walk me through the event loop phases. (timers -> pending -> poll -> check -> close +
   microtasks between each phase; process.nextTick vs Promise vs setTimeout vs setImmediate.)
3. Callback hell -> Promises -> async/await. Show error handling in each.
4. CommonJS vs ES Modules. require vs import. Why is `require` synchronous and cached?
5. How do you scale a Node app across CPU cores? (cluster / PM2 / worker_threads / horizontal.)
6. CPU-bound work in Node — why is it dangerous and how do you handle it? (worker_threads.)
7. How does Express middleware work? What does `next()` do? Error-handling middleware signature.
8. How do you prevent N+1 queries with Sequelize/Prisma? (eager loading / include / select.)
9. How do you do background jobs in Node? (BullMQ on Redis — same Redis I used for Sidekiq.)
10. How do you handle uncaughtException / unhandledRejection and do a graceful shutdown?

---------------------------------------------------------------------------------------------

## Is this enough to crack a 3.5-year Node.js interview? (honest take)

These notes cover the **theory + scenarios + my real projects** at the depth a 3.5-yr backend
role tests. But notes alone are NOT enough — reading != doing. To actually be ready, pair these
with hands-on reps:

- [ ] **Build one small real Express/Nest API** end to end (auth + DB + a BullMQ job + tests).
      Interviewers can tell in 2 minutes whether you've actually written Node or just read about it.
- [ ] **Be able to live-code**: refactor callbacks -> async/await, predict event-loop output,
      write an Express middleware, fix an N+1. Practice saying these OUT LOUD.
- [ ] **DSA in JavaScript**: my `dsa.rb` / `DSA_problem_solving.rb` are in Ruby — redo the core
      ones in JS (array/string/hashmap/two-pointer/recursion) since live rounds use the language
      of the role. JS specifics: `Map`/`Set`, `sort((a,b)=>a-b)`, `for...of`, destructuring.
- [ ] **Own the project stories cold** (file 27) — the EDI 24h->6min and the WhatsApp pipeline are
      my strongest cards; I must narrate them without notes.
- [ ] **SQL still applies** — my `sql_*` Rails files are language-agnostic; reuse them directly.

Verdict: notes = solid foundation + interview answers. Add ~1-2 weeks of building + speaking the
answers aloud, and a 3.5-yr Node interview is very crackable, especially leaning on my real
Rails-equivalent experience.

## One-paragraph elevator pitch (Rails dev -> Node dev)

"I come from a Ruby on Rails background where I built RESTful and GraphQL APIs, async
pipelines with Sidekiq on Redis, and optimized heavy data imports. Node maps cleanly onto
that experience: Express plays the role Rails plays, BullMQ on Redis replaces Sidekiq,
Sequelize/Prisma replace ActiveRecord, Jest replaces RSpec, and Mongoose replaces Mongoid —
which I already used on the Horizon claim-management platform. The biggest mental shift is
that Node is single-threaded and non-blocking by default, so I think in terms of the event
loop and never block it with CPU-heavy or synchronous work — I offload that to worker
threads or background jobs, the same way I offloaded heavy work to Sidekiq in Rails."
