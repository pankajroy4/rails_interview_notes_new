/*
===============================================================================================
                       TYPESCRIPT with NODE.JS
===============================================================================================
(I already have a typeScript.rb file in my Rails notes for the language itself — this file is
specifically TS-in-a-Node-backend: why, setup, and the patterns that come up in Node interviews.)
TypeScript is basically expected in serious Node shops. Coming from dynamically-typed Ruby, TS
gives me the safety Rails got from convention + tests, but at compile time.
*/

/*
-----------------------------------------------------------------------------------------------
Question 1: Why TypeScript on the backend?
-----------------------------------------------------------------------------------------------
Answer -> TS adds a static type system on top of JavaScript, checked at COMPILE time, then
compiled (transpiled) to plain JS that Node runs. Benefits for a backend:
  - Catch bugs before runtime (wrong shapes, null/undefined, typos) — huge in a dynamic lang.
  - Self-documenting APIs: function signatures + DTO types are the contract.
  - Refactoring confidence: rename/restructure and the compiler finds every break.
  - Editor superpowers: autocomplete, inline docs, go-to-definition.

  Coming from Ruby (no types), this is the biggest new discipline — but it's the same instinct
  as writing good tests: shift errors left, make contracts explicit. Ruby had Sorbet/RBS for
  this; in Node it's TS, and it's mainstream, not optional.
*/

/*
-----------------------------------------------------------------------------------------------
Question 2: How TS runs in a Node project (the build story)
-----------------------------------------------------------------------------------------------
Answer -> Node can't run .ts directly (historically); you compile or use a loader:
  - tsc (the compiler): tsconfig.json -> compiles src/*.ts to dist/*.js; `node dist/index.js`.
  - ts-node / tsx: run .ts directly in dev (no separate build step) — great for local dev.
  - Bundlers/transpilers: esbuild / swc are very fast TS->JS transpilers used in build pipelines.
  - Modern Node (recent versions) has experimental native TS stripping, but tsc/tsx is still
    the norm.

  Typical scripts:
    "dev":   "tsx watch src/index.ts",
    "build": "tsc",
    "start": "node dist/index.js"

  tsconfig.json essentials: "target": "ES2022", "module": "NodeNext", "strict": true,
  "outDir": "dist", "rootDir": "src", "esModuleInterop": true. ALWAYS turn on "strict".
*/

/*
-----------------------------------------------------------------------------------------------
Question 3: Core types you use constantly in a Node backend
-----------------------------------------------------------------------------------------------
Answer ->
  // basic annotations
  function add(a: number, b: number): number { return a + b; }

  // interfaces / types for DTOs and entities
  interface User { id: number; email: string; name?: string; role: 'user' | 'admin'; }
  type CreateUserDto = Omit<User, 'id'>;              // utility type

  // generics (e.g. a typed repository)
  interface Repository<T> { findById(id: number): Promise<T | null>; create(data: Partial<T>): Promise<T>; }

  // async return types are Promise<T>
  async function getUser(id: number): Promise<User | null> { /* ... */ }

  // union + narrowing
  type Result<T> = { ok: true; value: T } | { ok: false; error: string };

  Key utility types to name-drop: Partial<T>, Required<T>, Pick<T,K>, Omit<T,K>, Record<K,V>,
  Readonly<T>, Awaited<T>, ReturnType<T>. They model real backend shapes cleanly.
*/

/*
-----------------------------------------------------------------------------------------------
Question 4: Typing Express (a common practical question)
-----------------------------------------------------------------------------------------------
Answer ->
  import { Request, Response, NextFunction } from 'express';

  // typed request body via generics: Request<Params, ResBody, ReqBody, Query>
  function createUser(req: Request<{}, {}, CreateUserDto>, res: Response, next: NextFunction) {
    const { email } = req.body;     // typed as CreateUserDto
    res.status(201).json({ email });
  }

  // augmenting Request to add req.user (after auth middleware) — declaration merging
  declare global {
    namespace Express {
      interface Request { user?: { id: number; role: string }; }
    }
  }

  This (extending Request with req.user) is the canonical "have you used TS with Express?" check.
*/

/*
-----------------------------------------------------------------------------------------------
Question 5: TS + validation = one source of truth (Zod)
-----------------------------------------------------------------------------------------------
Answer -> The slick modern pattern: define a Zod schema ONCE and derive the TS type from it, so
runtime validation and compile-time types can't drift apart.

  import { z } from 'zod';
  const CreateUserSchema = z.object({ email: z.string().email(), name: z.string().min(2) });
  type CreateUserDto = z.infer<typeof CreateUserSchema>;   // type derived from the schema

  Now the validator and the type are guaranteed consistent. This solves a real problem: TS
  types vanish at runtime (they're erased), so you STILL need runtime validation at the
  boundary — Zod gives you both from one definition.
*/

/*
-----------------------------------------------------------------------------------------------
Question 6: The big gotcha — types are erased at runtime
-----------------------------------------------------------------------------------------------
Answer -> TS types DON'T exist at runtime; they're stripped during compilation. Consequences:
  - You can't validate external input using a TS interface alone — a malicious client can send
    anything. You MUST validate at runtime (Zod/Joi) at the edges (API bodies, queue payloads,
    third-party responses). TS protects YOUR code's internal consistency, not untrusted input.
  - `any` defeats the whole system; prefer `unknown` and narrow it. Lint against `any`.
  - Type assertions (`as User`) are promises you make to the compiler — they can lie. Avoid
    casting untrusted data; validate instead.

  "TypeScript secures the boundary BETWEEN my functions; runtime validation secures the
   boundary between my app and the outside world. I use both." — clean, senior framing.
*/

/*
-----------------------------------------------------------------------------------------------
Question 7: Quick wins to mention
-----------------------------------------------------------------------------------------------
Answer ->
  - "strict": true (and strictNullChecks) — the whole point; turn it on day one.
  - Type your service/repository layer + DTOs; let inference handle the rest.
  - Use discriminated unions for result/error types instead of throwing everywhere.
  - Generics for reusable repos/utilities.
  - Don't over-engineer types — readable, correct types beat clever ones.
  - NestJS is TS-native (decorators, DI, DTOs) — pairs naturally with everything above.
*/

module.exports = {};
