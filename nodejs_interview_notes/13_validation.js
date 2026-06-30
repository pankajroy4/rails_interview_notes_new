/*
===============================================================================================
                       INPUT VALIDATION (Joi / Zod / express-validator)
===============================================================================================
This is the ActiveModel validations + strong parameters equivalent. Express has NO built-in
validation, so you ALWAYS add a library. Validate at the edge: bad data should become a clean
422, never a deep crash or a security hole.
*/

/*
-----------------------------------------------------------------------------------------------
Question 1: Why validate, and where?
-----------------------------------------------------------------------------------------------
Answer -> Validate ALL external input (body, query, params, headers) at the BOUNDARY of the
system before it touches business logic or the DB. Reasons:
  - Data integrity (like Rails model validations).
  - Security: blocks injection, type-confusion (NoSQL operator injection), oversized payloads.
  - Clear errors: return 422 with a useful message instead of a 500 deep in the stack.

  Rails put validations in the model; in Node it's common to validate at the controller/route
  edge with a schema, AND keep DB-level constraints (unique index, NOT NULL) as the last line
  of defense. Belt and suspenders.
*/

/*
-----------------------------------------------------------------------------------------------
Question 2: The main libraries
-----------------------------------------------------------------------------------------------
Answer ->
  - Zod          -> TypeScript-first, infers types from the schema (one source of truth for
                    runtime validation AND static types). My default for TS projects.
  - Joi          -> mature, very expressive, framework-agnostic. Great for plain JS.
  - express-validator -> middleware-style, validates req fields inline. Express-specific.
  - class-validator   -> decorator-based, used heavily by NestJS (DTOs).

  Pick one and standardize. For a TS Node app I'd choose Zod; for NestJS, class-validator.
*/

/*
-----------------------------------------------------------------------------------------------
Question 3: Zod — schema + type inference (the modern favorite)
-----------------------------------------------------------------------------------------------
Answer ->
  const { z } = require('zod');

  const CreateUserSchema = z.object({
    name:     z.string().min(2).max(100),
    email:    z.string().email(),
    age:      z.number().int().positive().optional(),
    role:     z.enum(['user', 'admin']).default('user'),
    password: z.string().min(8),
  });

  // In TypeScript you also get the type for free:
  //   type CreateUserDto = z.infer<typeof CreateUserSchema>;

  // parse throws a ZodError on invalid input; safeParse returns a result object
  const result = CreateUserSchema.safeParse(req.body);
  if (!result.success) {
    return res.status(422).json({ error: 'validation', details: result.error.issues });
  }
  const data = result.data;   // typed, coerced, with defaults applied
*/

/*
-----------------------------------------------------------------------------------------------
Question 4: A reusable validation middleware (clean pattern)
-----------------------------------------------------------------------------------------------
Answer -> Wrap a schema into Express middleware so routes stay declarative — this is the
strong-params + validation combo in one place.

  // middlewares/validate.js
  const validate = (schema) => (req, res, next) => {
    const result = schema.safeParse({
      body: req.body,
      query: req.query,
      params: req.params,
    });
    if (!result.success) {
      return res.status(422).json({ error: 'validation', details: result.error.issues });
    }
    // replace with the parsed (coerced, stripped) values — like strong params whitelisting
    req.body = result.data.body;
    next();
  };

  // usage
  const schema = z.object({ body: CreateUserSchema });
  app.post('/users', validate(schema), createUserHandler);

  Bonus: parsing STRIPS unknown keys (with .strict() it rejects them), which is the Node
  version of strong params preventing mass assignment.
*/

/*
-----------------------------------------------------------------------------------------------
Question 5: Joi quick example (for non-TS projects)
-----------------------------------------------------------------------------------------------
Answer ->
  const Joi = require('joi');
  const schema = Joi.object({
    name:  Joi.string().min(2).required(),
    email: Joi.string().email().required(),
    age:   Joi.number().integer().min(0).optional(),
  });

  const { error, value } = schema.validate(req.body, { abortEarly: false, stripUnknown: true });
  if (error) return res.status(422).json({ details: error.details });
  // `value` is the cleaned object
*/

/*
-----------------------------------------------------------------------------------------------
Question 6: express-validator (middleware chains on req)
-----------------------------------------------------------------------------------------------
Answer ->
  const { body, validationResult } = require('express-validator');

  app.post('/users',
    body('email').isEmail().normalizeEmail(),
    body('password').isLength({ min: 8 }),
    body('name').trim().notEmpty(),
    (req, res, next) => {
      const errors = validationResult(req);
      if (!errors.isEmpty()) return res.status(422).json({ errors: errors.array() });
      next();
    },
    createUserHandler
  );

  Nice because it also SANITIZES (trim, normalizeEmail, escape). More verbose than a single
  schema, but very explicit per field.
*/

/*
-----------------------------------------------------------------------------------------------
Question 7: Validation + security overlap (say this to sound senior)
-----------------------------------------------------------------------------------------------
Answer -> Validation IS a security control, not just data hygiene:
  - Enforcing types stops NoSQL operator injection (a "string" field can't become {$gt:''}).
  - Whitelisting fields stops mass-assignment / privilege escalation (user can't set role:admin).
  - Length/size limits stop DoS via huge payloads and ReDoS.
  - Enums/formats stop garbage reaching business logic.

  "I treat the validation layer as the security boundary of the app — every external input is
   parsed against a strict schema before anything else runs, which is the strong-params +
   model-validations discipline from Rails, made explicit."
*/

module.exports = {};
