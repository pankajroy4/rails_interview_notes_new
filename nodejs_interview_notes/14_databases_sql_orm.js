/*
===============================================================================================
                       SQL DATABASES & ORMs (Sequelize / Prisma / Knex)
===============================================================================================
This is where my ActiveRecord experience transfers almost completely. The concepts (migrations,
associations, N+1, transactions, indexes, pooling) are identical — only syntax changes. My SQL
notes from the Rails folder still 100% apply (Postgres/MySQL don't care what language calls them).
*/

/*
-----------------------------------------------------------------------------------------------
Question 1: The ORM landscape in Node (and which to pick)
-----------------------------------------------------------------------------------------------
Answer ->
  - Prisma     -> modern, type-safe, schema-first (schema.prisma). Generates a fully typed
                  client. Excellent DX, great for TypeScript. My default for new TS projects.
  - Sequelize  -> mature, traditional ORM, model classes + associations, closest in feel to
                  ActiveRecord. Lots of legacy apps use it.
  - TypeORM    -> decorator-based (entities), used a lot with NestJS. ActiveRecord OR DataMapper
                  patterns.
  - Knex       -> a QUERY BUILDER, not a full ORM (no models/associations). You write
                  query-builder chains; great when you want SQL control. Often used under the hood.
  - Drizzle    -> newer, lightweight, SQL-like, type-safe. Gaining popularity.

  Rails analogy: Sequelize/TypeORM ≈ ActiveRecord (the model-centric ORM); Knex ≈ Arel/raw SQL
  builder; Prisma is its own thing (schema-first + generated typed client).
*/

/*
-----------------------------------------------------------------------------------------------
Question 2: Sequelize basics (the most ActiveRecord-like)
-----------------------------------------------------------------------------------------------
Answer ->
  const { Sequelize, DataTypes, Model } = require('sequelize');
  const sequelize = new Sequelize(process.env.DATABASE_URL, { logging: false });

  const User = sequelize.define('User', {
    name:  { type: DataTypes.STRING, allowNull: false },
    email: { type: DataTypes.STRING, unique: true, allowNull: false },
    active:{ type: DataTypes.BOOLEAN, defaultValue: true },
  });

  // CRUD (note: everything returns a Promise -> await it)
  const user = await User.create({ name: 'Ann', email: 'a@b.com' });
  const u    = await User.findByPk(1);
  const list = await User.findAll({ where: { active: true }, order: [['createdAt', 'DESC']],
                                    limit: 20, offset: 0 });
  await user.update({ name: 'Annie' });
  await user.destroy();

  // Associations (has_many / belongs_to)
  User.hasMany(Post);
  Post.belongsTo(User);
*/

/*
-----------------------------------------------------------------------------------------------
Question 3: Prisma basics (schema-first + typed client)
-----------------------------------------------------------------------------------------------
Answer ->
  // schema.prisma
  model User {
    id     Int     @id @default(autoincrement())
    email  String  @unique
    name   String?
    posts  Post[]                       // relation
  }
  model Post {
    id       Int   @id @default(autoincrement())
    title    String
    author   User  @relation(fields: [authorId], references: [id])
    authorId Int
  }

  // usage (fully typed)
  const prisma = new PrismaClient();
  const user = await prisma.user.create({ data: { email: 'a@b.com', name: 'Ann' } });
  const u    = await prisma.user.findUnique({ where: { id: 1 } });
  const list = await prisma.user.findMany({
    where: { posts: { some: {} } },
    include: { posts: true },           // eager load -> fixes N+1
    orderBy: { createdAt: 'desc' },
    take: 20, skip: 0,
  });

  Workflow: edit schema.prisma -> `prisma migrate dev` (creates SQL migration + applies) ->
  `prisma generate` (regenerates the typed client). This is the migration story below.
*/

/*
-----------------------------------------------------------------------------------------------
Question 4: Migrations (the ActiveRecord migration equivalent)
-----------------------------------------------------------------------------------------------
Answer -> Migrations are versioned, ordered scripts that evolve the schema, tracked in a
migrations table, so every environment converges to the same schema. Same idea as Rails.

  Sequelize (sequelize-cli):
    npx sequelize-cli migration:generate --name create-users
    // edit the up()/down() with queryInterface.createTable / addColumn / addIndex
    npx sequelize-cli db:migrate
    npx sequelize-cli db:migrate:undo

  Prisma:
    // change schema.prisma, then:
    npx prisma migrate dev --name create_users     // dev: generate + apply
    npx prisma migrate deploy                        // prod: apply committed migrations

  Knex:
    npx knex migrate:make create_users
    npx knex migrate:latest / migrate:rollback

  Best practices (same as Rails): never edit an applied migration, make them reversible,
  add indexes in migrations, and for huge tables use online/concurrent index creation to avoid
  locking (Postgres CREATE INDEX CONCURRENTLY).
*/

/*
-----------------------------------------------------------------------------------------------
Question 5: The N+1 problem in Node ORMs (you WILL be asked this)
-----------------------------------------------------------------------------------------------
Answer -> Identical disease to Rails: looping over N parents and lazily loading each one's
children fires 1 + N queries.

  // BAD: 1 query for users + 1 query PER user for posts = N+1
  const users = await User.findAll();
  for (const u of users) {
    const posts = await u.getPosts();    // a query each iteration
  }

  // FIX (Sequelize): eager load with include  (Rails .includes)
  const users = await User.findAll({ include: [{ model: Post }] });

  // FIX (Prisma): include / select
  const users = await prisma.user.findMany({ include: { posts: true } });

  // GraphQL resolvers: use DataLoader to batch + cache per request (see 23_graphql_nodejs.js).

  How to DETECT: log SQL (Sequelize `logging: console.log`, Prisma query events) and watch for
  repeated identical queries. There's no Bullet gem, but query logging + APM (New Relic,
  Datadog) surfaces it. This maps directly to the N+1 hunting I did in Rails.
*/

/*
-----------------------------------------------------------------------------------------------
Question 6: Transactions (atomicity for multi-step writes)
-----------------------------------------------------------------------------------------------
Answer -> Wrap multiple writes so they all succeed or all roll back (e.g. debit one account,
credit another). Same ACID idea as Rails' `ActiveRecord::Base.transaction`.

  // Sequelize (managed transaction — auto commit/rollback)
  await sequelize.transaction(async (t) => {
    await Account.decrement('balance', { by: 100, where: { id: from }, transaction: t });
    await Account.increment('balance', { by: 100, where: { id: to },   transaction: t });
    // if anything throws, the whole tx rolls back
  });

  // Prisma (interactive transaction)
  await prisma.$transaction(async (tx) => {
    await tx.account.update({ where: { id: from }, data: { balance: { decrement: 100 } } });
    await tx.account.update({ where: { id: to },   data: { balance: { increment: 100 } } });
  });

  Talk about isolation levels (READ COMMITTED default in Postgres; SERIALIZABLE for strict
  consistency), and that long transactions hold locks -> keep them short.
*/

/*
-----------------------------------------------------------------------------------------------
Question 7: Connection pooling (critical in single-threaded Node)
-----------------------------------------------------------------------------------------------
Answer -> Opening a DB connection per request is expensive, so the driver keeps a POOL of
reusable connections. In Node this is especially important because one process serves many
concurrent requests sharing the pool.

  Sequelize: new Sequelize(url, { pool: { max: 10, min: 0, idle: 10000, acquire: 30000 } });
  Prisma:    connection_limit in the DATABASE_URL or config.

  Sizing rule of thumb: total pool connections across ALL app instances must stay under the
  DB's max_connections. If you run 4 cluster workers × pool max 10 = 40 connections from ONE
  machine. This is a common production outage cause ("too many connections") — watch it,
  especially with serverless (use a proxy like PgBouncer / Prisma Accelerate / RDS Proxy).
*/

/*
-----------------------------------------------------------------------------------------------
Question 8: Query optimization & indexing (my SQL notes fully apply here)
-----------------------------------------------------------------------------------------------
Answer -> Same toolbox as Rails/SQL, because the DB is the same Postgres/MySQL:
  - Add indexes on columns used in WHERE / JOIN / ORDER BY / foreign keys. Composite indexes
    for multi-column filters (column order matters: most-selective / equality first).
  - EXPLAIN ANALYZE to read the query plan; look for Seq Scans on big tables, watch row
    estimates vs actual.
  - SELECT only needed columns (the `pluck`/`select` idea) instead of hydrating full rows.
  - Avoid N+1 (eager load), use pagination (keyset for deep pages), batch writes (bulkCreate /
    createMany / bulkWrite) instead of row-by-row.
  - Use the DB for set operations (aggregations, joins) rather than pulling rows into Node.
  - For very heavy reads, add caching (Redis) and/or read replicas.

  Bulk insert example (the 2M-record import pattern):
    await User.bulkCreate(batch, { updateOnDuplicate: ['name', 'email'] }); // Sequelize upsert
    await prisma.user.createMany({ data: batch, skipDuplicates: true });    // Prisma
  Batch in chunks (1k–5k), wrap in transactions where appropriate, stream the source.
*/

/*
-----------------------------------------------------------------------------------------------
Question 9: Raw SQL when you need it
-----------------------------------------------------------------------------------------------
Answer -> ORMs can't express every query; drop to raw SQL but ALWAYS parameterize (never
string-interpolate user input -> SQL injection).

  // Sequelize
  const [rows] = await sequelize.query(
    'SELECT * FROM users WHERE email = :email',
    { replacements: { email }, type: QueryTypes.SELECT });

  // Prisma (tagged template auto-parameterizes — safe)
  const rows = await prisma.$queryRaw`SELECT * FROM users WHERE email = ${email}`;

  Knowing when to leave the ORM (complex reporting queries, window functions, CTEs) is a
  seniority signal — same judgment I used writing stored procedures/complex SQL in Rails.
*/

module.exports = {};
