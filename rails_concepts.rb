=================================== Ruby Core Concepts ===================================
Question 1: Difference between nil and false?

Answer -> In Ruby, both nil and false are falsey in conditionals, but they represent different meanings.
false means an explicit negative boolean value.
nil means absence of value or “nothing”.

Conceptually, false answers “No”, while nil answers “No value exists”.

In Ruby, only false and nil are falsey. However, they are semantically different. false represents a boolean negative result, such as a flag being turned off. nil represents the absence of a value or an uninitialized state. For example, published: false means explicitly unpublished, while published: nil usually means not yet decided. This distinction is important when modeling data and avoiding logical bugs.

------------------------------------------------------------------------------------------------------
Question 2: Symbols vs Strings

Answer -> Strings are mutable objects used to store and manipulate text.
Symbols are immutable identifiers and are reused internally by Ruby.

Strings are flexible but create new objects each time.
Symbols are memory efficient and faster for identifiers.

Strings are mutable and each "name" creates a new object in memory. They are used for dynamic content like user input and JSON data. Symbols, written as :name, are immutable and Ruby stores only one copy of each symbol in a global symbol table. That makes them efficient for hash keys, method names, and internal identifiers. For example, { name: "John" } is preferred over { "name" => "John" } for performance and readability. Symbols cannot be modified and historically had memory concerns if dynamically generated in large numbers.

------------------------------------------------------------------------------------------------------
Question 3: How does Ruby Garbage Collection work?

Answer -> Ruby uses a generational mark-and-sweep garbage collector.
It automatically frees memory of unreachable objects.

It divides objects into young and old generations to optimize performance.

Ruby’s GC works in three main phases: mark, sweep, and optional compaction. In the mark phase, Ruby starts from root references (global variables, stack, etc.) and marks reachable objects. In the sweep phase, unmarked objects are removed and memory is reclaimed. Ruby uses generational GC, meaning most objects die young, so minor GCs run frequently on young objects, and major GCs run less often. Modern Ruby also supports incremental marking and compaction to reduce memory fragmentation and pause times.
                           ------------------------------------------
Long Answer -> Ruby mainly uses a Mark-and-Sweep garbage collection mechanism.

In the mark phase, Ruby starts from root references like global variables, local variables, stack references, classes, and threads. It traverses all reachable objects and marks them as alive.

Then in the sweep phase, objects that are not marked are considered unreachable, and Ruby frees their memory.

Modern Ruby also uses Generational Garbage Collection. The idea is that most objects die young. So Ruby divides objects into young generation and old generation.

Young objects are checked frequently using Minor GC, which is faster. Objects that survive multiple GC cycles are promoted to old generation, and Major GC scans both young and old objects.

Ruby also supports Incremental GC to reduce stop-the-world pause time by splitting GC work into smaller chunks. Newer Ruby versions also support Compaction GC, which helps reduce memory fragmentation and improves copy-on-write optimization in servers like Puma or Unicorn.

In Rails, excessive object allocation can increase GC pressure and slow down the application. So we try to optimize memory usage using techniques like pluck instead of loading full ActiveRecord objects, find_each for batch processing, and avoiding unnecessary object creation.

We can also monitor garbage collector statistics using GC.stat.

One important point is that even after GC frees Ruby heap memory, the operating system memory may not reduce immediately because Ruby may keep heap pages for future allocations.

------------------------------------------------------------------------------------------------------
Question 4: What is Duck Typing?

Answer -> Duck typing means Ruby focuses on behavior, not type.
If an object responds to the required methods, it can be used.

Ruby does not check class type explicitly; it checks method availability at runtime.

Duck typing follows the idea: “If it walks like a duck and quacks like a duck, treat it as a duck.” Instead of checking object types, Ruby simply calls the method. If the object responds to that method, it works; otherwise, it raises NoMethodError. This makes Ruby flexible and supports polymorphism naturally without strict inheritance hierarchies.

------------------------------------------------------------------------------------------------------
Question 5: Does Ruby support Multiple Inheritance?

Answer -> Ruby does not support multiple class inheritance.
It supports single inheritance and multiple modules via mixins.

Modules provide behavior sharing without inheritance conflicts.

Ruby avoids multiple inheritance to prevent the diamond problem. A class can inherit from only one superclass, but it can include multiple modules. Modules allow sharing behavior without creating an “is-a” relationship. For example:

class Duck < Animal
  include Flyable
  include Swimmable
end

This gives multiple-behavior capability while keeping method lookup predictable and simple.

------------------------------------------------------------------------------------------------------
Question 6: What is a Singleton Class?

Answer -> A singleton class is a hidden class attached to every object.
It stores methods defined only for that specific object.

Class methods are actually singleton methods of the class object.

In Ruby, every object has its own singleton class (also called eigenclass). When you define a method like def obj.method_name, Ruby stores it inside the object’s singleton class. During method lookup, Ruby first checks the singleton class before the normal class. This mechanism is how class methods work, because classes are objects too.

------------------------------------------------------------------------------------------------------
Question 7: Explain Ruby Method Lookup Path

Answer -> Ruby follows a strict order to find methods when called.

It checks:
  Singleton class
  Prepended modules
  Class
  Included modules
  Superclass chain

Ruby's method lookup is linear and predictable. When a method is called, Ruby first checks the object's singleton class. Then it checks modules prepended to that class, followed by the class itself, then included modules (in reverse order), and then moves up the inheritance chain. If no method is found, Ruby calls method_missing. Understanding this is crucial when debugging overrides and mixins.

------------------------------------------------------------------------------------------------------
Question 8: What are Modules used for?

Answer -> Modules are used for:
            Namespacing
            Mixins (code sharing)
            Utility functions
            Modules cannot be instantiated.

Modules help organize code and avoid naming collisions using namespaces like Admin::User. They allow behavior sharing through include, extend, or prepend, solving Ruby’s single inheritance limitation. They are also used for grouping related utility methods without creating objects.

------------------------------------------------------------------------------------------------------
Question 9: Mutable vs Immutable Objects

Answer -> Mutable objects can be changed after creation.
Immutable objects cannot be modified once created.

Arrays, Hashes, and Strings are mutable.
Integers, Symbols, true, false, and nil are immutable.

Mutable objects allow in-place modification using methods like << or push. Immutable objects return new objects instead of modifying the original. Immutability improves thread safety and predictability. Ruby allows making objects immutable using freeze, but freeze is shallow and does not freeze nested objects.

------------------------------------------------------------------------------------------------------
Question 10: How does freeze work?

Answer -> freeze makes an object immutable.
Any modification after freezing raises FrozenError.

Freeze only affects the object itself, not nested objects.

When freeze is called, Ruby sets an internal frozen flag. Any destructive method like << or gsub! will raise an error. However, freeze is shallow, meaning nested objects inside arrays or hashes remain mutable unless explicitly frozen.

=================================== Ruby Advanced Concepts ===================================
Question 11: What is yield in Ruby?

Answer -> yield is used to execute a block passed to a method.
It temporarily transfers control to the block and then returns back.

It allows methods to accept custom behavior.

In Ruby, blocks are implicit pieces of code passed to methods. When a method calls yield, it executes the given block. If no block is provided, it raises an error unless we check using block_given?. Yield can also pass arguments to the block and receive return values. It is widely used in iterators like each and in DSL-style APIs.

------------------------------------------------------------------------------------------------------
Question 12: What are Enumerators?

Answer -> An Enumerator allows iteration without immediately executing it.
It supports lazy evaluation and external iteration.

Enumerators separate iteration logic from execution.

In Ruby, calling methods like each without a block returns an Enumerator. This allows us to call next, chain transformations, or create lazy sequences using lazy. Enumerators are useful for large datasets and infinite sequences because they delay execution until needed, improving memory efficiency.

------------------------------------------------------------------------------------------------------
Question 13: Block vs Proc vs Lambda

Answer -> Blocks are implicit and not objects.
Procs and Lambdas are objects.
Lambdas behave like methods; Procs do not.

The main differences are argument handling and return behavior.

Blocks are passed implicitly to methods and executed using yield. A Proc is an object created using Proc.new and can be stored or passed around. A Lambda is a special type of Proc created using -> or lambda. Lambdas enforce strict argument checking and their return exits only the lambda itself. In contrast, a Proc’s return exits the enclosing method, which can cause unexpected behavior. In production code, lambdas are usually safer and more predictable.

------------------------------------------------------------------------------------------------------
Question 14: Difference between each, map, and reduce

Answer -> each is used for iteration with side effects.
map is used for transformation.
reduce is used for aggregation.

Choose based on intent, not just output.

each loops over elements and returns the original collection. It is used when performing actions like logging or saving records. map transforms each element and returns a new array without modifying the original. reduce (or inject) combines all elements into a single value using an accumulator, such as summing numbers or building a hash.

------------------------------------------------------------------------------------------------------
Question 15: How does Ruby handle exceptions?

Answer -> Ruby uses begin, rescue, else, and ensure for exception handling.
Exceptions unwind the stack until a matching rescue block is found.

By default, rescue catches StandardError.

When an error occurs, Ruby raises an exception and stops normal execution. Control transfers to the nearest rescue block. ensure always runs, even if an error occurs, making it ideal for cleanup logic. Developers can define custom exceptions by inheriting from StandardError. Proper exception handling ensures graceful error recovery without crashing the application.

------------------------------------------------------------------------------------------------------
Question 16: What is Monkey Patching?

Answer -> Monkey patching means reopening an existing class to modify behavior.
It changes global behavior at runtime.
It is powerful but risky.

Ruby allows reopening classes and redefining methods. For example, modifying String or Array. While Rails internally uses this pattern, uncontrolled monkey patching can cause unpredictable bugs since changes apply globally. Safer alternatives include composition or refinements.

------------------------------------------------------------------------------------------------------
Question 17: What are Refinements?

Answer -> Refinements allow modifying classes in a limited scope.
They prevent global side effects.

Refinements are activated using the using keyword.

Unlike monkey patching, refinements only apply within the file or module where they are enabled. This makes behavior modification controlled and predictable. Refinements are useful when extending core classes safely without affecting the entire application.

------------------------------------------------------------------------------------------------------
Question 18: How does Ruby handle Threads?

Answer -> Ruby supports native threads.
However, MRI Ruby has a Global Interpreter Lock (GIL).

Threads improve I/O concurrency but not CPU parallelism.

In MRI(Matz’s Ruby Interpreter) Ruby, the GIL ensures that only one thread executes Ruby code at a time. This prevents true parallel execution for CPU-bound tasks but allows efficient I/O-bound concurrency such as API calls or database operations. For true parallelism, we use multiple processes (Puma workers, Sidekiq processes) or alternative Ruby implementations like JRuby.

What is MRI?
“MRI stands for Matz’s Ruby Interpreter. It is the original and most widely used implementation of Ruby, created by Yukihiro Matsumoto, who is also called Matz.

When we normally say 'Ruby', most of the time we are actually referring to MRI Ruby.

MRI is written in C and it executes Ruby code using the YARV virtual machine, which stands for Yet Another Ruby VM.

Rails applications commonly run on MRI Ruby in production.

One important interview point is that MRI uses a Global VM Lock, also called GVL or previously GIL. Because of this, multiple Ruby threads cannot execute Ruby code in parallel on multiple CPU cores at the exact same time. This affects CPU-bound multithreading performance.

However, MRI still supports concurrency for I/O-bound operations like database calls, API requests, or file operations because threads can release the GVL while waiting for I/O.

MRI also contains Ruby’s garbage collector, memory management system, object model, and thread management internally.

------------------------------------------------------------------------------------------------------
Question 19: What is self in different contexts?

Answer -> self refers to the current execution context.
Its meaning changes depending on where it is used.

At top-level → self is main.
Inside class → self is the class object.
Inside instance method → self is the instance.

Understanding self is critical in Ruby. Inside a class definition, self refers to the class itself, which is why class methods are defined as def self.method. Inside instance methods, self refers to the object instance. Inside blocks and lambdas, self usually remains the same as the surrounding context. However, inside instance_eval or class_eval, self changes to the receiver, enabling DSL patterns used heavily in Rails.

------------------------------------------------------------------------------------------------------
Question 20: Class vs Module

Answer -> A class can be instantiated.
A module cannot be instantiated.

Classes represent objects.
Modules represent shared behavior or namespaces.

Classes are blueprints for creating objects and support inheritance and state. Modules are used for namespacing and behavior sharing via include, extend, or prepend. Ruby supports single inheritance for classes but allows multiple modules to be mixed in.

=================================== Rails Core Concepts ===================================
Question 21: What is Rails Philosophy?

Answer -> Rails follows Convention over Configuration and DRY.
It provides sensible defaults to reduce boilerplate code.

Rails focuses on developer productivity and clean architecture.

Convention over Configuration means Rails assumes default patterns (like table naming) so developers write less configuration code. DRY ensures that logic is defined once and reused. Rails follows MVC architecture and RESTful principles, emphasizing simplicity and maintainability.

------------------------------------------------------------------------------------------------------
Question 22: MVC Flow in Rails Request Lifecycle

Answer -> A request passes through middleware → routing → controller → model → view → response.

Rails strictly follows MVC architecture.
When a client sends an HTTP request, it first goes through Rack middleware. Routing determines the controller and action. The controller processes parameters and interacts with models. The model handles business logic and database queries. Finally, the view renders HTML or JSON, and the response is sent back through middleware to the client.

------------------------------------------------------------------------------------------------------
Question 23: What happens when you hit a Rails URL?

Answer -> Web server → Rack → Middleware → Routing → Controller → Model → View → Response.

Rails is built on top of Rack.

When a request hits a Rails app, the web server converts it into a Rack env hash. The request travels through middleware for sessions, logging, and security. Routing maps the request to a controller action. The controller executes business logic and renders a response. The response travels back through middleware before reaching the client.

------------------------------------------------------------------------------------------------------
Question 24: What is Rack?

Answer -> Rack is a minimal interface between Ruby web servers and frameworks.
A Rack app responds to call(env) and returns [status, headers, body].
Rails is built on Rack.

Rack standardizes communication between web servers like Puma and frameworks like Rails. Middleware sits between them and processes requests and responses. This design makes Rails modular and extensible.

------------------------------------------------------------------------------------------------------
Question 25: What is Middleware Stack?

Answer -> Middleware is a chain of components between the web server and Rails app.
Each middleware can modify request and response.

Middleware receives the env hash, can process or modify it, and either return a response or pass control to the next middleware using @app.call(env). On the way back, middleware can also modify the response. Order matters because execution is sequential.

=================================== Rails Routing & Request Handling ===================================
Question 26: How does Routing work in Rails?

Answer -> Routing maps an incoming HTTP request to a controller action.
Routes are defined in config/routes.rb.

Routes are matched top to bottom.

When a request reaches Rails, ActionDispatch::Routing checks routes sequentially. It matches the HTTP verb and URL pattern. Once a match is found, Rails extracts parameters (like :id) and dispatches the request to the corresponding controller and action. If no route matches, Rails returns a 404 error. Route order matters because the first matching route wins.

------------------------------------------------------------------------------------------------------
Question 27: What are RESTful Routing Principles?

Answer -> REST treats everything as a resource.
HTTP verbs define actions, not the URL.

URLs should be noun-based and stateless.
In RESTful routing, the same URL behaves differently depending on the HTTP method. For example:
  GET /users → index
  POST /users → create
  GET /users/:id → show
  PATCH /users/:id → update
  DELETE /users/:id → destroy

Rails supports REST using resources :users, which automatically generates standard CRUD routes. This keeps APIs predictable and consistent.

------------------------------------------------------------------------------------------------------
Question 28: What is ActionDispatch?

Answer -> ActionDispatch is the layer between Rack and Rails MVC.

It handles routing, sessions, cookies, and request/response objects.

ActionDispatch extends Rack and provides structured request and response handling. It manages routing (RouteSet), session middleware, parameter parsing, and exception handling. It is responsible for converting low-level Rack data into Rails-friendly objects like ActionDispatch::Request.

=================================== Rails Security & Parameters ===================================
Question 29: What are Strong Parameters?

Answer ->Strong Parameters prevent mass assignment vulnerabilities.
Only permitted attributes can be assigned.

In Rails, parameters come from user input and cannot be trusted. Using params.require(:user).permit(:name, :email) ensures only allowed fields are mass assigned. This prevents users from injecting protected attributes like admin: true.

------------------------------------------------------------------------------------------------------
Question 30: What is Mass Assignment Protection?

Answer -> Mass assignment allows assigning multiple attributes at once.
Strong parameters ensure only safe attributes are allowed.

When calling User.create(params[:user]), Rails could update all fields. Strong parameters enforce whitelisting to protect sensitive attributes. Database constraints should still exist as a final safety layer.

------------------------------------------------------------------------------------------------------
Question 31: Cookies vs Sessions

Answer -> Cookies are stored on the client.
Sessions represent user state across requests.
Rails uses cookies to store session identifiers.

Cookies are small pieces of data stored in the browser and sent with each request. Sessions store user-specific state (like logged-in user). By default, Rails uses CookieStore, meaning the entire session is encrypted and stored in the browser, but protected with signing and encryption.

------------------------------------------------------------------------------------------------------
Question 32: How does Rails handle Sessions?

Answer -> Rails manages sessions via middleware.

By default, session data is stored in encrypted cookies.

When a request comes in, Rails reads the session cookie, verifies it using the secret key, decrypts it, and exposes it as the session hash. If modified, Rails re-serializes and sends it back. For large-scale apps, server-side stores like Redis can be used.

------------------------------------------------------------------------------------------------------
Question 33: What is CSRF Protection?

Answer -> CSRF protection prevents forged requests from other sites.
Rails embeds authenticity tokens in forms.

When a form is rendered, Rails includes a hidden token. On submission, Rails verifies that the token matches the user session. If not, the request is rejected. This prevents attackers from tricking users into performing unintended actions.

------------------------------------------------------------------------------------------------------
Question 34: What is an Authenticity Token?

Answer -> An authenticity token is a per-session secret.
It verifies that the request originated from the application.

Rails generates a unique token for each session. It is embedded in forms and AJAX headers. If the token is missing or invalid, Rails raises an error.

=================================== Autoloading & Application Structure ===================================
Question 35: What is Zeitwerk?

Answer -> Zeitwerk is Rails’ modern code loader.
It automatically loads classes based on file paths.

Zeitwerk maps constants to file names. For example:
  app/models/user.rb → User
  app/controllers/admin/users_controller.rb → Admin::UsersController

It ensures consistent autoloading and thread safety. In production, it eager loads all files for performance.

------------------------------------------------------------------------------------------------------
Question 36: How does Autoloading work in Rails?

Answer -> Rails loads constants on demand.
Zeitwerk builds a constant-to-file map at boot.

When Ruby encounters an uninitialized constant, Zeitwerk loads the corresponding file automatically. In development, files reload on each request. In production, everything loads at boot for thread safety.

------------------------------------------------------------------------------------------------------
Question 37: Eager Load vs Lazy Load

Answer -> Lazy loading loads code when needed.
Eager loading loads all code at boot.
In development, Rails uses lazy loading for faster startup and reloading. In production, eager loading improves performance and prevents race conditions in multi-threaded environments.

------------------------------------------------------------------------------------------------------
Question 38: Rails Environments Differences

Answer -> Development → productivity.
Test → isolation and repeatability.
Production → performance and stability.

Development reloads code and shows detailed errors. Test runs with cached classes and minimal logging. Production eager loads code, enables caching, disables detailed errors, and optimizes for performance.

------------------------------------------------------------------------------------------------------
Question 39: What are Initializers?

Answer -> Initializers configure the application at boot.
They live in config/initializers.
Initializers run after Rails loads frameworks but before the app starts handling requests. They configure gems, middleware, global settings, and constants. They should be fast and idempotent.

=================================== Active Record & Database ===================================
Question 40: What is Active Record Pattern?

Answer -> Active Record maps objects to database rows.
Models handle both persistence and domain logic.

Each model class represents a table. Each instance represents a row. Active Record provides CRUD methods, validations, associations, and callbacks. It simplifies database interaction but can lead to fat models if not structured properly.

------------------------------------------------------------------------------------------------------
Question 41: What is the N+1 Query Problem?

Answer -> N+1 occurs when one query loads records and additional queries load associations.
It causes performance degradation.

Example: loading 100 posts and calling post.comments inside a loop triggers 101 queries. Solution: use includes, preload, or eager_load to load associations efficiently.

------------------------------------------------------------------------------------------------------
Question 42: includes vs joins vs preload vs eager_load

Answer -> joins → SQL join for filtering.
includes → eager loads and may use join or separate queries.
preload → separate queries only.
eager_load → forces LEFT OUTER JOIN.

joins does not load associated records into memory. includes prevents N+1 queries and decides strategy automatically. preload always runs multiple queries. eager_load forces a single joined query.

------------------------------------------------------------------------------------------------------
Question 43: Validations vs Database Constraints

Answer -> Validations are application-level.
Database constraints are database-level.
Use both for safety.

Validations provide user-friendly errors but can be bypassed. Database constraints like NOT NULL, UNIQUE, and FOREIGN KEY ensure absolute data integrity, especially in concurrent systems.

------------------------------------------------------------------------------------------------------
Question 44: Transactions Usage

Answer -> Transactions ensure atomic operations.
All operations succeed or all fail.

Using ActiveRecord::Base.transaction, Rails wraps operations in a database transaction. If an exception occurs, everything rolls back. after_commit is the correct place for external side effects.

------------------------------------------------------------------------------------------------------
Question 45: Optimistic vs Pessimistic Locking

Answer -> Optimistic locking uses a version column.
Pessimistic locking locks rows at database level.
Optimistic locking assumes conflicts are rare and raises StaleObjectError if version mismatches. Pessimistic locking uses SELECT FOR UPDATE to prevent concurrent updates. Optimistic is lightweight; pessimistic is strict but reduces concurrency.

------------------------------------------------------------------------------------------------------
Question 46: Difference between rails 6, 7 and 8?
Short Asnwer -> Rails 6 introduced Zeitwerk autoloading, multiple database support, and Action Text/Mailbox.

Rails 7 focused heavily on Hotwire, Turbo, Stimulus, and reducing JavaScript dependency using import maps.

Rails 8 focuses more on performance, simplified deployment using Kamal, and built-in infrastructure tools like Solid Queue and Solid Cache.

Long answer -> While working across Rails 6, 7, and 8, I noticed several practical improvements and changes.

In Rails 6, one major change was the Zeitwerk autoloader. Earlier, with classic autoloading, we sometimes faced issues with naming conventions and autoloading in development. Zeitwerk made autoloading much cleaner and thread-safe, but we also had to ensure file names and class names matched properly.

Rails 6 also introduced multiple database support, which was useful for read replicas and sharding use cases.
Another thing I noticed in Rails 6 was stronger integration with modern JavaScript using Webpacker.

In Rails 7, the biggest practical shift was import maps and Hotwire.

Earlier, most Rails apps heavily depended on Webpack, Node modules, and large frontend setups. With import maps, we could manage JavaScript without requiring Webpack in many cases.

Turbo was another major addition. Instead of writing custom AJAX code for many features, we could use Turbo Frames and Turbo Streams for partial page updates and realtime-like behavior.

Stimulus also became the preferred lightweight JavaScript framework for Rails.
Rails 7 also introduced load_async, which allows asynchronous query loading.
Another practical thing I noticed was better encrypted attributes support and improvements around frontend tooling flexibility like esbuild and Vite.

In Rails 8, Rails is moving more toward built-in infrastructure tools.
One major change is Solid Queue for background jobs and Solid Cache for caching.

Earlier, many applications depended heavily on Redis for jobs and caching, but Rails 8 is providing database-backed alternatives.
I also noticed changes in enum syntax and model APIs becoming cleaner.
Kamal deployment integration is another major addition in Rails 8 for containerized deployments.

Overall, Rails 8 feels more focused on simplifying infrastructure and reducing external dependencies while improving performance and developer productivity.”