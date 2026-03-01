Rails Performance Optimization & N+1 Problem  
============================================

Eager loading Part -1
-------------------------------------------------------------------------------

  @users = User.all
  @users.each do |user|
    puts user.posts.count
  end

  This is N+1 Query problem.

Ways to fix N+1 Query:
======================
  includes:	Avoid N+1 by eager loading associations
  preload:	Similar to includes; always 2 separate queries
  eager_load:	Uses a JOIN to load everything in 1 query

  ➤ Use .includes 99% of the time — it is smart enough to switch to joins when needed.

includes
========
  - Solves the N+1 query problem by eager loading associations. Rails chooses between preload or eager_load under the hood based on your query.
  - Example:
    @users = User.includes(:posts)
    @users.each do |user|
      puts user.posts.count
    end

  - SQL query: 
    SELECT "users".* FROM "users";
    SELECT "posts".* FROM "posts" WHERE "posts"."user_id" IN (1, 2, 3, ...);
  
  - Use case:
    You just want to access user.posts in memory — no condition/filter on posts.

preload
=======
  - Always uses two separate queries, regardless of any conditions.
    You want to preload posts but not join or filter them.
    Avoids complex joins.
  - Example:
    @users = User.preload(:posts).where(active: true)
   
  - SQL query:
    SELECT "users".* FROM "users" WHERE "users"."active" = true;
    SELECT "posts".* FROM "posts" WHERE "posts"."user_id" IN (1, 2, 3, ...);

  - Use Case:
    Use when you want to eager load but know you wll never filter/sort by the association attributes.
🔍  It is similar to includes, but wont switch to a JOIN even if you add conditions — which can be helpful for optimization or avoiding complex joins.

eager_load
==========
  - Forces an SQL JOIN, loading everything in one query. Useful when you want to filter, sort, or search using columns from the association.
    Needed when WHERE clause uses associated table.
    Gives 1 joined query.

  - Example:
    @users = User.eager_load(:posts).where("posts.published = true")
  
  - SQL query:
    SELECT "users"."id" AS t0_r0, "users"."name" AS t0_r1, ..., 
       "posts"."id" AS t1_r0, "posts"."title" AS t1_r1, ...
    FROM "users"
    LEFT OUTER JOIN "posts" ON "posts"."user_id" = "users"."id"
    WHERE "posts"."published" = true;

  - Use case:
    You need to filter or sort using fields in the posts table. Like
    Show all users who have published posts.
    Order users by the number of posts (requires a JOIN).

    
NOTE:
=======
➤ It is not possible to specify conditions on the eager loaded tables when using preload.
  🔸What this actually means:
    You can specify conditions — but only on the main table (like users). 
    You cannot filter by attributes of the associated table (like posts) using preload.
    
    User.preload(:posts).where(active: true)  #=> This is valid because the condition is on users.active.

    User.preload(:posts).where("posts.published = true")
      This will raise an error or return incorrect results. Why?
      Because preload loads associations in a separate query, and your WHERE clause references a table that is not yet joined. 
      Rails does not know how to process posts.published in the main query without a join.

NOTE: includes is a smart eager loader that may use separate queries or LEFT OUTER JOIN depending on usage. preload always loads associations using separate queries. joins performs SQL JOIN but does not eager load association data and may still cause N+1 when accessing associations.


Eager loading Part - 2 (Advance)
------------------------------------------------------------------------------------

How to Detect N+1 (3 ways)
==========================
① Manual: Logging
  Enable SQL logs in config/environments/development.rb:
    config.active_record.verbose_query_logs = true
  Look for repeated similar SELECTs like:
    SELECT "posts".* FROM "posts" WHERE "posts"."user_id" = ? LIMIT ?

② Gem: Bullet
=============
  gem 'bullet'
  In config/environments/development.rb:
    Bullet.enable = true
    Bullet.alert = true
    Bullet.bullet_logger = true
  Shows popup if N+1 detected.

③ Tests: rspec + bullet
========================
  You can even run Bullet in test env to fail tests if N+1 is present.

Smart includes: When It Switches Behavior
=========================================
  Rails automatically switches includes → eager_load if needed
    User.includes(:posts).where("posts.published = true")
  Rails sees the SQL touches posts, so instead of running 2 queries (preload), it does a JOIN like eager_load.

  This is why:
    includes: can mean preload or eager_load
    Depends on whether you filter/order on the associated table

  User.includes(:posts).where("posts.published = true")
    Here, you are telling Rails:
      "Give me users whose posts are published."
    This requires looking into the posts table (because of posts.published = true), so Rails must JOIN the posts table to evaluate the condition.
    Thus, Rails auto-converts includes(:posts) into eager_load(:posts), which uses a LEFT OUTER JOIN.

  If you do nott touch the associated table in the query, Rails can safely preload (2 separate queries).
  If you do touch it (filter/order), it needs to JOIN, because SQL can not filter something it has not fetched yet.

Avoiding Eager Load Bloat
==========================
  User.includes(:posts).limit(10)
  This loads 10 users and ALL their posts, which could be thousands

  Better => User.includes(:posts).limit(10).where(posts: { published: true }).references(:posts)
  Or load posts lazily if not needed up front.


Rails Internals
===============
  When we do:
    User.includes(:posts)
  Rails builds a JoinDependency or Preloader under the hood.

  We can inspect it via: ActiveRecord::Associations::Preloader.new.preload(User.all, :posts)
  Rails builds a graph/tree of relationships and decides whether to JOIN or issue separate queries.