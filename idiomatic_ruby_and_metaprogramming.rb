➤What is Metaprogramming?
===========================
  Metaprogramming in the context of Ruby on Rails refers to writing code that can dynamically generate, modify, or interact with other code at runtime. It is a core part of Rails “magic” — the reason you can write less code and still get powerful behavior.

  Instead of manually defining everything, your program can:
    Create methods on the fly
    Modify classes while the app is running
    Infer behavior from naming conventions

➤Why Rails uses metaprogramming?
=============================
  Rails is built on Ruby, which is highly dynamic. Rails leverages this to:
    Reduce boilerplate code
    Provide “convention over configuration”
    Make APIs feel natural and readable

➤Common examples of Metaprogramming in Rails
=============================================
  1.Dynamic finder methods (Active Record)
    In Rails models, you can write: User.find_by_email("test@example.com")
    Even if find_by_email is not explicitly defined, Rails creates it dynamically based on the database column (email).

  2.Associations
    class Post < ApplicationRecord
      belongs_to :user
    end

    Rails automatically generates methods like:
      post.user
      post.user=
      post.build_user

    No need to define them manually.

  3.method_missing
    Rails sometimes uses Ruby’s method_missing to catch undefined methods and handle them dynamically.

  4.define_method
    Rails internally uses things like:
      define_method(:my_method) do
        # dynamic behavior
      end
    to create methods at runtime.


➤Pros and Cons of Metaprogramming?
=============================================
  Pros:
    Cleaner code (less repetition)
    Flexible APIs
    Rapid development

  Cons:
    Harder to debug
    Can feel “magical” or confusing
    Errors may only appear at runtime


➤What is monkey patching?
=============================================
  Monkey patching means modifying or extending existing classes or methods at runtime, even if you did not write them originally.

  You “patch” a class by:
    Adding new methods
    Changing existing behavior
  without editing the original source code.

  Example 1: Modified Rubys built-in String class.
    class String
      def shout
        upcase + "!!!"
      end
    end

    "hello".shout # => "HELLO!!!"

    Here, we just modified Rubys built-in String class.

  Example 2: Overriding an existing method.
    class String
      def upcase
        "OVERRIDDEN"
      end
    end

    "hello".upcase
    # => "OVERRIDDEN"

    Here, We have changed how upcase works everywhere.

  NOTE:
    Rails itself uses monkey patching in places, but developers also use it to:
      Fix bugs in gems temporarily
      Extend framework behavior
      Customize third-party libraries

      Example:
        class ActiveRecord::Base
          def my_custom_method
            "Hello from all models!"
          end
        end

        Now every model in Rails has this method.

➤Pros and Cons of monkey patching
==================================
  Pros:
    Quick fixes without changing external libraries
    Powerful customization
    Can extend behavior globally

  Cons:
    Can break existing functionality unexpectedly
    Hard to track where behavior changed
    Conflicts with other code/gems
    Makes debugging harder

  NOTE:
   🔸Metaprogramming → Writing code that generates/modifies code dynamically
   🔸Monkey patching → A specific use of metaprogramming where you modify existing classes.

   🔸Monkey patching is a type of metaprogramming, but not all metaprogramming is monkey patching.

➤Idiomatic Ruby patterns & handy methods
==========================================
🔸tap
  → Initialize & modify an object inline, chain operations.
    user = User.new.tap do |u|
      u.name = "Alice"
      u.save
    end
  tap is a method defined on all Ruby objects.
  It:
    -Yields the object to a block.
    -Always returns the original object, not the result of the block.
    -So tap lets you “tap into” an object mid-chain to perform some side effects (like modifying it) and then keep using it.
      arr = [].tap do |a|
        a << 1
        a << 2
      end
      puts arr.inspect  # => [1, 2]

🔸each_with_object
  → Like inject but clearer when you want to build up a new object.
    result = [1, 2, 3].each_with_object([]) { |n, arr| arr << n * 2 }
    # => [2, 4, 6]

🔸inject / reduce
  → Accumulate values.
    sum = [1, 2, 3, 4].inject(0) { |sum, n| sum + n }
    # => 10

🔸map + compact
  → Replace filter_map method for old Ruby. In new ruby we use filter_map method (Ruby 2.7 onwards). It will automatically remove all nil values from array.
    [1, 2, 3].map { |n| n * 2 if n.even? }.compact
    # => [4]

🔸select & reject
  → Filter elements.

    [1, 2, 3].select(&:even?)  # => [2]
    [1, 2, 3].reject(&:even?)  # => [1, 3]

🔸Safe navigation operator &.
  → Avoid nil errors.
    user&.profile&.bio

🔸||=
  → Memoization.
    def expensive_calc
      @result ||= compute_heavy_thing
    end

🔸dig
  → Safely get nested hash/array values.

    params = { user: { address: { city: "Berlin" } } }
    params.dig(:user, :address, :city)  # => "Berlin"

🔸fetch with default
  → Hashes with fallback values.

    hash = { a: 1 }
    hash.fetch(:b, 42)  # => 42

🔸zip
  → Combine arrays element-wise.
    [1, 2].zip([3, 4])  # => [[1, 3], [2, 4]]

🔸%i and %w
  → Quick symbol or string arrays.
    %i[one two three]  # => [:one, :two, :three]
    %w[foo bar baz]    # => ["foo", "bar", "baz"]

🔸Splat (*)
  →Collect or expand arrays.
  def sum(*numbers)
    numbers.sum
  end

  sum(1, 2, 3)  # => 6
  arr = [1, 2, 3]
  sum(*arr)     # => 6

🔸Double splat ** for keyword args
  → Flexible method signatures.In Ruby, ** captures all keyword arguments passed to a method into a single Hash. It should be passed in last.

    def greet(message, **options)  # Here do not need to accept each keyword args individually.
      puts "#{message} #{options[:name]}"
    end

    greet("Hello", name: "Bob", age: 30)
    # => Hello Bob

🔸case with pattern matching (Ruby 2.7+)
  → Destructuring.
    case { a: 1, b: 2 }
    in { a: 1, b: b }
      puts b  # => 2
    end

🔸Struct or OpenStruct
  → Struct is a fast,lightweight, immutable-ish way to create simple classes with fixed attributes.

    Person = Struct.new(:name, :age)
    alice = Person.new("Alice", 30)

    puts alice.name  # => "Alice"
    puts alice.age   # => 30
    alice.name = "Bob"  # You can change known fields

  → OpenStruct is more flexible, but slower and more memory-hungry.
    You can add or remove fields at runtime. More flexible but slower than Struct. Great for dynamic data (like JSON or API payloads).
    
    require 'ostruct'
    person = OpenStruct.new(name: "Alice", age: 30)
    puts person.name  # => "Alice"
    # Add new fields dynamically
    person.city = "Wonderland"
    puts person.city  # => "Wonderland"

🔸Struct with default values
  Person = Struct.new(:name, :age) do
    def greeting
      "Hi, I'm #{name} and I'm #{age}."
    end
  end

  alice = Person.new("Alice", 30)
  puts alice.greeting # Hi, I'm Alice and I'm 30.

🔸yield_self
  → Like tap but returns the block result instead of the receiver.
    5.yield_self { |n| n * 2 }  # => 10

🔸yield
  →In Ruby, yield calls a block that was passed to a method without explicitly naming it.
   yield invokes the block.
   If there is no block given, yield will raise an error unless you check with block_given?.
   yield is super common for: DSLs (Rails routes blocks, config blocks)

    def say_hello
      puts "Before yield"
      yield if block_given?
      puts "After yield"
    end

    say_hello { puts "Hello from the block!" }
      Output:
        Before yield
        Hello from the block!
        After yield

    -The method say_hello runs until it sees yield.
    -yield jumps out to the block { puts "Hello from the block!" }.
    -The block runs.
    -After the block finishes, Ruby jumps back into the method after yield.

🔸yield with arguments
  →You can pass arguments to the block:
    def greet
      yield("Alice")
    end

    greet { |name| puts "Hello, #{name}!" }
    # => Hello, Alice!

🔸Equivalent with explicit block parameter
  →You can achieve the same thing like above by capturing the block explicitly with &block:
    def greet(&block)
      block.call("Alice")
    end

    greet { |name| puts "Hello, #{name}!" }

  →When to use yield vs &block
   - yield is idiomatic and simpler when you just want to run the block once.
   - &block is better when:
        You need to pass the block to another method.
        You want to store the block.
        You want to call the block multiple times.

    Examples: 
      ➤forwarding a block:
          def outer(&block)
            inner(&block)
          end

          def inner
            yield
          end

          outer { puts "Hi" }
          # => Hi

      ➤Custom iterators:
          def my_each(array)
            i = 0
            while i < array.size
              yield(array[i])
              i += 1
            end
          end

          my_each([1, 2, 3]) { |n| puts n }

      ➤Resource wrappers (like File.open):
          def with_resource
            puts "Open"
            yield
            puts "Close"
          end

          with_resource { puts "Doing stuff" }

🔸method_missing
  →Powerful metaprogramming: catch calls to undefined methods.
  class DynamicHello
    def method_missing(name, *args)
      puts "Hello, #{name}!"
    end
  end

  greet = DynamicHello.new
  greet.Alice   # => Hello, Alice!
  greet.Bob     # => Hello, Bob!
  Be careful: always pair with respond_to_missing?.

🔸define_method
  →Create methods dynamically.
  class Greeter
    [:english, :spanish].each do |lang|
      define_method("greet_in_#{lang}") do |name|
        case lang
        when :english then "Hello, #{name}!"
        when :spanish then "Hola, #{name}!"
        end
      end
    end
  end

  g = Greeter.new
  puts g.greet_in_english("Alice") # => Hello, Alice!
  puts g.greet_in_spanish("Alice") # => Hola, Alice!

🔸Symbol-to-Proc (&:)
  →Shorter syntax for calling methods on each element.
  ["foo", "bar"].map(&:upcase)  # => ["FOO", "BAR"]

🔸Aliasing methods
  →You can extend or wrap existing methods.
  class Person
    def greet
      "Hi"
    end

    alias_method :original_greet, :greet

    def greet
      "#{original_greet}, nice to meet you!"
    end
  end

🔸Monkey patching
  →Not always recommended — but good to know.
  class String
    def shout
      upcase + "!"
    end
  end

  "hello".shout  # => "HELLO!"

🔸Refinements
  →Safer than monkey patching — local to the scope where you use them.
  module StringExtensions
    refine String do
      def shout
        upcase + "!"
      end
    end
  end

  using StringExtensions
  "hello".shout  # => "HELLO!"

  Outside the using scope, shout will not exist.

🔸Custom Enumerable methods
  →Ruby’s Enumerable is magic — extend it with your own iterators.
  class Countdown
    include Enumerable

    def each
      3.downto(1) { |n| yield n }
    end
  end

  Countdown.new.map { |n| n * 2 }  # => [6, 4, 2]

🔸Case expressions with when
  →case is way more flexible than other languages.
    case value
    when String then "It is a String"
    when Integer then "It is an Integer"
    else "Unknown"
    end

🔸Singleton methods
  →Define a method on one object only.
  user = "Alice"
  def user.greet
    "Hi, #{self}!"
  end

  user.greet  # => "Hi, Alice!"

🔸Frozen objects
  →Immutable by design.
  str = "hello".freeze
  str << " world"  # => RuntimeError: can't modify frozen String


Ruby Metaprogramming Cheatsheet
------------------------------------------------------------------------
╰┈➤method_missing + respond_to_missing?

    class DynamicGreeter
      def method_missing(method, *args)
        if method.to_s.start_with?("hello_")
          "Hello, #{method.to_s.split('_').last.capitalize}!"
        else
          super
        end
      end

      def respond_to_missing?(method, include_private = false)
        method.to_s.start_with?("hello_") || super
      end
    end

    g = DynamicGreeter.new
    puts g.hello_world   # => "Hello, World!"

╰┈➤define_method

    class MathOps
      [:add, :subtract].each do |op|
        define_method(op) do |a, b|
          op == :add ? a + b : a - b
        end
      end
    end

    m = MathOps.new
    puts m.add(2, 3)     # => 5
    puts m.subtract(5, 2) # => 3

╰┈➤class_eval / instance_eval
    => Classes itself are an object.

    class Person; end
    Person.instance_eval do
      def hello
        "Hello"
      end
    end

    puts Person.hello #=> Hello
    puts Person.new.hello #=> Error

    Class is an object, so on that object( i.e on person), a singleton method gets defined here.

    Person.class_eval do
      def greet
        "Hi!"
      end
    end

    Here, Inside class, simply put this method, so it become instance method of the class.
    puts Person.new.greet  # => "Hi!"
    puts Person.greet # => Error.

╰┈➤Write your own map

    def my_map(array)
      result = []
      array.each { |e| result << yield(e) if block_given? }
      result
    end

    puts my_map([1, 2, 3]) { |n| n * 2 }  # => [2, 4, 6]

╰┈➤Create a simple DSL

    class Config
      attr_reader :settings

      def initialize(&block)
        @settings = {}
        instance_eval(&block)
      end

      def set(key, value)
        @settings[key] = value
      end
    end

    cfg = Config.new do
      set :timeout, 30
      set :retries, 5
    end

    puts cfg.settings  # => {:timeout=>30, :retries=>5}

╰┈➤Write a custom Enumerable

    class Counter
      include Enumerable

      def each
        1.upto(5) { |i| yield i }
      end
    end

    puts Counter.new.map { |n| n * n }  # => [1, 4, 9, 16, 25]

📌Interview pro tip: Ruby mindset
  - Use blocks a lot: map, select, reject — these show you know the Enumerable API well.
  - Use symbols instead of strings for keys if possible.
  - Chain methods when it makes sense: Ruby is built for expressive code.
  - Prefer &:method shorthand: map(&:upcase).
  - Be comfortable with method_missing, define_method, or basic metaprogramming if asked.
  - Know send and public_send.

📌Rails-specific idioms:
  - present? / blank?
  - try / try! (user.try(:name))
  - scope for ActiveRecord queries.
  - pluck for fast column retrieval.
  - find_each for batching.
  - find_or_create_by / first_or_initialize.
