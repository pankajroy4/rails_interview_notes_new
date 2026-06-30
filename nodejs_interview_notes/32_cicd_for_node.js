/*
===============================================================================================
                       CI/CD for NODE.JS (GitHub Actions)
===============================================================================================
(Mirrors my ci_cd_pipelines_questions.rb. The CONCEPTS — CI vs CD, why it matters, secrets,
pipeline stages — are identical to my Rails notes. Only the steps change: npm ci / lint / jest /
build instead of bundle install / rubocop / rspec.)
*/

/*
-----------------------------------------------------------------------------------------------
Q1: CI vs CD (concepts unchanged from my Rails notes)
-----------------------------------------------------------------------------------------------
Answer ->
  CONTINUOUS INTEGRATION (CI): merge code frequently into a shared branch; on every push/PR,
  automatically build, lint, type-check, and test. Catches issues early, prevents broken builds.

  CONTINUOUS DELIVERY (CD): every passing change is automatically built + ready to deploy, but the
  production release may need a manual approval.

  CONTINUOUS DEPLOYMENT: one step further — if the pipeline is green, it auto-deploys to prod with
  no manual gate.

  Why it matters: speed + fewer human errors + consistent, repeatable deploys + fast feedback. It
  prevents "integration hell" and de-risks releases. (Exactly my Rails answer — process is
  language-agnostic.)
*/

/*
-----------------------------------------------------------------------------------------------
Q2: Typical CI pipeline for a Node app (the Rails steps, translated)
-----------------------------------------------------------------------------------------------
Answer ->
  RAILS CI                         NODE CI
  ------------------------------   ----------------------------------------
  checkout                         checkout
  bundle install                   npm ci          (reproducible from package-lock.json)
  setup DB (Postgres service)      setup DB (Postgres/Redis service containers)
  db:schema:load / db:migrate      run migrations (prisma migrate deploy / knex migrate:latest)
  rubocop (lint)                   eslint (lint) + prettier --check (format)
  (sorbet)                         tsc --noEmit    (TypeScript type-check)
  rspec                            jest (unit + supertest integration) + coverage
  brakeman / bundler-audit         npm audit / snyk
  -> build artifact / image        npm run build + docker build + push image

  Flow: checkout -> install deps -> lint + type-check -> test (with DB/Redis services) -> security
  scan -> build the Docker image -> push to registry -> (CD) deploy.
*/

/*
-----------------------------------------------------------------------------------------------
Q3: A real GitHub Actions workflow (CI) for a Node/TS app
-----------------------------------------------------------------------------------------------
Answer ->
  # .github/workflows/ci.yml
  name: CI
  on:
    push: { branches: [main] }
    pull_request:

  jobs:
    test:
      runs-on: ubuntu-latest
      services:                                   # ephemeral DB/Redis for integration tests
        postgres:
          image: postgres:16
          env: { POSTGRES_PASSWORD: postgres, POSTGRES_DB: app_test }
          ports: ['5432:5432']
          options: >-
            --health-cmd pg_isready --health-interval 10s --health-timeout 5s --health-retries 5
        redis:
          image: redis:7
          ports: ['6379:6379']
      env:
        DATABASE_URL: postgres://postgres:postgres@localhost:5432/app_test
        REDIS_URL: redis://localhost:6379
      steps:
        - uses: actions/checkout@v4
        - uses: actions/setup-node@v4
          with: { node-version: 20, cache: 'npm' }   # cache npm for faster installs
        - run: npm ci
        - run: npm run lint                            # eslint
        - run: npx tsc --noEmit                        # type-check
        - run: npm run migrate                          # apply migrations to the test DB
        - run: npm test -- --coverage                   # jest + supertest + coverage
        - run: npm audit --audit-level=high || true     # dependency scan (non-blocking here)

  Key bits: `services:` gives a throwaway Postgres+Redis (the request-spec DB from my Rails CI),
  `cache: npm` speeds installs, and `npm ci` guarantees the lock-file versions.
*/

/*
-----------------------------------------------------------------------------------------------
Q4: The CD half — build image and deploy
-----------------------------------------------------------------------------------------------
Answer ->
  # .github/workflows/deploy.yml (runs on push to main, after CI passes)
  jobs:
    deploy:
      runs-on: ubuntu-latest
      steps:
        - uses: actions/checkout@v4
        - run: docker build -t $ECR_REPO:${{ github.sha }} .
        - run: |                                   # auth + push to ECR (registry)
            aws ecr get-login-password | docker login --username AWS --password-stdin $ECR_REGISTRY
            docker push $ECR_REPO:${{ github.sha }}
        - run: aws ecs update-service --cluster prod --service api --force-new-deployment

  Deploy targets differ by stack: ECS Fargate (push image, update service -> rolling deploy),
  Kubernetes (kubectl set image / Helm / ArgoCD), or PM2 over SSH for EC2 (`pm2 reload`). The CD
  step does a ROLLING, zero-downtime deploy with health checks (file 26 Q9).
*/

/*
-----------------------------------------------------------------------------------------------
Q5: Secrets in CI/CD (never commit them — same rule as Rails)
-----------------------------------------------------------------------------------------------
Answer -> Never put secrets in the repo or the workflow file. Use the CI provider's encrypted
secret store (GitHub Actions Secrets / OIDC) and inject as env at runtime:
    env: { JWT_SECRET: ${{ secrets.JWT_SECRET }} }
  In Rails I injected RAILS_MASTER_KEY; in Node it's DATABASE_URL, JWT_SECRET, AWS creds, etc.
  Better still: GitHub OIDC -> assume an AWS IAM role with no long-lived keys at all. Prod secrets
  live in AWS Secrets Manager/SSM and are pulled at deploy/runtime.
*/

/*
-----------------------------------------------------------------------------------------------
Q6: Branch protection / quality gates (ties to my "automated review" Rails answer)
-----------------------------------------------------------------------------------------------
Answer -> Make CI a GATE, not a suggestion:
  - Branch protection on main: required status checks (lint, type-check, tests, coverage) must pass
    before merge; require PR review.
  - Coverage threshold enforced in jest config so coverage can't silently drop (my 95%+ discipline).
  - Add automated PR review tooling: ESLint + a security linter, Dependabot/Snyk for dep CVEs,
    and optionally CodeQL. This is the Node version of my Rails answer — "juniors get instant
    automated feedback, humans review architecture and business logic." Tools change (RuboCop ->
    ESLint, Brakeman -> CodeQL/npm audit), the philosophy is identical.

  Tools I'd name: GitHub Actions / GitLab CI / Jenkins (concepts are the same: pipeline steps,
  test, deploy with environments + secrets).
*/

module.exports = {};
