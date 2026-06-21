1. How does Rails automatically create getter/setter methods for DB columns?
Answer: In Rails, models inherit from ApplicationRecord, which inherits from ActiveRecord::Base.

When the application boots, ActiveRecord connects to the database through the adapter and queries the table metadata using methods like columns and columns_hash.

ActiveRecord then dynamically defines attribute methods using define_attribute_methods, which internally uses define_method to generate getter and setter methods for each column.

If a method is called that has not been defined yet, Rails also uses method_missing to handle dynamic behavior, such as dynamic finders (in older Rails versions).

--------------------------------------------------------------------------------------------------
2.What happens if I add a new column directly in DB while the server is running?
Answer: Rails loads and caches schema metadata at boot. If you add a column directly in the database while the server is running, Rails will not detect it until the process is restarted or reset_column_information is called.

Attribute methods are generated based on cached schema, so them new column will not be accessible.

Even if Rails does not know about the column:
  User.find(1)
  The SQL query will still fetch the column, but:
    Rails will not expose it as a method
    It will not typecast it
    It will not include it in attributes

  Because attribute methods are generated from cached metadata.

-----------------------------------------------------------------------------------------------------
3.What is method_missing and why is it slower than define_method?
Answer: In Ruby, if you call a method that does not exist: obj.unknown_method
Ruby looks up the method in the method lookup chain.
If not found, Ruby calls: method_missing(:unknown_method, *args)
This is defined in BasicObject.

method_missing is invoked when a method lookup fails. It is slower because every call must go through Rubys method lookup failure path. In contrast, define_method creates actual methods in the class method table, enabling direct dispatch and VM optimizations. 
Rails moved from heavy method_missing usage to generated methods for performance reasons.

-------------------------------------------------------------------------------------------------------
4.How does Attribute API (Rails 5+) differ from simple column getters?
Answer: In Pre Rails 5 Attributes were:
  Based only on database columns
  Typecasting happened via columns_hash
  You could not easily define custom typed attributes

Example: user.age
Rails typecasts based on DB column type.

The Rails 5+ Attribute API decouples attribute definition from database columns. It provides a unified type system, supports custom types, virtual typed attributes, consistent casting, and dirty tracking. Unlike simple column-based getters, it uses ActiveModel::Attribute objects internally, making the system extensible and enabling features like encryption and serialization.

----------------------------------------------------------------------------------------------
5.What is the N+1 Query Problem?
Answer: N+1 happens when ActiveRecord lazily loads associations inside a loop, resulting in one initial query plus one query per record. It occurs due to lazy loading behavior. It can be detected via logs, Bullet gem, or APM tools. It is fixed using eager loading methods like includes, preload, or eager_load.

The N+1 query problem happens when:
  You load N records with one query
  Then for each record, you run another query to fetch associated data
  Total queries = 1 + N

Example: 
  users = User.all

  users.each do |user|
    puts user.posts.count
  end

  If there are 100 users:
    1 query → fetch users
    100 queries → fetch posts per user
    Total: 101 queries

---------------------------------------------------------------------------------------------------------
6.Why N+1 Quesry Problem happens?
Answer: ActiveRecord associations are lazy-loaded by default.
When you call user.posts
Rails executes a query at that moment: SELECT * FROM posts WHERE user_id = ?
Inside the loop, that happens for each user.

Rails has no idea ahead of time that you will need posts for all users.
So it issues queries one by one.

--------------------------------------------------------------------------------------------------------
7.What happens if you call count vs size on preloaded associations?
Answer: count always executes a SQL COUNT query regardless of preloading. size is smart — it uses in-memory records if already loaded, otherwise performs a COUNT query. 
length forces loading all records and counts them in Ruby, which can increase memory usage.

Assume we have: users = User.includes(:posts)
                user = users.first
🔹count:
    user.posts.count  => SELECT COUNT(*) FROM posts WHERE user_id = ?

    ALWAYS triggers a SQL COUNT(*)
    Ignores preloaded records
    Does NOT use in-memory association
    Even if posts are already loaded.

  So count hits the database again.

🔹 size:
    user.posts.size

    Rails checks:
      If association loaded → use in-memory array
      If not loaded → perform COUNT query

    So, If preloaded i.e User.includes(:posts) then it will do user.posts.size. No new query.

    If NOT preloaded then it will do:
      User.all.each { |u| u.posts.size }
    Then it behaves like count (one query per user → N+1).

🔹 length:
    user.posts.length
    It forces loading the full association into memory.

    If not loaded then it will execute SELECT * FROM posts WHERE user_id = ?
    Then counts Ruby array. More memory heavy.

-----------------------------------------------------------------------------------------------------
7.Why does joins + distinct sometimes become necessary?
Answer: JOIN duplicates parent rows for each matching child record. distinct ensures unique parent records when using joins for filtering.  
It is necessary when using joins for filtering But you want unique parent records.
Without distinct, pagination and count break.

Example:
  User.joins(:posts)

  SELECT users.* FROM users
  INNER JOIN posts ON posts.user_id = users.id

  If User A has 3 posts, the result set contains:
    User A
    User A
    User A
  Duplicates records. So when you do User.joins(:posts).count, You get inflated count.

Example:
  10 users and Total 50 posts
  You may get 50 instead of 10.

Solution to this is using distinct:
  User.joins(:posts).distinct

  SELECT DISTINCT users.* FROM users
  INNER JOIN posts ON posts.user_id = users.id

  Now duplicates removed at SQL level.
  Now you can do:  User.joins(:messages).distinct.count . This will give uniq parent record count.

------------------------------------------------------------------------------------------------------
8.How does ActiveRecord avoid duplicating parent records when using JOIN?
Answer: When using eager loading via JOIN, ActiveRecord reconstructs object graphs from the flattened SQL result set. It uses internal join dependency logic to deduplicate parent records by primary key and aggregates associated records into collections, preventing multiple parent object initialzation/instantiations (इन्स-टैन-शी-एशन्स).

 ➤The Problem
  JOIN returns:
  user_id	      post_id
    1	            10
    1	            11
    1	            12

  If naïvely instantiated (इन्स-टैन-शिएटेड), You would get 3 User objects.

 ➤What Rails Actually Does:
  When using eager_load, rails uses: ActiveRecord::Associations::JoinDependency

  Internally, Rails iterates over result rows
  Builds a hash map keyed by parent primary key
  Reuses existing parent instance if already built
  Appends child records to association collection

 ➤Pseudo logic:

    users_by_id = {}

    rows.each do |row|
      user_id = row["users_id"]

      user = users_by_id[user_id] ||= build_user(row)

      post = build_post(row)
      user.posts << post if post.present?
    end

    So: Only one User instance per ID. Posts accumulated into association

--------------------------------------------------------------------------------------------------------
9.Lets say we have this query: User.includes(:posts).where(posts: { published: true })
What happens if I add .references(:posts)?

Answer: .references(:posts) forces ActiveRecord to use a LEFT OUTER JOIN when using includes. It is primarily required when referencing associated tables via raw SQL strings, since Rails cannot automatically detect association usage in that case. In modern Rails, when using hash conditions like where(posts: {...}), .references is usually unnecessary.

🔹In Modern Rails (5+):

    User.includes(:posts).where(posts: { published: true }).references(:posts)

    In most cases → nothing changes.
    Rails was already smart enough to detect that posts was referenced in where.
    So .references(:posts) becomes redundant.

🔹Why Does .references Exist Then?
  Because this fails:
    User.includes(:posts).where("posts.published = true")
  Rails cannot parse raw SQL strings to detect association usage.
  So without .references, you get: PG::UndefinedTable: missing FROM-clause entry for table "posts"

  When You Add .references(:posts), you force Rails to use JOIN:
    User.includes(:posts).where("posts.published = true").references(:posts)

-------------------------------------------------------------------------------------------------------------
10.What is serialization in Rails?
Answer: Serialization in Rails refers to converting objects into formats like JSON for APIs, storing structured data in database columns using serialize or JSON types, and converting objects into transportable formats for background jobs via GlobalID. 
Rails supports serialization at multiple layers including JSON rendering, ActiveRecord attribute serialization, and ActiveJob argument serialization.

  🔸JSON Serialization (API Responses):
      render json: user
      Rails calls user.as_json then converts it to JSON.
      
      Internal flow: render json: user -> Calls ActiveSupport::JSON.encode -> Calls as_json -> Converts result to JSON string

    🔹What is as_json vs to_json?
        as_json → returns Ruby hash     => { "id" => 1, "name" => "Pankaj" }
        to_json → returns JSON string   => "{\"id\":1,\"name\":\"Pankaj\"}"

    🔹Customizing JSON output:
      Using only option direclty:  user.as_json(only: [:id, :name])
      Override in model:
        def as_json(options = {})
          super(only: [:id, :name])
        end

  🔸ActiveRecord serialize:
    This is Older way of serializing fields.

    Example:
      class User < ApplicationRecord
        serialize :settings, JSON
      end

      If DB column is text, It stores:
      {"dark_mode": true}

    Internally:
      Before save → convert Ruby object → JSON/YAML
      After load → parse JSON/YAML → Ruby object

   🔹Problems with serialize:
      No type safety
      No validation on structure
      Hard to query
      YAML unsafe historically
      Slow for large objects

      That is why modern Rails prefers: JSON column type (Postgres) or Attribute API

  🔸Serialization in Background Jobs:
      MyJob.perform_later(user)

      Rails does NOT pass object directly.
      It serializes it into:

        {
          "job_class": "MyJob",
          "arguments": [
            {"_aj_globalid": "gid://app/User/1"}
          ]
        }

        Rails uses GlobalID.

      🔹What is GlobalID?
        GlobalID converts user into "gid://app/User/1"
        When job runs then rails fetches record by ID

      🔹What happens if record is deleted before job runs?
        Deserialization fails: ActiveJob::DeserializationError, You must handle it.

  🔸Session Serialization
      Rails stores session in: Cookie store (default), Redis,DB
      If using cookie store: Session data is serialized and encrypted and Stored in browser

  🔸Custom Serializer Classes
      Example using ActiveModel::Serializer

      class UserSerializer < ActiveModel::Serializer
        attributes :id, :name
      end

      Used for:
        Clean API structure
        Versioning
        Association control
        Performance tuning

-----------------------------------------------------------------------------------------------
11.What is Idempotency?
Answer: An operation is idempotent if: Running it multiple times produces the same final result.

  Bad Example:
    def perform(payment_id)
      Payment.find(payment_id).update!(status: "completed")
      Wallet.increment!(:balance, amount)
    end

    If retried → wallet balance increases twice.

  Good Example:
    def perform(payment_id)
      payment = Payment.find(payment_id)
      return if payment.completed?

      Payment.transaction do
        payment.update!(status: "completed")
        Wallet.increment!(:balance, payment.amount)
      end
    end

    Now running twice does not duplicate effect.

-------------------------------------------------------------------------------------------------------
12.Suppose a user makes 2 payments (or double clicks pay), and you enqueue a background job.
How do you ensure the job is not processed twice?

Answer: Background job systems (Sidekiq, Resque, etc.) are at-least-once delivery systems.
Background jobs can run more than once due to retries. So I design them to be idempotent. I use database-level unique constraints and transactional checks to ensure that even if the job runs twice, it does not duplicate side effects. I may also use optimistic or pessimistic locking to prevent race conditions.

Background job systems like Sidekiq are at-least-once delivery systems, so jobs may run multiple times due to retries. To handle deduplication, I design jobs to be idempotent by checking state before processing, using database transactions and row-level locking, and enforcing unique constraints at the database level. For payments specifically, I use an idempotency key or unique transaction identifier so duplicate requests do not result in duplicate charges.

That means: A job can run multiple times.
Reasons:Retry after failure, Network glitch, Worker crash, Manual retry etc
So code must be idempotent.

There are multiple strategies to Handle Deduplication.

🔸Strategy 1:Database-Level Idempotency:
  ➤Use a unique constraint.
  
  Example: add_index :payments, :transaction_id, unique: true
  If same payment comes twice: DB raises error. This is the safest approach. Always prefer DB-level protection.

🔸Strategy 2:Idempotency Key
  Common in payment systems - Stripe does this.

  Client sends Idempotency-Key: abc123
  Store it in DB. If same key seen again then return existing result.

🔸Strategy 3:Check Before Processing

  def perform(payment_id)
    payment = Payment.find(payment_id)

    return if payment.processed?

    payment.with_lock do
      return if payment.processed?

      process_payment
      payment.update!(processed: true)
    end
  end

  with_lock prevents race condition.

---------------------------------------------------------------------------------------------------------
13.How do you guarantee exactly-once execution?
  Answer: We can not guarantee exactly-once execution.
    Distributed systems guarantee at-least-once, not exactly-once.
    So our design operations must be idempotent.

---------------------------------------------------------------------------------------------------------
14.REST Principles
Answer: REST stands for Representational State Transfer. It is an architectural style for designing scalable and maintainable APIs. It enforces stateless communication, resource-oriented URLs, proper HTTP verb usage, and client-server separation. It relies on HTTP semantics and idempotent operations for predictability.

First principle is statelessness — each request must contain all required information. The server should not store client session state.

Second is resource-based design — everything is treated as a resource, identified by a URL like /users/10.

Third is proper use of HTTP methods — GET for read, POST for create, PUT or PATCH for update, DELETE for remove.

Fourth is standard HTTP status codes — like 200, 201, 400, 401, 404, 500.

Fifth is idempotency — for example, calling PUT multiple times should not change the result.

And finally, REST APIs should be cacheable when possible and follow uniform interface principles.

  🔸Is POST idempotent? Answer-> No
  🔸Is PUT idempotent? Answer-> Yes — calling it multiple times produces same result.

----------------------------------------------------------------------------------------------------------
15. What is Webhook Signature Verification and how do you manage it?
Answer: Webhook signature verification ensures that incoming webhook requests are actually sent by a trusted provider and not by an attacker.

Typically, the sender generates an HMAC signature using a shared secret and includes it in the request header.

On our side, we recompute the HMAC using the same secret and the raw request body.
Then we compare the computed signature with the received signature using a secure comparison method like secure_compare to prevent timing attacks.

If the signature does not match, we reject the request with 401 Unauthorized.
This guarantees authenticity and integrity of the payload.

Provider sends: Request body, Timestamp and Signature header
Example: 
    timestamp = Time.now.to_i.to_s
    body = { name: "abc", role: "admin"}.to_json
    data = "#{timestamp}.#{body}"
    secret = ENV["webhook_secret"]
    digest = OpenSSL::HMAC.digest("SHA256", secret, data)
    
    signature = Base64.strict_encode64(digest)

    headers = {
      "Content-Type" => "application/json",
      "X-Signature" => "sha256=#{signature}",
      "X-Timestamp" => timestamp,
    }

Server computes: 
  received_signature = request.headers["X-Signature"]&.split("=")&.last 
  timestamp = request.headers["X-Timestamp"]

  return false if timestamp.blank?
  
  request_time = Time.at(timestamp.to_i)
  return false unless (Time.current - request_time).abs < 5.minutes

  data = "#{timestamp}.#{request.raw_post}"
  secret = ENV["webhook_secret"]
  expected = Base64.strict_encode64(OpenSSL::HMAC.digest("SHA256", secret, data)) #Compute

  ActiveSupport::SecurityUtils.secure_compare(expected, received_signature) #Comapre

----------------------------------------------------------------------------------------------------------
16.How to Secure APIs
Answer:To secure APIs, first I always enforce HTTPS to prevent man-in-the-middle attacks.
Second, I implement authentication — typically OAuth2, JWT tokens, or API keys depending on the use case.
Third, I implement authorization to ensure users can only access permitted resources.
Fourth, I validate all inputs strictly to prevent SQL injection, XSS, or mass assignment.
Fifth, I implement rate limiting using tools like rack-attack.
Also, I configure CORS to allow requests only from whitelisted origins.
I will also add Data-Level Security, to store sensitive data securely.
Finally, I log suspicious activities and monitor traffic patterns.

----------------------------------------------------------------------------------------------------------
17.What is Rate Limiting?
Answer: Rate Limiting means: Restrict number of requests per IP or user in a time window. 
For example: Max 100 requests per minute
Rate limiting protects APIs from abuse by restricting request frequency. In Rails, rack-attack can throttle by IP or user identifier. 
In distributed systems, Redis should be used as the backing store to ensure consistent rate limits across instances.

  Rack::Attack.throttle("req/ip", limit: 100, period: 1.minute) do |req|
    req.ip
  end

-----------------------------------------------------------------------------------------------------------
18.How Would You Design a Secure Public API for Third-Party Integrations?
Answer: For designing a secure public API, I would first implement strong authentication — usually OAuth2 or API key with HMAC signing.
I would enforce HTTPS only.
Then I would implement rate limiting per API key to prevent abuse.
I would add request signing to ensure integrity.
I would also version the API, like /v1/, to avoid breaking changes.
Input validation and schema validation are mandatory.
I would log all requests with request IDs for traceability.
I would also implement IP whitelisting if needed for high-security integrations.
And finally, I would monitor usage and revoke compromised keys immediately.

------------------------------------------------------------------------------------------------------------
19.How Would You Prevent Replay Attack in Webhook?
Answer: Replay attack happens when an attacker captures a valid request and replays it multiple times.
To prevent replay attacks, I would use a timestamp in the webhook header.
When verifying the signature, I also check if the timestamp is within a valid time window, for example within 5 minutes.
If the timestamp is too old, I reject the request.
Additionally, I can store webhook event IDs in Redis or database and ensure each event ID is processed only once.
That way even if someone replays the same payload, it will be rejected as duplicate.

------------------------------------------------------------------------------------------------------------
20.How Do You Design Rate Limiting in Distributed Architecture?
Answer: In distributed architecture, rate limiting must be centralized.
If we use multiple application servers, in-memory rate limiting will not work.
So we use a distributed store like Redis.
Each request increments a counter in Redis using atomic operations.
We can implement algorithms like token bucket or sliding window.
Redis ensures consistency across multiple instances.

For large-scale systems, we can also use API gateways like Kong or AWS API Gateway which provide built-in distributed rate limiting.

------------------------------------------------------------------------------------------------------------
21.How Would You Detect Abnormal Traffic Patterns?
Answer: To detect abnormal traffic, I would monitor metrics like request rate, error rate, response time, and unusual IP behavior.
If a single IP suddenly sends thousands of requests, that is suspicious.
I would integrate monitoring tools like Prometheus and Grafana.
I would also use alerting systems for traffic spikes.
Additionally, anomaly detection rules can be implemented based on baseline traffic behavior.
If abnormal activity is detected, I can automatically block IPs using rack-attack or firewall rules.

-----------------------------------------------------------------------------------------------------------
22.How Do You Secure Internal APIs Between Microservices?
Answer: For internal microservices, I never assume the network is trusted.
First, I use mutual TLS so both services authenticate each other.
Second, I use service-to-service authentication using JWT or internal service tokens.
Third, I restrict network access using private subnets and firewall rules.
Fourth, I implement role-based authorization even for internal APIs.
And finally, I use API gateways or service mesh like Istio to manage traffic securely.

🔸TLS(Transport Layer Security): It is a cryptographic protocol used to secure communication between services by providing encryption, authentication, and data integrity. It is the successor to the now-deprecated Secure Sockets Layer (SSL) protocol.

--------------------------------------------------------------------------------------------------------------
Question: What happens when we call User.find(1)
Answer: When we call User.find(1), several things happen internally inside Rails.

First, the find method is called from ActiveRecord::FinderMethods, because User inherits from ActiveRecord::Base and in ActiveRecord::Base, FinderMethods module is included.

Even though find returns a single record immediately, Rails still builds an ActiveRecord::Relation internally. This relation acts like a query builder. It holds information like table name, conditions, limit, and selected columns.

Next, this relation is converted into an abstract representation using Arel. Arel is Rails’ internal SQL AST builder. Instead of directly writing SQL strings, Rails builds a tree structure using Arel that represents the query.

Only after AST(abstract syntax tree) is ready → SQL string is generated.
This abstraction allows multiple adapters like PostgreSQL, MySQL, SQLite to all work without rewriting query logic.

Now Arel hands over the AST to the connection Adapter(PostgreSQLAdapter, Mysql2Adapter, SQLite3Adapter)

The adapter Converts AST to proper SQL string adds quoting rules and adds database-specific syntax.
After that, The adapter: Takes SQL, Uses connection pool, Sends query to database, Receives raw result rows.

The database executes the query and returns raw rows. At this point, all values come back as strings.

Then ActiveRecord performs type casting based on the model’s column definitions. For example, it converts string values into integers, booleans, or datetime objects as needed.

Finally, Rails instantiates (इन्स-टैन-शिएट्स) a User object, assigns the attributes, marks it as persisted, and returns the fully hydrated Ruby object.

If no record is found, it raises ActiveRecord::RecordNotFound.

So overall, the flow is:
  ActiveRecord::Relation → Arel → SQL generation → Connection adapter → Query execution → Type casting → Object instantiation (इन्स-टैन-शी-एशन).”

------------------------------------------------------------------------------------------------------
Question: Suppose, We need to store categories with a nested structure, where categories can have child categories, and this hierarchy can potentially go several levels deep. An example could be 'Electronics' → 'Devices' → 'Mobile' → 'Smart' and 'Feature'. How do you manage this in rails?

Answer: The most common way to represent this kind of hierarchy in a relational database is by using a self-referential model, where a category has a foreign key reference to its parent category. Each category record can have a parent_id field pointing to the parent category, and we can use Rails has_many and belongs_to associations to define the relationship.

In this model, the root categories, like 'Electronics', would have a parent_id of null, while their subcategories (e.g., 'Mobile') would have a parent_id pointing to the parent category.

This structure works well for most cases, but it does require multiple tables and joins, which could lead to performance issues as the category depth increases.

  # Generate the Categories table migration
  class CreateCategories < ActiveRecord::Migration[6.1]
    def change
      create_table :categories do |t|
        t.string :name, null: false
        t.references :parent, foreign_key: { to_table: :categories }, index: true
        t.timestamps
      end
    end
  end

  name: This is the name of the category (e.g., "Electronics", "Mobile", "Iot", "Smart", etc.).
  parent_id: This is a foreign key that references the same categories table. It points to the parent category. This makes it possible to create a tree-like structure.
  
  The parent column points to the parent category of the current category. For example, "Mobile" would have a parent_id pointing to "Device," and "Device" would have a parent_id pointing to "Electronics."

  class Category < ApplicationRecord
    # A category can have many subcategories (children).
    has_many :subcategories, class_name: 'Category', foreign_key: 'parent_id', dependent: :destroy
    
    # A category can belong to a parent category.
    belongs_to :parent, class_name: 'Category', optional: true
  end

  has_many :subcategories: This sets up the child categories (subcategories).
  belongs_to :parent: This sets up the parent category.
  optional: true: This makes the parent optional since the top-level categories (like "Electronics") will not have a parent.

    # Creating categories and subcategories
    electronics = Category.create(name: 'Electronics')
    
    device = electronics.subcategories.create(name: 'Device')

    mobile = device.subcategories.create(name: 'Mobile')

    iot = device.subcategories.create(name: 'Iot')
    smart = mobile.subcategories.create(name: 'Smart')
    feature = mobile.subcategories.create(name: 'Feature')


An alternative approach that could work well, especially if the structure is more dynamic or we need flexibility, is to use JSONB in PostgreSQL. With JSONB, we can store the entire category hierarchy in a single column, as a nested JSON object. This way, each category record would have a name and a data column where the nested categories are stored in JSON format.

Using JSONB offers great flexibility because we do not need to alter the schema if the category structure changes, and it allows us to store complex nested data in a single column. However, there are some downsides. For example, querying deeply nested data or performing complex joins can be more challenging with JSONB, especially if you have to traverse large trees. You also lose some benefits of relational integrity, like foreign keys, and might face performance concerns with large datasets unless we properly index the JSONB column.

On the other hand, using a relational approach with a self-referential model ensures that data integrity is maintained (since you can enforce parent-child relationships using foreign keys) and can easily handle complex queries and reporting. However, this comes with the overhead of creating and maintaining additional tables and joins, and it may not be as flexible if the category structure changes frequently.

----------------------------------------------------------------------------------------------------------
Question: If every 1 minute, 1 job enqueues 200 jobs — what problem can happen?
Answer: If every minute we enqueue 200 jobs, the main issue depends on whether our system can process 200 jobs per minute or not.
If processing speed is slower than enqueue rate, jobs will start accumulating in the queue.
Over time, this creates a backlog.

For example, lets say:
  200 jobs are added per minute
  Each job takes 3 seconds
  We have 5 workers

In 1 minute:
  5 workers * 60 seconds = 300 seconds capacity
  But required work = 200 * 3 = 600 seconds

So system can only handle half the load.
Remaining jobs will pile up every minute.

After 10 minutes → 1000+ pending jobs.
Users will experience delays.

Problems That Can Happen:
  Queue backlog increases
  Redis memory usage grows
  Job latency increases
  External API rate limits (if calling APIs)
  DB load spikes
  Retries increase system pressure

So the real problem is imbalance between enqueue rate and processing rate.
If we enqueue faster than we process, system becomes unstable and queue keeps growing.

So to fix this:
  Monitor queue latency
  Increase worker concurrency carefully
  Add rate limiting

--------------------------------------------------------------------------------------------------------
Question: What is Convention over Configuration in Rails?
Answer: Convention over Configuration in Rails means that Rails follows predefined naming conventions and project structure, so developers do not have to write a lot of manual configuration.

For example, if I create a model class called User, Rails automatically assumes the database table name is users. I do not need to explicitly configure that mapping.

Similarly, if I create a controller called UsersController with an action like show, Rails automatically renders the view file from app/views/users/show.html.erb.

In routing, when I write resources :users, Rails automatically generates all the standard RESTful routes like index, show, create, update, and destroy without defining each route manually.

This also applies to modules and namespaces. For example, if I define a controller inside a namespace like Admin::UsersController, Rails expects the file to be located in app/controllers/admin/users_controller.rb and the views inside app/views/admin/users/. So the folder structure follows the module namespace automatically.

So as long as we follow Rails conventions for naming, file structure, and namespaces, Rails wires everything together automatically. Only when we break these conventions then we need to add explicit configuration.

------------------------------------------------------------------------------------------------------------
Question: What is CAP Theorem ?
Answer: CAP Theorem (by Eric Brewer) states that in a distributed system, you can only guarantee two out of three properties:
            C - Consistency
            A - Availability
            P - Partition Tolerance
      When a network partition happens (communication failure between nodes), you must choose between Consistency and Availability.

      Consistency means - Every read receives the most recent write.
      Availability means - Every request receives a response.
      Partition Tolerance means - The system continues operating even if network communication breaks between servers.

      Here Partition refres to:
        Two servers in your system cannot talk to each other because of a network problem.
        Not crashed.
        Not shut down.
        Just network communication broken.

      Partition Tolerance means: The system continues to operate even when servers cannot communicate.

    Real example explain:
    ----------------------
      Imagine your Rails app uses:
        1 Primary PostgreSQL DB (for writes)
        1 Read Replica (for reads)

              Rails App
                |
              Primary DB  <----->  Replica DB

      Now suddenly, The network connection between Primary and Replica breaks. That is a partition.
      They are both running…, But they can not talk to each other.

      Now You Must Choose: C or A
        Because of CAP, you cannot have both.
          Option 1: Choose Consistency (CP)

                  You say: “If replica is not up-to-date, do not serve reads.”

                  So:
                    Reads from replica are blocked
                    Users may see errors
                    But data is correct
                    You sacrificed Availability.

          Option 2: Choose Availability (AP)
                  You say: “Keep serving reads even if replica might be stale.”

                  So:
                    Users can still load pages
                    But they might see old data
                    You sacrificed Strong Consistency.