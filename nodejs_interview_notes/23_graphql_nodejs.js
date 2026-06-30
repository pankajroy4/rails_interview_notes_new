/*
===============================================================================================
                       GRAPHQL with NODE (Apollo Server / type-graphql)
===============================================================================================
I have real GraphQL experience from PurePani (schemas + type-safe resolvers + 500 DAU). The
concepts transfer directly from graphql-ruby; only the JS tooling is new. Lean on that history.
*/

/*
-----------------------------------------------------------------------------------------------
Question 1: GraphQL recap (and the Rails connection)
-----------------------------------------------------------------------------------------------
Answer -> GraphQL is a query language + runtime where the CLIENT asks for exactly the fields it
needs from a single endpoint, against a strongly-typed schema. It fixes REST's over-fetching
(getting fields you don't need) and under-fetching (needing several round trips for nested data).

  "I built GraphQL APIs in PurePani with well-structured schemas and type-safe resolvers across
   30+ models. The mental model — schema, types, queries, mutations, resolvers — is identical
   between graphql-ruby and the JS ecosystem; I'm just swapping the resolver language."

  Core pieces:
   - Schema: types + the Query/Mutation/Subscription root types (the contract).
   - Resolvers: functions that fetch the data for each field.
   - One endpoint (POST /graphql); the query in the body describes the response shape.
*/

/*
-----------------------------------------------------------------------------------------------
Question 2: The JS GraphQL toolage
-----------------------------------------------------------------------------------------------
Answer ->
  - Apollo Server -> the most popular GraphQL server for Node; integrates with Express/standalone.
  - graphql-js    -> the reference implementation everything builds on.
  - type-graphql / Nexus -> CODE-FIRST: define schema from TS classes/decorators (type-safe).
  - @nestjs/graphql -> GraphQL inside NestJS (code-first or schema-first).
  - DataLoader     -> batching/caching to solve resolver N+1 (essential — see below).
  Client side: Apollo Client / urql / graphql-request.
*/

/*
-----------------------------------------------------------------------------------------------
Question 3: A minimal Apollo Server (schema-first)
-----------------------------------------------------------------------------------------------
Answer ->
  const { ApolloServer } = require('@apollo/server');
  const { startStandaloneServer } = require('@apollo/server/standalone');

  const typeDefs = `#graphql
    type User { id: ID!, name: String!, posts: [Post!]! }
    type Post { id: ID!, title: String! }
    type Query { user(id: ID!): User, users: [User!]! }
    type Mutation { createUser(name: String!, email: String!): User! }
  `;

  const resolvers = {
    Query: {
      user: (_parent, { id }, ctx) => ctx.userRepo.findById(id),
      users: (_parent, _args, ctx) => ctx.userRepo.findAll(),
    },
    Mutation: {
      createUser: (_p, args, ctx) => ctx.userService.create(args),
    },
    User: {
      // field resolver for the nested relation
      posts: (user, _args, ctx) => ctx.postLoader.load(user.id),   // DataLoader batches these
    },
  };

  const server = new ApolloServer({ typeDefs, resolvers });
  // context carries per-request stuff (auth user, loaders, repos)
  await startStandaloneServer(server, { context: async ({ req }) => buildContext(req) });
*/

/*
-----------------------------------------------------------------------------------------------
Question 4: The N+1 problem in GraphQL + DataLoader (THE key GraphQL interview topic)
-----------------------------------------------------------------------------------------------
Answer -> GraphQL makes N+1 very easy to cause: a query for 100 users that asks for each user's
posts calls the `posts` field resolver 100 times -> 100 DB queries. DataLoader fixes this by
BATCHING all the calls within a single tick into ONE query and CACHING per request.

  const DataLoader = require('dataloader');
  const postLoader = new DataLoader(async (userIds) => {
    // called ONCE with [all userIds collected this tick]
    const posts = await Post.findAll({ where: { authorId: userIds } });   // single IN query
    // must return results in the SAME ORDER as the input keys
    return userIds.map((id) => posts.filter((p) => p.authorId === id));
  });
  // resolver: ctx.postLoader.load(user.id)  -> N loads collapse into 1 query

  This is the exact same N+1 disease I fixed with .includes in Rails / include in Sequelize —
  DataLoader is the GraphQL-resolver-specific cure. Create loaders PER REQUEST (in context) so
  the cache doesn't leak across users.
*/

/*
-----------------------------------------------------------------------------------------------
Question 5: GraphQL-specific concerns (over-fetching's flip side)
-----------------------------------------------------------------------------------------------
Answer -> Flexibility for clients = new risks the server must control:
  - Expensive/abusive queries: deeply nested or huge queries can DoS the DB. Mitigate with
    query DEPTH limiting, COMPLEXITY/cost analysis, pagination on list fields, and timeouts.
  - Caching: HTTP caching is harder than REST (it's all POST /graphql). Use persisted queries,
    CDN-level APQ, response caching, and DataLoader's per-request cache.
  - Authorization: enforce per-FIELD/per-resolver (a user may query a field they can't see).
    Check permissions in resolvers/context, not just at the endpoint.
  - Error handling: GraphQL returns 200 with an `errors` array; design error shapes + codes.
  - Schema evolution: deprecate fields (@deprecated) instead of versioning the endpoint.
*/

/*
-----------------------------------------------------------------------------------------------
Question 6: REST vs GraphQL — when I'd choose each
-----------------------------------------------------------------------------------------------
Answer ->
  GraphQL when: many client types with different data needs (web/mobile), deeply nested/related
  data, you want to avoid endpoint sprawl, fast-moving frontend that wants flexible queries.

  REST when: simple resource CRUD, you want easy HTTP caching/CDNs, file up/downloads, public
  APIs where simplicity + cacheability matter, or webhooks.

  "I've shipped both — GraphQL in PurePani and REST elsewhere — so I pick based on the client's
   data-fetching needs and caching requirements, not hype. They can also coexist."
*/

module.exports = {};
