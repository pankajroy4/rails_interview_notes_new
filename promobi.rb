
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

======================================================================================================================================================================
-----------------------------------------------------------------------------------------------------------------------------------
2. Your courses.name and tutors.email columns do not have null: false at the database level, but you did add unique DB indexes. Why the inconsistency, and what is actually enforcing presence right now?
Good answer: acknowledges that only the Rails validation enforces presence, that it can be bypassed, and can reason about why they added the DB constraint for uniqueness (race conditions) but did not extend the same reasoning to presence — ideally recognizing it as an oversight rather than deflecting.

-----------------------------------------------------------------------------------------------------------------------------------
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


=====================================================================================================================================================================

Explain tutors.target.select(&:new_record?) in Course#tutors_have_unique_emails — what would change if you used tutors.select(&:new_record?) instead, and why did you avoid that?

You left a comment saying that at scale you would move tutor creation to a background job with bulk inserts. Walk through what that implementation would actually look like — what happens to the APIs response/status code if creation becomes async?

Your pagination clamps per_page to [1,100]. What is your reasoning for that upper bound, and what would break if a client requested per_page=100000 without the clamp?
If two identical POST requests for the same course name land at the same instant, walk me through exactly what happens at each layer (validation, DB constraint, controller) and which one you are relying on to prevent a duplicate.

=======================================================================================================================================================================

-----------------------------------------------------------------------------------------------------------------------------------
2. In Course#tutors_have_unique_emails you wrote tutors.target.select(&:new_record?) instead of tutors.select(&:new_record?). Why?
Good answer covers: .target reads only what is already built/loaded in memory without triggering an extra DB query on the association — relevant because calling tutors on a persisted course would otherwise force-load existing children from the DB during validation.

-----------------------------------------------------------------------------------------------------------------------------------
10. Why active_model_serializers instead of Jbuilder or just calling .as_json with include:? What would you lose or gain switching to one of those?
Good answer covers: AMS gives declarative, reusable serializer objects with consistent root-key behavior and easy association control; Jbuilder gives more rendering flexibility per-view at the cost of more boilerplate; as_json is fastest to write but leaks serialization concerns into controllers/models. Tests whether the gem choice was a reasoned pick or copied boilerplate.


=================================================================================================================================================================
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

===================================================================================================================================================================

Walk me through tutors_have_unique_emails in course.rb — why tutors.target.select(&:new_record?) instead of just tutors.select(&:new_record?)? What would change if you used the latter?

Why did you add rescue_from ActiveRecord::RecordNotUnique on top of the uniqueness validation? What's the failure mode you're protecting against, and why can not the validation alone catch it?

rescue_from StandardError is registered before rescue_from ActionDispatch::Http::Parameters::ParseError in base_controller.rb. Which handler actually fires for a ParseError, and why? What would happen if you added a new narrow rescue_from after the StandardError line by mistake?

Your 500 handler swallows everything via rescue_from StandardError. What does that do to your experience debugging in development? Was that a deliberate trade-off?

render_record_not_unique parses exception.cause&.message to figure out which index was violated. What happens if the pg gem or Postgres changes that error string format? How would you make this more robust?

The nested-attributes limit is 50. Is there any path, today or in a plausible near-future version of this API, where a course could end up with more than 50 tutors? Walk me through why or why not.

Why did not you introduce a service object for course creation? At what point (what additional requirement) would you reach for one?

If I asked you to add a PATCH /api/v1/courses/:id to update a course's tutors, what would break or need rethinking in your current uniqueness-validation approach?
Your courses_spec.rb request spec references routes (/api/v1/courses/index, /api/v1/courses/create) that don't exist in your app. Walk me through what happened there.

The CORS initializer defaults allowed_origins to "*" outside production. Is that something you would want to revisit before this went to a staging environment shared with other engineers?
=====================================================================================================================================================================

Walk me through why you moved email uniqueness off Tutor and onto Course. What happens if we add a TutorsController tomorrow?

What would happen today if a client POSTs a malformed JSON body? Have you checked? How would you make every error response guaranteed-JSON in production?

You wrote (in an earlier, now-removed comment) that you considered a Form Object pattern and rejected it for simplicity — what would make you reconsider that decision as the app grows? At what point does Course become "too fat"?

tutors_have_unique_emails builds Tutor.where("LOWER(email) IN (?)", emails) — walk me through why this is safe from SQL injection, and whether you considered a citext column or a DB-level case-insensitive constraint instead of raw SQL LOWER() indexes.

The original commit had a real password in database.yml. Talk me through what you'd do differently if this were a real production repo that had already been pushed with a secret in it.

dependent: :destroy is on Course has_many :tutors but there's no destroy endpoint yet. If you added one, what would you watch out for with a course that has 50 tutors?

Why rescue_from ActiveRecord::RecordNotUnique at all, given you already validate uniqueness in Ruby before saving? Walk me through the race condition this protects against.

If this API needed to support 10,000 courses and 50 tutors each, what's the first thing you'd look at — indexes, query patterns, or something else?

Why no authentication on the create endpoint — was that discussed as out of scope, or an oversight?

====================================================================================================================================================================
"Walk me through what happens when a client calls GET /api/v1/courses with ?per_page=5. What response do they actually get?" (Tests whether they have run it since submitting, and whether they can self-diagnose the Pagy bug live.)

What's the difference between Pagy's :items and :limit variables? How did you choose limit?" (Did they read Pagy's docs, or guess based on other gems like Kaminari?)

"Why did you move the tutor email uniqueness check off the Tutor model and onto Course as a custom validation, instead of just using uniqueness: true on Tutor#email?" (Verify this was deliberate, not accidental.)

"Is there a race condition in tutors_have_unique_emails? If so, what actually prevents bad data from landing in the DB?" (Checks if they understand their own defense-in-depth setup or got lucky.)

"Why did you add a catch-all route and a separate NotFoundController? What would happen without it?"

"What testing did you do manually before submitting — walk me through your verification process for the index and create endpoints."

"If this course catalog needed to support 10 million courses, what would break first, and what would you change?"

"Why :unprocessable_content instead of :unprocessable_entity?" (Confirms genuine Rails knowledge vs. coincidence/IDE autocomplete.)

"Was full CRUD (show/update/destroy) part of the original scope you were given, and if so, what did you cut and why, given the 3-day window?"

"The CORS config only allows GET/POST/OPTIONS — was that intentional given your current routes, or just copied from a template?"

====================================================================================================================================================================
"Walk me through hitting your own GET /courses endpoint — what does the actual JSON response look like? Did you check it before submitting?" (direct probe on the pagination bug and self-verification habits)

"Your index action builds a meta hash with page/pages/count. Where does that end up in the response, and why?" (tests whether they understand AMS adapters, or can diagnose it live if shown the empty response)

"What happens if a client sends per_page=-1 or per_page=abc? Walk me through the code path." (tests awareness of untrusted input)

"Why did you move email-uniqueness validation off Tutor and onto Course? What breaks if someone creates a Tutor directly without going through Course?" (tests whether the trade-off was deliberate and fully reasoned, or accidental)

"You handle ActiveRecord::RecordNotUnique in the controller by string-matching the Postgres index name in the exception message. What happens if that message format changes across Postgres versions, and is there a more robust way to get the violated constraint name?"

"You added a limit: 50 to accepts_nested_attributes_for and rescue TooManyRecords. What made you think to do that, and what would you pick that number based on?" (tests whether this was genuine production thinking or a lucky default)

"Why structure CORS to hard-fail at boot in production if ALLOWED_ORIGINS is missing, rather than defaulting to something safe?" (tests whether the fail-fast design was intentional)

"If you had to add an update or destroy endpoint for a single Tutor tomorrow, what would you need to revisit given how validation is currently structured?"

"Did you run rubocop or brakeman before submitting? What did they report?"

"Your final submission isn't committed to git — walk me through your workflow for this assignment."

====================================================================================================================================================================
Why a custom tutors_have_unique_emails validation instead of validates :email, uniqueness: true on Tutor — what specifically breaks with the simpler approach in a nested-attributes create?

Your course-name uniqueness is backed by a case-insensitive DB index; the tutor-email index is case-sensitive while your validation treats email case-insensitively. Walk through what happens with two concurrent requests creating Foo@x.com and foo@x.com.
render_record_not_unique always blames "Course's name" — what happens if the tutors-email index raises that same exception instead? How would you fix it?

GET /courses returns every course and every nested tutor, unpaginated. How does this behave at 100k courses, and what would you add?

You left the Form Object decision as an explicit comment — at what point would the complexity justify extracting it?

You mentioned background jobs + bulk inserts for tutor creation at scale — sketch how you'd handle partial validation failures in that batch.

database.yml has real-looking local credentials committed. What's your personal rule for what goes in that file vs. .env/credentials?

Was authentication/authorization intentionally out of scope, or an oversight? What would you add first for a real product?

rack-cors is in the Gemfile but the initializer is fully commented out — intentional, or missed?

A leftover request spec hits a nonexistent route (GET /courses/create) and a factory has course: nil that would fail validation — what is your pre-submission checklist, even when tests themselves are out of scope?


====================================================================================================================================================================
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
Good answer should cover: belongs_to just declares the Ruby-level association; the real one-tutor-one-course constraint is structural — course_id is a single foreign key column on tutors, not a join table — so a tutor physically cannot reference more than one course. Distinguishes "I know the Rails DSL" from "I understand why the schema shape itself enforces the business rule."

-----------------------------------------------------------------------------------------------------------------------------------
8. If I asked you to also support "update a course's tutors" (add/remove tutors from an existing course), what would you need to change about accepts_nested_attributes_for and your strong params, and what new failure mode would you need to test?
Good answer should cover: needs allow_destroy: true (currently false, confirmed by their own course_spec.rb test asserting allow_destroy(false)), needs :id permitted in tutors_attributes for Rails to know which record to update vs. create, and the new failure mode is a tutor id belonging to a different course being spoofed in the request (mass-assignment-adjacent security concern).

-----------------------------------------------------------------------------------------------------------------------------------
9. Your per_page param clamps to a max of 100 and falls back to 20 on invalid input, but you do not validate page the same way in the controller — Pagy's own error handling catches that instead. Why the asymmetry?'

Good answer should cover: per_page is their own application-level parameter with their own business rule (a max cap), so they wrote custom clamping logic for it; page is Pagy's own parameter, and Pagy already raises a typed Pagy::VariableError for invalid values, which they chose to catch centrally in BaseController rather than reimplement. Tests whether they understand why they didn't write redundant validation for something a library already handles.

-----------------------------------------------------------------------------------------------------------------------------------
10. Walk me through why RuboCop and Brakeman are both in your CI pipeline, not just RSpec. What would each one have caught that the other would not?
Good answer should cover: RuboCop catches style/consistency issues, not bugs; Brakeman performs static security analysis for things like SQL injection, mass assignment, or unsafe redirects — a clean test suite says nothing about security posture, and a security scanner says nothing about code style. Tests whether the CI setup was a copy-pasted Rails default they do not understand, or a deliberate choice.



