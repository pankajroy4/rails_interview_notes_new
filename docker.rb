Installing Docker: 
  ➤ macOS: Download Docker Desktop for Mac https://www.docker.com/products/docker-desktop/
  ➤ Ubuntu: Use sudo apt install docker.io
Start Docker and run a test command:
  ➤ docker --version
  ➤ docker run hello-world
If permission error:
  - Means that your user does not have the necessary permissions to access the Docker daemon socket.
Add your user to the docker group:
  ➤ sudo usermod -aG docker $USER
Apply the group change:
  ➤ newgrp docker
Ensure the Docker daemon is running:
  sudo systemctl status docker
If it is not active, start it:
  sudo systemctl start docker

Docker Basic:
===============================================================================================================
➤Docker Hub:
  Docker Hub is - A public cloud-based registry for Docker images.

  What You Can Do on Docker Hub:
    Search for existing images
    Example: ubuntu, node, mysql, nginx, etc.
    You do not have to build your own — just pull from Docker Hub.

  Pull images using:
    docker pull ubuntu

  Run images directly:
    docker run ubuntu

    Docker checks if the ubuntu image exists locally.
    If not, it pulls it from Docker Hub.
    Then it creates and runs a container from it.
    (Docker automatically pulls the image from Docker Hub if it is not already on your machine)

➤Docker daemon
  The Docker daemon (dockerd) is the background service that manages everything Docker does on your system.
  Think of it like the brain or engine of Docker. It is responsible for:
    🔸Creating, running, and stopping containers
    🔸Building and managing images
    🔸Handling networking and volumes
    🔸Pulling images from Docker Hub
    🔸Exposing the Docker API (so the Docker CLI or other tools can talk to it)

  🔸Architecture Overview:
    Here is how Docker components work together:
    You (CLI) → Docker client → Docker daemon (dockerd) → Containers & Images

    - Docker client (e.g. docker run, docker build) is what you use in the terminal.
    - The client talks to the Docker daemon via a socket (usually /var/run/docker.sock).
    - The daemon then does all the heavy lifting.

    Example: When we run:
      docker run hello-world

     🔸The Docker client sends a request to the daemon.
     🔸The daemon pulls the image "hello-world" if it does not exist locally(only the first time, unless you delete it or use --pull always)
     🔸It creates and starts a container from that image.
     🔸Start that new container. The container runs and outputs the result.
     🔸The daemon sends the output back to your terminal.

  Docker creates a new container every time you run docker run. Even if you are using the same image, docker run creates a new container each time.The image acts like a template, and each docker run call creates a fresh copy (a new instance of a container) from that template.

------------------------------------------------------------------------------------------------------------------------------
➤What is Docker?
  Docker is a tool that packages your application — and everything it needs to run — into a single unit called a “container.”
  It is designed to make it easier to create, deploy, and run applications by using containers.
  Containers allow you to package your application with all dependencies (OS, Ruby, gems, etc.) so it runs consistently across all environments. Think of it like:
   -> A virtual environment + your Rails app + Ruby + gems + PostgreSQL + Linux, all bundled into one.

  How It Works (High-Level):  
    Imagine your Rails app runs on:
        Ruby 3.2, Bundler, Node.js, PostgreSQL, Ubuntu, Some system dependencies (libpq-dev, etc.)
    🔸Without Docker:
        You install Ruby, Bundler, Postgres, Redis etc on your machine.
        You deal with OS-specific issues (macOS vs Ubuntu)
        You fight environment bugs in teams

    🔸With Docker, you do this instead:
      Everything is defined in a Dockerfile and docker-compose.yml
      Anyone can run: docker compose up
      Dev, test, and CI/CD use the same environment
      Deployment is smoother because your container = production

      Create a Docker image (like a blueprint). This image:
        - It includes everything above.
        - Defined in a Dockerfile.
      Run a container from that image
        - It is like launching a virtual Linux box that runs your Rails app.

➤ Key Terms:
  🔸Image:	Your Rals app packaged with Ruby,Bundler,etc. A blueprint or recipe (like a .iso or .exe) — read-only, reusable.
  🔸Container: A running instance of your image (like running rails server.  like running a program from that .exe.)
  🔸Dockerfile:	The script that builds your image (like a recipe)
  🔸Volume:	Folder shared between your machine and container (like /app).Persistent data storage
  🔸Port mapping: Expose container ports to your host (e.g., 3000 → 3000)
  🔸Docker Hub:	Public repo for base images (like Ruby, Postgres, Ubuntu)
  🔸Docker daemon: Background service that runs and manages containers
  🔸Networks:	Communication between containers
  🔸Docker Compose:	YAML config to manage multi-container setups

➤ Create and run a container. Lets start with a simple "Ubuntu Linux" container:
      docker run -it ubuntu bash
    What happen with this command
      docker run	 :Tells Docker to create and start a new container
      -it	         :Makes it interactive (stdin, tty)
      ubuntu	     :The image to use (Docker will pull if not present)
      bash	       :The command to run in the container
    We now have a shell inside an Ubuntu container.

    🔸Exit the container: exit
    🔸This shows all containers, including exited ones:
        docker ps -a
    🔸This shows all downloaded images:
      docker images

    🔸Run and Auto-Delete (--rm)
        docker run --rm -it ubuntu bash
      Now when we exit, the container is gone. --rm Automatically removes container on exit.

    🔸Remove a container: docker rm your_container_id
    🔸Remove all stopped containers: docker container prune

➤ Ephemeral Nature of Containers:
    This is very important for Rails developers.
    If you do not use volumes, all changes inside a container are lost when it exits.
    We can fix it using Docker volumes (-v).


Dockerizing a Simple Ruby App
================================================================================================================
➤ Set Up a Simple Ruby App
    - Make a new folder and move inside it: 
        mkdir docker-ruby-hello && cd docker-ruby-hello
    - Create a simple Ruby file:
        touch hello.rb
    - Add some content inside hello.rb:
        puts "👋 Hello from Ruby inside Docker!"

➤ Create a Dockerfile inside the project root:
    touch Dockerfile
    
    - Add this content to Dockerfile
        # Base image: official Ruby with Linux
        FROM ruby:3.2
        # Create app directory inside container
        WORKDIR /app
        # Copy your Ruby file into container
        COPY hello.rb .
        # Default command to run when container starts
        CMD ["ruby", "hello.rb"]

    What this content of Dockerfile will do:
      FROM	           => Uses Ruby with Debian/Ubuntu base image
      WORKDIR /app     =>	Sets /app as the working directory
      COPY hello.rb .	 => Copies your file into the container
      CMD	             => Tells Docker to run ruby and hello.rb by default

➤ Build Your Docker Image
    Run this command in the project folder:
      docker build -t ruby-hello .
        #OR, we can also use below command to build docker image:
      docker buildx build -t ruby-hello .
    
    What this command will do:
      -t ruby-hello => tags your image with the name "ruby-hello"
      .             => uses current directory as the context
 
➤ Run the Image as a Container
    docker run ruby-hello
    - It will run the app inside a container, You will see the expected output.

➤ Clean Up
    Docker will not let you remove an image if there is any container (even stopped) that was created from that image.

    docker image ls         # See your images
    docker container ls -a  # See containers, even stopped ones

    Remove the container first
      docker rm container_id_or_name
    Now remove the image
      docker image rm image_name

➤ Difference between ` docker buildx build -t ruby-hello . ` and  ` docker build -t ruby-hello . `:
  🔸docker build -t ruby-hello .
    -This is the classic Docker build command. Comes with Docker by default.
    -Uses the default Docker builder (legacy or BuildKit if enabled).
    -Builds a Docker image from the Dockerfile in the current directory (.).
    -Simple, straightforward.
    -Limited to building for the current platform (e.g., linux/amd64 if on an x86_64 machine).

  🔸docker buildx build -t ruby-hello .
    -Uses Docker Buildx, a CLI plugin for Docker. Needs to be installed separately.
    -Buildx provides advanced build features:
      ⋆Supports multi-platform builds (e.g., build amd64 and arm64 images at once).
      ⋆Uses BuildKit by default for faster builds with better caching.
      ⋆Allows building and pushing images remotely.
      ⋆Supports build caching, inline secrets, and more.
    -Can be used for cross-platform builds, even for platforms different from the host.
    -Requires Docker Buildx plugin installed (which you installed already).

Dockerizing a Rails App (Base Setup)
==========================================================================================
➤ To dockerizing a rails app we need to define a `Dockerfile` and `docker-compose.rb` file (Both at project root location).
➤ Minimal content inside the Dockerfile:
    # Use Ruby base image
    FROM ruby:3.2
    # Install system dependencies
    RUN apt-get update -qq && apt-get install -y build-essential libpq-dev nodejs
    # Set working directory
    WORKDIR /app
    # Copy Gemfiles and install gems
    COPY Gemfile Gemfile.lock ./
    RUN bundle install
    # Copy the rest of the code
    COPY . .
    # Precompile assets if needed 
    RUN bundle exec rake assets:precompile
    # Expose port 3000
    EXPOSE 3000
    # Start Rails server by default
    CMD ["rails", "server", "-b", "0.0.0.0"]

➤ Minimal content inside docker-compose.yml:/
    version: '3.9'

    services:
      db:
        image: postgres:15
        volumes:
          - postgres_data:/var/lib/postgresql/data
        environment:
          POSTGRES_USER: postgres
          POSTGRES_PASSWORD: password

      web:
        build: .
        command: rails server -b 0.0.0.0
        volumes:
          - .:/app
        ports:
          - "3000:3000"
        depends_on:
          - db
        environment:
          DATABASE_URL: postgres://postgres:password@db:5432/postgres

    volumes:
      postgres_data:

➤ After dockerizing the rails app, we can build image and run the rails app inside the docker.
  Build Image and Set Up the App:
   🔸docker compose build                             # build image
   🔸docker compose run web rake db:create db:migrate # Database creation
   🔸docker compose up                                # Running app. it launches containers for each service, each based on their respective image.
  http://localhost:3000                               # Visit, Rails app is running inside Docker!

   🔸docker compose down                              # Stop and clean up
   🔸docker compose run web rails c                   # Rails console in container

  To seed the data in docker container run the command:
    docker compose exec web bin/rails db:seed

  To run rails console in docker container run the command:
      docker compose exec web bin/rails c

  To Drop database and seed
    docker compose exec web bin/rails db:drop db:create db:migrate db:seed

  When you run:
    docker compose run web rake db:create db:migrate
  You are telling Docker Compose:
    “Hey, start a new container using the settings defined under the web: service, but override the command and run rake db:create db:migrate instead of the default Rails server.”

  build: .	 => Uses the image built from your Dockerfile
  Uses volumes, environment, etc.	All settings from web: are loaded
  Replaces command:	Instead of rails server, it runs rake db:create db:migrate
  Ignores ports:	Because you're not starting the server, you don't need port mapping here
  Does not use depends_on fully	=> It starts the db container, but does not wait for DB readiness (we wll improve this later)


Difference Between "docker build" and "docker compose build":
==============================================================
  ➤docker build -t my_image .
    Builds a single image using the Dockerfile in the current directory and tag it with name "my_image".
    No database, no volumes, no networking — just builds one image.
    You must manually run containers afterward with docker run.
    It is like: "Just build this image. I will figure out the rest."

  ➤docker compose build
    Reads a docker-compose.yml file.
    Builds multiple services (like web, db, redis, etc.). It will create images for each service that have build: instructions.
    It prepares your entire application stack.
    After building, you use "docker compose up" to launch everything at once.
    It is like: "Build the whole app ecosystem, not just one image."

  In short:
    "docker build" :	Just one image (e.g. your app). Simple scripts, base setup
    "docker compose build"	All services from compose file. Full-stack apps (Rails + DB + more)

Explanation of docker-compose.yml file
============================================

version: '3.9' #Version of Docker Compose syntax. Defines which features you can use.'3.9' is stable and modern.
services:      # You define each component of your app under this. Think: services = containers.
  #Web App service (Rails)
  web:  #Service name: “web” (you can name it anything)
      build: .  #Tells Docker to build an image using the Dockerfile in the current directory.
      command: rails server -b 0.0.0.0  #This overrides the default CMD in the Dockerfile. -b 0.0.0.0 allows external access (host → container)
      volumes:
        - .:/app
        #Maps current folder (.) to /app inside container.So changes on your machine instantly affect the app in the container (live reload during dev).
      ports:
        - "3000:3000"
        #Docker maps your host's port 3000 to the container's port 3000.So when Rails listens on localhost:3000 inside container, you can access it from your browser. Forwards traffic from your host into the container
      depends_on:
        - db
        #Ensures that db starts before web. But it does not wait for the database to become ready (we will fix that later with a wait script).
      environment:  # (9)
        DATABASE_URL: postgres://postgres:password@db:5432/postgres
        #Sets environment variables inside the container. DATABASE_URL is a standard ENV used by Rails to connect to Postgres. 
  #PostgreSQL Service
  db:  #Service name: “db”
    image: postgres:15  #Uses the official Postgres image from Docker Hub. No build, just pulls
    volumes:
      - postgres_data:/var/lib/postgresql/data 
      #Persists your database files between container restarts. Named volume postgres_data (defined at the bottom).
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: password
      #These variables are used by the Postgres image to create the default user and password.

#Volumes Declaration
volumes:
  postgres_data:  #Declares the named volume used by the db container.This is like a persistent folder managed by Docker.


Deep explanation of docker-compose.yml file
=============================================
  command: rails s -b 0.0.0.0
  ports:
    - "3000:3000"

    The -b 0.0.0.0 tells Rails to listen on all network interfaces, including the one Docker uses to expose your app to your host machine. Without it, your Rails server will not be reachable from outside the container, even though you have exposed port 3000:3000

    Inside the Docker container
      By default, if you just run:
        rails server
      Rails binds to: localhost (127.0.0.1:3000)
      That means: “Only accept connections from inside this container — not the outside world.”
      So even if you do:
        ports:
          - "3000:3000"
      You still can not access the Rails app in your browser (localhost:3000) because Rails is only listening to the container's internal localhost — not to Docker's external network.

      Browser hits localhost:3000, Docker maps port 3000 → 3000 in the container.
      The request does reach the container’s port 3000, but…
      Rails inside the container is only listening on 127.0.0.1, not 0.0.0.0.
      And that means:
      Rails says: “Sorry, I only accept connections from myself (localhost), not the Docker network.”

      Solution: -b 0.0.0.0
        This tells Rails: “Listen on all network interfaces, not just localhost.” This includes the Docker interface (eth0) that connects to your host machine — so now you can open your app in a browser at: http://localhost:3000

  ---------------------------------------------------------------------------------------------------------------     

  services:
    db:
      image: postgres
      volumes:
        - postgres_data:/var/lib/postgresql/data
  volumes:
    postgres_data:

  ➤The path "/var/lib/postgresql/data" is the path inside the container where PostgreSQL stores its database files.
  ➤A volume is persistent storage that lives outside the container’s filesystem, managed by Docker.

  🔸When you do this:
    volumes:
      - postgres_data:/var/lib/postgresql/data

    It means: “Hey Docker! Mount a named volume called postgres_data into the container, at the path /var/lib/postgresql/data.”
    That way:
      PostgreSQL will write data to /var/lib/postgresql/data as usual
      But Docker stores that data in a special volume on the host, not inside the container
      So even if the container is deleted, the data is preserved

    It is like saying:
      "Mount an external hard drive (named postgres_data) into the container at the /var/lib/postgresql/data folder."
    Everything written inside that folder goes to that external drive. If the container crashes or is rebuilt — data is still there.


  🔸When you do this:
    volumes:
      postgres_data:

    This tells Docker: "Please create a named volume called postgres_data. I will be using it in one of the services." You do not need to specify a path — Docker manages its location internally(usually somewhere like /var/lib/docker/volumes/...).

  ➤You can define as many named volumes as you want, and use them in any service within your docker-compose.yml.
   You can create multiple named volumes under the volumes: key and mount them to any container’s path using volumes: inside each service.
   Think of it like:
      Plug different "USB drives" (named volumes) into different containers.
    
      version: '3.9'
      services:
        db:
          image: postgres:15
          volumes:
            - postgres_data:/var/lib/postgresql/data

        redis:
          image: redis:7
          volumes:
            - redis_data:/data

        app:
          build: .
          volumes:
            - app_storage:/my-app/tmp

      volumes:
        postgres_data:
        redis_data:
        app_storage:

🧑‍🏫 Lesson 4: Connecting Rails to Postgres in Docker Compose
