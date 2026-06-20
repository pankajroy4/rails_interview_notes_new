Model Associations
===========================
 🔹Relationships in Rails:
   Relationship among tables in database can be one-to-one, one-to-many, many-to-many.

    when we combine 'has_one' on one model and 'belongs_to' on the other, then we are defining a one-to-one relationship in Rails.
    when we combine 'has_many' on one model and 'belongs_to' on the other, then we are defining a one-to-many relationship in Rails.
    For many-to-many relationship in rails:
      we can either use:
        has_and_belongs_to_many 
      OR
        has_many :through

  ➤ One-to-one
      class User < ApplicationRecord
        has_one :profile
      end

      class Profile < ApplicationRecord
        belongs_to :user
      end

      →users table: id
      →profiles table: id, user_id
      →Each user has one profile.
      →Each profile belongs to one user.
      →Foreign key lives on the belongs_to side (profiles.user_id).

  ➤ One-to-many
      class User < ApplicationRecord
        has_many :posts
      end

      class Post < ApplicationRecord
        belongs_to :user
      end

      →users table: id
      →posts table: id, user_id
      →One user → many posts.
      →One post → one user.
      →Foreign key on the posts table.

  ➤ Many-to-many
     🔸Option A: has_and_belongs_to_many (HABTM)
        class Student < ApplicationRecord
          has_and_belongs_to_many :courses
        end
        
        class Course < ApplicationRecord
          has_and_belongs_to_many :students
        end

        →Join table: courses_students with student_id, course_id. in the intermediate table ,By default, it only has the two foreign keys (no id, no timestamps).
        →Rails expects this table, but there is no corresponding CourseStudent model.
        →Quick setup, no join model exists. We will have to create an intermidiate table with migration. 

      🔸Option B: has_many :through (preferred)
        class Student < ApplicationRecord
          has_many :enrollments
          has_many :courses, through: :enrollments
        end

        class Course < ApplicationRecord
          has_many :enrollments
          has_many :students, through: :enrollments
        end

        class Enrollment < ApplicationRecord
          belongs_to :student
          belongs_to :course
          # extra attributes like :grade, :enrolled_on
        end

        →Join table: enrollments with student_id, course_id, plus optional extra columns.
        →Flexible — lets you add validations, callbacks, and extra data on the relationship.
        →More flexible, join table backed by a model. Here a actual model will be there with table.

Associations:
==================

╰➤has_many & belongs_to

    class User < ApplicationRecord
      has_many :posts
    end

    class Post < ApplicationRecord
      belongs_to :user
    end

    post.user → fetches the user of a post
    user.posts → fetches all posts of a user

    DB rule: belongs_to side always has the foreign key.

    The posts table has a user_id column (because Post has belongs_to :user).
    The users table has no reference to posts.
    Yet, when you call:  user.posts
    Rails is able to fetch all posts for that user. How Rails Does It?

    When you declare:
      class User < ApplicationRecord
        has_many :posts
      end

    Rails builds an association object that knows how to query the database. Specifically:
      has_many :posts tells Rails:
        Look at the posts table. Find all rows where user_id = user.id
  
       🔸So internally, when you call:
          user.posts
        Rails runs something like:
          SELECT "posts".* 
          FROM "posts" 
          WHERE "posts"."user_id" = #{user.id}
  
       🔸when you call:
          post.user
        It tells rails, look at user table , find that record where the column id = posts.user_id
        Rails uses the belongs_to :user association and will run essentially this SQL:
          SELECT "users".* 
          FROM "users" 
          WHERE "users"."id" = #{posts.user_id}
          LIMIT 1


╰➤has_one & belongs_to
    class User < ApplicationRecord
      has_one :profile
    end

    class Profile < ApplicationRecord
      belongs_to :user
    end

   🔸user.profile → single profile
      It tells rails, look at profile table, find that record where the column user_id = user.id
      Rails sees has_one :profile. So it knows the foreign key is on the profiles table (profiles.user_id). SQL generated is like:

        SELECT "profiles".*
        FROM "profiles"
        WHERE "profiles"."user_id" = #{user.id}
        LIMIT 1

   🔸profile.user → back reference
      It tells rails, look at user table , find that record where the column id = profile.user_id
      Rails sees belongs_to :user. It knows the foreign key is profiles.user_id. SQL generated is like:

        SELECT "users".*
        FROM "users"
        WHERE "users"."id" = #{profile.user_id}
        LIMIT 1


╰➤has_many :through

    class User < ApplicationRecord
      has_many :memberships
      has_many :groups, through: :memberships
    end

    class Group < ApplicationRecord
      has_many :memberships
      has_many :users, through: :memberships
    end

    class Membership < ApplicationRecord
      belongs_to :user
      belongs_to :group
      # plus extra columns: role, joined_at, etc.
      validates :role, presence: true
    end

    Here:
      User  & Group        → Many-to-Many (through memberships)
      User  & Membership   → One-to-Many (a user can have many memberships)
      Group & Membership   → One-to-Many (a group can have many memberships)

      So each Membership is the join table with extra attributes (like role, joined_at, etc.), making it a "has many through with extra data" pattern.

   🔸Now you can do:
      ➤user.groups
        On first access (lazy-loaded), Rails issues an INNER JOIN from the through table to the target table:

          SELECT "groups".*
          FROM "groups"
          INNER JOIN "memberships"
            ON "memberships"."group_id" = "groups"."id"
          WHERE "memberships"."user_id" = #{user.id}

        Results are cached on the user instance (subsequent user.groups calls do not hit the DB unless you call .reload).
        No default ordering unless you add one (e.g., has_many :groups, -> { order(name: :asc) }, through: :memberships).
        If duplicates are possible (multiple memberships pointing to the same group), add -> { distinct } to the association to get SELECT DISTINCT.

        So:
          user.groups → groups INNER JOIN memberships, filtered by memberships.user_id = user.id.

      ➤group.users
        Symmetric query:

          SELECT "users".*
          FROM "users"
          INNER JOIN "memberships"
            ON "memberships"."user_id" = "users"."id"
          WHERE "memberships"."group_id" = #{group.id}

        Same lazy-loading + association caching apply.

        So:
          group.users → users INNER JOIN memberships, filtered by memberships.group_id = group.id.

      ➤user.memberships.first.role

        This is two steps:
          1🔸Load the first membership for the user
              (.first adds a LIMIT 1 and, if no explicit order exists, orders by the primary key ascending.)

              SELECT "memberships".*
              FROM "memberships"
              WHERE "memberships"."user_id" = #{user.id}
              ORDER BY "memberships"."id" ASC
              LIMIT 1

          2🔸Read role from the already-loaded row — no extra SQL:
              # role is a column on the loaded Membership instance
              user.memberships.first.role  # no additional query

      ➤NOTE: If you only need the role and not the object, you can avoid instantiating (इन्स-टैन-शी-एटिंग) it:
              user.memberships.order(:id).limit(1).pick(:role)  # one query, returns the value

      ➤N+1 avoidance (eager loading)
       🔸When iterating, prefer eager loading:
          # Users and their groups (has_many :through)
          User.includes(:groups).find_each do |u|
            u.groups.each { |g| ... }  # no N+1
          end

          Rails will typically perform:
          -Load users
          -Preload memberships for those users
          -Load all groups referenced by those memberships(three queries instead of 1 + N).

       🔸If you need conditions on the through table while fetching groups:
          # Only groups where the user’s membership role is 'admin'
          user.groups.merge(Membership.where(role: "admin"))
          Rails still joins through memberships and adds the role filter.

      ➤Handy operations
        🔸Create a membership via the through association:
            user.groups << group  # creates a Membership(user_id: user.id, group_id: group.id)

          Or explicitly with extra columns:
            user.memberships.create!(group: group, role: "admin", joined_at: Time.current)

      ➤Indexes (performance)
        Make sure you have indexes (and foreign keys) on the join columns:
          add_index :memberships, :user_id
          add_index :memberships, :group_id
          add_index :memberships, [:user_id, :group_id], unique: true # if you want to prevent duplicates

╰➤has_and_belongs_to_many:

    class User < ApplicationRecord
      has_and_belongs_to_many :groups
    end

    class Group < ApplicationRecord
      has_and_belongs_to_many :users
    end

   🔸Rails expects a join table named after the two models in alphabetical order (e.g., groups_users). (not users_groups). It is a pure join table.
   🔸You must create this table manually with a migration.
   🔸What it is: A shortcut for a simple many-to-many relationship.
   🔸Join table: Exists, but no model class for it.
   🔸Columns: Just two foreign keys (user_id, group_id). The table contains only the two foreign keys (user_id, group_id) — no id column by default.
   🔸Best for: When the relationship itself does not have any extra data.
   🔸Indexes: add a unique composite index to prevent duplicate links, plus supporting indexes.

   Migration (typical):
    class CreateGroupsUsersJoin < ActiveRecord::Migration[7.1]
      def change
        create_join_table :groups, :users do |t|
          t.index [:group_id, :user_id], unique: true
          t.index :user_id
          t.index :group_id
        end

        add_foreign_key :groups_users, :users,  on_delete: :cascade
        add_foreign_key :groups_users, :groups, on_delete: :cascade
      end
    end

    ➤If you need a non-standard table name or FK names, you can pass options on the association:
      has_and_belongs_to_many :groups, join_table: :my_memberships,
                                      foreign_key: :member_id,
                                      association_foreign_key: :team_id

   🔸Now you can do:
      ➤user.groups

        SELECT "groups".*
        FROM "groups"
        INNER JOIN "groups_users"
          ON "groups"."id" = "groups_users"."group_id"
        WHERE "groups_users"."user_id" = #{user.id};

      ➤When you add record:
        user.groups << group
        # => INSERT INTO "groups_users" ("user_id","group_id") VALUES (?, ?)

      ➤When you remove:
        user.groups.delete(group)
        # => DELETE FROM "groups_users" WHERE "user_id" = ? AND "group_id" = ?
      
        When a User (or Group) is destroyed, Rails will clear the join rows for that record during the destroy process. 
        Adding DB FKs with ON DELETE CASCADE ensures cleanup even if deletes happen outside Rails.


╰➤has_and_belongs_to_many v/s has_many :through

| Feature / Method                 |       HABTM (has_and_belongs_to_many)             |     has_many :through                              |
|----------------------------------|---------------------------------------------------|----------------------------------------------------|
| 🔸Join table                    →| Pure join table (no model, just two FKs)          | Full join model (`Membership`) with its own        |
|                                  |                                                   |  table and model class                             |
|                                  |                                                   |                                                    |
| 🔸Association read              →| `user.groups`, `user.group_ids`,                  | Same methods available                             |
|                                  | `user.groups.count`, `user.groups.exists?`,       |                                                    |
|                                  | `user.groups.loaded?`, `user.groups.reload`       |                                                    |
|                                  |                                                   |                                                    |
|                                  |                                                   |                                                    |
| 🔸Association write             →| `user.groups << g`, `user.groups.create!(attrs)`, | Same methods; Rails just manages the `memberships` |
|   (add/replace/remove)           | `user.group_ids = [..]`, `user.groups.delete(g)`, | table instead of the HABTM join table              |
|                                  | `user.groups.clear`                               |                                                    |
|                                  |                                                   |                                                    | 
|                                  |                                                   |                                                    |
| 🔸Eager load                    →| `User.includes(:groups)`                          | Same                                               |
|                                  |                                                   |                                                    |
| 🔸Dependent cleanup             →| Cannot attach `dependent: :destroy`               | Can use `dependent: :destroy` on `:memberships` to |
|                                  | (no join model) — you must rely on DB FKs for     |  cascade properly                                  |
|                                  |   cleanup                                         |                                                    |
|                                  |                                                   |                                                    |
| 🔸Extra attributes on join      →| Not possible (table has only FKs)                 | Possible (e.g. `role`, `joined_at`)                |
| 🔸Validations/Callbacks on join →| Not possible                                      | Possible on `Membership` model                     |
| 🔸Direct access to join rows    →| Not available                                     | Yes (`user.memberships`, `group.memberships`)      |
| 🔸Best for                      →| Very simple many-to-many with no extra data on    | Many-to-many with extra data, validations, or      |
|                                  | the join                                          | callbacks                                          |


╰➤polymorphic association:
    A polymorphic association lets a model belong to more than one other model on a single association.
    Instead of having separate foreign keys for each possible parent, we store:
      an ID (*_id)
      and a type (*_type)
    Rails uses these two columns to figure out which table/model to look up.

    Example: Comments on multiple models
      Assume we want a Comment that can belong to either a Post or a Photo.

     🔸Schema:
        comments
          id
          body
          commentable_id      # integer
          commentable_type    # string ("Post" or "Photo")

      class Comment < ApplicationRecord
        belongs_to :commentable, polymorphic: true
      end

      class Post < ApplicationRecord
        has_many :comments, as: :commentable
      end

      class Photo < ApplicationRecord
        has_many :comments, as: :commentable
      end

      post = Post.create(title: "Hello")
      photo = Photo.create(title: "Sunset")

      # Add comments
      post.comments.create(body: "Nice post!")
      photo.comments.create(body: "Beautiful photo!")

      # Accessing parent
      comment = Comment.first
      comment.commentable   # => could be a Post or Photo, depending on commentable_type

      Rails figures it out by looking at both columns:
        if commentable_type = "Post" and commentable_id = 1, Then
          SELECT "posts".* 
          FROM "posts" 
          WHERE "posts"."id" = 1

   🔸Advantages
      DRY: One comments table works for multiple models.
      Extensible: Easy to add more commentable models later.
      Queries are uniform (comment.commentable works no matter what).

   🔸Limitations
      →No inverse_of support
        Rails can not automatically set inverse associations for polymorphic relations, so inverse_of does not work here.
          Example: comment.commentable.comments will not automatically include unsaved in-memory comments.

      →Querying can be less efficient
        Since commentable_type is a string, and queries may involve joins on multiple models.

      →Validations / callbacks
        Extra care is needed if you validate parent presence or handle nested attributes.

      →Migration complexity
        You need both *_id and *_type in the polymorphic table:

        create_table :comments do |t|
          t.text :body
          t.references :commentable, polymorphic: true, null: false
          t.timestamps
        end

    NOTE:
      Suppose we have model "Plan", and we have:
        class Plan < ApplicationRecord
          belongs_to :planable, polymorphic: true
        end

      Let we have two more models: WebPlan and MobilePlan.
      Then it is not necessary that we should have has_many association in these two models:
        Means , this is not necessary:
          class WebPlan < ApplicationRecord
            has_many :plans, as: :planable   #Not necessary
          end

          class MobilePlan < ApplicationRecord
            has_many :plans, as: :planable #Not necessary
          end

        We can directly use the polymorphic association while creating records for web_paln and mobile_plan. For example:

          web_plan = WebPlan.create!(name: "Starter Web Plan")
          mobile_plan = MobilePlan.create!(name: "Starter Mobile Plan")

          plan = Plan.create!(
            name: "Basic Plan",
            planable: web_plan   # Rails automatically sets planable_id and planable_type
          )

          # Same for mobile plan
          plan2 = Plan.create!(
            name: "Mobile Plan A", 
            planable: mobile_plan    # Rails automatically sets planable_id and planable_type
          )

        We can also do this like this:
          plan  = Plan.create!(name: "Basic Plan", planable_type: "WebPlan", planable_id: web_plan.id)
          plan2 = Plan.create!(name: "Mobile Plan A", planable_type: "MobilePlan", planable_id: mobile_plan.id)

     🔸When has_many :plans, as: :planable is useful to write in parent model?
        You should add has_many :plans, as: :planable if you want convenient access from the other side:

          web_plan.plans     # => [#<Plan id:1, name:"Basic Plan", planable_type:"WebPlan", planable_id:1>]
          mobile_plan.plans  # => [#<Plan id:2, name:"Mobile Plan A", planable_type:"MobilePlan", planable_id:1>]

        Without it, you would have to query manually:
          Plan.where(planable: web_plan)
          Plan.where(planable: mobile_plan)

    
╰➤Polymorphic associations can represent either one-to-one, one-to-many(most common) or many-to-many :
  🔸It depending on how you design them.
  
  ➤one-to-one polymorphic relationship:
    if you want a one-to-one polymorphic relationship, you just constrain it at the database/model level:

    class Plan < ApplicationRecord
      belongs_to :planable, polymorphic: true
      validates :planable_id, uniqueness: { scope: :planable_type }
    end
    This validation ensures that a given planable (e.g., a WebPlan or MobilePlan) can only ever have one Plan.

    Example:
      class WebPlan < ApplicationRecord
        has_one :plan, as: :planable
      end

      class MobilePlan < ApplicationRecord
        has_one :plan, as: :planable
      end

    Now:
      web_plan = WebPlan.create!(name: "Starter Web Plan")

      # first plan is fine
      Plan.create!(name: "Basic Plan", planable: web_plan)
      # second plan for same web_plan will fail (because of uniqueness validation)
      Plan.create!(name: "Another Plan", planable: web_plan)
      # => Validation error

  ➤One-to-many polymorphic relationship(most common)
    class Comment < ApplicationRecord
      belongs_to :commentable, polymorphic: true
    end

    class Post < ApplicationRecord
      has_many :comments, as: :commentable
    end

    class Photo < ApplicationRecord
      has_many :comments, as: :commentable
    end

    -A Post has many comments
    -A Photo has many comments
    -Each Comment belongs to exactly one parent (post or photo)

  ➤Many-to-many polymorphic relationship (via join model)
    If you want, polymorphism can also be used to set up a many-to-many relationship.
    Example: Tags that can apply to posts, photos, or users.

    Schema:
      tags
        id | name

      taggings
        id | tag_id | taggable_id | taggable_type

    class Tag < ApplicationRecord
      has_many :taggings
      has_many :posts, through: :taggings, source: :taggable, source_type: 'Post'
      has_many :photos, through: :taggings, source: :taggable, source_type: 'Photo'
    end

    When using a polymorphic join model (like Tagging for tagging posts and photos), Rails needs hints to resolve the polymorphic association.
      source: → tells Rails which association to use from Tagging (in this case, :taggable).
      source_type: → specifies which model class to use ('Post', 'Photo').

    class Tagging < ApplicationRecord
      belongs_to :tag
      belongs_to :taggable, polymorphic: true
    end

    class Post < ApplicationRecord
      has_many :taggings, as: :taggable
      has_many :tags, through: :taggings
    end

    class Photo < ApplicationRecord
      has_many :taggings, as: :taggable
      has_many :tags, through: :taggings
    end

    Now:
      post.tags   # many-to-many through taggings
      photo.tags  # same
    Here, the polymorphic join model (Tagging) enables a many-to-many relationship.

    So:
      By default (e.g., comments), polymorphic = one-to-many.
      If you introduce a join model (e.g., taggings), polymorphic can power a many-to-many.
    
╰➤Single Table Inheritance (STI):
    STI is a Rails feature that allows multiple Ruby classes to share the same database table, with a special type column telling Rails which class a record belongs to.
    Instead of making a new table for each subclass, Rails stores them all in one table.

    class Vehicle < ApplicationRecord
      # This is the base class
    end

    class Car < Vehicle
    end

    class Bike < Vehicle
    end

    Database (vehicles table)
      vehicles
        id | type   | name       | wheels
        ---------------------------------
        1  | Car    | Tesla      | 4
        2  | Bike   | Mountain   | 2

    Car.create(name: "Tesla", wheels: 4)
    Bike.create(name: "Mountain", wheels: 2)

    Vehicle.all  # => [#<Car id: 1, name: "Tesla", wheels: 4>,  #<Bike id: 2, name: "Mountain", wheels: 2>]
    v = Vehicle.first
    v.class  # => Car

   🔸Rails looks at the type column to instantiate (इन्स-टैन-शिएट) the right Ruby class.
   🔸How it works:
      The parent class (Vehicle) corresponds to the table (vehicles).
      The table must have a type string column (Rails uses it automatically).
      Each subclass (Car, Bike) inherits from the parent, but Rails sets type accordingly.
      All subclasses share the same schema (columns of vehicles).

   🔸Pros:
      DRY: No need for separate tables.
      Easy querying: Vehicle.all gets cars and bikes together.
      Shared behavior: common logic stays in the parent (Vehicle).
   🔸Cons
      Column bloat: All subclasses share the same columns. If Car has fields that Bike never uses, the table gets messy (lots of NULLs).
      Subclass-specific validations: You can validate differently in each subclass, but the schema is still shared.
      Renaming or moving subclasses: Since the type column stores class names ("Car", "Bike"), refactoring class names requires migrating DB data.
      No polymorphism flexibility: Sometimes a polymorphic association is better if you want unrelated models, not subclasses of one parent.

   🔸Rails does not automatically add a type column to any table.
     You (the developer) add it in a migration if you intend to use STI:
      create_table :vehicles do |t|
        t.string :type   # required for STI
        t.string :name
        t.integer :wheels
      end

╰➤Counter Cache
    Rails can maintain a cached count column for associated records.
    For example, Instead of calling user.posts.count (which hits the DB), 
    you can add a posts_count column to the users table and let Rails keep it in sync automatically:

    class Post < ApplicationRecord
      belongs_to :user, counter_cache: true
    end

    -Requires users table to have an integer column named posts_count.
    -Rails will increment/decrement this column whenever posts are created/destroyed.
    -You can customize the column name:
        belongs_to :user, counter_cache: :articles_count


╰➤Dependent options
    dependent: :destroy
      Loads each associated record and calls .destroy on them.
      Runs callbacks and validations on each child.
      Slower but safer.

    dependent: :delete_all
      Issues a single SQL DELETE without instantiating (इन्स-टैन-शी-एटिंग) child objects.
      Does not run callbacks/validations.
      Much faster but can skip important cleanup logic.

    dependent: :nullify
      Sets the foreign key to NULL on destroy (instead of deleting children).
      Example: deleting a User keeps Posts, but sets user_id = NULL.

    choose :destroy if you need callbacks, :delete_all if performance matters and you do not need callbacks.

╰➤inverse_of:
    ➤inverse_of tells Rails which association on the other model points back to this one. 
    With it, ActiveRecord can link objects in memory without extra SQL and keep both sides of the relationship in sync.

      class User < ApplicationRecord
        has_many :posts, inverse_of: :user
      end

      class Post < ApplicationRecord
        belongs_to :user, inverse_of: :posts
      end

      -Rails knows user.posts is the inverse of post.user.
      -When you attach records in memory, Rails will set the back-reference too, without hitting the database.
      -The same Ruby object instance is reused on both sides (object identity), so changes propagate immediately.

    ➤Why inverse_of matters:
      🔸No extra queries
          user = User.first
          post = user.posts.build(title: "Hello")
          post.user          # => returns *the same* `user` object (no SELECT)
        
        Without a usable inverse, Rails might reload user from the DB when you call post.user.

      🔸In-memory mirroring
          user = User.new(name: "Ada")
          post = Post.new(title: "Intro")
          post.user = user
          user.posts.include?(post)   # true *because of* inverse_of (even before saving)

        Without inverse_of, user.posts may not include post until it’s saved & reloaded.

      🔸Nested attributes & validation work smoothly
          When you do accepts_nested_attributes_for :posts, inverse_of lets Rails validate parent/children together (and run callbacks) without persisting mid-way.

      🔸Autosave & dirty tracking behave as expected
        Changes on the child that depend on the parent (and vice-versa) are visible immediately; autosave can persist them in one go.


╰➤touch
    Updates updated_at of parent when child changes.

    class Post < ApplicationRecord
      belongs_to :user, touch: true
    end


    Now when a post is updated, user.updated_at also updates.

╰➤autosave
    Automatically saves associated objects when parent is saved.

    class User < ApplicationRecord
      has_many :posts, autosave: true
    end

    user = User.first
    post = user.posts.first
    post.title = "Updated!"
    user.save  # post also gets saved automatically

╰➤accepts_nested_attributes_for
    Allows saving parent + child in one form.

    class User < ApplicationRecord
      has_one :profile
      accepts_nested_attributes_for :profile
    end

    Form:
      <%= form_for @user do |f| %>
        <%= f.text_field :name %>
        
        <%= f.fields_for :profile do |p| %>
          <%= p.text_field :bio %>
        <% end %>
      <% end %>
    Submitting this form creates/updates both user and profile.




https://chatgpt.com/share/68a6d392-a1a4-800e-8460-acca7f631e9a  -> Given AI Assisment