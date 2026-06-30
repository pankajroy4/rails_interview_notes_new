/*
===============================================================================================
                       AUTHENTICATION, AUTHORIZATION & SECURITY
===============================================================================================
Maps to Devise + Pundit + Rails' built-in protections from my Rails notes. In Node you wire
these yourself, so understanding the mechanics (not just the gem) matters more.
*/

/*
-----------------------------------------------------------------------------------------------
Question 1: Authentication vs Authorization (don't mix them up)
-----------------------------------------------------------------------------------------------
Answer ->
  AUTHENTICATION (authn) = "who are you?" — verifying identity (login). 401 if it fails.
  AUTHORIZATION (authz)  = "what are you allowed to do?" — permissions/roles. 403 if it fails.

  Rails analogy: Devise = authentication, Pundit/CanCanCan = authorization. In Node: a JWT or
  session handles authn; middleware/guards (or casl) handle authz.
*/

/*
-----------------------------------------------------------------------------------------------
Question 2: Password hashing — bcrypt (NEVER store plaintext)
-----------------------------------------------------------------------------------------------
Answer -> Hash passwords with a SLOW, salted algorithm (bcrypt / argon2 / scrypt). Never store
or log plaintext; never use fast hashes (md5/sha256) for passwords (too easy to brute-force).

  const bcrypt = require('bcrypt');

  // on signup
  const hash = await bcrypt.hash(plainPassword, 12);   // 12 = cost factor (work)
  // store `hash` in the DB

  // on login
  const ok = await bcrypt.compare(plainPassword, user.passwordHash);
  if (!ok) throw new UnauthorizedError();

  - The "salt" is generated and embedded in the hash automatically -> identical passwords get
    different hashes, defeating rainbow tables.
  - Cost factor (rounds) makes hashing deliberately slow; bump it as hardware improves.
  - bcrypt is CPU-bound and uses the libuv thread pool — fine, but heavy login bursts can add
    event-loop pressure; argon2 is the modern recommendation.
*/

/*
-----------------------------------------------------------------------------------------------
Question 3: JWT (JSON Web Tokens) — the dominant API auth method
-----------------------------------------------------------------------------------------------
Answer -> A JWT is a stateless, signed token the client sends on each request (usually
`Authorization: Bearer <token>`). The server VERIFIES the signature instead of looking up a
session — so no server-side session store is needed (fits REST's statelessness, scales well).

  Structure (3 base64url parts separated by dots): header.payload.signature
    header    -> { "alg": "HS256", "typ": "JWT" }
    payload   -> claims: { "sub": userId, "role": "admin", "iat": ..., "exp": ... }
    signature -> HMAC/ RSA signature over header+payload using a secret/private key

  IMPORTANT: the payload is ENCODED (base64), NOT encrypted — anyone can read it. Never put
  secrets/passwords in a JWT. The signature only guarantees it wasn't TAMPERED with.

  const jwt = require('jsonwebtoken');

  // issue on login
  const token = jwt.sign({ sub: user.id, role: user.role }, process.env.JWT_SECRET,
                         { expiresIn: '15m' });

  // verify in middleware
  const payload = jwt.verify(token, process.env.JWT_SECRET);   // throws if invalid/expired
  req.user = payload;
*/

/*
-----------------------------------------------------------------------------------------------
Question 4: Access tokens + refresh tokens (the real-world pattern)
-----------------------------------------------------------------------------------------------
Answer -> Short-lived access token + long-lived refresh token balances security and UX:
  - ACCESS token: short expiry (e.g. 15 min), sent on every API call. If stolen, it's only
    useful briefly.
  - REFRESH token: long expiry (days/weeks), stored securely (httpOnly cookie ideally), used
    ONLY to get a new access token when the old one expires.

  Why: pure JWTs can't be "revoked" before they expire (they're stateless). So:
   - Keep access tokens short.
   - Store refresh tokens server-side (DB/Redis) so you CAN revoke them (logout, password
     change, "log out all devices") — this re-introduces a little state by design.
   - Rotate refresh tokens on use and detect reuse (theft detection).

  This stateless-vs-revocation tension is a favorite interview discussion.
*/

/*
-----------------------------------------------------------------------------------------------
Question 5: JWT vs sessions (know the trade-off)
-----------------------------------------------------------------------------------------------
Answer ->
  SESSIONS (stateful):
    - Server stores session data (in Redis/DB), client holds only a session ID cookie.
    - Easy to REVOKE (delete the session). Natural for server-rendered apps.
    - Needs a shared session store across instances when scaling horizontally.
  JWT (stateless):
    - Nothing stored server-side; the token IS the state. Scales trivially across instances.
    - Hard to revoke before expiry (need a denylist/short expiry + refresh tokens).
    - Great for APIs, mobile, and microservices (pass the token between services).

  Rule of thumb: APIs/microservices -> JWT; traditional server-rendered session-y app ->
  cookie sessions. Many real apps use httpOnly cookies to STORE a JWT (best of both for web).
*/

/*
-----------------------------------------------------------------------------------------------
Question 6: Where to store the token on the client (security nuance)
-----------------------------------------------------------------------------------------------
Answer ->
  - localStorage: easy, but readable by JS -> vulnerable to XSS (a script can steal the token).
  - httpOnly, Secure, SameSite cookie: JS can't read it -> safe from XSS token theft, but you
    must defend against CSRF (use SameSite=Strict/Lax + CSRF tokens for state-changing requests).
  Best practice for web: store tokens in httpOnly Secure cookies; for mobile, secure storage.
*/

/*
-----------------------------------------------------------------------------------------------
Question 7: Passport.js (the Devise-ish ecosystem) + RBAC authorization
-----------------------------------------------------------------------------------------------
Answer ->
  Passport.js is a flexible authentication middleware with 500+ "strategies" (local username/
  password, JWT, OAuth Google/GitHub/Facebook, SAML). You pick strategies and Passport handles
  the plumbing. Good when you need social login / OAuth.

  AUTHORIZATION (RBAC) is usually just middleware (the Pundit equivalent):

  const authorize = (...allowedRoles) => (req, res, next) => {
    if (!req.user) return res.status(401).json({ error: 'unauthenticated' });
    if (!allowedRoles.includes(req.user.role)) return res.status(403).json({ error: 'forbidden' });
    next();
  };
  app.delete('/users/:id', requireAuth, authorize('admin'), deleteUser);

  For fine-grained, attribute-based rules (this user can edit THIS post), use a library like
  casl, or write policy functions per resource (the Pundit policy-object pattern translated).
*/

/*
-----------------------------------------------------------------------------------------------
Question 8: OWASP Top 10 in a Node/Express context (security checklist)
-----------------------------------------------------------------------------------------------
Answer -> Rails gives many of these for free; in Node I wire them explicitly.

  1. Injection (SQL/NoSQL):
     - Use parameterized queries / the ORM; NEVER string-concatenate user input into queries.
     - NoSQL injection: an attacker sends { "$gt": "" } as a value -> sanitize/validate input
       types (express-mongo-sanitize), and validate with Joi/Zod so a string field can't become
       an operator object.

  2. Broken auth:
     - bcrypt/argon2 hashing, short-lived JWTs, rate-limit login, lock accounts on brute force.

  3. XSS (Cross-Site Scripting):
     - Escape output; for APIs returning JSON, set correct Content-Type; sanitize HTML if you
       render user content. helmet sets a Content-Security-Policy.

  4. CSRF (Cross-Site Request Forgery):
     - For cookie-based auth, use SameSite cookies + CSRF tokens (csurf). Token-in-header
       (Authorization: Bearer) APIs are largely immune since the browser won't auto-attach it.

  5. Security headers: use helmet() -> HSTS, X-Content-Type-Options, X-Frame-Options, CSP.

  6. Sensitive data exposure: HTTPS everywhere, don't log secrets/PII, hash passwords,
     keep secrets in env/secrets manager, never commit .env.

  7. Misconfiguration: disable x-powered-by (app.disable('x-powered-by')), least-privilege DB
     users, lock down CORS to known origins (not '*').

  8. Rate limiting / DoS: express-rate-limit (Redis-backed), body size limits
     (express.json({ limit: '1mb' })), guard against ReDoS regexes.

  9. Vulnerable dependencies: npm audit / Snyk / Dependabot in CI (bundler-audit equivalent).

  10. Insufficient logging/monitoring: structured logs, alerting, audit trails for sensitive ops.
*/

/*
-----------------------------------------------------------------------------------------------
Question 9: A compact "secure my Express API" answer
-----------------------------------------------------------------------------------------------
Answer (interview soundbite) ->
  "I layer security like I did in Rails. At the app edge: helmet for headers, CORS locked to
   known origins, express-rate-limit on auth and public endpoints, and body-size limits. For
   authn I use bcrypt/argon2 for passwords and short-lived JWTs with refresh tokens stored
   server-side so I can revoke them. For authz I use role/policy middleware (the Pundit idea).
   I validate every input with Zod so injection and type-confusion attacks are blocked at the
   boundary, use parameterized ORM queries, keep secrets in env/secrets manager, run npm audit
   in CI, and serve only over HTTPS. Security is layers, not one switch."
*/

module.exports = {};
