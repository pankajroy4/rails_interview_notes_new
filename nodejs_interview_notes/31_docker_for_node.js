/*
===============================================================================================
                       DOCKER for NODE.JS
===============================================================================================
(Mirrors my docker.rb / docker_question.rb. Docker concepts are identical to my Rails notes —
the only thing that changes is the Dockerfile contents for a Node app instead of a Rails app.
I already have Docker on my resume, so I lean on that and just show the Node specifics.)
*/

/*
-----------------------------------------------------------------------------------------------
Q1: What is Docker and why use it? (concepts unchanged from my Rails notes)
-----------------------------------------------------------------------------------------------
Answer -> Docker packages an app + ALL its dependencies (runtime, libraries, OS bits) into a
single portable unit called a CONTAINER, so it runs identically across dev, CI, and prod —
killing "works on my machine" bugs.

  IMAGE     -> the immutable blueprint/template (built from a Dockerfile).
  CONTAINER -> a running instance of an image (each `docker run` creates a fresh one).
  DOCKERFILE-> the recipe to build an image.
  REGISTRY  -> where images live (Docker Hub, AWS ECR). pull/push images.
  VOLUME    -> persistent storage outside the container's writable layer.
  Docker daemon (dockerd) does the work; the CLI talks to it via a socket.

  For Node: instead of bundling Ruby+gems, I bundle Node + node_modules + my app, so the container
  IS the deployable artifact — same image runs in CI and prod.
*/

/*
-----------------------------------------------------------------------------------------------
Q2: A production Dockerfile for a Node app (MULTI-STAGE — the key best practice)
-----------------------------------------------------------------------------------------------
Answer -> Use a multi-stage build: a "build" stage with the full toolchain (compile TS, install
dev deps), then a slim "runtime" stage that copies only what's needed. This keeps the final image
small and free of build tools / dev dependencies.

  # ---- build stage ----
  FROM node:20-alpine AS build
  WORKDIR /app
  COPY package*.json ./
  RUN npm ci                       # install ALL deps (incl dev) for building/compiling TS
  COPY . .
  RUN npm run build                # e.g. tsc -> dist/

  # ---- runtime stage ----
  FROM node:20-alpine AS runtime
  WORKDIR /app
  ENV NODE_ENV=production
  COPY package*.json ./
  RUN npm ci --omit=dev            # ONLY production deps -> smaller, fewer CVEs
  COPY --from=build /app/dist ./dist
  USER node                        # run as non-root (security)
  EXPOSE 3000
  CMD ["node", "dist/server.js"]   # NOT `npm start` — see Q5 (signals/PID 1)

  Why each line matters:
   - node:20-alpine -> small base image.
   - COPY package*.json THEN npm ci BEFORE copying source -> layer caching: deps only reinstall when
     package.json changes, not on every code edit. Huge build-speed win.
   - npm ci (not npm install) -> reproducible install strictly from package-lock.json.
   - --omit=dev in runtime -> no jest/typescript/etc. in the shipped image.
   - USER node -> never run as root in a container.
*/

/*
-----------------------------------------------------------------------------------------------
Q3: .dockerignore (do not skip this)
-----------------------------------------------------------------------------------------------
Answer -> Like .gitignore but for the Docker build context. Critically, exclude node_modules so
the host's (possibly platform-wrong) modules aren't copied in — you want them installed INSIDE the
image.

  # .dockerignore
  node_modules
  npm-debug.log
  .git
  .env
  dist
  coverage
  Dockerfile
  .dockerignore

  Without this, the build context balloons and you risk shipping a local node_modules built for a
  different OS/arch (native modules break).
*/

/*
-----------------------------------------------------------------------------------------------
Q4: docker-compose for local dev (app + Postgres + Redis)
-----------------------------------------------------------------------------------------------
Answer -> Compose spins up the whole stack with one command (`docker compose up`) — app, DB, Redis,
all wired together. This is how the team gets an identical dev environment.

  # docker-compose.yml
  services:
    app:
      build: .
      ports: ["3000:3000"]
      environment:
        DATABASE_URL: postgres://postgres:postgres@db:5432/app
        REDIS_URL: redis://redis:6379
      depends_on: [db, redis]
      volumes:
        - .:/app                 # live code mount for dev
        - /app/node_modules      # keep container's node_modules (don't shadow with host)
    db:
      image: postgres:16-alpine
      environment: { POSTGRES_PASSWORD: postgres, POSTGRES_DB: app }
      volumes: [pgdata:/var/lib/postgresql/data]
    redis:
      image: redis:7-alpine
  volumes: { pgdata: {} }

  Note services reach each other by SERVICE NAME (db, redis) over the compose network — that's why
  DATABASE_URL uses host `db`, not localhost.
*/

/*
-----------------------------------------------------------------------------------------------
Q5: Node-in-Docker gotchas (these separate juniors from seniors)
-----------------------------------------------------------------------------------------------
Answer ->
  - PID 1 / SIGNALS: a Node process started as PID 1 doesn't get default signal handlers, so
    SIGTERM (sent by Docker/k8s on stop) may be ignored -> no graceful shutdown, dropped requests.
    Fixes: use an init (`--init`, or tini) so signals are forwarded, AND handle SIGTERM in code
    (file 08 graceful shutdown). Use `CMD ["node", "server.js"]` (exec form), NOT `npm start`
    (npm doesn't forward signals well).
  - DON'T run cluster/PM2 inside the container by default — prefer ONE Node process per container
    and scale by running more CONTAINERS (k8s replicas / ECS tasks). Let the orchestrator scale.
  - HEALTHCHECK: add one so the orchestrator knows the app is ready.
        HEALTHCHECK CMD wget -qO- http://localhost:3000/health || exit 1
  - Pin the Node version (node:20-alpine, not node:latest) for reproducibility.
  - Keep secrets OUT of the image — inject env at runtime (don't COPY .env or bake keys in layers;
    layers are inspectable).
  - Alpine uses musl libc; some native modules need build deps — install them in the build stage only.
*/

/*
-----------------------------------------------------------------------------------------------
Q6: Common Docker commands (Rails-notes parity)
-----------------------------------------------------------------------------------------------
Answer ->
  docker build -t my-api .                 # build image from Dockerfile
  docker run -p 3000:3000 --env-file .env my-api
  docker ps / docker ps -a                 # running / all containers
  docker logs -f <container>               # tail logs
  docker exec -it <container> sh           # shell into a running container
  docker compose up -d / down              # start/stop the whole stack
  docker images / docker rmi <img>         # list / remove images
  docker system prune                      # reclaim space
  docker push <registry>/my-api:tag        # push to ECR/Docker Hub (CI does this)
*/

module.exports = {};
