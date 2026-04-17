ActiveRecord Models - Validations, Callbacks, Scopes, Enums, Attribute API, Concerns:
=====================================================================================
╰➤Conditional Validation:
    Used when validation depends on context or attributes.
      validates :gst_number, presence: true, if: -> { country == 'IN' }

    we are using a lambda (-> { ... }) to conditionally apply the presence: true validation on gst_number.
    How is country accessed inside the lambda?
      Even though you did not explicitly pass country into the lambda, Rails implicitly evaluates the lambda in the context of the model instance.
      So, internally, it is as if Rails does something like: your_model_instance.valid?

      When that happens, Rails checks your validation rules and evaluates the lambda like this:
        your_model_instance.instance_exec(&lambda)
      Which means:
        self.country == 'IN'
      So country is just a method call on self — and in this context, self is the current instance of your model.

╰➤Rails context-based validations:
    Rails supports context-based validations using the :on option. This allows you to define validations that only run in specific scenarios giving you flexibility in how and when validations are applied.
    Example:
     🔸validates :email, presence: true, on: :create
      Here "create" is inbuilt context provided by rails.

      By default, when you run: user.valid?
      Rails runs all validations without any context (i.e., the default validations).


     🔸validates :role, presence: true, on: :admin_context
      Here we defined a custom context "admin_context". role is only validated when you call valid?(:admin_context).

        user = User.new(email: 'abc@example.com')
        user.valid? =>  This will validates all attribute of user except role.
        user.save => Rails will internally execute user.valid?(:default)
          So only validations with:
            no on: option, or explicitly on: :create (if it is a new record), or on: :update (if it is persisted) will run.

        user.valid?(:admin_context) => This will runs only the validations defined with on: :admin_context. It will skip the default validations (the ones without an on: option).


      🔸Rails does support save(context: :your_context)
        user.save(context: :admin_context)
        Rails will run:
          All validations with no context (i.e., normal validations — validates :email, presence: true)
          Plus all validations with on: :admin_context

      Validations with a custom on: context will not run during normal save or valid? calls. You have to explicitly pass the context using valid?(:context) or save(context: :context). This is useful when you need conditional validations like admin-only rules.”

    NOTE: Model validation can be bypassed (update_column, raw SQL).

╰➤Callbacks:
    Callbacks are used for Normalize data, Trigger side effects, Audit logs, triggering Background jobs etc.
    Some common callbacks are: before_validation, before_save, after_save, after_commit etc.
    
   🔸Types of Callbacks
      -Before
        before_validation, before_save, before_create, before_update, before_destroy, before_commit
      -After
        after_validation, after_save, after_create, after_update, after_destroy, after_commit
      -Around
        around_save, around_create, etc. → wraps the action.

   🔸Difference between before_save and before_create?
      - before_save runs on both create + update.
      - before_create runs only on create.

   🔸Why use after_commit instead of after_save for emails?
      - Because if transaction rolls back, you do not want an email to go.
      - after_commit triggers only after transaction is committed successfully.

    Problems with callbacks:
     🔸Hidden logic:	Behavior is not visible from outside
     🔸Hard to test:	Especially after_commit ones
     🔸Hard to reuse:	Can not reuse in background/service jobs

    Better Alternative to callbacks are Service Object: 
      For example: UserRegistrationService.new(params).call
      Where the logic is separated into service classes, not tied to model lifecycle.


╰➤What enum does:
    When you declare:
      class Booking < ApplicationRecord
        enum status: { pending: 0, confirmed: 1, cancelled: 2 }
      end

    Rails treats status as a state-like attribute stored as an integer in the DB, but exposed as readable names in Ruby.
    It auto-generates:
      Getter/Setter, Predicates (one per value), Bang transition methods (set + save!), Scopes (class methods), Mapping hash (class method), 

    🔸Getter/Setter
        booking.status         # => "pending"
        booking.status = :confirmed
        booking.status = "cancelled"

    🔸Predicates (one per value)
        booking.pending?       # => true/false
        booking.confirmed?     # => true/false
        booking.cancelled?     # => true/false

    🔸Bang transition methods (set + save!)
        booking.confirmed!     # sets status to confirmed and saves (runs validations)

        If validations fail, confirmed! raises ActiveRecord::RecordInvalid.
        Non-bang booking.status = :confirmed; booking.save won’t raise; it returns false if invalid.

    🔸Scopes (class methods)
        Booking.pending        # WHERE status = 0
        Booking.confirmed
        Booking.cancelled

    🔸Mapping hash (class method)
        Booking.statuses       # => { "pending" => 0, "confirmed" => 1, "cancelled" => 2 }
        → Use Booking.statuses["confirmed"] to get the underlying integer.

    ➤Array shorthand vs explicit mapping:
      This:
        enum status: %i[draft published archived]
      is shorthand for:
        enum status: { draft: 0, published: 1, archived: 2 }

    ➤Prefixes & Suffixes (avoid name clashes, improve readability):
      Example:
        enum status: %i[draft published archived], _suffix: true
        This will Generates:
          post.draft_status?     # instead of post.draft?
          post.published_status!
          Post.draft_status      # scope

      🔸_suffix: true appends _status (the attribute name).
      🔸_prefix: true prepends the attribute name, e.g. status_draft?.
      🔸You can also pass a string: _prefix: :booking → booking_draft?.

       Use these when values clash with existing methods (e.g., open, errors) or when you want more readable calls (draft_status?).

    ➤Queries we will actually write:
      # Type-casted where:
     🔸Booking.where(status: :pending)

      # IN queries:
     🔸Booking.where(status: %i[pending confirmed])

      # Counts:
     🔸Booking.group(:status).count      # => {0=>12, 1=>8, 2=>3}
      
      # If you want names instead of integers:
     🔸Booking.group(:status).count
          .transform_keys { |i| Booking.statuses.key(i) }    # => {"pending"=>12, "confirmed"=>8, "cancelled"=>3}

      # Ordering by enum order (by integer):
     🔸Booking.order(:status)         # pending -> confirmed -> cancelled

      NOTE: update_all does not type-cast symbols. Use the integer:
          Booking.pending.update_all(status: Booking.statuses["confirmed"])


╰➤Attribute API:
    In Rails, the Attribute API is a set of methods and behavior that allow you to work with model attributes in a more powerful, type-aware, and extensible way.
    It was introduced and improved in Rails 5+ and is deeply tied into ActiveModel/ActiveRecord.
    It is the system behind how model attributes:
      🔸are defined
      🔸are type casted
      🔸are changed
      🔸support custom types

    Rails Attribute API provides a structured way to manage model attributes with type casting, default values, change tracking, and custom serialization. It is extensible — you can even define custom types using ActiveModel::Type.

   🔸Key Features of Attribute API:

        |        Feature         |                       Description                                                           |
        |------------------------|---------------------------------------------------------------------------------------------|
        |     Type Casting       |      Automatically converts values to the correct type (e.g., `Date`, `Integer`, `Boolean`) |
        |     Dirty Tracking     |      Tracks if an attribute was changed                                                     |
        |     Default Values     |      You can define default values                                                          |
        |     Custom Types       |      You can define your own logic for attribute serialization/deserialization              |
        |     "attribute" Method |      Lets you define virtual or typed attributes                                            |

   🔸Example: Using attribute in a Model
      class User < ApplicationRecord
        attribute :admin, :boolean, default: false
      end
      -Adds an admin attribute.
      -Ensures it is treated as a boolean (true/false).
      -Defaults to false.

      Usage:
        user = User.new
        user.admin # => false
        user.admin = "1"
        user.admin # => true (casted to boolean)

   🔸If your model has a column :age, and it is an integer column, then:
        user.age = "20"     # string input
        user.age            # => 20 (automatically casted to integer)

      Rails uses the Attribute API to:
        Store raw values
        Cast them to proper types
        Track changes
        Serialize/deserialize to/from DB

   🔸Custom Types Example (Advanced)
      Lets say you want an attribute that stores currency in cents but interacts in dollars:

        # app/types/money_type.rb
        class MoneyType < ActiveModel::Type::Integer
          def cast(value)
            value.to_f.round(2)
          end

          def serialize(value)
            (value.to_f * 100).to_i
          end
        end

        # app/models/product.rb
        class Product < ApplicationRecord
          attribute :price, MoneyType.new
        end

        product = Product.new(price: "12.99")
        product.price       # => 12.99
        product[:price]     # => 1299 (raw cents sent to DB)

   🔸Some Important methods of Attribute API:
      attribute_names
      has_attribute?(:name)
      read_attribute(:name)
      write_attribute(:name, value)
      attributes_before_type_cast
      changed_attributes
      will_save_change_to_attribute?

╰➤Virtual Attribute:
    Virtual attributes are attributes that do not exist in the DB but behave like regular model attributes. They are often used in forms or computed fields. 
    With Rails Attribute API method (attribute :name, :type), you can define virtual attributes with typecasting and change tracking.

    A virtual attribute:
     -Is not stored in the database.
     -Behaves like a regular model attribute (getter/setter).
     -Can be used in forms, validations, and business logic.

   🔸Using attribute (Attribute API) — recommended in Rails 5+

      class User < ApplicationRecord
        attribute :full_name, :string
      end

      This defines full_name as a virtual attribute.
      It behaves like a string.
      But it is not saved to the database unless you manually do something with it.

      Usage:
        user = User.new(full_name: "John Doe")
        user.full_name         # => "John Doe"
        user.full_name_changed? # => true

   🔸We can also use the virtual attribute in pure ruby class. Use ActiveModel::Model for Pure Ruby Classes.
    Even if you do not use ActiveRecord, you can do:
      class ContactForm
        include ActiveModel::Model
        attribute :name, :string
        attribute :email, :string
        attribute :message, :string
      end
      This gives you:
        -Validations
        -Type casting
        -Form compatibility

╰➤Concerns in Rails?
    Concerns are modules used to extract reusable code (like methods, validations, scopes, callbacks, etc.) from models, controllers, or other classes.
    They help avoid fat models/controllers and promote separation of concerns (hence the name).

    Why are Concerns Important?
     🔸Avoid duplication: Common logic shared across multiple models can go into a concern.
     🔸Promote single responsibility: Keep each file focused.
     🔸Make code more readable and maintainable.
     🔸Encourage reuse of logic across different models or controllers.

    Example
      # app/models/concerns/soft_deletable.rb
      module SoftDeletable
        extend ActiveSupport::Concern

        included do
          scope :active, -> { where(deleted_at: nil) }

          def soft_delete
            update(deleted_at: Time.current)
          end

          def deleted?
            deleted_at.present?
          end
        end
      end

      Include the Concern in a Model
      # app/models/user.rb
      class User < ApplicationRecord
        include SoftDeletable
      end

      That is it! The User model now has:
        User.active
        user.soft_delete
        user.deleted?
      You can include this concern in any other model that has a deleted_at column.

   🔸Using ActiveSupport::Concern gives you:
      -A cleaner syntax for included blocks.
      -Easy use of class methods with class_methods do.

      module SoftDeletable
        extend ActiveSupport::Concern

        included do
          scope :active, -> { where(deleted_at: nil) }
        end

        class_methods do
          def soft_deleted_count
            where.not(deleted_at: nil).count
          end
        end
      end

   🔸extend ActiveSupport::Concern
      This adds syntactic sugar and structure for writing modules (concerns) in Rails.
      Without it, modules in Ruby are more manual and require included hooks and extra boilerplate.

      With ActiveSupport::Concern, We get:
        1. included do ... end
        Code inside runs when the module is included in a class.
        Cleaner and avoids included method conflicts.

        2. class_methods do ... end
        All methods inside become class methods of the including class.
        You do not need to manually define a self.included hook.

 🔸Examples of Controller Concerns
    # app/controllers/concerns/authorizable.rb
    module Authorizable
      extend ActiveSupport::Concern

      included do
        before_action :authorize_resource!
      end

      private

      def authorize_resource!
        # Assume you set @resource in your controller
        unless current_user.can_access?(@resource)
          redirect_to root_path, alert: "Permission denied."
        end
      end
    end

    Now any controller that includes this concern will automatically:
      -Run the before_action :authorize_resource!
      -Redirect resource to root path which do not have access.

    Use it like:
      class ProjectsController < ApplicationController
        include Authorizable

        before_action :set_project

        def show; end

        private

        def set_project
          @resource = Project.find(params[:id])
        end
      end

╰➤Delegate:
    In Rails, delegate is an ActiveSupport macro that allows us to forward method calls from one object to an associated object. It helps reduce boilerplate and improves readability. For example, if Order belongs_to User, instead of writing a wrapper method for user.name, we can use delegate :name, to: :user. It follows the Law of Demeter and keeps models clean.

    Delegate is a macro used to forward method calls from one object to another object.

    Without delegation:
      class Order < ApplicationRecord
        belongs_to :user

        def user_name
          user.name
        end
      end

    With delegation:
      class Order < ApplicationRecord
        belongs_to :user

        delegate :email, :name, to: :user, prefix: true
      end

    Now you can call:
      order.user_email
      order.user_name

    🔸Important Options in delegate
      ➤to:
        Specifies the target object.
        delegate :name, to: :user

      ➤prefix:
        Adds prefix to avoid name conflicts.
        delegate :name, to: :user, prefix: true

        Now we can access like: user_name

      ➤Custom prefix:
        delegate :name, to: :user, prefix: :account

        Now we can access like: account_name

      ➤allow_nil: true
        Prevents error if delegated object is nil.
        delegate :name, to: :user, allow_nil: true
        
        Without allow_nil: NoMethodError if user is nil
        With allow_nil: Returns nil

    🔸How It delegate Internally:
      Delegate dynamically defines a method using Module#define_method.
      Internally, Rails roughly generates something like:
        def name
          user.name
        end
      
╰➤In Rails models, we never define attributes (database columns) explicitly. So how does Rails automatically know about them?
  Answer: Rails uses ActiveRecord, which connects to the database and reads the table schema at runtime. When the model class loads, ActiveRecord queries the database for column information and dynamically defines getter and setter methods via define_method for each column using metaprogramming.

╰➤ActiveRecord Connects to Database
  ApplicationRecord inherits from ActiveRecord::Base
  When Rails boots:
    It establishes DB connection
    Loads schema information

  ActiveRecord runs a query like:
    SELECT column_name, data_type
    FROM information_schema.columns
    WHERE table_name = 'users';

  So Rails now knows:
    Column names
    Data types
    Defaults
    Null constraints

  Rails stores this metadata in:
    User.columns
    User.columns_hash
    User.attribute_names

  After loading column info, Rails dynamically defines methods like:
    def name
      read_attribute(:name)
    end

    def name=(value)
      write_attribute(:name, value)
    end

    It uses define_method internally.
    So Rails generates methods at runtime.

    Attribute values are stored in @attributes Which is an instance of ActiveModel::AttributeSet
    So when you do user.name, it actually calls read_attribute(:name) which fetches from internal attribute hash.

==========================================================================================
🔸Difference between before_save and after_save?

  Both before_save and after_save are ActiveRecord callbacks that run during the save lifecycle, but the key difference is when they execute relative to persistence.

  before_save runs before the record is written to the database, while after_save runs after the record has been successfully persisted.

  In terms of use cases:

    I use before_save when I want to modify or normalize data before it gets stored, like formatting fields or setting derived attributes.
    I use after_save when I want to trigger side effects after persistence, like logging, sending notifications, or updating related records.

  One important thing is:
    Even though after_save runs after the save call, it still runs inside the database transaction. So if something fails later in the transaction, changes can still be rolled back.

  Example:
      before_save :normalize_email
      after_save :log_activity

      def normalize_email
        self.email = email.downcase.strip
      end

      def log_activity
        Rails.logger.info("User saved with id #{id}")
      end

🔸Difference between before_save and before_create?

  The main difference is about scope of execution.

  before_save runs on both create and update, while before_create runs only when a new record is being created.

  So if I want logic to run every time the record is saved — whether it is a new record or an update — I use before_save.

  But if the logic should run only once at creation time, I use before_create.

  Practical scenario:
    before_create: generate a unique token or set default values only once
    before_save: normalize or validate fields every time

  Example:
    before_create :generate_token
    before_save :normalize_name

    def generate_token
      self.token = SecureRandom.hex(10)
    end

    def normalize_name
      self.name = name.capitalize
    end


🔸Difference between after_save and after_commit?
  after_save runs immediately after the save operation, but still inside the transaction.
  after_commit, on the other hand, runs only after the database transaction has been successfully committed.

  So the key difference is:
    after_save: may run even if the transaction later rolls back
    after_commit: runs only when data is permanently persisted

  Why this matters:

  If you are triggering external side effects, like:
    sending emails
    calling APIs
    pushing jobs to background workers
  You should always use after_commit, because you do not want those actions to happen if the transaction fails.

  Example:

    after_commit :send_welcome_email

    def send_welcome_email
      UserMailer.welcome_email(self).deliver_later
    end

  If we used after_save here and the transaction rolled back, the email could still be sent, which is inconsistent.


NOTE:
    In Rails, there is no before_commit callback.
    In Rails ActiveRecord, we do not really have a standard before_commit callback like we have before_save or before_create.

    In Rails, instead of before_commit, we generally rely on callbacks like before_save or after_save for logic that should run before the transaction is committed.

    Rails does not provide a standard before_commit, so we treat callbacks like before_save and after_save as pre-commit logic, and after_commit as post-commit logic. For anything external or irreversible, I always prefer after_commit.


🔸Callback Order in rails ActiveRecord:
    For a create operation, the order is roughly:
      before_validation
      after_validation
      before_save
      before_create
      -- DB INSERT happens here --
      after_create
      after_save
      after_commit

    For an update operation, it becomes:
      before_validation
      after_validation
      before_save
      before_update
      -- DB UPDATE happens --
      after_update
      after_save
      after_commit

    Key observations:
      before_save runs before both create and update
      before_create / before_update are more specific
      after_save runs after create/update but before commit
      after_commit runs only after transaction is complete

NOTE:
    The difference between after_create and after_save is mainly about scope and timing within the save lifecycle.

    after_create runs only once, when a record is first created (INSERT)
    after_save runs every time the record is saved, so on both create and update

    after_create runs first
    then after_save runs

    Both after_create and after_save run inside the transaction.
    So if the transaction fails later, both can still be rolled back.
    That is why for external side effects, we prefer: after_commit

🔸Available around callbacks in rails:
  “around_* callbacks wrap the operation and give full control over execution flow, but I use them carefully because they can make the code harder to understand compared to before/after callbacks.”

  Rails supports:
    around_save
    around_create
    around_update
    around_destroy

    For create, it looks like:
      around_save (before part)
        around_create (before part)
          -- INSERT happens --
        around_create (after part)
      around_save (after part)


🔸When do we actually use around callbacks?
  In real projects, around_* is rarely used, but useful in cases like:
    1.Performance measurement
        around_save :measure_time
    2. Wrapping logic (transactions, logging, instrumentation)
    3. Temporary state changes

  NOTE: If we forget to call yield, the actual operation never happens.

        “around_* callbacks wrap the entire operation. Their 'before' part runs before before_* callbacks, and their 'after' part runs after after_* callbacks.

        around_save (before part)
          before_save
          around_create (before part)
            before_create
            -- INSERT happens --
            after_create
          around_create (after part)
          after_save
        around_save (after part)
        after_commit