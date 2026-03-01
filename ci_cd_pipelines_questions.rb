=================================== CI/CD pipelines ==================================================
Question 1: What is CI/CD?

Answer -> CI/CD stands for Continuous Integration and Continuous Delivery or Deployment. CI ensures that code changes are merged frequently, automatically built, and tested. CD automates the process of releasing these changes safely to staging or production.
 
------------------------------------------------------------------------------------------------------
Question 2: What is Continuous Integration (CI)?

Answer -> Continuous Integration is the practice of frequently integrating code into a shared branch and automatically running builds and tests. It helps detect issues early and prevents broken builds.
 
------------------------------------------------------------------------------------------------------
Question 3: What is Continuous Delivery?

Answer -> Continuous Delivery means every change is automatically built, tested, and ready to be deployed at any time, but deployment may still require manual approval.
 
------------------------------------------------------------------------------------------------------
Question 4: What is Continuous Deployment?

Answer -> Continuous Deployment goes one step further—if the pipeline passes, changes are automatically deployed to production without manual approval.
 
------------------------------------------------------------------------------------------------------
Question 5: Why is CI/CD important?

Answer -> CI/CD improves delivery speed, reduces human errors, ensures consistent deployments, and increases confidence by running automated tests, linters, and checks for every change.
 
------------------------------------------------------------------------------------------------------
Question 6: What problems does CI/CD solve?

Answer -> It prevents integration hell, reduces deployment risks, catches bugs early, automates repetitive tasks, and provides fast feedback to developers.
 
------------------------------------------------------------------------------------------------------
Question 7: What are common CI steps for a Rails application?

Answer -> Typical CI steps include checking out code, installing dependencies, setting up the database, running migrations, running RSpec tests, running linters like RuboCop, and sometimes running security scanners like Brakeman.
 
------------------------------------------------------------------------------------------------------
Question 8: What is the typical CI pipeline flow for Rails?

Answer -> Checkout → bundle install → setup DB → rails db:create db:schema:load → run tests → run lint/security checks → generate artifacts like coverage reports.
 
------------------------------------------------------------------------------------------------------
Question 9: How do you set up database in CI for Rails?

Answer -> Usually we use Postgres or MySQL services in CI, set DATABASE_URL, and run rails db:create db:schema:load or db:migrate. Using schema load is faster for tests.
 
------------------------------------------------------------------------------------------------------
Question 10: Why is schema:load faster than migrate in CI?

Answer -> schema:load creates the test DB in one shot instead of running many migrations, so it is much faster and reduces CI time.
 
------------------------------------------------------------------------------------------------------
Question 11: How do you handle assets in CI for Rails?

Answer -> In CI we usually skip heavy asset compilation unless required. In production pipelines, we run rails assets:precompile during build time.
 
------------------------------------------------------------------------------------------------------
Question 12: How do you handle Rails credentials in CI?

Answer -> We never commit secrets. CI/CD tools provide secure secret storage. For Rails, we inject RAILS_MASTER_KEY and other credentials as environment variables or secret files.
 
------------------------------------------------------------------------------------------------------
Question 13: Which CI/CD tools have you used?

Answer -> I have worked with tools like GitHub Actions / GitLab CI / Jenkins. The concepts are similar: define pipeline steps, run tests, and deploy using environments and secrets.
 
------------------------------------------------------------------------------------------------------
Question 14: What is Jenkins?

Answer -> Jenkins is an open-source automation server used to create CI/CD pipelines. Pipelines are usually written using Jenkinsfiles and support custom workflows.
 
------------------------------------------------------------------------------------------------------
Question 15: What is GitHub Actions?

Answer -> GitHub Actions is GitHub’s CI/CD platform. Workflows are defined in YAML and can run on push/PR events, build/test apps, and deploy automatically.
 
------------------------------------------------------------------------------------------------------
Question 16: What are common stages in a CI/CD pipeline?

Answer ->  Build, test, quality checks, security scanning, packaging, deploy to staging, approval step, deploy to production, and post-deploy monitoring.
 
------------------------------------------------------------------------------------------------------
Question 17: What is the "build" step in Rails CI/CD?

Answer ->  Build means installing dependencies and preparing artifacts—like gems, JS packages, and compiled assets—so we can run tests or deploy consistently. 
 
------------------------------------------------------------------------------------------------------
Question 18: What checks would you add beyond unit tests?

Answer ->  I would add RuboCop for linting, Brakeman for security checks, bundler-audit for vulnerable gems, and maybe coverage thresholds. 
 
------------------------------------------------------------------------------------------------------
Question 19: Why do we run RuboCop in CI?

Answer ->  RuboCop enforces consistent coding standards and catches code smells early so codebase remains maintainable. 
 
------------------------------------------------------------------------------------------------------
Question 20: What is Brakeman?

Answer ->  Brakeman is a static security scanner for Rails. It detects common security vulnerabilities like SQL injection, XSS issues, and unsafe mass assignment patterns. 
 
------------------------------------------------------------------------------------------------------
Question 21: What is bundler-audit?

Answer ->  It checks gem dependencies against known security vulnerabilities and warns if a gem version is insecure. 
 
------------------------------------------------------------------------------------------------------
Question 22: What is deployment automation?

Answer ->  It means deployment steps like building, releasing, migrating, restarting services are automated and repeatable rather than manual. 
 
------------------------------------------------------------------------------------------------------
Question 23: What is a deployment artifact?

Answer ->  An artifact is the output of the build that gets deployed—like a Docker image, tarball, or compiled build. 
 
------------------------------------------------------------------------------------------------------
Question 24: Why do we deploy artifacts instead of code?

Answer ->  Deploying artifacts ensures reproducibility. The exact same build that passed tests in CI gets deployed, reducing environment drift. 
 
------------------------------------------------------------------------------------------------------
Question 25: What is Blue-Green deployment?

Answer ->  In blue-green deployment, we maintain two production environments. Blue is live, green is the new version. Once green is ready, we switch traffic. Rollback is easy by switching back. 
 
------------------------------------------------------------------------------------------------------
Question 26: What is Canary deployment?

Answer ->  Canary deployment releases a new version to a small percentage of users first. If metrics look good, we increase traffic gradually. 
 
------------------------------------------------------------------------------------------------------
Question 27: What is Rolling deployment?

Answer ->  Rolling deployment updates servers gradually—some instances run old version while others run new version until the rollout completes. 
 
------------------------------------------------------------------------------------------------------
Question 28: Which deployment strategy is safest?

Answer ->  Blue-green and canary are usually safer because they allow quick rollback and controlled rollout. 
 
------------------------------------------------------------------------------------------------------
Question 29: How do you handle DB migrations in CI/CD?

Answer ->  Migrations are usually run during deployment as a separate step. We ensure they are backward-compatible so old and new app versions can run during rollout. 
 
------------------------------------------------------------------------------------------------------
Question 30: What is a backward-compatible migration?

Answer ->  It means the migration does not break the old code while the new deployment is rolling out. For example, add new columns first, deploy code, then remove old columns later. 
 
------------------------------------------------------------------------------------------------------
Question 31: Why is migration planning important in rolling deployments?

Answer ->  Because during rollout, multiple app versions may run simultaneously. Non-compatible migrations can crash old instances and cause downtime. 
 
------------------------------------------------------------------------------------------------------
Question 32: How do you avoid downtime while deploying migrations?

Answer ->  Use zero-downtime migration practices: add columns with defaults carefully, avoid locking operations, use background jobs for backfills, and deploy schema changes in phases. 
 
------------------------------------------------------------------------------------------------------
Question 33: How do you deploy Sidekiq in CI/CD?

Answer ->  Sidekiq workers are deployed along with the Rails release. We restart workers after deploy so they run the latest code. 
 
------------------------------------------------------------------------------------------------------
Question 34: What happens if job code changes during deployment?

Answer ->  Old workers might pick up new jobs or incompatible payloads. We handle it using job versioning, backward-compatible job formats, and graceful restarts. 
 
------------------------------------------------------------------------------------------------------
Question 35: What is rollback?

Answer ->  Rollback means reverting production to the previous stable version if deployment fails or causes issues. 
 
------------------------------------------------------------------------------------------------------
Question 36: How do you rollback safely in Rails?

Answer ->  Rollback app version and ensure DB changes are compatible. Ideally migrations are reversible or schema changes are designed so old code still works. 
 
------------------------------------------------------------------------------------------------------
Question 37: What if migration has already been run but you rollback app code?

Answer ->  This is why backward-compatible migrations matter. If a breaking migration is applied and app code is rolled back, it can break. The safe approach is multi-step migration releases. 
 
------------------------------------------------------------------------------------------------------
Question 38: What are environments in CI/CD?

Answer ->  Environments are stages like development, staging, and production. Each environment can have different configs and deployment approvals. 
 
------------------------------------------------------------------------------------------------------
Question 39: Why do we deploy to staging first?

Answer ->  Staging is a production-like environment used to validate deployments and run smoke tests before releasing to real users. 
 
------------------------------------------------------------------------------------------------------
Question 40: What is a smoke test?

Answer ->  A smoke test is a quick set of checks after deployment to verify the system is running—like health endpoint, basic login, and critical flows. 
 
------------------------------------------------------------------------------------------------------
Question 41: How do you manage secrets in CI/CD?

Answer ->  Secrets are stored in CI secret managers and injected into runtime via env vars. We avoid printing secrets in logs and restrict access by roles. 
 
------------------------------------------------------------------------------------------------------
Question 42: Why should secrets never be stored in repo?

Answer ->  Because anyone with repo access could leak them, and even if deleted later, git history can expose them. It’s a major security risk. 
 
------------------------------------------------------------------------------------------------------
Question 43: How does Docker fit into CI/CD?

Answer ->  CI builds a Docker image, runs tests using that image, pushes it to a registry, and CD pulls the same image into staging/production. 
 
------------------------------------------------------------------------------------------------------
Question 44: Why use Docker in CI/CD?

Answer ->  It ensures consistency across build, test, and production environments and makes deployments repeatable. 
 
------------------------------------------------------------------------------------------------------
Question 45: What do you monitor after deployment?

Answer ->  I monitor error rates, response latency, CPU/memory usage, DB performance, and background job failures. Alerts help detect problems early. 
 
------------------------------------------------------------------------------------------------------
Question 46: What is deployment observability?

Answer ->  It means tracking deployments with metrics, logs, and traces so we know what changed and how it impacted the system. 
 
------------------------------------------------------------------------------------------------------
Question 47: What is trunk-based development?

Answer ->  Developers merge small changes frequently into the main branch. CI validates each change to keep main always deployable. 
 
------------------------------------------------------------------------------------------------------
Question 48: What is GitFlow?

Answer ->  GitFlow uses long-running branches like develop, release, hotfix, and feature branches. It adds structure but can slow down delivery. 
 
------------------------------------------------------------------------------------------------------
Question 49: Which is better: GitFlow or trunk-based?

Answer ->  For fast continuous delivery, trunk-based is preferred. GitFlow is useful for strict release management but can be heavy. 
 
------------------------------------------------------------------------------------------------------
Question 50: What is pipeline optimization?

Answer ->  Reducing build time using caching, parallel jobs, incremental builds, and skipping unnecessary steps. 
 
------------------------------------------------------------------------------------------------------
Question 51: What is caching in CI pipelines?

Answer ->  Caching stores dependencies like Ruby gems or node modules so future pipeline runs are faster. 
 
------------------------------------------------------------------------------------------------------
Question 52: How do you speed up Rails CI?

Answer ->  Cache bundler, use schema load instead of migrate, run tests in parallel, reduce asset compilation, and split jobs into stages. 
 
------------------------------------------------------------------------------------------------------
Question 53: What is a feature flag?

Answer ->  A feature flag allows releasing code to production but enabling the feature only for certain users or later. It reduces deployment risk. 
 
------------------------------------------------------------------------------------------------------
Question 54: Why are feature flags useful in CI/CD?

Answer ->  They decouple deployment from release. We can ship code safely and toggle feature rollout gradually. 
 
------------------------------------------------------------------------------------------------------
Question 55: How do you ensure quality gates in CI?

Answer ->  Use failing pipeline checks: tests must pass, RuboCop must pass, security scans must pass, minimum coverage threshold must be met. 