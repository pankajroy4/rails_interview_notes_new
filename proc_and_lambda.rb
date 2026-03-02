Proc and Lambda in ruby:
==========================
➤In ruby, Both proc and lambda are instance i.e object of inbuilt Proc class.
  puts Proc.new.class  # => Proc
  puts lambda {}.class # => Proc

  🔸the symbol -> is modern short syntax for lambda
    puts -> {}.class # => Proc

  🔸Ruby creates an object of Proc class.
  🔸The Proc class defines a method called .call — that is how you run the block of code.
  🔸call is the standard method for executing a Proc or lambda in Ruby.

➤How to create proc:
  p = Proc.new { "Hello User!" }
  p.call #=> Hello User!
  
  🔸 .() is short syntax for .call()
      p.() #=> Hello User!

  🔸Parameterised proc:
      p = Proc.new { |user| "Hello #{user}" }
      p.call("John") #=> Hello John
      p.call "John" #=> Hello John
      p.("John") #=> Hello John

➤How to create lambda:
  l = lambda { ... }   #OR
  l = -> { ... }
  Example:
    my_lambda = -> { puts "Hello User!" } #OR 
    my_lambda = lambda { puts "Hello User!" } 

    my_lambda.call # Hello User!
    my_lambda.()     # Hello User!

  🔸Parameterised Lambda:
      my_lambda = ->(name) { puts "Hi #{name}!" }  #OR
      my_lambda = lambda { |name| puts "Hi #{name}!" }

      my_lambda.call("Alice") # Hi Alice!
      my_lambda.call "Alice" # Hi Alice!
      my_lambda.("Alice")     # Hi Alice!

    NOTE:
      ->(args) { ... } is syntax for lambdas that includes the parameter list directly.
      lambda is a method that needs a block — the block defines the parameters with | |.

Differecne betwwen lambda and Proc:
=====================================
➤lambda is just a Proc with special rules for "return" and "arguments".

➤How proc and lambda handle return:
  Proc: return exits from the enclosing method.
  lambda: return exits only from the lambda itself.

  Example:
    def proc_test
      p = Proc.new { return "Proc says bye!" }
      p.call
      return "You will never see this!"
    end

    def lambda_test
      l = -> { return "Lambda says bye!" }
      l.call
      return "You WILL see this!"
    end

    puts proc_test    # => "Proc says bye!"
    puts lambda_test  # => "You WILL see this!"

  🔸Proc's return acts like return from the method containing it.
  🔸lambda's return just returns from the lambda.

➤How proc and lambda handle arguments:
  Proc: arguments are flexible — it will not raise an error if you pass the wrong number of arguments.
  lambda: arguments are strict — wrong arity raises an ArgumentError.

  Example:
    p = Proc.new { |a, b| puts "a: #{a}, b: #{b}" }
    l = ->(a, b) { puts "a: #{a}, b: #{b}" }  # OR
    l = lambda { |a,b| puts "a: #{a}, b: #{b}" }

    p.call(1)  # => a: 1, b:
    l.call(1)  # => ArgumentError: wrong number of arguments. Expected 2 arguments but passed only one.

  USE CASE:
    🔸Use lambda when you want a safe, method-like block (especially when you return inside).
    🔸Use Proc when you want more flexibility, but be careful with return!

Arguments with lambda and proc:
================================
➤Proc and lambda can accepts any number of arguments. 
  But proc is flexiable. It will not throw error even if you do not paas the expected argument defined in proc whereas
  Lambda will enforce the exact number of arguments you declare (unlike Proc) otherwise it will throw error.

    my_lambda = ->(a, b, c) { puts "a: #{a}, b: #{b}, c: #{c}" }

    my_lambda.call(1, 2, 3)   # a: 1, b: 2, c: 3
    my_lambda.call(1, 2)      # ArgumentError: wrong number of arguments

Using splat with lambda:
==========================
➤You can handle variable no. of arguments with a splat (*args) in lambda.
  splat collect all given args into an array

    l = ->(*args) { puts "You gave me: #{args.inspect}" }
    l.call(1)         # You gave me: [1]
    l.call(1, 2, 3)   # You gave me: [1, 2, 3]


============================************************=====================================
                -------------- Proc and Lambda in Rails model --------------
============================************************=====================================

In Ruby, method calls with one or multiple arguments can be written with or without parentheses — both forms mean the same thing:
  puts "Hi" ,"Hello"   # => Hi, Hello
  puts("Hi", "Hello")  # => Hi, Hello
  
  Rails style guide and idiomatic Rails code prefer the no parentheses version for scope — because it reads like DSL code.

➤Scope in model:
----------------
  🔸scope is just a class method on ActiveRecord::Base.
    scope is a Rails method that adds a custom query to your model.
    scope takes two arguments:
      → the method name to define and 
      → the block of code that runs when you call the scope

    Example:
      scope :recent, -> { order(created_at: :desc) }
      scope :by_name, ->(name) { ... }
        
      Here:
        :by_name          → the method name to define, so we can call something like User.by_name
        ->(name) { ... }  → the block of code that runs when you call the scope

    Example:
      scope :by_name, ->(name) { where('lower(name) ilike ? or mobile_no ilike ?', "%#{name}%", "%#{name}%") }
     
     🔸How this works under the hood:
        scope is a Rails method that adds a custom query to your model.
        The ->(name) { ... } is a lambda (which is just an anonymous function).
        When you call User.by_name("bob"), Rails calls the lambda, passing "bob" to it, and runs whatever the lambda returns — which must be an ActiveRecord relation.

        When you write:  scope :by_name, ->(name) { ... }
          Rails basically does this:
            def self.by_name(name)
              where(...)
            end
    
        So the lambda is used to dynamically define a class method on User.

   🔸A scope must be callable, so:
      If the scope takes no arguments, you can just pass a relation:
        scope :active, where(active: true)
      If it needs arguments, you must wrap the logic in a lambda or proc:
        scope :by_name, ->(name) { ... }

      This makes the scope lazy — it is just a method that runs when you call it.

NOTE:
╰┈➤
 🔸When you write:
    my_lambda = ->(name) { ... } 
    you store the lambda in a variable. Later, you can run it as =>  my_lambda.call("Bob")  # => "Hi Bob!"

 🔸But when you write: 
    scope :by_name, ->(name) { ... }  
    
    Here you do not store it in a variable yourself — Rails does it for you.
    You pass the lambda as an argument to the scope method.

    So effectively you are calling:
      scope(:by_name, ->(name) { ... })
    
    except you did not store it in my_lambda first — you just created the lambda inline and handed it to scope.

 🔸scope is just a class method on ActiveRecord::Base that does something like this behind the scenes:
    def self.scope(name, body)
      define_singleton_method(name) do |*args|
        body.call(*args)
      end
    end

 🔸So scope:
    -Takes your lambda (body)
    -Defines a class method with the given name (:by_name)
    -When you call User.by_name("Bob"), Rails calls the lambda with "Bob"
    -So you do not manually store the lambda — scope stores it by wiring it up as a method.

╰┈➤Below both style of writing are exactly the same.
    scope :by_name, ->(name) { where('lower(name) ilike ? or mobile_no ilike ?', "%#{name}%", "%#{name}%") }  # Style 1 — common idiomatic Rails style
    scope(:by_name, ->(name) { where('lower(name) ilike ? or mobile_no ilike ?', "%#{name}%", "%#{name}%")} ) # Style 2 — same thing with explicit parentheses

    It is just like:
      puts "Hi" ,"Hello"   # => Hi, Hello
      puts("Hi", "Heloo")  # => Hi, Hello

➤Validations in model:
------------------------
🔸A typical validation might look like this:
    class User < ApplicationRecord
      validates :name, presence: true
    end

    Here:
      validates :name, presence: true
    is the same as:
      validates(:name, presence: true)

    Both are identical — because validates is just a class method that takes:
      The attribute name(s)
      Options (like presence: true)

🔸validator:
    class User < ApplicationRecord
      validates :email, presence: true, uniqueness: true

      validates :age, numericality: { greater_than_or_equal_to: 18 }
    end
    
    AND 
    
    class User < ApplicationRecord
      validates(:email, presence: true, uniqueness: true)

      validates(:age, numericality: { greater_than_or_equal_to: 18 })
    end

    Again — no difference! Ruby syntax allows parentheses to be optional for method calls. Both are exactly same.

🔸DSL idea
    validates works just like scope:
    It is a class method on ActiveModel::Validations.

🔸Takeaway:
    scope, validates, has_many, belongs_to, before_save —
      All these Rails macros follow the same style:
        They are class methods.
        They build DSL-style behavior.
        Parentheses are optional.

➤Using lambda for validate:
--------------------------
 🔸Examples:
    class User < ApplicationRecord
      validate ->(user) {
        if user.age.present? && user.age < 18
          user.errors.add(:age, "must be at least 18")
        end
      }

      validates :gst_number, presence: true, if: -> { country == 'IN' }   #Condoitional validation
    end

    class Order < ApplicationRecord
      validate ->(record) {
        if record.total_amount && record.total_amount < 0
          record.errors.add(:total_amount, "cannot be negative")
        end
      }
    end

 🔸Using a named lambda for reuse:
    class Product < ApplicationRecord
      validate PRICE_VALIDATION = ->(product) {
        if product.price.present? && product.price < 0
          product.errors.add(:price, "must be positive")
        end
      }
    end

 🔸With multiple validate calls:
    class Account < ApplicationRecord
      validate ->(acc) { acc.errors.add(:name, "can't be blank") if acc.name.blank? }
      validate ->(acc) { acc.errors.add(:email, "must contain @") unless acc.email.include?("@") }
    end

➤Using lambda for a callback:
--------------------------------
 🔸Examples:
    class Post < ApplicationRecord
      before_save ->(post) { post.title = post.title.strip if post.title.present? }
    end

 🔸Using a named lambda:
    class Article < ApplicationRecord
      SET_DEFAULT_STATUS = ->(article) {
        article.status ||= 'draft'
      }

      before_validation SET_DEFAULT_STATUS
    end

 🔸Conditional lambda
    class Invoice < ApplicationRecord
      before_save ->(invoice) { invoice.status = "paid" }, if: ->(invoice) { invoice.paid_at.present? }
    end

➤Avoid dynamic scoping:
--------------------------
Avoid dynamic scopes like:
  def self.search(term)
    where("name LIKE ?", "%#{term}%")
  end

  - it is considered "dynamic":
  - It creates a method at runtime that is not registered as a scope.
  - It is harder to chain with other scopes or reuse in query composition.
  - Does not benefit from ActiveRecord optimizations for scopes.
  - No guarantees it is lazy—sometimes developers accidentally run queries in such custom methods.
  - Harder to compose: You can not combine this easily with other scopes or use it in .merge queries.

Better to use:
  scope :with_name_like, ->(term) { where("name ILIKE ?", "%#{term}%") }

  This defines a named scope, which is a recommended and Rails-native way of declaring chainable queries.
  Usage:User.with_name_like("john")

  - Can be chained with other scopes. User.active.with_name_like("john")
  - Lazy evaluation: Scopes are only evaluated when the final query is triggered (e.g., .to_a, .each, .first).
  - Declarative and discoverable: Scopes are listed when introspecting a model.
  - More semantic: with_name_like reads better and clearly describes its intent.
  - Performance: Scopes are optimized by Rails for chaining and merging.

---------------------------------------------------------------------------------------------------------------
Question: What is closure in Rails?
Answer: In Ruby, a closure is a block, proc, or lambda that captures and retains access to variables from the lexical scope in which it was defined, even after that scope has exited. 
Rails uses closures heavily in scopes, callbacks, routes, and controller filters.

Example 1: Closure in methods.
  def outer_method
    message = "Hello"

    return Proc.new { puts message }
  end

  my_proc = outer_method # Method call finished
  my_proc.call #Output: "Hello"

  Here:
    message is a local variable inside outer_method
    Normally, it should disappear after the method finishes
    But the Proc remembers it
    That is a closure
    The Proc closes over (captures) the variable message.

Example 2: Closure via block.
  my_proc = Proc.new do 
              3.times do |i|
                puts i
              end
            end

  my_proc.call
  
Note: Closures capture Local variables by reference (not by value).
    Example:
      x = 10
      my_proc = Proc.new { puts x }
      x = 20
      my_proc.call

    Output: 20
    Because it captured reference, not value.