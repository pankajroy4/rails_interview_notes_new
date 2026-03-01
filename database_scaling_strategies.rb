Database Scaling Strategies
============================
➤ Scaling Options Overview

  |        Type            |               What It Means                      |          When to Use                      |
  | ---------------------- | ------------------------------------------------ | ----------------------------------------- |
  | 🔸Vertical Scaling   → | Make one DB server stronger (more RAM, CPU, SSD).| In early stages of your app               |
  | 🔸Horizontal Scaling → | Add more DBs or servers to divide the load.      | For very large systems                    |
  | 🔸Read Replicas      → | Create read-only copies of DB for reading.       | If most queries are `SELECT`              |
  | 🔸Partitioning       → | Break large tables into smaller pieces.          | Huge tables like logs, orders             |
  | 🔸Sharding           → | Split data into multiple databases.              | When user data is huge or region-specific |


➤Vertical Scaling (Scaling up)
  → Vertical scaling means upgrading the hardware resources of your existing database or application server:
    🔸Add more CPU cores
    🔸Add more RAM
    🔸Use faster SSDs
    🔸Maybe move to a higher-tier managed DB instance (if on cloud)
    You start with a server having 2 CPUs + 8 GB RAM → Upgrade to 8 CPUs + 64 GB RAM
    You just point your app to the same database (no code change)


➤Horizontal Scaling (Scaling out)
  → Horizontal scaling means adding more servers (nodes) to share the load:
    🔸More database nodes
    🔸More application servers
    🔸Often combined with load balancers
    You run 4 instances of your app server (e.g., Puma, Passenger) behind an Nginx load balancer
    You set up a PostgreSQL cluster with multiple nodes
      upstream app_servers {
        server app1.example.com;
        server app2.example.com;
        server app3.example.com;
      }

    It is Good for:
      Enterprise-level apps
      High availability (one node can go down, system stays up)
      Handle both high reads and writes


➤Read Replicas (Read Scaling)
  → Read replicas are copies of your primary database that handle only read queries:
    🔸Primary DB → handles writes + authoritative data
    🔸Replicas → serve SELECT queries

  Replication is usually asynchronous → slight lag between primary and replicas.

  In Rails, you can use replica-aware configurations: # Rails 6+ has built-in support
    ActiveRecord::Base.connected_to(role: :reading) do
      # your SELECT queries
    end

    # database.yml
    production:
      primary:
        database: myapp_prod
      primary_replica:
        database: myapp_prod_replica
        replica: true

  Lag: Replica might be behind the primary → stale reads
  You still need to scale writes separately
  Rails queries need to be directed correctly (reading vs writing)


➤Partitioning (Table Partitioning)
  → Partitioning means breaking a big table into smaller, more manageable pieces (partitions) within the same DB instance:
   🔸Rows go into different partitions based on a column value (e.g. created_at, region, status)

  In PostgreSQL:

  CREATE TABLE orders (
    id SERIAL PRIMARY KEY,
    created_at TIMESTAMP NOT NULL,
    ...
  ) PARTITION BY RANGE (created_at);

  Example in Rails, if you have:
    class Order < ApplicationRecord
    end

  You would manage partitions at DB level → Rails can stay mostly unaware unless you do manual querying of partitions.
  It is good for Large tables where queries filter on the partition key.
  Time-based data: logs, orders, events.
  Easier archiving/deletion of old data.


➤Sharding
  → Sharding = splitting data across multiple database servers (shards), where each shard holds a portion of the data. Each shard is independent. For example:
    User 1 - 100k => shard 1
    User 100k+ => shard 2

    Unlike partitioning → data is split across different DB instances.

  Example in Rails 6+:
    ActiveRecord::Base.connected_to(shard: :shard_one) do
      # queries for shard one
    end

    # database.yml:
    production:
      shard_one:
        database: myapp_shard1
      shard_two:
        database: myapp_shard2
    Or, we can use gems like: octopus for sharding management

  It is good for Multi-tenant apps (each client in its own shard)
  Region-specific data (US shard, EU shard)
  Very high data volume (beyond what partitioning can handle)
  NOTE: Application logic must route to the right shard


Rails Configuration For Database Scaling:
===========================================

➤Horizontal Scaling (App servers + Load balancer => Application Tier)
-------------------------------------------------
  🔸You add more app servers (Rails instances)
  🔸A load balancer (Nginx / AWS ALB / HAProxy) routes requests

  → Example Nginx config for load balancing Rails apps:

    upstream rails_app {
      server app1.internal.example.com:3000;
      server app2.internal.example.com:3000;
      server app3.internal.example.com:3000;
    }

    server {
      listen 80;
      server_name myapp.com;

      location / {
        proxy_pass http://rails_app;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
      }
    }
  → No database.yml changes → the DB connection details stay the same on each app server.
  → We are running multiple Rails app servers (on same or different machines).
  → These app servers all point to the same database (typically a single PostgreSQL instance).
  → This is horizontal scaling of the application tier only.(NOT the database tier)

  🔸When We Say "Horizontal Scaling for Database", This means: Read Replicas, Partitioning, Sharding, Clustering etc.

➤Read Replicas (PostgreSQL + Rails)
-----------------------------------
  Assume we have:
    Primary: db-primary.example.com
    Replica: db-replica.example.com
  Then:

    #database.yml
      production:
        primary:
          adapter: postgresql
          host: db-primary.example.com
          username: myuser
          password: <%= Rails.application.credentials.db[:password] %>
          database: myapp_production
          pool: 20

        primary_replica:
          adapter: postgresql
          host: db-replica.example.com
          username: myuser
          password: <%= Rails.application.credentials.db[:password] %>
          database: myapp_production
          replica: true
          pool: 20


    #In Rails code (Rails 6+):
    #Use replica for read-only queries
      ActiveRecord::Base.connected_to(role: :reading) do
        posts = Post.where(published: true).limit(10)
        puts posts.pluck(:title)
      end

    → Rails automatic read/write splitting:
    → If you use connected_to(role: :writing) + connected_to(role: :reading) properly, Rails will direct queries accordingly.


➤Partitioning (PostgreSQL)
--------------------------
  Example: You want to partition orders by year.

  #Migration example
    class CreatePartitionedOrders < ActiveRecord::Migration[7.0]
      def up
        execute <<~SQL
          CREATE TABLE orders (
            id bigserial NOT NULL PRIMARY KEY,
            user_id bigint NOT NULL,
            total numeric NOT NULL,
            created_at timestamp NOT NULL,
            updated_at timestamp NOT NULL
          ) PARTITION BY RANGE (created_at);
        SQL

        #Create partitions
        execute <<~SQL
          CREATE TABLE orders_2024 PARTITION OF orders
          FOR VALUES FROM ('2024-01-01') TO ('2025-01-01');
        SQL

        execute <<~SQL
          CREATE TABLE orders_2025 PARTITION OF orders
          FOR VALUES FROM ('2025-01-01') TO ('2026-01-01');
        SQL
      end

      def down
        execute "DROP TABLE IF EXISTS orders CASCADE;"
      end
    end

  #In Rails model
    class Order < ApplicationRecord
      #Rails doesn't need to know about partitions unless you want
    end
  → Your app queries Order as usual. PostgreSQL handles routing to the right partition.


➤Sharding (Rails 6+ native support)
-----------------------------------
  Example: Two shards by region

  #database.yml
    production:
      shard_one:
        adapter: postgresql
        host: shard-one-db.example.com
        username: myuser
        password: <%= Rails.application.credentials.db[:password] %>
        database: myapp_shard_one

      shard_two:
        adapter: postgresql
        host: shard-two-db.example.com
        username: myuser
        password: <%= Rails.application.credentials.db[:password] %>
        database: myapp_shard_two

  #In Rails code
  #Connect to shard one
    ActiveRecord::Base.connected_to(shard: :shard_one) do
      User.create!(name: "Shard One User")
    end

    #Connect to shard two
    ActiveRecord::Base.connected_to(shard: :shard_two) do
      User.create!(name: "Shard Two User")
    end

  #Example logic to route queries
    def with_shard_for_region(region)
      shard = case region
              when 'us' then :shard_one
              when 'eu' then :shard_two
              else :shard_one
              end

      ActiveRecord::Base.connected_to(shard: shard) do
        yield
      end
    end

    with_shard_for_region('us') do
      User.find(1)
    end


Centralized Connection Routing Module (Service Object / Helper)
===============================================================
➤Do not Repeat connected_to(...) do ... end everywhere.
  Create database-aware helper methods or concerns to handle this logic centrally.
  
╰┈➤🔸We can create a service to wrap all connection logic:
    #app/services/database_router.rb
    class DatabaseRouter
      def self.with_read(&block)
        ActiveRecord::Base.connected_to(role: :reading, &block)
      end

      def self.with_write(&block)
        ActiveRecord::Base.connected_to(role: :writing, &block)
      end

      def self.with_shard(region, &block)
        shard = case region.to_s
                when 'us' then :shard_one
                when 'eu' then :shard_two
                else :shard_one
                end

        ActiveRecord::Base.connected_to(shard: shard, &block)
      end
    end

    Usage Anywhere:
      # Read-only operation
      DatabaseRouter.with_read do
        @posts = Post.published.limit(10)
      end

      # Sharded operation
      DatabaseRouter.with_shard('eu') do
        User.create!(name: "User from EU")
      end

╰┈➤🔸ApplicationConcern for Sharded Models (Multi-Tenant / Region-Based)
    If we are doing multi-tenancy, create a concern to inject connected_to logic automatically.

    #app/models/concerns/shard_aware.rb
    module ShardAware
      extend ActiveSupport::Concern

      class_methods do
        def on_shard(region, &block)
          DatabaseRouter.with_shard(region, &block)
        end
      end
    end

    #app/models/user.rb
    class User < ApplicationRecord
      include ShardAware
    end

    #Usage:
    User.on_shard('us') do
      User.find_by(email: 'foo@example.com')
    end
    Now any model including ShardAware gets shard routing for free.

╰┈➤🔸Controller-Level Abstraction
    If your controller needs to run actions in a specific DB (like read-only), abstract it with before_action.

    #app/controllers/application_controller.rb
    class ApplicationController < ActionController::Base
      def with_read_db
        DatabaseRouter.with_read { yield }
      end

      def with_shard(region)
        DatabaseRouter.with_shard(region) { yield }
      end
    end

    #app/controllers/posts_controller.rb
    class PostsController < ApplicationController
      def index
        with_read_db do
          @posts = Post.published.limit(10)
        end
      end
    end


╰┈➤🔸Auto-Shard Based on Tenant/Region (Multi-Tenant Use Case)
    If your app is multi-tenant, centralize shard logic based on request headers, subdomains, or user location:

    #app/controllers/application_controller.rb
    class ApplicationController < ActionController::Base
      around_action :connect_to_tenant_shard

      private

      def connect_to_tenant_shard(&action)
        # Determine region from logged-in user or subdomain fallback
        region = current_user&.region || request.subdomain || :us

        # Use read/write based on request method
        role = request.get? ? :reading : :writing

        DatabaseRouter.with_shard_and_role(region: region, role: role) do
          action.call #OR yield
        end
      end
    end

    #Controller Usage: Nothing Extra Needed
    #app/controllers/orders_controller.rb
    class OrdersController < ApplicationController
      def index
        # Auto-sharded to the user's region or subdomain
        @orders = Order.where(status: 'delivered').limit(10)
        render json: @orders
      end

      def create
        @order = Order.create!(user_id: current_user.id, total: 99.99)
        render json: @order, status: :created
      end
    end



Combining all three (Sharding,Partitioning and Read Replicas) together:
=========================================================================
╰┈➤ Visual Architecture:

      +-------------------+       +-------------------+
      | Rails Application | <---> |  DB Connection    |
      +-------------------+       +-------------------+
                                      |     |
          +---------------------------+     +----------------------------+
          |                                                             |
      +-------------+   +-------------+                         +---------------+
      | Shard: US   |   | Shard: EU   |                         | Shard: Asia   |
      | Primary     |   | Primary     |                         | Primary       |
      | + Partitions|   | + Partitions|                         | + Partitions  |
      +-------------+   +-------------+                         +---------------+
          |                   |                                       |
          | (replica)         | (replica)                             | (replica)
      +-------------+   +-------------+                         +---------------+
      | Read Replica|   | Read Replica|                         | Read Replica  |
      +-------------+   +-------------+                         +---------------+

╰┈➤ File Structure:

      app/
      ├── services/
      │   └── database_router.rb     # Routes to correct shard/replica
      ├── models/
      │   └── concerns/
      │       └── shard_aware.rb     # Adds .on_shard abstraction
      config/
      └── database.yml               # Multi-shard + replica + partitioned tables



  #config/database.yml (simplified example)
  ------------------------------------------
    production:
    primary_shard_us:
      database: myapp_us
      host: us-primary.example.com
      adapter: postgresql

    replica_shard_us:
      database: myapp_us
      host: us-replica.example.com
      adapter: postgresql
      replica: true

    primary_shard_eu:
      database: myapp_eu
      host: eu-primary.example.com
      adapter: postgresql

    replica_shard_eu:
      database: myapp_eu
      host: eu-replica.example.com
      adapter: postgresql
      replica: true

  #app/services/database_router.rb
  ---------------------------------------
  class DatabaseRouter
    def self.with_shard_and_role(region:, role:, &block)
      shard_key = "#{role}_shard_#{region}".to_sym
      ActiveRecord::Base.connected_to(shard: shard_key, role: role, &block)
    end

    def self.with_read(region:, &block)
      with_shard_and_role(region: region, role: :reading, &block)
    end

    def self.with_write(region:, &block)
      with_shard_and_role(region: region, role: :writing, &block)
    end
  end


  #app/models/concerns/shard_aware.rb
  -----------------------------------
  module ShardAware
    extend ActiveSupport::Concern

    class_methods do
      def on_shard(region, role: :writing, &block)
          DatabaseRouter.with_shard_and_role(region: region, role: role, &block)
        end
      end
    end
  end

  #Example Model
  class Order < ApplicationRecord
    include ShardAware
  end

  #Usage Example
  # Read from US shard's replica
  Order.on_shard(:us, role: :reading) do
    Order.where(status: 'delivered').limit(10)
  end

  # Write to EU shard
  Order.on_shard(:eu, role: :writing) do
    Order.create!(user_id: 1, total: 99.99)
  end


  Partitioning in PostgreSQL (per shard)
  ---------------------------------------
  Each shard DB should have tables like this:

    #in us-primary DB
    CREATE TABLE orders (
      id SERIAL PRIMARY KEY,
      status TEXT,
      created_at TIMESTAMP NOT NULL
    ) PARTITION BY RANGE (created_at);

    CREATE TABLE orders_2024 PARTITION OF orders
    FOR VALUES FROM ('2024-01-01') TO ('2025-01-01');

  Rails can still interact with this transparently.

