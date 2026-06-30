/*
===============================================================================================
                       TESTING in Node (Jest / Supertest / mocking)
===============================================================================================
My resume claims 95%+ RSpec coverage — testing is a strength I want to carry over. Jest is the
RSpec of Node. The DISCIPLINE transfers entirely; only syntax + mocking style change.
*/

/*
-----------------------------------------------------------------------------------------------
Question 1: The testing landscape
-----------------------------------------------------------------------------------------------
Answer ->
  - Jest      -> all-in-one: test runner + assertions + mocking + coverage. The default. (≈ RSpec)
  - Vitest    -> Jest-compatible API, faster, great with Vite/ESM/TS. Rising fast.
  - Mocha     -> runner only; pair with Chai (assertions) + Sinon (mocks). Older but common.
  - Supertest -> HTTP assertions against an Express app (≈ Rails request specs / rack-test).
  - node:test -> Node's built-in test runner (no dependency) — fine for small projects.

  The test PYRAMID applies as in Rails: many fast unit tests, fewer integration tests, a few
  end-to-end. My RSpec "model specs + request specs" split maps to "unit tests + Supertest
  integration tests."
*/

/*
-----------------------------------------------------------------------------------------------
Question 2: Jest basics (the RSpec mapping)
-----------------------------------------------------------------------------------------------
Answer ->
  // sum.test.js
  const { sum } = require('./sum');

  describe('sum()', () => {                 // RSpec: describe "sum"
    it('adds two numbers', () => {           // RSpec: it "adds..."
      expect(sum(2, 3)).toBe(5);             // RSpec: expect(sum(2,3)).to eq(5)
    });

    it('handles negatives', () => {
      expect(sum(-1, -2)).toBe(-3);
    });
  });

  Common matchers:
    toBe(x)            -> strict === (primitives)        (RSpec eq / equal)
    toEqual(obj)       -> deep equality (objects/arrays)
    toStrictEqual(obj) -> deep + type-strict
    toContain(item)    -> array/string includes           (RSpec include)
    toThrow(Error)     -> function throws                  (RSpec raise_error)
    toHaveBeenCalledWith(args) -> mock assertions          (RSpec have_received)
    resolves / rejects -> for promises: await expect(p).resolves.toBe(x)

  Hooks: beforeEach / afterEach / beforeAll / afterAll  (RSpec before(:each)/(:all)).
*/

/*
-----------------------------------------------------------------------------------------------
Question 3: Testing async code (critical in Node)
-----------------------------------------------------------------------------------------------
Answer -> Return/await the promise so Jest waits for it; forgetting to await = false passes.

  it('fetches a user', async () => {
    const user = await getUser(1);
    expect(user.id).toBe(1);
  });

  // testing rejections
  it('throws on missing user', async () => {
    await expect(getUser(999)).rejects.toThrow('not found');
  });

  // resolves matcher
  it('resolves', async () => {
    await expect(Promise.resolve(42)).resolves.toBe(42);
  });
*/

/*
-----------------------------------------------------------------------------------------------
Question 4: Mocking (the part that's most different from RSpec)
-----------------------------------------------------------------------------------------------
Answer ->
  jest.fn()                 -> a mock function; assert how it was called.
  jest.spyOn(obj, 'method') -> wrap a real method; observe or override it.
  jest.mock('./module')     -> auto-mock or factory-mock an entire module (the import).

  // mock a function
  const send = jest.fn().mockResolvedValue({ ok: true });
  await notify(send);
  expect(send).toHaveBeenCalledWith('hello');
  expect(send).toHaveBeenCalledTimes(1);

  // mock a whole module (e.g. stub the DB layer in a service test)
  jest.mock('../repositories/userRepo');
  const userRepo = require('../repositories/userRepo');
  userRepo.findByEmail.mockResolvedValue(null);

  // spy + restore
  const spy = jest.spyOn(mailer, 'send').mockResolvedValue();
  // ... test ...
  spy.mockRestore();

  jest.mock is hoisted to the top of the file (a common surprise). RSpec's allow/receive maps
  to jest.fn/spyOn; instance_double maps to typed mocks (with TS) or manual mock objects.
*/

/*
-----------------------------------------------------------------------------------------------
Question 5: Integration tests with Supertest (= Rails request specs)
-----------------------------------------------------------------------------------------------
Answer -> Supertest fires real HTTP requests at your Express app (no need to run a server) and
asserts on the response. Export `app` WITHOUT calling listen() so tests can import it.

  const request = require('supertest');
  const app = require('../src/app');     // the express app (no .listen)

  describe('POST /api/v1/users', () => {
    it('creates a user', async () => {
      const res = await request(app)
        .post('/api/v1/users')
        .send({ name: 'Ann', email: 'a@b.com', password: 'secret12' })
        .expect(201);
      expect(res.body.data).toHaveProperty('id');
      expect(res.body.data.email).toBe('a@b.com');
    });

    it('rejects invalid input with 422', async () => {
      await request(app).post('/api/v1/users').send({ email: 'bad' }).expect(422);
    });

    it('requires auth on protected routes', async () => {
      await request(app).delete('/api/v1/users/1').expect(401);
    });
  });

  This is exactly my RSpec request-spec workflow (hit the endpoint, assert status + body),
  just with Supertest instead of rack-test.
*/

/*
-----------------------------------------------------------------------------------------------
Question 6: Test data, the DB, and isolation
-----------------------------------------------------------------------------------------------
Answer ->
  - Use a SEPARATE test database (NODE_ENV=test) and reset state between tests (truncate, or
    wrap each test in a transaction that rolls back — the RSpec DatabaseCleaner/transactional
    fixtures idea).
  - Factories instead of fixtures: fishery / factory.ts / faker generate test objects (the
    FactoryBot equivalent).
      const userFactory = Factory.define(() => ({ name: faker.person.fullName(),
                                                  email: faker.internet.email() }));
  - For pure unit tests, mock the repository so no DB is needed at all (fast).
  - testcontainers can spin up a real Postgres/Redis in Docker for integration tests in CI.
  - Make tests deterministic: control time (jest.useFakeTimers), seed randomness, no real
    network calls (mock external APIs with nock / msw).
*/

/*
-----------------------------------------------------------------------------------------------
Question 7: Coverage, CI, and good-test principles
-----------------------------------------------------------------------------------------------
Answer ->
  - jest --coverage produces a report; enforce thresholds in jest config (coverageThreshold)
    so coverage can't silently drop — the gate behind my "95%+ coverage" claim.
  - Run tests in CI on every PR (GitHub Actions): install, lint, type-check, test, coverage.
  - Good tests: test BEHAVIOR not implementation, one logical assertion focus per test, clear
    names ("returns 422 when email is invalid"), AAA structure (Arrange/Act/Assert), fast and
    independent (no shared mutable state, order-independent).
  - Test the important stuff: business rules, edge cases, error paths, auth/authorization,
    validation — not getters/trivial code. Coverage % is a means, not the goal.

  INTERVIEW SOUNDBITE: "I carry the same testing discipline from my Rails work — I hit 95%+
  with RSpec model and request specs. In Node that's Jest for unit tests with mocked
  repositories, Supertest for request-level integration tests, factories for data, a separate
  test DB with rollback isolation, and enforced coverage thresholds in CI."
*/

module.exports = {};
