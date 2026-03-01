🔹Basic Queries
    User.all
    User.find(1)
    User.find_by(email: "test@example.com")
    User.where(name: "Alice") #Returns a relation (chainable, lazy).

🔹Filtering (where)
    User.where(age: 18)
    User.where("age > ?", 18)
    User.where("name LIKE ?", "%john%")
    User.where(age: [18, 21, 25])  # IN query

🔹Selecting Columns
    User.select(:id, :name)

🔹Ordering & Limiting
    User.order(created_at: :desc)
    User.limit(5)
    User.offset(10)

🔹Counting & Aggregates
    User.count
    User.minimum(:age)
    User.maximum(:age)
    User.average(:age)
    User.group(:role).count

🔹Joins & Includes (Associations)
    Eager load (includes)
    users = User.includes(:posts).all  #Preloads posts to avoid N+1 queries.

    Joins
      User.joins(:posts).where(posts: { published: true })
      
      SQL:
        SELECT "users".* 
        FROM "users" 
        INNER JOIN "posts" ON "posts"."user_id" = "users"."id" 
        WHERE "posts"."published" = TRUE

🔹Scopes (Reusable Queries)
    class User < ApplicationRecord
      scope :active, -> { where(active: true) }
      scope :recent, -> { order(created_at: :desc) }
    end

    User.active.recent

🔹Advanced: Arel & Custom SQL
    Rails lets you drop down to SQL when needed:

    User.where("LENGTH(name) > ?", 5)
    User.find_by_sql("SELECT * FROM users WHERE age > 20")

🔸Relations are lazy & chainable
    A Relation builds SQL as you chain; it only hits the DB on load (e.g., to_a, each, first, pluck, count, rendering in views).
    Chain safely: User.active.where("age > ?", 18).order(last_sign_in_at: :desc).limit(20).

🔸Filtering power moves
    User.where(role: %w[admin moderator])        # IN (...)
    User.where("age BETWEEN ? AND ?", 18, 30)
    User.where("name ILIKE ?", "%john%")         # Postgres case-insensitive
    User.where.not(status: %w[archived banned])
    User.where(created_at: ..1.week.ago)         # endless-range (≤)

  OR: User.where(active: true).or(User.where(locked: false))
  Dynamic LIKE safety: pattern = ActiveRecord::Base.sanitize_sql_like(query)

🔸Picking columns (avoid loading whole rows)
    User.pluck(:id, :email)     # returns arrays, no model instantiation
    User.pick(:email)           # single value (nil if none)
    User.ids                    # all IDs fast
    User.select(:id, :email)    # models but only selected attrs loaded

🔸Sorting, limits, pagination
    User.order(last_sign_in_at: :desc).limit(50).offset(100)
    User.reorder(:name)                   # replace previous order
    User.distinct.count(:email)          # DISTINCT count

🔸Aggregates & grouping
    User.group(:role).count                              # {"admin"=>12, "user"=>834}
    Order.group(:user_id).sum(:total_cents)
    Order.where(status: "paid")
        .group(:user_id).having("SUM(total_cents) > ?", 50_00)
    
🔸size vs count vs length:
    count → SQL COUNT every time (unless loaded).
    size → uses loaded records (or COUNT if not loaded).
    length → loads all, counts in Ruby (avoid on big sets).

🔸Joins vs Eager loading (N+1)
    joins → SQL JOIN, does not preload separate instances; good for filtering/sorting on joined table.
    includes → may run extra queries to preload associations; avoids N+1 when reading.
    eager_load → forces a LEFT OUTER JOIN preload (single SQL).
    preload → always separate queries for preloading.

🔸Filter on joined table:
    User.joins(:posts).where(posts: { published: true }).distinct

🔸Avoid N+1 when rendering posts for users:
    users = User.includes(:posts).limit(50)  # later: users.each { |u| u.posts.each ... }

🔸Filter on included table? Use `references` or split:
    User.includes(:posts).references(:posts)
      .where("posts.published = ?", true)

🔸Preferred split: join for filtering + preload for avoiding N+1
    User.joins(:posts).merge(Post.published).preload(:posts).distinct

🔸left_outer_joins for “with or without”:
    User.left_outer_joins(:posts).where(posts: { id: nil })   # users with no posts
    # Rails ≥ 6 has sugar:
    User.where.missing(:posts)            # none
    User.where.associated(:posts)         # at least one

🔸Scopes you will actually reuse
    class Post < ApplicationRecord
      scope :published, -> { where(published: true) }
      scope :recent,    -> { order(published_at: :desc) }
      scope :by_author, ->(user) { where(user_id: user) }
    end

    Post.published.recent.by_author(current_user)

    →Compose with merge:
      User.joins(:posts).merge(Post.published.recent)

🔸Subqueries & advanced FROM
    top_posts = Post.select(:user_id)
                    .group(:user_id)
                    .order(Arel.sql("COUNT(*) DESC"))
                    .limit(10)

    User.where(id: top_posts)     # subquery IN (...)

    # FROM a subquery with alias:
    sub = Post.select("user_id, COUNT(*) AS cnt").group(:user_id)
    User.from(sub, :t).joins("JOIN users ON users.id = t.user_id")
        .select("users.*, t.cnt AS posts_count")

🔸Window functions (Postgres, MySQL 8+)
    Post.select(<<~SQL)
      posts.*,
      ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY created_at DESC) AS rownum
    SQL
    .where("ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY created_at DESC) = 1") # or wrap as subquery

    (Usually wrap the window calc in a subquery then filter on rownum.)

🔸Arel for clean SQL-building
    u = User.arel_table
    User.where(u[:age].gteq(18).and(u[:active].eq(true)))

    Arel keeps things SQL-injection-safe while allowing complex boolean logic.

🔸Bulk operations (no callbacks)
    User.where(inactive: true).delete_all   # fast, no callbacks
    User.update_all(role: "member")         # one UPDATE
    Post.in_batches(of: 1_000).update_all(published: true)
    User.find_each(batch_size: 1_000) { |u| ... }    # loads in batches w/ callbacks

🔸Upserts & inserts (great for ETL)
    # Rails ≥ 6
    User.insert_all([{ email: "a@x.com" }, { email: "b@x.com" }])
    User.upsert_all([{ email: "a@x.com", name: "Alice" }], unique_by: :index_users_on_email)

🔸Locking & concurrency
    # Pessimistic locking (FOR UPDATE)
    User.lock.where(id: ids).to_a
    user.with_lock { user.balance -= 100; user.save! }   # wraps transaction
    # Optimistic locking: add `lock_version` int column; Rails auto-manages it.

🔸Overriding/cleaning conditions
    User.where(active: true).unscope(:where)             # remove all WHEREs
    User.where(active: true).rewhere(active: false)      # replace same key
    User.order(:name).except(:order)                     # drop order

🔸Counter caches & size
    # In Profile: belongs_to :user, counter_cache: true  # adds users.profiles_count
    User.order(profiles_count: :desc)
    # `user.profiles.size` uses counter if not loaded, else in-memory

🔸Polymorphic & conditional association queries
    Comment.where(commentable: Post.where(published: true))
    # or
    Comment.where(commentable_type: "Post")
          .joins("JOIN posts ON posts.id = comments.commentable_id")
          .where("posts.published = TRUE")
