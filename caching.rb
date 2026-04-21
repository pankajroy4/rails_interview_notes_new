What is Caching?
=================
 ➤ Caching stores the result of expensive operations (e.g., DB queries, API calls, view rendering) so they can be reused without repeating the work.
 ➤ Rails supports multiple cache layers:
    Fragment Cache: =>	Cache parts of views
    Page Cache:	=> Cache full page (not common today)
    Action Cache: =>	Cache full controller action
    Low-Level: =>	Store any custom data manually

  Redis is commonly used as the backing store for all of these.

Low-Level Caching (Manual)
===========================
  Low-Level Cching is used when caching computed data.

  Rails.cache.fetch("active_products", expires_in: 10.minutes) do
    Product.where(active: true).to_a
  end

  If key exists → returns cache
  Else → executes block and stores result

Page Caching(Full HTML caching) 
===============================
  Page caching stores the entire rendered HTML as a static file and serves it directly from the web server (like Nginx), bypassing Rails completely.
  That means:
    No controller
    No DB
    No Rails stack
    Just static file response

  This was common before Rails 4.

  🔹How it worked (Rails 3 era):
      class ProductsController < ApplicationController
        caches_page :index
      end

      When someone visits: GET /product
      Rails generates:
        public/products.html

      After that, Nginx serves the file directly.

  🔹Why it is rarely used now:
      Does not work well with authentication
      Hard to expire properly
      Removed from core Rails (available via gem)
        
      If needed today use gem like: gem 'actionpack-page_caching'
      But in real projects, we use reverse proxy caching (Nginx, Cloudflare, CDN).

Action Caching
==============
Action caching caches the entire controller response BUT still runs filters (like authentication)
So unlike page caching, in Action caching:
  before_action runs
  Authorization runs
  But the view rendering is skipped if cached
  
  Example (Old Rails)
    class ProductsController < ApplicationController
      before_action :authenticate_user!
      caches_action :show
    end

    If authenticated:
      Rails checks cache
      Returns cached HTML
      Skips DB and view rendering

  Now Action caching is Removed from Rails core.
  But if you still have to use then use the gem:
    gem 'actionpack-action_caching'
  But again — modern Rails apps rarely use this.

Fragment Caching with Redis
===========================
  Useful when you want to cache view partials:

  <% cache(@user) do %>
    <%= render @user %>
  <% end %>

  This will store the HTML for @user in Redis. The cache key is based on @user.cache_key_with_version.>

Low-Level Caching (Manually Caching Any Data)
=============================================
  Store data:
    Rails.cache.write("user_#{user.id}_stats", expensive_stats)
  
  Read (and fallback):
    stats = Rails.cache.fetch("user_#{user.id}_stats", expires_in: 10.minutes) do
      user.calculate_stats
    end
  
  This is known as fetch with fallback — most common pattern.

Russian Doll Caching
====================
  It is a nested fragment caching technique in Rails. The idea comes from Russian dolls (matryoshka) — one doll inside another.
  In Rails views:
    You cache the outer object (e.g., a post)
    Inside it, you also cache its associated objects (e.g., comments)
  When one part changes, only that part is re-rendered — not everything.

  <% cache(@post) do %>
    <h2><%= @post.title %></h2>
    <p><%= @post.body %></p>

    <% @post.comments.each do |comment| %>
      <% cache(comment) do %>
        <div><%= comment.body %></div>
      <% end %>
    <% end %>
  <% end %>>

  Suppose:
    @post has 5 comments.
    One comment is edited.
  With Russian Doll Caching:
    Only the updated comment's cache is invalidated'.
    The rest (post + other comments) are reused from Redis.
    This makes rendering much faster!

  Russian Doll Caching = nested fragment caching
  Fragment Caching = caching any individual block (could be outer or inner)
  So when you nest fragment caches inside each other, it becomes Russian Doll Caching — just like dolls inside dolls.

  Use it when:
    You have parent-child nested views
    Each object changes independently
    You want to optimize partial rendering

   When Not to Use It?
    If objects change together every time — just cache the whole thing
    If your data is highly dynamic and cache invalidation overhead is high

Cache Invalidation — How It Works
=================================
  Rails uses cache_key_with_version, which includes: Model name, ID, updated_at
  post.cache_key_with_version # => "posts/42-20250602123456"
  So if post.updated_at changes, the key becomes new, and old cache is automatically ignored. No need to delete manually — new key replaces old.

Caching Queries
===============
  Rails.cache.fetch("recent_posts", expires_in: 15.minutes) do
    Post.published.order(created_at: :desc).limit(10).to_a
  end
  Avoid querying the DB every time — cache it in Redis.

---------------------------------------------------------------------------------------------
Question: How to Enable Caching in Development?
Answer: By default, caching is OFF in development.

  To enable caching in development, Run:
    rails dev:cache

  It toggles:
    tmp/caching-dev.txt

  In production:
    config.cache_store = :redis_cache_store

  Example:
    config.cache_store = :redis_cache_store, { url: ENV['REDIS_URL']}

---------------------------------------------------------------------------------------------
Question: How do you expire fragment cache manually?
Answer:
  expire_fragment(@product)
  or
  Rails.cache.delete("active_products")

---------------------------------------------------------------------------------------------
Question: How does Rails generate cache keys?
Answer: 
  Rails uses:
    model_name/id-updated_at
  So when updated_at changes → cache auto expires.
  This is called cache key versioning.

---------------------------------------------------------------------------------------------
Question: Difference between Redis and Memcached for caching?
Answer:
  Redis → persistent, supports data structures
  Memcached → pure in-memory, faster but simpler

---------------------------------------------------------------------------------------------
Question: How Rails Makes Russian Doll Work
Answer: Rails uses cache_key_with_version
Example: products/5-20260228123045
When product updates:
updated_at changes
version changes
cache key changes

only that fragment invalidates
Outer fragment automatically references new inner keys.
This is why manual expiration is usually unnecessary.

---------------------------------------------------------------------------------------------
Question: When NOT to Use Russian Doll?
Answer: When we have:
  Very simple pages
  Small datasets
  Highly dynamic real-time dashboards
  When invalidation logic is complex
then we should not use Russian Doll caching because overusing nested caching can increase cache memory usage.

---------------------------------------------------------------------------------------------
Question: What is ActiveSupport::Cache?
Answer: ActiveSupport::Cache is a framework built into Rails that provides a unified caching interface. It is essentially an abstraction layer for caching, similar to how ActiveJob abstracts background jobs. 
With ActiveSupport::Cache, you can use methods like Rails.cache.fetch, write, and read in your Rails code without worrying about the underlying caching technology.

The real benefit is that you can switch or scale your cache backend — for example, Memcached, Redis, or even an in-memory store — without changing your application logic. It also provides features like namespaces, expiration times, and fetch blocks, making caching safer and more flexible.

So, ActiveSupport::Cache is more than just a client; it is a framework within Rails that standardizes caching and allows developers to write backend-agnostic, maintainable, and scalable caching code.

---------------------------------------------------------------------------------------------
Question: What Memcached Actually Is?
Answer: Memcached is a separate caching server/software.
  It runs independently on a server (or multiple servers in a cluster).
  Its job is to store data in memory for very fast access.
  It is not Ruby code, and it is not part of Rails.

  You can install it on Linux, macOS, or Windows as a service:
    sudo apt install memcached   # on Ubuntu/Debian
    memcached -d -p 11211        # start the server, Just like we start Sidekiq or redis server.

  🔸How Rails Talks to Memcached?
    Rails communicates with Memcached using a gem / client library, like: dalli . It is the most common Ruby client for Memcached.
    Example in Rails:

      Rails.cache = ActiveSupport::Cache::MemCacheStore.new("localhost:11211")
      Rails.cache.write("user:123", user)
      Rails.cache.read("user:123")

    Here, dalli gem is the bridge between Rails and the Memcached server.
    Without a gem, Rails cannot talk to Memcached.

    So:
      Memcached is a server/software
      Dalli (or another gem) = client library that Rails uses to communicate with Memcached

      It is similar to how Sidekiq uses Redis: Redis is the server, and redis-rb is the gem that Rails or Sidekiq uses to connect to it.

  🔸Configuring Memcached for Rails:
    Tell Rails to use Memcached as its cache store. This is usually done in the environment config files.

    Example (production):
      # config/environments/production.rb Or in config/environments/development.rb
      Rails.application.configure do
        config.cache_store = :mem_cache_store, "localhost:11211"
        # Or for multiple servers:
        config.cache_store = :mem_cache_store, ["cache1:11211", "cache2:11211"]
      end

      Note: ActiveSupport::Cache::MemCacheStore.new("localhost:11211") is equivalent, but using config.cache_store is the Rails standard way.

    NOTE: Now the role of ActiveSupport::Cache comes in picture. No matter what is our cache store, our code syntax to read/write cache will remain same, just like ActiveJob, it works as abstraction layer.

  🔸Configuring different cache store:
    We have many Cache store for rails like: memory_store, redis, solid_cache_store, mem_cache_store, null_store - for test environment. In production.rb or development.rb , we can configure like:

      config.cache_store = :mem_cache_store, "localhost:11211" # for Memcached
      config.cache_store = :redis_cache_store, { url: ENV['REDIS_URL'], expires_in: 1.hour } # for redis
      config.cache_store = :null_store # Avoid any caching.
      config.cache_store = :solid_cache_store. # Rails 8 default.
      config.cache_store = :memory_store # In memory

  🔸Reading/Writing Cache:
    Use Rails.cache.write or Rails.cache.read wherever your Rails code needs caching (controllers, models, services, jobs)

    Examples:
      ➤In a controller:
        def show
          @user = Rails.cache.fetch("user:#{params[:id]}", expires_in: 15.minutes) do
            User.find(params[:id])
          end
        end

      ➤In a model or service object:
        Rails.cache.write("user:#{user.id}", user)

      ➤In a background job:
        class CacheUserJob < ApplicationJob
          def perform(user_id)
            user = User.find(user_id)
            Rails.cache.write("user:#{user.id}", user)
          end
        end

So, we can say, Memcached is a high-performance distributed in-memory key-value Store used for caching.
Important Reality:
  In modern Rails apps, Memcached is less common than Redis. Redis dominates because it does caching + Sidekiq + pub/sub
---------------------------------------------------------------------------------------------
Question: How Memcached Works (Internally)?
Answer: Memcached is a distributed in-memory key-value store used purely for caching. It stores data in RAM and uses LRU(Least Recently Used) eviction. It is ideal for reducing database load by caching frequently accessed or expensive queries. Unlike Redis, it does not support persistence or complex data structures. 
I would use Memcached when I only need fast ephemeral caching in high-traffic applications.

Memcached is an in-memory caching system, so all the data is stored directly in RAM. Because it operates entirely in memory and does not touch disk, it is extremely fast — typically sub-millisecond latency.

Internally, it uses an LRU eviction policy, which stands for Least Recently Used. That means when the allocated memory is full and new data needs to be added, Memcached automatically removes the least recently accessed keys to make space.

In distributed environments, data is spread across multiple Memcached servers using consistent hashing. This ensures that keys are distributed evenly, and if a node is added or removed, only a small portion of keys need to be remapped.

Memcached is also multi-threaded, so it can handle many concurrent client connections efficiently.

There is no disk storage and no persistence layer. If the server restarts, all cached data is lost. But that is completely fine because cache is meant to be a temporary optimization layer — the source of truth is always the main database.

----------------------------------------------------------------------------------------------------------------
Question: What happens if Memcached crashes?
Answer: Cache is lost, but system still works because DB is source of truth.

----------------------------------------------------------------------------------------------------------------
Question:How does Memcached scale?
Answer: It uses consistent hashing to distribute keys across multiple servers.

----------------------------------------------------------------------------------------------------------------
Question: What is cache stampede?
Answer: When many requests miss cache at same time and all hit DB then cache stampede occurs.
    Solution to prevent cache stampede:
      Use race_condition_ttl
      Add random expiry
      Use distributed locking

    Example:
      Rails.cache.fetch("active_products",
        expires_in: 10.minutes,
        race_condition_ttl: 10.seconds) do
        Product.active.to_a
      end

------------------------------------------------------------------------------------------------------------
Question: What is LRU?
Answer: LRU stands for Least Recently Used.
  It is a cache eviction(निष्कासन) policy.

  Its job is to decide which items to remove when the cache is full.
  Rule: the item that has not been used for the longest time gets removed first.

 🔸How It Works:
    Every time you read or write a key, it becomes the “Most recently used.”
    When the cache is full, LRU evicts the least recently used key.

    Example:
        +-----------------------------------------+
        | Cache Keys | Usage Order (recent → old) |
        |------------|----------------------------|
        |  A, B, C   |       C, B, A              |
        +-----------------------------------------+

    If a new key D comes in and cache is full, A gets evicted because it was used the longest time ago.

 🔸Data Structures Behind LRU:
    To implement LRU efficiently, most caching systems (like Memcached or Redis) use a combination of Hash Map (Dictionary) and Doubly Linked List.

    ➤Hash Map(Dictionary):
      Stores key → node reference (not the value directly)
      Allows O(1) access to any key

    ➤Doubly Linked List:
      Stores the actual key → value pairs (in nodes)
      Keeps track of usage order (most recently used → least recently used)
      Allows O(1) insertion, removal, and moving nodes to the front.

    ➤Combined approach:
      Hash map points to nodes in the doubly linked list.
      When you access a key, move it to the front of the list.
      When you need to evict, remove the tail node (least recently used).

  This is how LRU achieves fast reads, writes, and evictions, all in constant time.

==============================================================================================================
🔸HTTP Caching (Using ETag or Last-Modified):
  HTTP caching using ETag or Last-Modified is browser-level or proxy-level caching. It is different from Redis or Memcached.

  Instead of storing rendered HTML/data in server memory (generally redis), we let the browser ask the server — "Has this resource changed?"
  If it has not changed, the server returns 304 Not Modified without sending the response body.
  This saves bandwidth, reduces CPU usage, and improves response time.

🔸ETag (Entity Tag):
  ETag is basically a fingerprint of the response.
  It can be generated based on:
    Record updated_at
    Record cache key (model_name/id)
    Or full response body digest

  The server sends an ETag in HTTP response header like ETag: "abc123xyz"
  The browser stores it.
  Next time, browser sends that ETag in HTTP request header:
    If-None-Match: "abc123xyz"
  If the resource has not changed, server automatically responds: 304 Not Modified. So No response body is sent.

  Example: In Rails, this is extremely simple using fresh_when or stale?.
      class ProductsController < ApplicationController
        def show
          @product = Product.find(params[:id])
          fresh_when(@product)
          # If stale, Rails will render normally.
        end
      end

      We use stale?() method when we want manual checks, like:
        def show
          @product = Product.find(params[:id])

          if stale?(etag: @product)
            render
          end
        end
        
  ➤What Rails Does Internally to generate ETag?
    When you call fresh_when(@product) then rails automatically generates ETag and sets caching headers based on the model record using: 
      @product.cache_key_with_version

    Which looks like: products/5-20260228103000
  
    If updated_at changes → cache key changes → ETag changes → browser gets new response.
    If nothing changed → Rails returns 304 Not Modified.

    cache_key_with_version is a method provided by ActiveRecord.
    Every ActiveRecord model automatically gets it.

🔸Last-Modified:
  Last-Modified is simpler.
  Rails sends the last updated timestamp of the resource in the HTTP response header.

  Example header:
    Last-Modified: Wed, 28 Feb 2026 10:30:00 GMT
  The browser stores it.
  In next request browser sends it back in HTTP request header:
    If-Modified-Since: Wed, 28 Feb 2026 10:30:00 GMT

  If the resource was not updated after that time → return 304. So No response body is sent.

  Example using Last Modified:
    class ProductsController < ApplicationController
      def show
        @product = Product.find(params[:id])

        fresh_when last_modified: @product.updated_at
      end
    end

    Or manually:

    def show
      @product = Product.find(params[:id])

      if stale?(last_modified: @product.updated_at)
        render
      end
    end
    
    +---------------------------------------------------+
    |         ETag           |      Last-Modified       |
    |------------------------|--------------------------|
    | Based on fingerprint   | Based on timestamp       |
    | More accurate          | Less precise             |
    | Detects content change | Detects only time change |
    | Slightly heavier       | Very lightweight         |
    +---------------------------------------------------+

==============================================================================================================
🔸Cache Invalidation Strategies:
  There are few Strategies which we should use for Cache Invalidation.

  🔹Strategy 1: Time-Based Expiration (TTL)
    This is the simplest. example: Rails.cache.fetch("products", expires_in: 10.minutes)
    After 10 min → automatically expires.
    But, there are some pros and cons.
    Pros is that is the very easy to implement but cons is that it may serve stale data.

  🔹Strategy 2: Version-Based (Rails Default)
    Rails uses cache_key_with_version. Key includes: products/5-20260228130000
    When updated_at changes → new key → old key ignored.
    Automatic invalidation.
    Best for ActiveRecord models.

  🔹Strategy 3: Manual Invalidation
    example: Rails.cache.delete("products")
    Used when:
      Bulk updates
      Background job updates
      Complex dependencies

  🔹Strategy 4: Event-Based Invalidation
    We use events like callbacks for invalidation. Example:

      after_commit :expire_cache

      def expire_cache
        Rails.cache.delete("top_products")
      end

  🔹Strategy 5: Write-Through Caching
    When writing to DB, Also update cache. Example:
      product.update!(name: "New")
      Rails.cache.write("product_#{product.id}", product)

    This keeps cache always fresh.

  🔹Strategy 6: Cache-Aside Pattern (Most Common)
    General flow is:
      Check cache
      If miss → fetch DB
      Store in cache
      Return

    Rails fetch implements this.