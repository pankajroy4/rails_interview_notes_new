/*
===============================================================================================
                       MODULES (CommonJS vs ESM) and the npm ECOSYSTEM
===============================================================================================
Coming from Rails: this replaces `require`/`require_relative` + Bundler/Gemfile. The module
system question ("CommonJS vs ESM") comes up constantly.
*/

/*
-----------------------------------------------------------------------------------------------
Question 1: What is a module in Node?
-----------------------------------------------------------------------------------------------
Answer -> In Node, every file is its own module with its own scope. Variables declared in a
file are private to that file unless you explicitly export them. This avoids the global-scope
pollution problem of old browser JS. There are two module systems:
  - CommonJS (CJS): the original Node system — require() / module.exports. Synchronous.
  - ES Modules (ESM): the JavaScript standard — import / export. Asynchronous, statically
    analyzable. Works in browsers and Node.
*/

/*
-----------------------------------------------------------------------------------------------
Question 2: CommonJS — require / module.exports
-----------------------------------------------------------------------------------------------
Answer ->
  // math.js
  function add(a, b) { return a + b; }
  function sub(a, b) { return a - b; }
  module.exports = { add, sub };          // export an object
  // OR: module.exports.add = add;  module.exports.sub = sub;
  // OR single export: module.exports = add;

  // app.js
  const { add } = require('./math');      // destructure what you need
  const math = require('./math');          // or grab the whole object
  console.log(add(2, 3));

  Key facts about require():
   - It is SYNCHRONOUS — it reads + executes the file right then. Fine because modules load at
     startup, not per-request.
   - It is CACHED — a module's code runs only ONCE; subsequent require() calls return the same
     cached exports object (require.cache). This is why module-level code (e.g. a DB connection)
     acts like a singleton.
   - `exports` is just a reference to module.exports. Reassigning `exports = {...}` BREAKS the
     link (use module.exports = ... instead). This is a classic gotcha.
*/

/*
-----------------------------------------------------------------------------------------------
Question 3: ES Modules — import / export
-----------------------------------------------------------------------------------------------
Answer ->
  // math.mjs  (or .js with "type":"module" in package.json)
  export function add(a, b) { return a + b; }     // named export
  export const PI = 3.14;
  export default function () {}                    // default export

  // app.mjs
  import addDefault, { add, PI } from './math.mjs';
  import * as math from './math.mjs';

  Enable ESM by either:
   - file extension .mjs, OR
   - "type": "module" in package.json (then .js files are ESM; use .cjs for CommonJS).

  Differences from CommonJS:
   - import/export are STATIC (must be top-level, hoisted) — enables tree-shaking by bundlers.
   - imports are ASYNCHRONOUS and resolved before execution.
   - top-level await is allowed in ESM (not in CJS).
   - __dirname / __filename DON'T exist in ESM; derive them:
        import { fileURLToPath } from 'url';
        import { dirname } from 'path';
        const __filename = fileURLToPath(import.meta.url);
        const __dirname = dirname(__filename);
   - You can dynamically import CJS from ESM with await import('...'), but importing ESM from
     CJS requires dynamic import() too (can't `require` an ESM module directly, historically).
*/

/*
-----------------------------------------------------------------------------------------------
Question 4: CommonJS vs ESM — the interview comparison
-----------------------------------------------------------------------------------------------
Answer ->
  ASPECT              CommonJS (require)            ES Modules (import)
  -----------------   ---------------------------   ---------------------------------
  Syntax              require / module.exports      import / export
  Loading             synchronous                   asynchronous
  Timing              resolved at runtime           resolved/hoisted before execution
  Analysis            dynamic (can require in if)   static (top-level only) -> tree-shakeable
  Top-level await     no                            yes
  __dirname           available                     no (use import.meta.url)
  Caching             require.cache                 module registry
  Default in Node     historically yes              the modern standard; opt-in via "type"
  Browser support     no (needs bundler)            native

  What I say: "CommonJS is Node's original synchronous system and still everywhere; ESM is the
  official standard, statically analyzable, tree-shakeable, and what new code uses, especially
  with TypeScript. Many projects use ESM with a bundler/transpiler. The main practical pain is
  interop between the two."
*/

/*
-----------------------------------------------------------------------------------------------
Question 5: Module resolution — how Node finds a module
-----------------------------------------------------------------------------------------------
Answer -> When you require/import 'x', Node resolves it in this order:
  1. Core module? (e.g. 'fs', 'http', 'node:path') -> use the built-in.
  2. Starts with './' or '../' or '/'? -> a file/folder path. Node tries x, x.js, x.json,
     x.node, then x/index.js, then x/package.json "main"/"exports".
  3. Otherwise it's a package -> walk UP the directory tree looking in node_modules/x at each
     level until found (or error). This is why nested node_modules can exist.

  package.json "exports" field (modern) controls what paths a package exposes and can map
  different entry points for require vs import (conditional exports).
*/

/*
-----------------------------------------------------------------------------------------------
Question 6: package.json — the Gemfile of Node
-----------------------------------------------------------------------------------------------
Answer -> package.json is the manifest for a Node project. Key fields:

  {
    "name": "my-api",
    "version": "1.2.3",
    "type": "module",                 // or "commonjs"
    "main": "dist/index.js",          // entry point for require()
    "exports": { ".": "./dist/index.js" },
    "scripts": {
      "start": "node dist/index.js",
      "dev": "nodemon src/index.js",
      "test": "jest",
      "build": "tsc"
    },
    "dependencies": {                  // needed at runtime (like Gemfile :default group)
      "express": "^4.19.2"
    },
    "devDependencies": {               // needed only in dev/test (like Gemfile :development)
      "jest": "^29.7.0",
      "typescript": "^5.4.0"
    },
    "engines": { "node": ">=18" }
  }

  - dependencies vs devDependencies: runtime vs dev-only (npm install --production skips dev).
  - scripts: run with `npm run <name>` (start/test are special: `npm start`, `npm test`).
*/

/*
-----------------------------------------------------------------------------------------------
Question 7: Semantic versioning (semver) and the ^ ~ symbols
-----------------------------------------------------------------------------------------------
Answer -> Versions are MAJOR.MINOR.PATCH (e.g. 4.19.2):
  - MAJOR: breaking changes
  - MINOR: new features, backward compatible
  - PATCH: bug fixes, backward compatible

  Range operators:
  - ^4.19.2  -> allow MINOR + PATCH updates: >=4.19.2 <5.0.0  (most common default)
  - ~4.19.2  -> allow PATCH only: >=4.19.2 <4.20.0
  - 4.19.2   -> exact pin
  - *        -> any version (dangerous)

  package-lock.json (the Gemfile.lock equivalent) records the EXACT resolved versions of the
  whole dependency tree so installs are reproducible across machines/CI. Always commit it.
  `npm ci` installs strictly from the lock file (use in CI); `npm install` may update it.
*/

/*
-----------------------------------------------------------------------------------------------
Question 8: npm vs yarn vs pnpm; common commands
-----------------------------------------------------------------------------------------------
Answer -> All three install packages from the npm registry; they differ in speed/lockfiles/
disk usage:
  - npm   -> default, ships with Node. package-lock.json.
  - yarn  -> faster historically, yarn.lock, workspaces.
  - pnpm  -> uses a content-addressable store + symlinks -> huge disk savings, strict, fast.
           Increasingly popular for monorepos.

  Common npm commands (Bundler equivalents in parentheses):
    npm install                 (bundle install)
    npm install express         (add a gem + bundle)
    npm install -D jest         (add to :development group)
    npm ci                      (bundle install --deployment, reproducible from lock)
    npm uninstall express
    npm update
    npm run <script>            (rake task-ish)
    npm audit / npm audit fix   (bundler-audit)
    npx <bin>                   (run a package binary without installing globally)
    npm outdated
*/

/*
-----------------------------------------------------------------------------------------------
Question 9: Security & supply chain (be ready, it's a maturity signal)
-----------------------------------------------------------------------------------------------
Answer -> npm's huge ecosystem of small packages is powerful but a supply-chain risk:
  - Run `npm audit` (and in CI) to catch known CVEs; tools like Snyk/Dependabot automate it.
  - Pin versions + commit the lock file; review what `postinstall` scripts a package runs.
  - Watch for typosquatting (expres vs express) and unmaintained packages.
  - Prefer fewer, well-maintained deps; use core modules when reasonable.
  This is the Node equivalent of bundler-audit + careful Gemfile hygiene in my Rails work.
*/

module.exports = {};
