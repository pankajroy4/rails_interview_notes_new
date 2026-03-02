=================================== Docker ==================================================
Question 1: What is Docker?

Answer -> Docker is a containerization platform that packages an application along with its dependencies into an image. That image can run consistently across environments like development, staging, and production. It solves the problem of "it works on my machine".

------------------------------------------------------------------------------------------------------
Question 2: What problem does Docker solve?

Answer -> Docker solves environment consistency. It ensures everyone runs the same OS libraries, runtime versions, and dependencies. It also simplifies deployment by shipping the application as a standardized container image.
 
------------------------------------------------------------------------------------------------------
Question 3: What is the difference between Docker and a Virtual Machine?

Answer -> Virtual machines virtualize hardware and run full guest operating systems. Containers virtualize the OS level and share the host kernel. Containers are lighter, start faster, and use fewer resources than VMs.

------------------------------------------------------------------------------------------------------
Question 4: What is a Docker image?

Answer -> A Docker image is an immutable template containing application code, runtime, system packages, and dependencies. It is like a snapshot used to create containers.
 
------------------------------------------------------------------------------------------------------
Question 5: What is a Docker container?

Answer -> A container is a running instance of a Docker image. It’s isolated, lightweight, and runs as a process on the host OS.

------------------------------------------------------------------------------------------------------
Question 6: What is the difference between an image and a container?

Answer -> An image is the packaged blueprint. A container is the running instance created from that blueprint.

------------------------------------------------------------------------------------------------------
Question 7: What is Dockerfile?

Answer -> A Dockerfile is a text or .yml file containing instructions to build a Docker image, like choosing the base image, installing dependencies, copying code, and defining the start command.

------------------------------------------------------------------------------------------------------
Question 8: What is the purpose of FROM in a Dockerfile?

Answer -> FROM defines the base image. For Rails, we commonly use ruby:<version> as the base image.

------------------------------------------------------------------------------------------------------
Question 9: What is a Docker layer?

Answer -> Each Dockerfile instruction creates a layer. Layers are cached so Docker can reuse them during rebuilds, making builds faster.

------------------------------------------------------------------------------------------------------
Question 10: Why is caching important in Docker builds?

Answer -> Caching speeds up builds. For Rails apps, we should copy Gemfile and Gemfile.lock first, run bundle install, then copy app code—so gem installs are cached unless Gemfile changes.

------------------------------------------------------------------------------------------------------
Question 11: How do you Dockerize a Rails application?

Answer -> I create a Dockerfile using a Ruby base image, install OS dependencies like Node/Yarn if needed, run bundle install, copy the Rails code, precompile assets in production build, and run the app using Puma. For development, I use docker-compose with Postgres/Redis.
 
------------------------------------------------------------------------------------------------------
Question 12: What services are common in docker-compose for Rails?

Answer -> Rails usually runs with Postgres, Redis (Sidekiq), and sometimes Nginx. So docker-compose defines multiple services like web, db, redis, and sidekiq.

------------------------------------------------------------------------------------------------------
Question 13: Why do we use docker-compose?

Answer -> docker-compose helps run multi-container applications locally. For Rails, it is the easiest way to run app + database + redis + sidekiq together with one command.
 
------------------------------------------------------------------------------------------------------
Question 14: How do you run Rails migrations in Docker?

Answer -> I typically run migrations using docker compose exec web rails db:migrate. In CI/CD pipelines, migrations are run as a dedicated step before deploying new containers.
 
------------------------------------------------------------------------------------------------------
Question 15: How do you handle Rails credentials/secrets in Docker?

Answer -> Secrets should not be baked into Docker images. We inject them via environment variables, secret managers, or mounted files in runtime. For Rails, we can set RAILS_MASTER_KEY as an environment variable in production.
 
------------------------------------------------------------------------------------------------------
Question 16: Common Docker commands you use daily?

Answer -> 
  docker build -t app .
  docker run -p 3000:3000 app
  docker ps / docker ps -a
  docker logs <container>
  docker exec -it <container> bash
  docker compose up / down
  docker images
 
------------------------------------------------------------------------------------------------------
Question 17: How do you debug a container?

Answer -> I check logs using docker logs, then I enter the container using docker exec -it. I verify environment variables, filesystem, running processes, and network connectivity.
 
------------------------------------------------------------------------------------------------------
Question 18: What is port mapping in Docker?

Answer -> Port mapping exposes container ports to the host. For example -p 3000:3000 maps container port 3000 to host port 3000.

------------------------------------------------------------------------------------------------------
Question 19: What is the default Docker network behavior?

Answer -> Docker creates a bridge network by default. Containers can communicate using container names inside the same network, especially when using docker-compose.

------------------------------------------------------------------------------------------------------
Question 20: In docker-compose, how does Rails connect to Postgres?

Answer -> In database.yml, the host should be the service name, like host: db rather than localhost.
 
------------------------------------------------------------------------------------------------------
Question 21: Why does localhost not work inside a container?

Answer -> Inside a container, localhost refers to that container itself—not the host machine or another container.
 
------------------------------------------------------------------------------------------------------
Question 22: What happens to data when a container stops?

Answer -> By default, container filesystem data is ephemeral. If the container is removed, data is lost unless it Is stored in volumes.
 
------------------------------------------------------------------------------------------------------
Question 23: What is a Docker volume?

Answer -> A Docker volume is persistent storage managed by Docker. For Rails, it is used for Postgres data and sometimes for file uploads in development.
 
------------------------------------------------------------------------------------------------------
Question 24: Bind mount vs volume?

Answer -> A bind mount maps a host directory into a container. A volume is managed by Docker. Bind mounts are common in development for live code reloading.

------------------------------------------------------------------------------------------------------
Question 25: How do you pass environment variables to containers?

Answer -> Using -e KEY=value or using environment: in docker-compose. Also .env files can be used for local dev.
 
------------------------------------------------------------------------------------------------------
Question 26: How do you handle different envs like dev/test/prod in Docker?

Answer -> By using different compose files or overriding variables. For example docker-compose.yml for dev, docker-compose.prod.yml for production overrides.
 
------------------------------------------------------------------------------------------------------
Question 27: What is the difference between CMD and ENTRYPOINT?

Answer -> CMD provides default arguments for the container. ENTRYPOINT defines the executable itself. ENTRYPOINT is harder to override; CMD is easier.
 
------------------------------------------------------------------------------------------------------
Question 28: Why do Rails containers need an entrypoint script sometimes?

Answer -> To handle startup steps like removing stale tmp/pids/server.pid, running migrations, and preparing the environment before starting Puma.

------------------------------------------------------------------------------------------------------
Question 29: Why should a container run only one process?

Answer -> Docker best practice is one main process per container. Rails web server, Sidekiq, and Cron should ideally run in separate containers for better scaling and monitoring.
 
------------------------------------------------------------------------------------------------------
Question 30: How do you run Sidekiq in Docker?

Answer -> I create a separate sidekiq service using the same image as Rails but with a different command: bundle exec sidekiq. Redis runs as another service.
 
------------------------------------------------------------------------------------------------------
Question 31: Why do we need Redis for Sidekiq?

Answer -> Redis stores job queues. Sidekiq pushes jobs into Redis and worker processes pop jobs from Redis and execute them.
 
------------------------------------------------------------------------------------------------------
Question 32: What are Docker best practices for Rails?

Answer -> 
  Use slim images
  Use multi-stage builds for production
  Avoid running as root
  Cache bundle install properly
  Keep images immutable
  Put secrets in runtime env, not inside image
  Use health checks and proper logging

------------------------------------------------------------------------------------------------------
Question 33: What is multi-stage build?

Answer -> Multi-stage build allows building dependencies in one stage and copying only needed artifacts to the final image. This produces smaller and cleaner production images.
 
------------------------------------------------------------------------------------------------------
Question 34: Why avoid running container as root?

Answer -> For security. Running as root increases the impact if the container is compromised.

------------------------------------------------------------------------------------------------------
Question 35: How do you reduce Docker image size?

Answer -> Use slim base images, clean apt cache, avoid unnecessary build tools in final image, and use multi-stage builds.
 
------------------------------------------------------------------------------------------------------
Question 36: How does Docker help in CI/CD?

Answer -> CI builds a Docker image, runs tests inside containers, then pushes the image to a registry. Deployment pulls the exact same image and runs it in staging/production, ensuring consistency.
 
------------------------------------------------------------------------------------------------------
Question 37: What is a Docker registry?

Answer -> A Docker registry stores Docker images, like Docker Hub, GitHub Container Registry, AWS ECR. CI pushes images, and servers pull them during deployment.
 
------------------------------------------------------------------------------------------------------
Question 38: Rails container builds but fails at runtime. What do you do?

Answer -> I check logs. Then verify env vars like DB config. I enter container using exec and try running Rails commands. Usually issues are missing env vars, DB host mismatch, or missing system dependencies.
 
------------------------------------------------------------------------------------------------------
Question 39: Gem installation is very slow every build. Why?

Answer -> Because Docker cache is not being used properly. The fix is to copy only Gemfile and Gemfile.lock first, run bundle install, then copy full code.

------------------------------------------------------------------------------------------------------
Question 40: rails s fails with pid error in Docker. Why?

Answer -> It happens due to stale tmp/pids/server.pid. Usually solved by deleting it in entrypoint script before starting server.
 
------------------------------------------------------------------------------------------------------
Question 41: Postgres connection failing in Docker-compose?

Answer -> Common reasons: using localhost instead of db, wrong credentials, container not ready yet, or wrong database.yml settings.

------------------------------------------------------------------------------------------------------
Question 42: How do you ensure Docker security?

Answer -> Run as non-root user, scan images for vulnerabilities, keep base images updated, avoid storing secrets in images, and apply least privilege.
 
------------------------------------------------------------------------------------------------------
Question 43: What is the difference between COPY and ADD?

Answer -> COPY is straightforward file copy. ADD can also extract tar files and download URLs, but it’s better to use COPY unless ADD features are needed.
 
------------------------------------------------------------------------------------------------------
Question 44 What is a .dockerignore file?

Answer -> It prevents unnecessary files like log/, tmp/, .git/, node_modules/ from being copied into the image, which reduces build context size and speeds up builds.

------------------------------------------------------------------------------------------------------
Question 45: What is the build context?

Answer -> Build context is the set of files sent to Docker daemon during build. That is why .dockerignore matters.
 
------------------------------------------------------------------------------------------------------
Question 46: What are health checks in Docker?

Answer -> Health checks define how Docker verifies container health. For Rails, it can ping a /health endpoint to ensure the service is working.
 
------------------------------------------------------------------------------------------------------
Question 47: When would you use Nginx with Rails containers?

Answer -> In production, Nginx can be used as a reverse proxy to handle SSL termination, static assets, caching, and forwarding requests to Puma.

------------------------------------------------------------------------------------------------------
Question 48: Your Dockerized Rails app works locally but fails on EC2. Why?

Answer -> If a Dockerized Rails app works locally but fails on EC2, I immediately suspect environment or configuration differences between local and production.
The most common cause is missing environment variables. Locally, we often rely on .env files, but on EC2 those variables may not be injected into the container. So I verify all required variables like SECRET_KEY_BASE, DATABASE_URL, Redis URL, API keys, etc.
Another common issue is a DATABASE_URL mismatch. Locally we may be using SQLite or a local Postgres instance, but on EC2 it should connect to RDS or a production database. If the connection string is incorrect, the app will boot but fail during DB initialization.

Production credentials are another frequent cause. Rails encrypted credentials must be properly mounted, and RAILS_MASTER_KEY must be available inside the container. If not, Rails will crash on boot.

Assets are also a big issue. In production, Rails expects precompiled assets. If assets:precompile is not executed during the Docker build stage, the app may fail when serving static files.

Sometimes the problem is a wrong ENTRYPOINT or CMD in the Dockerfile — for example, forgetting to run bundle exec puma -C config/puma.rb or not running migrations before starting the server.

How I Fix It:
  First, I ensure the Dockerfile uses a multi-stage build:
    One stage for installing gems and compiling assets
    A final lightweight runtime image

  Second, I verify that RAILS_ENV=production is set inside the container and not defaulting to development.

  Third, I double-check environment variables using:
    docker exec -it container_name env

  Finally, I inspect logs using:
    docker logs container_name
    and verify database connectivity from inside the container.

    