/*
===============================================================================================
                       NESTJS  (the most "Rails-like" Node framework)
===============================================================================================
If an interviewer asks "what would you use for a big structured app?", NestJS is the answer
that resonates with a Rails dev. It brings convention, structure, DI, and TypeScript to Node —
the opinionated framework Express isn't. Worth knowing even at a conceptual level.
*/

/*
-----------------------------------------------------------------------------------------------
Question 1: What is NestJS and why does it exist?
-----------------------------------------------------------------------------------------------
Answer -> NestJS is an opinionated, TypeScript-first Node framework (built on top of Express or
Fastify) that provides a structured architecture out of the box: modules, controllers,
providers/services, dependency injection, decorators, guards, pipes, interceptors. It exists
because plain Express gives no structure, which hurts large teams/codebases — Nest brings
"convention over configuration" to Node, heavily inspired by Angular (and, in spirit, Rails).

  For a Rails dev: Nest is the closest thing to Rails' batteries-included, opinionated feel.
  Modules ≈ engines/namespaces, providers/services ≈ service objects, guards ≈ before_action/
  Pundit, pipes ≈ strong params + validations, the DI container ≈ Rails wiring.
*/

/*
-----------------------------------------------------------------------------------------------
Question 2: The building blocks (map them to Rails)
-----------------------------------------------------------------------------------------------
Answer ->
  MODULE       -> groups a feature's controllers + providers (@Module). Like a Rails namespace/
                  engine. The app is a tree of modules.
  CONTROLLER   -> handles routes via decorators (@Get, @Post). Thin, like a Rails controller.
  PROVIDER/SERVICE -> @Injectable() business logic, injected via constructor. The service-object
                  layer, with real DI.
  PIPE         -> transforms/validates incoming data (ValidationPipe + class-validator DTOs) —
                  strong params + model validations.
  GUARD        -> authorization/authentication before a handler runs (canActivate) — before_action
                  + Pundit.
  INTERCEPTOR  -> wraps handlers (logging, response transform, caching) — around_action.
  FILTER       -> exception handling (@Catch) — rescue_from.
  DTO          -> typed + validated request objects (class with class-validator decorators).
*/

/*
-----------------------------------------------------------------------------------------------
Question 3: A NestJS slice in code (so it's not abstract)
-----------------------------------------------------------------------------------------------
Answer ->
  // users.controller.ts
  @Controller('users')
  export class UsersController {
    constructor(private readonly usersService: UsersService) {}   // DI via constructor

    @Get(':id')
    findOne(@Param('id') id: string) {
      return this.usersService.findOne(+id);
    }

    @Post()
    create(@Body() dto: CreateUserDto) {     // dto auto-validated by the global ValidationPipe
      return this.usersService.create(dto);
    }
  }

  // users.service.ts
  @Injectable()
  export class UsersService {
    constructor(@InjectRepository(User) private repo: Repository<User>) {}
    findOne(id: number) { return this.repo.findOneBy({ id }); }
    create(dto: CreateUserDto) { return this.repo.save(dto); }
  }

  // create-user.dto.ts  (validation lives on the DTO via decorators)
  export class CreateUserDto {
    @IsEmail() email: string;
    @IsString() @MinLength(2) name: string;
    @MinLength(8) password: string;
  }

  // users.module.ts
  @Module({
    imports: [TypeOrmModule.forFeature([User])],
    controllers: [UsersController],
    providers: [UsersService],
  })
  export class UsersModule {}

  Notice how much this looks like Rails: skinny controller, injected service, validations
  declared declaratively, modules wiring it together. That's the selling point.
*/

/*
-----------------------------------------------------------------------------------------------
Question 4: Dependency Injection in Nest (the headline feature)
-----------------------------------------------------------------------------------------------
Answer -> Nest has a real IoC (Inversion of Control) container. You mark a class @Injectable(),
declare it as a provider in a module, and Nest constructs and injects it wherever its type is
requested in a constructor. Benefits:
  - No manual wiring; no `require` spaghetti.
  - Trivial testing: provide a mock for a dependency in the test module.
  - Clear, typed dependency graph.

  This is the structural advantage over Express, where I'd wire DI by hand (file 19). Nest does
  it for me — the Rails "it just works" feeling, with explicit types.
*/

/*
-----------------------------------------------------------------------------------------------
Question 5: What else Nest gives you out of the box
-----------------------------------------------------------------------------------------------
Answer ->
  - CLI + generators (nest g module users, nest g resource users) — Rails generators vibe.
  - First-class TypeORM/Prisma/Mongoose integration.
  - Built-in support for REST AND GraphQL (code-first or schema-first) AND microservices
    (TCP, Redis, NATS, Kafka, RabbitMQ transports) AND WebSockets (gateways).
  - @nestjs/swagger -> auto-generated OpenAPI docs from decorators.
  - @nestjs/config (config + validation), @nestjs/bull (BullMQ integration), caching, scheduling.
  - Testing utilities (Test.createTestingModule) for easy DI-based unit/e2e tests.
*/

/*
-----------------------------------------------------------------------------------------------
Question 6: When to choose Nest vs plain Express
-----------------------------------------------------------------------------------------------
Answer ->
  CHOOSE NESTJS when: large app / large team, you want enforced structure + TypeScript + DI,
  long-lived enterprise codebase, you value convention and built-in integrations. (The Rails
  trade: structure + productivity at the cost of more concepts/boilerplate up front.)

  CHOOSE EXPRESS (or Fastify) when: small service, you want minimal overhead and full control,
  a quick prototype, or a tiny microservice where Nest's structure is overkill.

  INTERVIEW SOUNDBITE: "Coming from Rails, I appreciate opinionated structure, so for a serious
  product I'd lean toward NestJS — it gives me modules, DI, guards, pipes and TypeScript, which
  recreate the skinny-controller/service-object/before_action discipline I'm used to. For a
  small focused microservice, plain Express or Fastify keeps it lean."
*/

module.exports = {};
