
1. You added both a Rails-level uniqueness validation (case_sensitive: false) and a database unique index, with a rescue_from for RecordNotUnique. What problem does the DB index solve that the Rails validation alone doeS NOT?

Good answer covers: the race condition between two concurrent requests both passing validation before either commits (TOCTOU); the DB constraint is the only actual guarantee under concurrency; the Rails validation exists purely for fast, friendly feedback in the common case.

-----------------------------------------------------------------------------------------------------------------------------------
2. In Course#tutors_have_unique_emails you wrote tutors.target.select(&:new_record?) instead of tutors.select(&:new_record?). Why?
Good answer covers: .target reads only what is already built/loaded in memory without triggering an extra DB query on the association — relevant because calling tutors on a persisted course would otherwise force-load existing children from the DB during validation.

A good candidate should explain: calling tutors on an unloaded association triggers a DB query to load existing records; .target accesses the in-memory array of already-built/loaded objects without forcing a load. Since nested attributes already populate the in-memory association, using .target avoids an unnecessary query. Someone who copied this without understanding would struggle to explain the actual mechanism.

-----------------------------------------------------------------------------------------------------------------------------------
3. Walk me through exactly what happens when course.save is called with tutors_attributes containing one invalid tutor. Is this wrapped in a transaction, and where does that transaction actually come from?
Good answer covers: accepts_nested_attributes_for builds in-memory child records; Rails' autosave-association callbacks save parent and children inside one implicit transaction during save; if any child fails validation, the parent's save returns false and nothing is persisted — they should be able to point to their own rollback test as proof.

-----------------------------------------------------------------------------------------------------------------------------------
4. Your GET /courses uses Course.includes(:tutors). If you removed includes, what would actually break, and how would you prove it in a test (not just by eyeballing the controller)?
Good answer covers: without eager loading, each course would issue a separate query to fetch its tutors (N+1); proof requires either a query-count assertion, a tool like the bullet gem, or subscribing to ActiveSupport::Notifications for sql.active_record in a test.

-----------------------------------------------------------------------------------------------------------------------------------
5. Why does Tutor not have its own uniqueness validation for email, relying instead on logic inside Course? What breaks if someone later adds a direct "create tutor" endpoint?
Good answer covers: acknowledges the coupling; recognizes a direct-tutor-creation path would skip the Course-level check and fall through to a raw DB uniqueness violation instead of a clean validation error — tests whether this was a deliberate, understood trade-off or an oversight.

-----------------------------------------------------------------------------------------------------------------------------------
6. You return 400 for too many nested tutors but 422 for a tutor with a bad email. What's the actual distinction you're drawing between those two status codes?
Good answer covers: 400 = structurally malformed/invalid request (an exception, not a validation failure — the request itself violates a hard limit); 422 = well-formed request that fails business/semantic validation. Weak candidates will not have a crisp distinction and will say "I just picked one."

-----------------------------------------------------------------------------------------------------------------------------------
7. Your base_controller rescues StandardError first in the file, then more specific exceptions like RecordNotUnique afterward. When a RecordNotUnique is actually raised, which handler runs, and why doesn't the generic one win since it was declared first?
Good answer covers: Rails' rescue_from (via ActiveSupport::Rescuable) matches by exception ancestry across all registered handlers and picks the most specific/most-recently-declared match, not simply "first declared" — this is the kind of internals question that separates "it worked" from "I know why it worked."

-----------------------------------------------------------------------------------------------------------------------------------
8. Two identical POST /courses requests for the same course name land at the database at nearly the same instant. Trace exactly what happens to each one, end to end.
Good answer covers: both may pass the in-app Rails validation (neither sees the other's uncommitted row); both attempt INSERT; the DB's unique index on LOWER(name) lets exactly one succeed; the other raises ActiveRecord::RecordNotUnique, caught by rescue_from, resulting in a 409.

-----------------------------------------------------------------------------------------------------------------------------------
9. Why cap per_page at 100 instead of letting clients request any page size? What's the actual failure mode you're preventing?
Good answer covers: unbounded LIMIT risk (memory/response-size blowup, accidental or deliberate resource exhaustion), not a theoretical concern — a client (or bot) requesting per_page=1000000 would force serialization of the entire table.

-----------------------------------------------------------------------------------------------------------------------------------
10. Why active_model_serializers instead of Jbuilder or just calling .as_json with include:? What would you lose or gain switching to one of those?
Good answer covers: AMS gives declarative, reusable serializer objects with consistent root-key behavior and easy association control; Jbuilder gives more rendering flexibility per-view at the cost of more boilerplate; as_json is fastest to write but leaks serialization concerns into controllers/models. Tests whether the gem choice was a reasoned pick or copied boilerplate.

==========================================================================================================
3. Walk me through what happens at the database level when you POST a course with two tutors. How many INSERT statements run, and in what transaction?
Good answer: one INSERT for the course, then one INSERT per tutor, all wrapped in a single implicit transaction because of accepts_nested_attributes_for — Rails automatically wraps autosave-association saves in a transaction. Should be able to explain why the rollback spec passes.

-----------------------------------------------------------------------------------------------------------------------------------
4. Your render_record_not_unique handler parses exception.cause&.message and string-matches on index names. Why not catch the uniqueness violation earlier, at the Rails validation level, and avoid this entirely?
Good answer: explains defense-in-depth — model-level uniqueness validation has a TOCTOU (time-of-check-to-time-of-use) race under concurrent requests, so the DB constraint is the real guarantee, and the rescue handler exists specifically to translate that lower-level DB exception into a clean API error instead of a 500. Bonus points if they admit this path isn't covered by a test and discuss how they'd test it (e.g., forcing a race or bypassing the validation).

-----------------------------------------------------------------------------------------------------------------------------------
5. Your GET /courses uses Course.includes(:tutors). What would happen to the query count if you used Course.eager_load(:tutors) instead? When would you reach for one over the other?
Good answer: includes uses a separate query (or decides to LEFT JOIN depending on whether conditions reference the association) while eager_load always forces a LEFT OUTER JOIN in a single query; includes is generally preferred unless you need to filter/order on the associated tables columns, in which case the implicit join might not pick up the condition correctly and eager_load (or explicit references) is needed.

-----------------------------------------------------------------------------------------------------------------------------------
8. You chose not to build a Form Object / service object for course creation, and left a comment about it. At what point — more fields, more cross-model logic, async side effects — would you change that decision?
Good answer: a thoughtful answer naming concrete triggers (e.g., multiple models beyond two, needing to fire notifications/jobs post-creation, multi-step validation spanning unrelated records, wanting to reuse the same creation logic from multiple controllers/contexts) shows they are not just avoiding abstraction reflexively but have a mental model of when it earns its cost.

-----------------------------------------------------------------------------------------------------------------------------------
9. Why did you choose request specs over controller specs for the API tests, and model specs for validations rather than testing everything through the API?
Good answer: request specs exercise the full stack (routing, middleware, params parsing) closer to real usage and controller specs are effectively deprecated/discouraged in modern Rails testing guidance; model specs are faster and more precise for validation logic, and testing every validation edge case only through slow full-stack request specs would be redundant and slower. Tests whether the test architecture was a deliberate choice.

-----------------------------------------------------------------------------------------------------------------------------------
10. Your CORS config allows * origins by default outside production but restricts to an explicit allowlist in production. What is the actual risk of a wildcard CORS origin, and why is it acceptable in dev but not prod?
Good answer: explains wildcard CORS + credentialed requests (cookies/auth headers) is dangerous because any origin could make authenticated cross-origin requests on behalf of a user; for a token-based JSON API with no cookie-based session, the practical risk is lower but still worth restricting in production to limit which domains can call the API at all. Tests whether the CORS config was copy-pasted or actually reasoned about.


==========================================================================================================
Walk me through why rescue_from StandardError is registered first in base_controller.rb but more specific rescues still take priority. Do you know why that works, or did it just happen to work?

You used tutors.target.select(&:new_record?) instead of tutors.select(&:new_record?) in the uniqueness validation — why? What would change if you called tutors directly here?

Your comment about the TOCTOU race on uniqueness and the RecordNotUnique rescue — walk me through exactly how two concurrent requests creating the same course name would play out, step by step, including what the user of each request actually sees.
Was allowing a course to be created with zero tutors a deliberate decision, or did it just not come up? How would you have handled it either way, and why?
If this API needed a background-job-based bulk tutor import (as you noted in your comment), what would change in the current model/controller design to support both the synchronous and background paths cleanly?

Why did you choose to log only exception.class and exception.message on a 500, and not the backtrace? How would you debug a production incident with only what is currently logged?

The CORS config defaults to a specific personal domain in production if ALLOWED_ORIGINS isn't set. What's the risk there, and how would you change it for a real multi-tenant/production deploy?

Why did you choose Active Model Serializers over jbuilder or plain as_json, given the Gemfile had jbuilder commented out as the default option?

Talk me through the trade-off note you left about not extracting a Form Object — at what point (what additional requirement) would you actually make that extraction?

What would you test first if you had one more hour and RSpec was not off the table?

==========================================================================================================

render_record_not_unique parses exception.cause&.message to figure out which index was violated. What happens if the pg gem or Postgres changes that error string format? How would you make this more robust?

The current implementation is fragile because it depends on the exact wording of a database error message. If PostgreSQL or the pg gem changes that format, our application might fail to identify the violated constraint and return a generic error.

To make it more robust, I would extract the constraint name from PostgreSQL's structured diagnostic information instead of parsing the error message. The pg gem exposes the constraint name through the PostgreSQL result's diagnostic fields.

I would also keep the mapping between constraint names and user-friendly field names centralized, and handle cases where the diagnostic information is unavailable.

This makes the error handling less dependent on implementation-specific error messages and easier to maintain.



If I asked you to add a PATCH /api/v1/courses/:id to update a course's tutors, what would break or need rethinking in your current uniqueness-validation approach?'

==========================================================================================================

Walk me through why you moved email uniqueness off Tutor and onto Course. What happens if we add a TutorsController tomorrow?

tutors_have_unique_emails builds Tutor.where("LOWER(email) IN (?)", emails) — walk me through why this is safe from SQL injection, and whether you considered a citext column or a DB-level case-insensitive constraint instead of raw SQL LOWER() indexes.


If this API needed to support 10,000 courses and 50 tutors each, what's the first thing you'd look at — indexes, query patterns, or something else?

==========================================================================================================
"Walk me through what happens when a client calls GET /api/v1/courses with ?per_page=5. What response do they actually get?" (Tests whether they have run it since submitting, and whether they can self-diagnose the Pagy bug live.)

"If this course catalog needed to support 10 million courses, what would break first, and what would you change?"


"If you had to add an update or destroy endpoint for a single Tutor tomorrow, what would you need to revisit given how validation is currently structured?"


==========================================================================================================
1. Walk me through what happens, step by step, when a POST request includes 2 valid tutors and 1 tutor with a missing email. Why does the whole request fail instead of saving the 2 valid tutors?
Good answer should cover: accepts_nested_attributes_for builds all tutor records in memory first; course.save triggers validation on the course and (by default) all its associated new records; if any fail, the whole save returns false and nothing is persisted — this is a single transaction under the hood even though they never wrote ActiveRecord::Base.transaction explicitly. Distinguishes genuine understanding from "I called accepts_nested_attributes_for because a tutorial told me to."

-----------------------------------------------------------------------------------------------------------------------------------
2. Your tutors_have_unique_emails validation reads tutors.target.select(&:new_record?) instead of tutors.select(&:new_record?). What is the difference, and why did you choose .target?
Good answer should cover: tutors (without .target) can trigger a DB load of the association if it isn't already loaded; .target reads only what's currently in memory, avoiding an unnecessary query during validation. This is explicitly commented in their own code — tests whether they understand their own comment or just wrote it defensively.

-----------------------------------------------------------------------------------------------------------------------------------
3. You removed email-uniqueness validation from the Tutor model and moved it to Course, citing an N+1 problem. What exactly was N+1 about validating uniqueness on the Tutor model directly?
Good answer should cover: if uniqueness were validated per-tutor via the standard validates_uniqueness_of, each of the N nested tutors being created would fire its own SELECT to check uniqueness — N queries for N tutors — versus their solution, which does one batched Tutor.where(email: emails_array) query for the whole set.

-----------------------------------------------------------------------------------------------------------------------------------
4. Why does your test simulate PG::UniqueViolation → ActiveRecord::RecordNotUnique with a stub instead of actually triggering a real race condition?
Good answer should cover: a genuine race condition requires two concurrent requests to both pass application-level validation before either commits — not reliably reproducible in a synchronous request-spec. Stubbing the exception path is a pragmatic way to test "does my rescue_from correctly interpret and respond to this exception" without needing real concurrency. Tests whether they understand why they could not test this for real, versus just mimicking a pattern.

-----------------------------------------------------------------------------------------------------------------------------------
5. Why did you add a unique index on LOWER(name) instead of just adding unique: true on the name column directly?
Good answer should cover: Postgres unique: true on a plain column is case-sensitive; "Ruby" and "ruby" would both be allowed, bypassing the models case_sensitive: false uniqueness validation under concurrent writes. The functional index on LOWER(name) is what actually makes the DB-level guarantee match the model-level intent.

-----------------------------------------------------------------------------------------------------------------------------------
6. Your index endpoint uses Course.includes(:tutors). What would happen to the SQL if you used Course.joins(:tutors) instead, and when would you reach for joins over includes?
Good answer should cover: joins would INNER JOIN and silently drop courses with zero tutors (since you tested this case explicitly, they should notice the conflict); joins is for filtering/conditions on the association, includes/preload is for avoiding N+1 when you need to display the association.

-----------------------------------------------------------------------------------------------------------------------------------
7. What is actually enforcing that a Tutor can only belong to one Course in your schema — is it the belongs_to :course line, or something else?
Good answer should cover: belongs_to just declares the Ruby-level association; the real one-tutor-one-course constraint is structural — course_id is a single foreign key column on tutors, not a join table — so a tutor physically cannot reference more than one course.

-----------------------------------------------------------------------------------------------------------------------------------
8. If I asked you to also support "update a course's tutors" (add/remove tutors from an existing course), what would you need to change about accepts_nested_attributes_for and your strong params, and what new failure mode would you need to test?
Good answer should cover: needs allow_destroy: true (currently false, confirmed by their own course_spec.rb test asserting allow_destroy(false)), needs :id permitted in tutors_attributes for Rails to know which record to update vs. create, and the new failure mode is a tutor id belonging to a different course being spoofed in the request (mass-assignment-adjacent security concern).

-----------------------------------------------------------------------------------------------------------------------------------
9. Your per_page param clamps to a max of 100 and falls back to 20 on invalid input, but you do not validate page the same way in the controller — Pagy's own error handling catches that instead. Why the asymmetry?'  

Good answer should cover: per_page is their own application-level parameter with their own business rule (a max cap), so they wrote custom clamping logic for it; page is Pagy's own parameter, and Pagy already raises a typed Pagy::VariableError for invalid values, which they chose to catch centrally in BaseController rather than reimplement. Tests whether they understand why they didn't write redundant validation for something a library already handles.

-----------------------------------------------------------------------------------------------------------------------------------
10. Walk me through why RuboCop and Brakeman are both in your CI pipeline, not just RSpec. What would each one have caught that the other would not?
Good answer should cover: RuboCop catches style/consistency issues, not bugs; Brakeman performs static security analysis for things like SQL injection, mass assignment, or unsafe redirects — a clean test suite says nothing about security posture, and a security scanner says nothing about code style. Tests whether the CI setup was a copy-pasted Rails default they do not understand, or a deliberate choice.


  ======================================================

  Since we support nested attributes for Tutors, an update request can contain both existing Tutors and new Tutors. I would normalize all submitted emails and check for duplicates within the submitted collection first. Then I would query the database for matching emails while excluding the IDs of existing Tutors being updated. This prevents a Tutor from conflicting with its own existing email while still detecting conflicts with other records. Finally, I would rely on a case-insensitive unique database index as the last line of defense against concurrent requests.

  existing_tutor_ids = tutors.map(&:id).compact

  existing_emails = Tutor
    .where("LOWER(email) IN (?)", emails)
    .where.not(id: existing_tutor_ids)

    -----------
  update_only ka use primarily has_one association ke saath hota hai. Ye control karta hai ki nested attributes existing associated record ko update karein ya nahi, jab uska ID provide nahi kiya gaya ho.

-------------

  I would first inspect Rails development logs to identify SQL queries executed by the GET endpoint. For automated measurement, I would subscribe to sql.active_record using ActiveSupport::Notifications and count relevant SQL events. I would then write request specs with multiple Courses and associated Tutors to verify that query count remains approximately constant as the number of Courses increases. I would also use Bullet to detect N+1 queries.

---------------
  duplicate(conflict) - 409
  Missing record (Not found) - 404
  validation failre(invalid) - 422
  invalid request/bad request - 400 
  created -  201
  ok - 200

-----------------
  I would implement idempotency using an Idempotency-Key header. The client generates a unique key for each logical POST request and reuses it for retries. On the server, I would store the key, a request-payload digest, and the completed response. I would enforce uniqueness at the database level to handle concurrent requests and use a transaction to coordinate Course creation, nested Tutor creation, and idempotency-result persistence. If the same key and payload are received again, I would return the stored response instead of creating another Course. I would also reject reuse of the same key with a different payload.

-----------------

  1. Shallow copy
Shallow copy mein naya outer object banta hai, lekin uske andar ke nested objects ke references share hote hain.

original = [[1, 2], [3, 4]]
copy = original.dup

copy[0] << 99
copy << [5, 9]

puts original.inspect
# [[1, 2, 99], [3, 4]]

puts copy.inspect
# [[1, 2, 99], [3, 4], [5, 9]]

2. Deep copy
Deep copy mein outer object ke saath nested mutable objects bhi independently copy kiye jaate hain.
Ruby mein Array aur Hash ke liye koi universal built-in deep_dup method available nahi hai, lekin Rails mein deep_dup available hai.

original = [[1, 2], [3, 4]]
copy = original.deep_dup

copy[0] << 99

puts original.inspect
# [[1, 2], [3, 4]]

puts copy.inspect
# [[1, 2, 99], [3, 4]]

------------

I prefer composition over inheritance when a class needs another object's behavior without having a genuine is-a relationship. Composition reduces tight coupling, allows dependencies to be replaced at runtime, and makes unit testing easier. I use inheritance when the subtype relationship is meaningful and the child can safely substitute for its parent.'
-----------
Overusing Rails concerns can create hidden dependencies, scatter business logic across multiple files, and make callbacks and method lookup harder to trace. Concerns are useful for cohesive, reusable behavior shared across models, but they should not become containers for unrelated business logic. For complex workflows, I prefer service objects with explicit dependencies. In my Course-Tutor API, I would keep validations and associations in the models and move complex multi-step creation logic into a service only when the complexity justifies it.
-----------
Devise is a Rails authentication solution built on top of Warden. It provides modules for password authentication, registration, password recovery and other authentication features. During login, Devise finds the user, verifies the submitted password against the stored password digest, and establishes an authenticated identity. In browser applications, this is commonly maintained through a session. For APIs, I would explicitly choose session-based authentication or a token-based approach, depending on the client and security requirements
----------
OAuth 2.0 is an authorization framework that defines how clients obtain access to protected resources, while JWT is a token format used to carry claims. OAuth access tokens can be JWTs or opaque tokens. If I am building a Rails API, I would choose OAuth 2.0 when delegated authorization and third-party access are required. I would consider JWT when a signed, self-contained bearer token fits the authentication architecture. For user sign-in through an identity provider, I would use OpenID Connect rather than OAuth 2.0 alone.
-----------

For a large PostgreSQL table, I would prefer CREATE INDEX CONCURRENTLY to minimize write blocking. In Rails, I would use algorithm: :concurrently with disable_ddl_transaction!, because concurrent index creation cannot run inside a transaction block. Before deployment, I would inspect the query plan, check for existing indexes and, for unique indexes, identify duplicate data. After deployment, I would verify index validity and monitor database load. If the migration fails, I would check for an invalid index before retrying.
Production mein low-traffic window aur monitoring plan karna best practice hai.

------------------
For a large table, I would use the Expand-Migrate-Contract pattern. First, I would add the new nullable column without removing the old one. Then I would deploy backward-compatible application code that writes to both columns and backfill historical records in small, resumable batches. After verifying consistency, I would switch reads to the new column, monitor the application, and remove the old column in a later deployment. For data migrations, I would avoid long transactions, account for concurrent writes, and ensure that each batch can safely be retried.