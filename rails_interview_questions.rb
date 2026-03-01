Question 1: You are a senior developer. You have to review the code of you juniors. How do you review them without manual intervension?

Answer -> I build an automated review system (quality gates) around the PR workflow.
In real teams, this usually means: every pull request must pass automated checks before it can be merged. Human review still exists for architecture/business logic, but juniors get instant feedback automatically for 70-90% of issues.
Every PR must pass formatting, linting, static analysis, security scans, tests, and quality thresholds in CI before merge. Tools like RuboCop, Brakeman, bundler-audit, RSpec, SonarQube/CodeQL, and Danger add automated review comments directly on PRs. Branch protection prevents merging until everything is green. Human review is reserved only for architecture and business-critical logic.

As a senior developer, I try to reduce manual effort by setting up strong automated checks. In most teams I’ve worked with, every pull request goes through a CI pipeline. That pipeline runs our test suite, linting tools like RuboCop, and security scanners like Brakeman. So basic issues like style violations, failing tests, or obvious security problems are caught automatically before I even open the PR. I also make sure branch protection rules are enabled, so nothing gets merged unless checks pass. Because of that, when I review code, I can focus more on design decisions, performance concerns, and whether the solution fits the overall architecture, instead of pointing out formatting or small mistakes.

------------------------------------------------------------------------------------------------------
Question 2: Let's say you're explaining the Rails request-response cycle to someone who is not super familiar with Rails. How would you break it down in simple terms?

Answer -> I usually explain the Rails request-response cycle as a structured pipeline.

When a user makes a request—like visiting a URL—the request first hits the Rails router, which decides which controller and action should handle it based on the route definitions.

The request then moves to the controller, which acts as the coordinator. The controller may fetch or update data by interacting with models, which handle database logic and business rules.

Once the controller has what it needs, it prepares a response—either rendering a view (for HTML) or returning JSON (for APIs). The view is combined with layout and templates to generate the final output.

Finally, Rails sends the response back to the browser with an appropriate HTTP status code and headers.

In short: Request → Router → Controller → Model → View → Response
This clear separation of responsibilities is what makes Rails applications easy to reason about and maintain.

------------------------------------------------------------------------------------------------------
Question 3: Can you explain how Rails validations work and maybe give an example of when you would use them?

Answer -> Validations are rules we define in models to make sure only valid data gets saved to the database. Rails runs them automatically before saving a record. Validations are model-level guards to ensure data integrity before hitting the database.

For example, if I have a User model, I might validate presence of email and uniqueness of email. So if someone tries to create a user without an email or with a duplicate one, Rails will prevent saving and return errors. I use validations whenever there are business rules about what data is acceptable.

------------------------------------------------------------------------------------------------------
Question 4: Can you explain the difference between a has_many and a belongs_to association, and maybe give an example of when you would use each one?

Answer -> belongs_to defines ownership and holds the foreign key, while has_many defines the inverse collection. The important part is lifecycle and dependency.

For example, an Order belongs_to :user and User has_many :orders. The belongs_to side is required by default in modern Rails, which enforces presence unless marked optional. I also think about dependent behavior — like has_many :orders, dependent: :nullify or :destroy — depending on business rules.

------------------------------------------------------------------------------------------------------
Question 5: How do you handle environment-specific configuration in Rails? So for example, how do you manage settings that are different in development, test, and production?

Answer -> Rails already gives a strong foundation for this with separate environments: development, test, and production.

For configuration that differs per environment, I typically use a combination of environment files and environment variables. For example, logging levels, caching behavior, and class loading are configured inside config/environments.

For sensitive or deploy-specific data like API keys, database credentials, or third-party tokens, I always rely on environment variables. In modern Rails, credentials.yml.enc is also a good option, especially when combined with per-environment credentials.

The key idea is that code stays the same across environments, but configuration changes based on where the app is running.

------------------------------------------------------------------------------------------------------
Question 6: How would you handle a task that takes a long time to process, like sending out a bunch of emails or generating a big report?

Answer -> I never handle long-running tasks inside a web request because it blocks the request and hurts user experience.

Instead, I use background jobs. The controller triggers a job, immediately responds to the user, and the heavy work happens asynchronously.

For example, sending bulk emails, generating reports, or syncing with third-party APIs are perfect use cases for background jobs. Tools like Sidekiq or Delayed Job help process these jobs efficiently.

This approach keeps the application responsive and scalable.

------------------------------------------------------------------------------------------------------
Question 7: What are some best practices to secure a Rails app against common vulnerabilities?

Answer -> Rails provides strong security defaults, but securing an application still requires deliberate effort.

First, I rely on Rails’ built-in protections like CSRF tokens, strong parameters, and automatic SQL injection prevention. I never interpolate user input directly into SQL or HTML.

Authentication and authorization are clearly separated—authentication handled by Devise or similar, and authorization enforced via Pundit policies or similar mechanisms. This ensures access control is explicit and testable.

I also enforce secure headers (CSP, HSTS, X-Frame-Options) and always store secrets using encrypted credentials or environment variables, never in source control.

On the data side, I validate and sanitize all inputs and avoid exposing sensitive fields in APIs or logs. Regular dependency updates and security audits via tools like bundler-audit are part of my routine.

Ultimately, security is about layers—no single feature protects you. It’s about combining framework protections, good coding habits, and operational discipline.

Short Answer -> I follow layered security. At the Rails level: strong parameters, CSRF protection, secure cookies, and avoiding mass assignment. At the dependency level: regular bundle audits and Brakeman scans.

At the infrastructure level: HTTPS everywhere, proper CORS rules for APIs, and rate limiting using Rack::Attack if needed. Security is not one feature — it is multiple layers working together.

------------------------------------------------------------------------------------------------------
Question 8: What are a couple of ways you can improve the performance of a Rails app if you notice it is getting a bit slow?

Answer -> When a Rails app starts slowing down, the first thing I do is measure before optimizing. I use tools like Bullet, Skylight, New Relic, or Rails logs to identify bottlenecks—whether they are database-related, rendering-related, or network-related.

Most performance issues come from the database layer, so I look for N+1 queries, missing indexes, and inefficient queries. Adding proper indexes, using includes, and avoiding unnecessary object loading often gives immediate gains.

Next, I focus on caching. Fragment caching, low-level caching, and HTTP caching (ETags, conditional GETs) can dramatically reduce response times when used correctly.

For heavy or slow tasks—like sending emails or processing files—I move the work to background jobs using Sidekiq or Active Job so user requests stay fast.

Finally, I review view rendering and asset delivery, ensuring partials are not overused and assets are properly compressed and cached. Performance is usually about fixing a few high-impact problems rather than rewriting the entire system.

------------------------------------------------------------------------------------------------------
Question 9: How do you typically handle exceptions in a Rails application, and what are some best practices for making sure errors are logged and users see friendly messages?

Answer -> In a Rails application, I approach exception handling at multiple layers rather than relying on a single global solution.

At the controller level, I use rescue_from to catch known, expected exceptions—such as ActiveRecord::RecordNotFound, authorization errors from Pundit, or custom business logic errors. This allows me to return meaningful HTTP responses like 404, 403, or 422 while keeping controllers clean and predictable.

For unexpected or system-level errors, I let Rails handle them naturally and rely on a centralized error tracking tool like Sentry, Honeybadger, or Bugsnag. These tools capture stack traces, request context, user IDs, and environment details, which is far more effective than relying only on log files.

From a logging perspective, I ensure that errors are logged with enough context—such as request IDs, user information, and parameters (with sensitive data filtered). Rails’ tagged logging helps a lot here, especially in distributed systems.

For user experience, I never expose raw exception messages. Instead, I render friendly, non-technical error pages or JSON responses like “Something went wrong, please try again later.” The goal is to be transparent but not alarming.

Overall, the best practice is to treat errors as first-class citizens: catch what you expect, monitor what you do not, log everything responsibly, and always protect the user experience.

------------------------------------------------------------------------------------------------------
Question 10: How would you design a RESTful API in Rails, and what are some conventions or best practices you follow when building APIs?

Answer -> When designing a RESTful API in Rails, I start by modeling the API around resources, not actions. Each resource maps cleanly to standard HTTP verbs—GET, POST, PUT/PATCH, and DELETE—which keeps the API intuitive and predictable.

I typically namespace APIs under /api and version them, such as /api/v1, to allow backward compatibility as the system evolves. This is critical in production systems where multiple clients may depend on older versions.

I keep controllers thin by pushing business logic into service objects or models, and I use serializers (like ActiveModelSerializers or JSONAPI::Serializer) to control the response structure. This keeps responses consistent and avoids leaking internal model details.

From a standards perspective, I use:
  Proper HTTP status codes (200, 201, 401, 404, 422)
  Consistent JSON response formats
  Pagination, filtering, and sorting for collections
  Token-based authentication (JWT or Devise Token Auth)

Security-wise, I avoid exposing unnecessary fields, validate all inputs, and throttle requests where needed. Overall, my goal is to make the API predictable, stable, secure, and easy to consume, not just functional.

Short Answer: 
  I follow REST conventions strictly — proper HTTP verbs, status codes, and resource-based routes. I keep controllers thin and move logic to services.

  I also handle versioning from the start, use token-based authentication, and ensure consistent JSON response structure with serializers. Good APIs are predictable and backward-compatible.

------------------------------------------------------------------------------------------------------
Question 11: What testing frameworks do you like to use with Rails, and how do you structure your tests to make sure your application is reliable?

Answer -> I prefer RSpec for Rails because it is expressive and widely adopted. I structure tests into models, requests, and services. We can easily use factory bot and faker gem for data creation.

Models test validations and logic, request specs test endpoints, and service specs test business flows. This layered approach keeps tests fast and reliable.

------------------------------------------------------------------------------------------------------
Question 12: Can you walk me through how you typically deploy a Rails app to production and any tools like capistrano or services you like to use for that?

Answer -> When I deploy a Rails application to production, I always treat deployment as a repeatable and automated process, not something that depends on manual steps.

Typically, I start by ensuring the application is production-ready. That means all environment-specific configurations are properly set using environment variables or Rails credentials, background jobs are configured, and the database is properly indexed and migrated.

In a traditional server-based setup, I have used Capistrano quite a bit. Capistrano helps automate the entire deployment flow—pulling code from the repository, installing gems, running database migrations, precompiling assets, and restarting the application server. One thing I like about Capistrano is that it supports zero-downtime deployments using release directories and symlinks, which makes rollbacks very easy if something goes wrong.

For the runtime stack, I usually use Puma as the app server and Nginx as the reverse proxy. Nginx handles SSL termination, static assets, and request forwarding, while Puma runs the Rails processes.

In more modern setups, I have also worked with platform-as-a-service tools like Heroku or Render. In those cases, deployments are usually integrated into a CI/CD pipeline where tests run first, and only successful builds are deployed. These platforms abstract away a lot of infrastructure concerns, which is great for smaller teams or fast-moving products.

After deployment, I always verify logs, background workers, and monitoring tools like Sentry to make sure everything is stable. If something goes wrong, having a clear rollback strategy is very important.

------------------------------------------------------------------------------------------------------
Question 13: How do you typically set up and manage background jobs in Rails, and what tools do you prefer?

Answer -> In a Rails application, I use background jobs whenever I have tasks that are time-consuming and don't need to run during the main web request. I typically define these jobs using Active Job, which gives me a nice unified interface, and then I use Sidekiq and Redis as the backend to actually process those jobs. This is really useful for things like sending emails, generating big reports, or any other heavy lifting that I don't want to slow down the user experience. By using background jobs, I can keep the main app response fast and let the longer tasks run behind the scenes.

------------------------------------------------------------------------------------------------------
Question 14: If you needed to scale a Rails app to handle a much larger number of users, what steps would you take?

Answer -> When scaling a Rails application, I always start by identifying where the bottleneck is, rather than scaling blindly.

The first step is usually database optimization, because that is often the biggest bottleneck. I look at slow queries, add proper indexes, remove N+1 queries, and optimize data access patterns.

Next, I focus on caching—fragment caching, low-level caching, and HTTP caching where applicable. Caching reduces repeated work and significantly improves response times.

After that, I scale the application layer by running multiple application servers behind a load balancer. Background jobs are also separated into their own workers so long-running tasks do not affect web requests.

If the app continues to grow, I may introduce read replicas for the database, move heavy workloads into background jobs, or even extract certain responsibilities into separate services. The key idea is to scale incrementally and based on evidence, not assumptions.

------------------------------------------------------------------------------------------------------
Question 15: How would you handle adding a new feature to a legacy Rails application that you did not originally build? What steps would you take to make sure it is integrated smoothly?

Answer -> When working on a legacy Rails application, my first priority is to understand the existing system before writing any new code.

I start by reading the relevant parts of the codebase, understanding the data models, and checking what test coverage exists. If tests are missing or weak in the area I am touching, I usually add characterization tests first. This helps me understand current behavior and protects against accidental regressions.

Once I am confident I understand the flow, I design the new feature in a way that fits the existing architecture rather than forcing a completely new pattern. I try to make changes incremental and isolated, avoiding large refactors unless absolutely necessary.

After implementing the feature, I make sure it is well-tested, code-reviewed, and documented. The goal is to improve the system without increasing technical debt.

------------------------------------------------------------------------------------------------------
Question 16: Can you explain how Rails MVC architecture works and how it helps structure a typical Rails application?

Answer -> Rails follows the Model-View-Controller architecture, which helps clearly separate responsibilities in the application.

The model layer is responsible for data and business logic. It handles database interactions, validations, associations, and domain rules.

The controller acts as the coordinator. It receives requests, interacts with models, and decides what response to return. Controllers should stay thin and focused on orchestration rather than business logic.

The view layer handles presentation. It takes data from the controller and renders HTML or JSON. Keeping views focused on display logic makes them easier to maintain.

This separation makes the application easier to understand, test, and scale as it grows.

------------------------------------------------------------------------------------------------------
Question 17: How would you handle file uploads in a Rails application and what are some best practices or gems you might use?

Answer -> In a Rails application, you can handle file uploads using either Active Storage, which is built into Rails, or a gem like CarrierWave. Both options let you easily attach files to your models and manage things like generating different versions of an image. For example, with Active Storage, you just declare an attachment in your model and Rails handles the rest, including connecting to cloud storage if you need it. With CarrierWave, you have a lot of flexibility in defining how files are uploaded and processed. Either way, it is straightforward to get file uploads working securely and efficiently in Rails.

For file uploads, I usually rely on Active Storage in modern Rails applications. It integrates well with Rails and supports cloud storage services like Amazon S3.

My approach is to avoid storing files directly on the application server, especially in production. Instead, files are stored externally, which makes scaling much easier.

I always validate file size and content type to prevent abuse. If files need processing, like image resizing or document conversion, I move that work into background jobs so uploads don’t block user requests.

Security is also important, so I make sure access to private files is properly controlled.

------------------------------------------------------------------------------------------------------
Question 18: Imagine you need to optimize a slow-running report in a Rails app. How would you approach finding the bottleneck and improving the performance?

Answer -> The first thing I do is measure before changing anything. I look at logs, query times, and request durations to understand where the slowdown is happening.

Often, slow reports are caused by inefficient database queries. I check for N+1 queries, missing indexes, or loading too much data into memory. Sometimes rewriting the query or using database-level aggregation can make a huge difference.

If the report is inherently heavy, I move it into a background job and notify the user when it’s ready. Caching previously generated reports is also a common optimization.

The key is to fix the root cause, not just mask the symptom.

------------------------------------------------------------------------------------------------------
Question 19: Can you explain how you would implement role-based authorization in a Rails application and which gems you might use to handle it?

Answer -> For role-based authorization, I prefer using Pundit. Roles are usually stored on the user model, and policies define what actions a user is allowed to perform.

Each policy is explicit and easy to test, which I like. For example, an admin may be allowed to manage all records, while a regular user can only access their own data.

This approach keeps authorization logic out of controllers and models, making the application easier to maintain and reason about.

------------------------------------------------------------------------------------------------------
Question 20: How do you handle background jobs in Rails, and what are some of the use cases where you’d definitely want to use a background job instead of handling something in a request?

Answer -> In Rails, I handle background jobs using Active Job with a backend like Sidekiq. Any task that takes more than a fraction of a second or depends on external systems is a strong candidate for a background job.

Typical use cases include sending emails, processing file uploads, generating reports, syncing with third-party APIs, and running scheduled maintenance tasks.

Handling these tasks asynchronously keeps the application responsive and improves user experience. It also makes the system more resilient, because background jobs can retry on failure instead of failing a user request.

------------------------------------------------------------------------------------------------------
Question 21: Can you explain how you would handle and structure API versioning in a Rails application, and why versioning might be important?

Answer -> When building APIs in Rails, I treat versioning as something that should be planned early, even if the first version is simple. The main reason versioning is important is because once an API is consumed by clients—like mobile apps or third-party systems—you can’t freely change it without breaking those clients.

The most common approach I use is namespace-based versioning, such as api/v1 and api/v2. Each version has its own controllers, and sometimes its own serializers. This keeps changes isolated and makes it very clear which behavior belongs to which version.

When introducing a new version, I avoid breaking changes in the existing one. Instead, I add the new behavior to the next version and slowly deprecate the older one. This gives consumers time to migrate.

Overall, API versioning is about stability and trust—clients should feel confident that updates will not unexpectedly break their integration.

------------------------------------------------------------------------------------------------------
Question 22: Can you tell me about a time when you faced a significant challenge in a project and how you handled it?

Answer -> One significant challenge I faced was dealing with serious performance issues in a production Rails application. The application worked fine initially, but as data grew, response times became unacceptable.

Instead of immediately jumping to scaling infrastructure, I started by analyzing logs and profiling database queries. I discovered a combination of N+1 queries and missing database indexes that were slowing down critical endpoints.

I fixed the query issues using eager loading, added the necessary indexes, and introduced caching where appropriate. I also added monitoring so we could catch similar issues earlier in the future.

The result was a noticeable improvement in performance and stability. More importantly, the experience taught me to measure first, then optimize, rather than guessing.

------------------------------------------------------------------------------------------------------
Question 23: Can you describe a situation where you had to collaborate with a difficult team member, and how you handled it?

Answer -> Yes, I have definitely encountered that situation. In one case, a team member was very strong technically but resistant to feedback and collaboration, which started affecting the team’s productivity.

Instead of confronting them directly in a negative way, I focused on clear communication. I tried to understand their perspective and aligned discussions around shared goals, like code quality and delivery timelines.

I also kept conversations focused on the work rather than personalities. Over time, this helped build mutual respect and improved collaboration. I believe handling such situations calmly and professionally is an important part of being a senior developer.

------------------------------------------------------------------------------------------------------
Question 24: Can you explain how Rails Active Record manages database transactions and what are some best practices for handling them?

Answer -> Active Record provides built-in support for database transactions, which are essential when multiple database operations need to succeed or fail together.

In Rails, I use transactions when updating multiple related records where partial updates could leave the system in an inconsistent state. For example, creating an order and updating inventory should happen within a single transaction.

Best practices include keeping transactions short and focused, avoiding external API calls inside them, and handling exceptions properly so that failed operations are rolled back cleanly.

Used correctly, transactions are a powerful tool for maintaining data integrity.

------------------------------------------------------------------------------------------------------
Question 25: Can you explain how Rails handles background jobs and what role Active Job plays in that process?

Answer -> Rails handles background jobs through Active Job, which acts as a framework-level abstraction. Active Job provides a consistent interface for defining and running jobs, regardless of which backend is used.

The actual job execution is handled by adapters like Sidekiq, Delayed Job, or Resque. This separation is useful because it allows you to switch job backends without rewriting your job code.

Active Job also integrates nicely with Rails features like retries, callbacks, and logging. In practice, it helps standardize background processing across the application.

------------------------------------------------------------------------------------------------------
Question 26: Can you explain the difference between before_action, after_action, and around_action filters in Rails controllers, and when you might use each one?

Answer -> Controller filters allow you to run code at different points in the request lifecycle.

before_action runs before the controller action and is commonly used for things like authentication, authorization, or loading shared resources.

after_action runs after the action is completed, usually for tasks like logging or cleanup, although it’s used less frequently.

around_action wraps the entire action, which makes it useful for cases like measuring performance or handling transactions around a request.

I use filters carefully to avoid hidden logic and keep controllers readable.

------------------------------------------------------------------------------------------------------
Question 27: Can you explain what strong parameters are in Rails and why they are important for security?

Answer -> Strong parameters are a security feature in Rails that prevent mass assignment vulnerabilities. Instead of allowing all parameters to be assigned automatically, Rails requires you to explicitly permit which attributes are allowed.

This is important because without strong parameters, malicious users could modify sensitive fields like roles or permissions.

By whitelisting parameters, Rails ensures that only intended data can be written to the database, which significantly improves application security.

------------------------------------------------------------------------------------------------------
Question 28: Can you explain what a Rails migration is and how it helps manage database schema changes?

Answer -> Rails migrations are a way to manage database schema changes in a structured and version-controlled manner.
Each migration represents a change, such as creating a table or adding a column. Because migrations are committed to the codebase, they allow the entire team to stay in sync.

Migrations also make it easy to move forward or roll back schema changes, which is especially important when deploying to different environments.

------------------------------------------------------------------------------------------------------
Question 29: Can you explain what the Rails asset pipeline is and how it works?

Answer -> The Rails asset pipeline is a framework for managing and serving static assets like CSS, JavaScript, and images. In earlier versions of Rails, the pipeline used Sprockets to compile, minify, and fingerprint assets so that browsers could cache them efficiently. This helped reduce load times and ensure that updates to assets were always reflected for users.

In newer versions of Rails, there’s been a shift toward using tools like Importmap, which lets you manage JavaScript dependencies without a build step, and there are also newer tools like Propshaft that aim to simplify asset management further. The idea is to make it easier to handle assets in a more modern, lightweight way while still benefiting from things like caching and fingerprinting.

------------------------------------------------------------------------------------------------------
Question 30: Can you explain how Rails handles caching and what types of caching are available out of the box?

Answer -> Rails provides several caching mechanisms out of the box to improve performance.

There is fragment caching, which caches parts of a view, and low-level caching, which allows caching arbitrary data. Rails also supports HTTP caching using ETags and conditional GETs.

By combining these caching strategies with a proper cache store like Redis or Memcached, Rails applications can significantly reduce load and improve response times.

------------------------------------------------------------------------------------------------------
Question 31: Can you explain what concerns are in Rails and how they help with organizing code?

Answer -> In Rails, concerns are a way to extract and share reusable behavior across models or controllers without duplicating code. They are essentially Ruby modules that are included where needed. it also supports models life cycles method.

I usually use concerns when multiple models or controllers share common logic, like soft deletion, tagging, or common scopes. Instead of repeating the same methods in multiple places, I move that logic into a concern.

Concerns help keep classes smaller and more focused. However, I try not to overuse them, because too many concerns can make it harder to understand where behavior is coming from. Used thoughtfully, they are a clean way to organize shared logic.

------------------------------------------------------------------------------------------------------
Question 32: How concerns are different from service objects?

Answer -> Concerns are typically used to share reusable bits of logic that might be sprinkled across multiple models or controllers. They are all about mixing in behavior that is relevant to more than one class. So if you have a few models that all need the same set of methods, you put those methods in a concern and include it wherever needed. Concern supports lifecylce methods of model like callbacks(before_save, after_save etc).

Service objects, on the other hand, are used to encapsulate a specific unit of business logic that might not really belong in a model or a controller. They are more about handling a complex process or a single operation that can be called from multiple places. For example, if you have a complex checkout process or a payment workflow, you would put that in a service object rather than a concern.

In short, concerns are for sharing reusable behavior across classes, while service objects are for organizing specific pieces of business logic into their own classes.

Also - The main difference is purpose and responsibility.

Concerns are used to share behavior across multiple classes. They extend the functionality of models or controllers and usually depend on the context they are included in.

Service objects, on the other hand, are used to encapsulate a specific business operation or workflow. They are typically standalone objects that perform a task, like processing a payment or onboarding a user.

In short, concerns are about reusability of behavior, while service objects are about orchestrating business logic. Mixing the two can lead to confusing code, so I keep their responsibilities clearly separated.

------------------------------------------------------------------------------------------------------
Question 33: Can you explain the difference between unit tests and integration tests in Rails, and when you might use each one?

Answer -> Unit tests focus on testing individual components in isolation, such as a model method or a service object. They are fast, easy to write, and help catch bugs early.

Integration tests, on the other hand, test how multiple parts of the system work together. For example, a request spec that hits a controller, runs validations, saves data, and returns a response.

I use unit tests to verify business logic and edge cases, and integration tests to ensure that real user flows work correctly. A healthy test suite usually has more unit tests and fewer integration tests, because integration tests are slower but provide higher confidence.

------------------------------------------------------------------------------------------------------
Question 34: Can you explain what service objects are in a Rails application and when you might use them?

Answer -> Service objects are plain Ruby objects that encapsulate complex business logic that doesn’t naturally belong in a model or controller.

I use service objects when an operation involves multiple models, external APIs, or several steps that would otherwise clutter a controller or model. For example, creating an order, charging a payment, and sending notifications is a good candidate for a service object.

Service objects improve readability, testability, and maintainability by keeping responsibilities clearly separated. They also make it easier to reason about and change business workflows over time.

------------------------------------------------------------------------------------------------------
Question 35: Can you explain how you approach testing a Rails model with RSpec and what kind of things you typically test for?

Answer -> When testing a Rails model with RSpec, I focus on behavior rather than implementation details.

I usually test validations, associations, and scopes first. After that, I test any custom methods or business logic defined in the model, especially edge cases.

I avoid testing Rails internals and focus on what the model is responsible for. Clear, focused model tests make it easier to refactor confidently later.

------------------------------------------------------------------------------------------------------
Question 36: Can you explain how you handle environment variables and secrets in a Rails production environment? What tools or practices do you use to keep those credentials secure?

Answer -> In production, I never hardcode secrets into the codebase. Instead, I use environment variables or Rails encrypted credentials.

For cloud platforms, secrets are usually managed through the platform’s configuration dashboard. Locally, tools like dotenv can be used, but those files are never committed to version control.

The goal is to keep secrets secure, environment-specific, and easy to rotate when needed.

------------------------------------------------------------------------------------------------------
Question 37: Can you explain how you would diagnose and improve a slow-running Rails action? What tools or methods would you use to figure out where the bottleneck is?

Answer -> When I need to diagnose a slow-running Rails action, I usually start by looking at the database queries. I use tools like the Bullet gem to identify N+1 query problems and make sure I am using eager loading properly. If the queries themselves are slow, I will use the EXPLAIN command or a tool like rack-mini-profiler to see which queries need indexing or optimization. Once the database is tuned, I also look at what else the action is doing—like if it is sending emails or generating large reports—and move those tasks into background jobs. Finally, I will add caching for any heavy computations to keep the response times quick.

------------------------------------------------------------------------------------------------------
Question 38: Can you explain how you handle error handling in a Rails application? For example, how do you manage and respond to exceptions in controllers or across the application?

Answer -> When dealing with a slow Rails action, my first step is to measure and observe. I look at logs, request timings, and database query durations.

Very often, performance issues are caused by inefficient queries or N+1 problems. I fix those using eager loading, better query structure, or database indexes.

If the action is still slow, I consider caching or moving heavy logic into background jobs. The key is to fix the actual bottleneck rather than applying random optimizations.

------------------------------------------------------------------------------------------------------
Question 39: How do you manage database migrations in Rails, especially when working in a team environment? Can you explain how you handle merging or conflicts with migrations when multiple developers are working on the same project?

Answer -> In a team environment, I keep migrations small, focused, and well-named. Each migration should do one thing clearly.

When conflicts arise, especially in schema files, I resolve them carefully and ensure migrations run in the correct order. Communication with the team is important to avoid overlapping changes.

Before deploying, I always review pending migrations and test them in staging to prevent production issues.

------------------------------------------------------------------------------------------------------
Question 40: Can you explain what a polymorphic association is in Rails and give an example of when you might use one?

Answer -> A polymorphic association allows a model to belong to more than one other model using a single association.

For example, a Comment can belong to a Post or a Photo. Instead of having multiple foreign keys, the comment stores both an ID and a type.

I use polymorphic associations when different models share the same relationship behavior. However, I use them carefully, because they can make queries and constraints more complex.

------------------------------------------------------------------------------------------------------
Question 41: In a Rails application, what are callbacks and when might you use them? Can you give an example of a before or after callback and how you would use it in a model?

Answer -> Callbacks allow you to hook into different stages of a model’s lifecycle, such as before saving or after committing to the database.

I use callbacks for things like normalizing data, generating derived values, or triggering side effects that must happen alongside persistence.

That said, I use callbacks sparingly. Overusing them can make the code hard to follow and debug. For more complex workflows, I prefer service objects instead.

------------------------------------------------------------------------------------------------------
Question 42: Can you describe how you would set up a Rails backend to serve as an API for a React frontend? In other words, explain the architecture and any best practices you’d follow to ensure smooth integration between a Rails API and a React single-page application.

Answer: -> If I have to set up a Rails backend to serve as an API for a React single-page application, I approach it with a clear separation of concerns: Rails as a pure backend API and React as the frontend consumer.

On the backend, I create the Rails app in API-only mode. This removes unnecessary middleware like views and sessions and keeps the application lightweight. Rails is responsible only for business logic, data validation, authentication, and persistence.

I design clean, versioned REST APIs—usually under /api/v1—so that future changes do not break existing clients. Controllers are kept thin, and most business logic lives in service objects or domain layers.

For authentication, I avoid cookie-based sessions and use token-based auth, typically JWT. The React app stores the token securely and sends it with every request via headers.

I standardize API responses using serializers, so every response has a consistent JSON structure. This makes frontend integration predictable and reduces coupling between frontend and backend.

On the frontend, React consumes these APIs using Axios or Fetch. State management is handled on the client side, and routing is done using React Router. The backend remains completely stateless.

To ensure performance and reliability, I add proper database indexing, background jobs for long-running tasks, and caching where required—usually Redis for low-level caching. I also implement CORS properly so the React app can communicate securely with the Rails API.

Finally, I ensure smooth integration by having a clearly defined API contract, proper error handling, and environment-specific configuration for development, staging, and production. This setup scales well and allows both frontend and backend teams to work independently.”

------------------------------------------------------------------------------------------------------
Question 43: How would you implement global search across multiple models without associations?

Answer: -> In this case, since there are no associations between the models, I cannot use joins. So instead of querying each model separately and merging in Ruby, I would prefer using SQL UNION.

The reason is that UNION allows me to combine multiple SELECT queries into a single result set at the database level. This is more efficient because:
    Only one query is executed
    Sorting and pagination can happen at database level
    It reduces memory usage in Rails
    It scales better than merging arrays in Ruby

For example, suppose I have User, Product, and Order models, and user searches for “john”.
I would write something like this:

    keyword = "%#{params[:query]}%"

    sql = <<-SQL
      SELECT id, name AS title, 'User' AS record_type, created_at
      FROM users
      WHERE name ILIKE :keyword

      UNION ALL

      SELECT id, title, 'Product' AS record_type, created_at
      FROM products
      WHERE title ILIKE :keyword

      UNION ALL

      SELECT id, order_number AS title, 'Order' AS record_type, created_at
      FROM orders
      WHERE order_number ILIKE :keyword

      ORDER BY created_at DESC
    SQL

    results = ActiveRecord::Base.connection.exec_query(
      sql,
      "Global Search",
      [[nil, keyword]]
    )

Here, I make sure:
    Each SELECT returns same number of columns
    Columns are normalized
    I add a record_type column to identify which model it belongs to
    Sorting happens at database level

If the application becomes large scale, I would move to PostgreSQL full-text search or Elasticsearch for better performance and ranking.
That would be my approach.

