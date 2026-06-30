/*
===============================================================================================
                    RAILS  ->  NODE.JS   CONCEPT MAPPING  (read this first)
===============================================================================================
This file is the single most useful thing for me. Every time an interviewer asks a Node
question, I can anchor it to the Rails concept I already know cold, then explain the Node
version. The goal is: "I'm not learning from zero, I'm translating."
*/

/*
-----------------------------------------------------------------------------------------------
BIG PICTURE: the two ecosystems side by side
-----------------------------------------------------------------------------------------------

  CONCEPT                 RAILS / RUBY                     NODE.JS / JS ECOSYSTEM
  ---------------------   ------------------------------   ----------------------------------
  Language                Ruby                             JavaScript / TypeScript
  Runtime                 MRI/CRuby (YARV VM)              Node.js (V8 engine + libuv)
  Web framework           Rails (full, opinionated)        Express (minimal) / NestJS (opinionated)
  Package manager         Bundler + RubyGems (Gemfile)     npm / yarn / pnpm (package.json)
  Dependency lock         Gemfile.lock                     package-lock.json / yarn.lock
  ORM                     ActiveRecord                     Sequelize / Prisma / TypeORM / Knex
  ODM (NoSQL)             Mongoid                          Mongoose
  Migrations              ActiveRecord migrations          Sequelize / Prisma / Knex migrations
  Background jobs         Sidekiq / Resque / ActiveJob     BullMQ / Bull / Agenda
  Job queue store         Redis                            Redis (same!)
  Caching                 Rails.cache (Redis/Memcached)    node-cache / ioredis / Redis
  Testing framework       RSpec                            Jest / Mocha + Chai
  Test request specs      request specs (rack-test)        Supertest
  Factories               FactoryBot                       Fakerjs + factory-girl / fishery
  Mocking                 RSpec mocks, instance_double     jest.mock / jest.fn / sinon
  Auth (authn)            Devise                           Passport.js / custom JWT
  Auth (authz)            Pundit / CanCanCan               casl / custom middleware / guards
  Validation              ActiveModel validations          Joi / Zod / express-validator / class-validator
  Serialization           ActiveModel::Serializer / jbuilder  custom mappers / class-transformer
  Env/secrets             credentials.yml.enc / ENV        dotenv (.env) / process.env
  Templating              ERB / Slim                       EJS / Pug / Handlebars (mostly APIs now)
  Realtime                ActionCable                      Socket.io / ws
  GraphQL                 graphql-ruby                     Apollo Server / graphql-js / type-graphql
  App server              Puma / Unicorn                   Node itself (single process) + cluster/PM2
  Process manager         systemd / Puma workers           PM2 / cluster module / Docker
  Asset pipeline          Sprockets / importmap            webpack / vite / esbuild (frontend only)
  Console                 rails console                    node REPL / ts-node
  Routing                 config/routes.rb                 Express Router / file-based (Next.js)
  Linting                 RuboCop                          ESLint
  Formatting              RuboCop / standardrb             Prettier
  Static analysis         Brakeman, bundler-audit          npm audit, snyk, eslint-plugin-security
  Type system             (none, duck typing) / Sorbet     TypeScript
*/

/*
-----------------------------------------------------------------------------------------------
THE #1 MENTAL SHIFT: concurrency model
-----------------------------------------------------------------------------------------------

RAILS:
  - Each web request is handled by a thread/process (Puma spins up workers + threads).
  - Ruby code can BLOCK freely. If a request does a slow DB call, that worker is busy, but
    other workers/threads keep serving. Concurrency comes from MANY workers/threads.
  - I scale by adding Puma workers (processes) and threads, and offloading heavy stuff to
    Sidekiq so the web worker is freed up fast.

NODE:
  - ONE thread runs my JavaScript (the event loop). There are no per-request threads.
  - I must NEVER block that thread. A blocking/synchronous call (e.g. a big JSON.parse, a
    sync crypto hash, a while-loop crunching numbers) freezes EVERY user's request.
  - Instead, all I/O (DB, HTTP, file) is asynchronous and non-blocking. While one request
    waits on the DB, the single thread serves other requests. Concurrency comes from
    NON-BLOCKING I/O, not from many threads.
  - For CPU-heavy work I use worker_threads or offload to a background job (BullMQ).
  - To use all CPU cores I run multiple Node processes (cluster module / PM2 / k8s replicas).

INTERVIEW SOUNDBITE:
  "In Rails, concurrency comes from running many workers and threads that are allowed to
   block. In Node, concurrency comes from a single non-blocking event loop, so the golden
   rule is never block the loop — I push CPU-heavy or long-running work to worker threads
   or to a Redis-backed job queue, exactly like I pushed heavy work to Sidekiq in Rails."
*/

/*
-----------------------------------------------------------------------------------------------
REQUEST LIFECYCLE: Rails vs Express
-----------------------------------------------------------------------------------------------

RAILS:   Request -> Rack -> Middleware stack -> Router (routes.rb) -> Controller before_action
         -> Controller action -> Model (ActiveRecord) -> View/Serializer -> Response

EXPRESS: Request -> http server -> Middleware chain (app.use ...) -> Router -> route handler(s)
         -> (call services / ORM) -> res.json()/res.send() -> Response
         (errors fall through to error-handling middleware)

  Rails before_action / around_action  ==  Express middleware that calls next()
  Rails controller action              ==  Express route handler (req, res, next)
  Rails strong params                  ==  validation middleware (Joi/Zod) + manual picking
  Rails render json:                   ==  res.status(200).json(payload)
  Rails rescue_from                    ==  error-handling middleware (err, req, res, next)
*/

/*
-----------------------------------------------------------------------------------------------
ACTIVERECORD  ->  SEQUELIZE / PRISMA  (quick translations)
-----------------------------------------------------------------------------------------------

  RAILS (ActiveRecord)                       SEQUELIZE                         PRISMA
  ----------------------------------------   -------------------------------   --------------------------------
  User.find(1)                               User.findByPk(1)                  prisma.user.findUnique({where:{id:1}})
  User.find_by(email: e)                     User.findOne({where:{email:e}})   prisma.user.findFirst({where:{email:e}})
  User.where(active: true)                   User.findAll({where:{active:true}}) prisma.user.findMany({where:{active:true}})
  User.create!(attrs)                        User.create(attrs)                prisma.user.create({data:attrs})
  user.update!(attrs)                        user.update(attrs)                prisma.user.update({where,data})
  user.destroy                               user.destroy()                    prisma.user.delete({where})
  User.includes(:posts)  (eager load)        User.findAll({include: Post})     prisma.user.findMany({include:{posts:true}})
  User.count                                 User.count()                      prisma.user.count()
  User.order(created_at: :desc)              User.findAll({order:[['createdAt','DESC']]}) prisma.user.findMany({orderBy:{createdAt:'desc'}})
  has_many :posts                            User.hasMany(Post)                relation in schema.prisma
  belongs_to :user                           Post.belongsTo(User)              relation in schema.prisma
  transaction do ... end                     sequelize.transaction(async t=>{}) prisma.$transaction([...])

  The N+1 problem exists in BOTH. In Rails I fix it with .includes; in Sequelize with
  `include`, in Prisma with `include`/`select`. Same disease, same cure: eager loading.
*/

/*
-----------------------------------------------------------------------------------------------
SIDEKIQ  ->  BULLMQ  (this is almost a 1:1 for me)
-----------------------------------------------------------------------------------------------

  RAILS / SIDEKIQ                              NODE / BULLMQ
  ------------------------------------------   ------------------------------------------
  class MyWorker; include Sidekiq::Worker      const queue = new Queue('my', {connection})
  MyWorker.perform_async(args)                 queue.add('jobName', data)
  def perform(args); ...; end                  new Worker('my', async job => {...})
  sidekiq_options retry: 5                     { attempts: 5, backoff: {...} }
  queue_as :critical                           new Queue('critical')
  Sidekiq dashboard (web UI)                   Bull Board (web UI)
  Redis as the backing store                   Redis as the backing store (same!)

  Everything I said in my Rails notes about idempotency, retries, dead jobs, and Redis
  connection pools applies almost word-for-word to BullMQ. See 16_background_jobs.js.
*/

/*
-----------------------------------------------------------------------------------------------
RSPEC  ->  JEST  (testing translations)
-----------------------------------------------------------------------------------------------

  RSPEC                              JEST
  -------------------------------   --------------------------------
  describe "Thing" do               describe('Thing', () => {})
  context "when X" do                describe('when X', () => {})  (or nested describe)
  it "does Y" do                    test('does Y', () => {})  /  it('does Y', () => {})
  expect(x).to eq(5)                expect(x).toBe(5)
  expect(x).to be_truthy            expect(x).toBeTruthy()
  expect(arr).to include(3)         expect(arr).toContain(3)
  before(:each)                     beforeEach()
  let(:user) { ... }                (just a const in beforeEach, or a factory)
  allow(obj).to receive(:m)         jest.spyOn(obj, 'm') / jest.mock(...)
  FactoryBot.create(:user)          UserFactory.build() (fishery) / faker
  request specs (get '/users')      supertest: request(app).get('/users')

  My resume says 95%+ coverage with RSpec — I frame Jest as "same discipline, new syntax."
*/

/*
-----------------------------------------------------------------------------------------------
THINGS THAT ARE GENUINELY DIFFERENT (don't get caught off guard)
-----------------------------------------------------------------------------------------------

1. No "convention over configuration" in Express. Rails gives you structure for free;
   Express gives you nothing — YOU decide the folder structure, the ORM, the validation lib.
   This is why NestJS exists (it brings Rails-like opinions/structure to Node). Interviewers
   love asking "how do you structure a large Express app?" — see 19_architecture_patterns.js.

2. Everything async by default. In Rails `User.find(1)` returns the user. In Node the DB call
   returns a Promise; you `await` it. Forgetting `await` is the #1 beginner bug — you get a
   pending Promise instead of data, and errors vanish.

3. No global request context like Rails. Rails has CurrentAttributes / request-local globals.
   Node has AsyncLocalStorage for that, but it's not as baked-in. State must be passed
   explicitly or via middleware on `req`.

4. Single-threaded gotchas: a CPU-bound loop blocks ALL users. In Rails one slow request
   only ties up one worker. This changes how I think about heavy computation.

5. npm has a LOT more, smaller packages (left-pad culture). Ruby gems tend to be bigger and
   more "batteries included". Expect to wire together more small libraries in Node.

6. TypeScript is basically expected in serious Node shops. Ruby is dynamically typed; Node
   teams increasingly use TS for the safety Rails got from convention + tests. Lean into TS.
*/

/*
-----------------------------------------------------------------------------------------------
HOW TO TALK ABOUT MY EXISTING PROJECTS IN A NODE INTERVIEW
-----------------------------------------------------------------------------------------------

- Horizon (claim mgmt, MongoDB/Mongoid, bulk upsert 24h -> 6min):
    "I'd build the same in Node with Mongoose bulkWrite() using unordered ops and batching,
     run the import in a BullMQ worker, and stream the EDI file instead of loading it all in
     memory. The optimization principles (bulk ops, batching, indexes) are identical."

- WhatsApp bulk messenger (webhooks, Sidekiq, rate limits):
    "Node is actually a great fit here — webhook ingestion is I/O bound, which is Node's
     sweet spot. I'd use Express for the webhook endpoint, push each event to a BullMQ queue,
     and use a rate-limited worker (Bottleneck or BullMQ's limiter) to respect Meta's API
     limits — the same fault-tolerant pipeline idea I built with Sidekiq."

- 2M EDI record import:
    "Stream + batch + bulk-upsert. In Node: createReadStream + a parser, accumulate batches
     of ~1-5k, bulkWrite with ordered:false, backpressure-aware. Same 99.6% win is available."
*/

module.exports = {}; // notes file
