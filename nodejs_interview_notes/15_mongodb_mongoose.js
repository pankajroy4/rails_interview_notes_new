/*
===============================================================================================
                              MONGODB + MONGOOSE
===============================================================================================
HUGE advantage for me: I already used MongoDB + Mongoid on the Horizon claim platform. Mongoose
is the Node ODM and is conceptually almost identical to Mongoid. I can speak from real
experience here — lean into the Horizon story.
*/

/*
-----------------------------------------------------------------------------------------------
Question 1: MongoDB basics (and when to choose it over SQL)
-----------------------------------------------------------------------------------------------
Answer -> MongoDB is a document database: data is stored as flexible BSON documents (JSON-like)
in collections, instead of rows in tables. No fixed schema at the DB level.

  RELATIONAL (Postgres)      MONGODB
  ------------------------   ---------------------------
  database                   database
  table                      collection
  row                        document (BSON/JSON)
  column                     field
  JOIN                       embedding OR $lookup
  schema enforced by DB      schema flexible (enforced in app via Mongoose)

  Choose MongoDB when: flexible/evolving schemas, document-shaped data, high write throughput,
  denormalized reads, horizontal scaling via sharding. Choose SQL when: strong relational
  integrity, complex joins/transactions, reporting. (Horizon used Mongo for the claim documents
  + the ~2M EDI part records — document-shaped, high-volume import.)
*/

/*
-----------------------------------------------------------------------------------------------
Question 2: What is Mongoose? (= Mongoid for Node)
-----------------------------------------------------------------------------------------------
Answer -> Mongoose is an ODM (Object Document Mapper) that adds the structure MongoDB lacks:
schemas, validation, middleware (hooks), population (joins), and a clean model API. Mongoid did
exactly this for Rails — so this is familiar territory.

  const mongoose = require('mongoose');
  await mongoose.connect(process.env.MONGO_URL);

  const userSchema = new mongoose.Schema({
    name:  { type: String, required: true },
    email: { type: String, required: true, unique: true, lowercase: true },
    role:  { type: String, enum: ['user', 'admin'], default: 'user' },
    age:   { type: Number, min: 0 },
  }, { timestamps: true });               // adds createdAt / updatedAt

  const User = mongoose.model('User', userSchema);
*/

/*
-----------------------------------------------------------------------------------------------
Question 3: CRUD with Mongoose
-----------------------------------------------------------------------------------------------
Answer ->
  const user = await User.create({ name: 'Ann', email: 'a@b.com' });

  const u    = await User.findById(id);
  const one  = await User.findOne({ email: 'a@b.com' });
  const list = await User.find({ role: 'user' })
                         .sort({ createdAt: -1 })
                         .limit(20).skip(0)
                         .select('name email')        // projection (only these fields)
                         .lean();                       // return plain JS objects (faster)

  await User.updateOne({ _id: id }, { $set: { name: 'Annie' } });
  const updated = await User.findByIdAndUpdate(id, { name: 'Annie' }, { new: true, runValidators: true });
  await User.deleteOne({ _id: id });

  .lean() is an important perf tip: skips hydrating full Mongoose documents (with getters/
  setters/methods) and returns plain objects — much faster for read-only queries.
*/

/*
-----------------------------------------------------------------------------------------------
Question 4: Embedding vs Referencing (the core Mongo data-modeling decision)
-----------------------------------------------------------------------------------------------
Answer -> Two ways to model relationships:

  EMBEDDING (subdocuments inside the parent doc):
    - Great for data that's read together and "owned" by the parent (e.g. an order's line items,
      a claim's status history). One read gets everything; atomic updates within a doc.
    - Downside: documents can grow large; the 16MB document size limit; duplication if shared.

  REFERENCING (store an ObjectId pointing to another collection) + populate():
    - Great for many-to-many, large/independent, or shared entities (users, products).
    - Needs a second query / $lookup (or .populate()) to resolve — Mongo's version of N+1.

  Rule of thumb: "embed what you read together and own; reference what's shared or unbounded."
  Mongo modeling is access-pattern-driven (model for your queries), unlike normalized SQL.
*/

/*
-----------------------------------------------------------------------------------------------
Question 5: populate() — the "join" (and its N+1 trap)
-----------------------------------------------------------------------------------------------
Answer ->
  const postSchema = new mongoose.Schema({
    title:  String,
    author: { type: mongoose.Schema.Types.ObjectId, ref: 'User' },   // reference
  });

  const posts = await Post.find().populate('author', 'name email');   // resolves authors

  populate runs an extra query (an $in lookup) to fetch the referenced docs. Done in a loop it
  becomes N+1; done once on a list it batches the ids into a single $in — so populate the LIST,
  don't populate inside a per-item loop. Same N+1 discipline as ActiveRecord includes.
*/

/*
-----------------------------------------------------------------------------------------------
Question 6: Aggregation pipeline (the powerful part — Mongo's "SQL group by/join")
-----------------------------------------------------------------------------------------------
Answer -> The aggregation pipeline transforms documents through stages ($match, $group, $sort,
$lookup, $project, $unwind ...). It's how you do analytics/reporting in Mongo.

  const result = await Order.aggregate([
    { $match: { status: 'paid', createdAt: { $gte: start } } },     // filter (WHERE)
    { $group: { _id: '$customerId', total: { $sum: '$amount' }, count: { $sum: 1 } } }, // GROUP BY
    { $sort: { total: -1 } },
    { $limit: 10 },
    { $lookup: { from: 'customers', localField: '_id', foreignField: '_id', as: 'customer' } }, // JOIN
  ]);

  Pipelines run in the DB (efficient). Put $match/$sort early and on indexed fields so the DB
  can use indexes before the heavy stages.
*/

/*
-----------------------------------------------------------------------------------------------
Question 7: Mongoose middleware/hooks & virtuals (the Mongoid callbacks equivalent)
-----------------------------------------------------------------------------------------------
Answer ->
  // pre-save hook (like Rails before_save) — e.g. hash a password
  userSchema.pre('save', async function () {
    if (this.isModified('password')) this.password = await bcrypt.hash(this.password, 12);
  });

  // virtual (computed property, not stored)
  userSchema.virtual('fullName').get(function () { return `${this.first} ${this.last}`; });

  // instance + static methods
  userSchema.methods.isAdmin = function () { return this.role === 'admin'; };
  userSchema.statics.findByEmail = function (email) { return this.findOne({ email }); };

  These map directly onto Mongoid callbacks, scopes, and methods I already used in Horizon.
*/

/*
-----------------------------------------------------------------------------------------------
Question 8: bulkWrite — the Horizon 2M-record import, in Node
-----------------------------------------------------------------------------------------------
Answer -> This is my signature optimization story, retold for Node. In Rails/Mongoid I used
bulk upserts to go 24h -> 6min. The Mongoose equivalent:

  // Build unordered bulk upserts and batch them
  async function importParts(records) {
    const BATCH = 5000;
    for (let i = 0; i < records.length; i += BATCH) {
      const batch = records.slice(i, i + BATCH);
      const ops = batch.map((r) => ({
        updateOne: {
          filter: { partNumber: r.partNumber },
          update: { $set: r },
          upsert: true,
        },
      }));
      await Part.bulkWrite(ops, { ordered: false });   // ordered:false = independent docs,
      // a failure on one doesn't stop the rest, and the driver parallelizes better
    }
  }

  WHY it's fast (same reasons as my Rails answer):
   - bulkWrite sends MANY operations in ONE round trip instead of one query per record.
   - ordered:false lets the server process ops without stopping on the first error and improves
     throughput.
   - Batching keeps memory bounded; I'd STREAM the source EDI file (createReadStream + parser)
     so I never load 2M records into memory at once (see 06_streams_and_buffers.js).
   - Run it inside a BullMQ worker so it doesn't block the web process.
   - Ensure an index on the upsert filter field (partNumber) or every upsert does a full scan.

  Saying this confidently, with the index + ordered:false + streaming details, shows the
  optimization was real and that I understand WHY it worked — not just that it did.
*/

/*
-----------------------------------------------------------------------------------------------
Question 9: Indexes & transactions in Mongo (quick hits)
-----------------------------------------------------------------------------------------------
Answer ->
  - Indexes: userSchema.index({ email: 1 }, { unique: true }); compound indexes follow the
    ESR rule (Equality, Sort, Range) for field order. Without indexes, queries do COLLSCANs.
  - explain('executionStats') shows whether a query used an index (IXSCAN) or scanned (COLLSCAN).
  - Transactions: supported on replica sets/sharded clusters since 4.0
    (session.startTransaction()), but the Mongo philosophy prefers modeling so a single-document
    update is atomic (embedding) rather than relying on multi-doc transactions.
  - The 16MB document size limit means unbounded embedded arrays are an anti-pattern (e.g. don't
    embed millions of events in one doc — reference them).
*/

module.exports = {};
