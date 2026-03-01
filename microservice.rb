
=================================== Microservices ==================================================

Question 1: What are microservices?

Answer -> Microservices is an architectural style where an application is broken down into small, independent services, each responsible for a single business capability.
Each service runs independently, has its own database, and communicates with other services over APIs or messaging systems.
Unlike a monolith, microservices allow teams to develop, deploy, and scale services independently.

Microservices is an architectural approach where an application is split into small, independent services. Each service is responsible for a single business capability, runs independently, and communicates with other services using APIs or messaging systems. The key idea is independent development, deployment, and scaling of each service.

------------------------------------------------------------------------------------------------------
Question 2: How are microservices different from a monolithic architecture?

Answer -> In a monolithic architecture, all features like authentication, payments, orders, notifications—are part of a single codebase and deployment unit.

In microservices: Each service has its own codebase. Each service can be deployed independently. Services can be written in different technologies. Failures are isolated
Microservices improve scalability and team autonomy but increase operational complexity.

In a monolithic architecture, the entire application is deployed as a single unit, and all features share the same codebase and database. In microservices, each feature or business capability is a separate service with its own codebase and usually its own database. This allows independent deployment and better scalability, but it also adds operational complexity.

------------------------------------------------------------------------------------------------------
Question 3: Why do companies move from monolith to microservices?

Answer ->  Companies usually move to microservices when:
The monolith becomes too large to maintain
Deployments become slow and risky
Different parts of the system need different scaling
Multiple teams work on the same codebase causing conflicts

Microservices help solve scalability, deployment, and team ownership problems.

Companies usually move to microservices when the monolith becomes difficult to maintain, deployments become risky, or different parts of the system need to scale independently. Microservices help large teams work independently and deploy faster without impacting the entire system.

------------------------------------------------------------------------------------------------------
Question 4: What are the main advantages of microservices?

Answer -> Independent deployment, Better scalability, Technology flexibility, Fault isolation, Faster development for large teams. Each service can evolve independently without affecting the entire system.

The main advantages are independent deployment, better scalability, fault isolation, and flexibility in technology choices. Teams can own and scale their services independently, which improves development speed in large systems.

------------------------------------------------------------------------------------------------------
Question 5: What are the disadvantages of microservices?

Answer -> Microservices increase system complexity. Debugging becomes harder, network calls introduce latency, and data consistency is more difficult to manage. They also require strong DevOps practices, so they are not always the right choice for small teams.

------------------------------------------------------------------------------------------------------
Question 6: How do microservices communicate with each other?

Answer: -> Microservices communicate either synchronously using REST or gRPC APIs, or asynchronously using message queues or event systems like Kafka or RabbitMQ. The choice depends on whether an immediate response is required
For example, an Order Service may call a Payment Service via HTTP or publish an event like order_created.

------------------------------------------------------------------------------------------------------
Question 7:What is synchronous vs asynchronous communication?

Answer: -> In synchronous communication, one service waits for another services response, like an HTTP API call. In asynchronous communication, services communicate through events or queues like Kafka, Sidekiq, RabbitMQ and do not wait for an immediate response, which improves scalability, resilience and fault tolerance.”

------------------------------------------------------------------------------------------------------
Question 8: How is data handled in microservices?

Answer: -> Each microservice owns its own database.
Services do not directly access another services database.
All communication happens via APIs or events.
This avoids tight coupling and ensures service autonomy.

------------------------------------------------------------------------------------------------------
Question 9: How do you maintain data consistency across microservices?

Answer: -> Microservices usually follow eventual consistency instead of strong consistency.
Common approaches:
  Event-driven architecture
  Saga pattern
  Compensation transactions
  Strong database transactions across services are avoided.

Strong Consistency Means - When a write succeeds, every read immediately sees that write.
System behaves like there is one source of truth that updates atomically. (Rails Monolith Style)

Eventual Consistency Means - After a write succeeds, other parts of the system may not see it immediately.
But given some time, all systems will become consistent.
So correctness is not immediate, but guaranteed later.

------------------------------------------------------------------------------------------------------
Question 10:What is the Saga pattern?

Answer: -> The Saga pattern manages distributed transactions across multiple services.
Each service performs a local transaction and publishes an event.
If something fails, compensating actions are triggered to undo previous steps.
This avoids database-level distributed transactions.

------------------------------------------------------------------------------------------------------
Question 11: What is API Gateway in microservices?

Answer: -> An API Gateway acts as a single entry point for all client requests.
Responsibilities:
  Routing requests to services
  Authentication and authorization
  Rate limiting
  Request aggregation
  Clients do not call microservices directly.

An API Gateway acts as a single entry point for clients. It routes requests to the correct microservice and can also handle authentication, rate limiting, and request aggregation. This prevents clients from calling services directly.

------------------------------------------------------------------------------------------------------
Question 12: How is authentication handled?

Answer: -> Authentication is usually centralized using JWT or OAuth. The client sends a token with each request, and individual services validate the token instead of maintaining sessions.

------------------------------------------------------------------------------------------------------
Question 13: How do microservices handle failures?

Answer: -> They use techniques like timeouts, retries, circuit breakers, and graceful degradation. These patterns prevent a failing service from bringing down the entire system.

------------------------------------------------------------------------------------------------------
Question 14: What is a circuit breaker?

Answer: -> A circuit breaker stops requests to a failing service after a certain failure threshold. This protects the system from cascading failures and allows the service time to recover.

------------------------------------------------------------------------------------------------------
Question 15: How are microservices deployed?

Answer: -> Microservices are commonly deployed using containers like Docker and orchestrated with tools like Kubernetes. Each service has its own CI/CD pipeline and can be deployed independently.

------------------------------------------------------------------------------------------------------
Question 16: When should you NOT use microservices?

Answer: -> Microservices are not ideal for small teams, simple applications, or when DevOps maturity is low. In such cases, a well-structured monolith is usually a better choice.
