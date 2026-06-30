/*
===============================================================================================
                       ELASTICSEARCH with NODE.JS
===============================================================================================
(Mirrors my elastic_search.rb Rails notes. The CONCEPTS are 100% identical — ES doesn't care
which language talks to it; it's a REST engine. Only the client changes: elasticsearch-model gem
-> @elastic/elasticsearch npm client. The multi-model "global search" scenario at the end is the
same Flipkart-style question from my Rails notes, re-answered in Node.)
*/

/*
-----------------------------------------------------------------------------------------------
Q1: What is Elasticsearch and why use it alongside Postgres/Mongo?
-----------------------------------------------------------------------------------------------
Answer -> Elasticsearch is a distributed, REST-based search and analytics engine built on Apache
Lucene. It's optimized for full-text search, typo tolerance, relevance ranking, autocomplete,
complex filtering, and aggregations — things relational DBs do poorly at scale.

It does NOT replace Postgres/Mongo; it COMPLEMENTS them. The database stays the SOURCE OF TRUTH;
ES holds a separate, search-optimized INDEX of that data. The two are EVENTUALLY CONSISTENT — you
write to the DB, then sync to ES (often async via a job), so there's a small indexing delay.

  "In a typical Node app, Postgres/Mongo is the primary store, but it's not built for fuzzy
   search, relevance scoring, or multi-field text search. For an e-commerce search where users
   type partial words, misspellings, and combine filters (price, category, rating), Elasticsearch
   handles that efficiently. The DB remains authoritative; ES is the searchable index, kept in
   sync via background jobs." (Word-for-word my Rails answer — the reasoning is language-agnostic.)
*/

/*
-----------------------------------------------------------------------------------------------
Q2: Core ES vocabulary (table-stakes)
-----------------------------------------------------------------------------------------------
Answer ->
  INDEX     -> like a table; stores documents. Optimized for search, not relations.
  DOCUMENT  -> a JSON object = one record (a product, a user). Schema-flexible.
  MAPPING   -> the schema/field types for an index (text vs keyword vs number vs date).
  ANALYZER  -> processes text before indexing/searching: tokenize, lowercase, remove stop words,
               stemming ("Running" -> "run"). Drives search accuracy.
  text vs keyword -> `text` is analyzed (full-text search); `keyword` is exact-match/filter/sort
               (ids, enums, statuses). Choosing wrong here is the #1 ES beginner mistake.
  SHARD/REPLICA -> how ES distributes + replicates an index across nodes for scale + HA.
  FUZZY query -> typo tolerance via edit distance ("iphnoe" still matches "iphone").
  AGGREGATIONS -> analytics: counts by category, avg price, grouping — fast + powerful.
*/

/*
-----------------------------------------------------------------------------------------------
Q3: The Node client + basic indexing/search
-----------------------------------------------------------------------------------------------
Answer -> Use the official @elastic/elasticsearch client.

  const { Client } = require('@elastic/elasticsearch');
  const es = new Client({ node: process.env.ELASTICSEARCH_URL });

  // create an index with an explicit mapping (do this, don't rely on dynamic mapping in prod)
  await es.indices.create({
    index: 'products',
    mappings: {
      properties: {
        name:        { type: 'text' },                 // analyzed -> full-text
        description: { type: 'text' },
        category:    { type: 'keyword' },               // exact filter
        price:       { type: 'float' },
        rating:      { type: 'float' },
      },
    },
  });

  // index a document (after the DB write — DB is source of truth)
  await es.index({ index: 'products', id: String(product.id), document: {
    name: product.name, description: product.description,
    category: product.category, price: product.price, rating: product.rating,
  }});

  // search (multi_match across fields + a filter)
  const result = await es.search({
    index: 'products',
    query: {
      bool: {
        must:   { multi_match: { query: 'iphone 15', fields: ['name^3', 'description'] } }, // name boosted
        filter: [{ range: { price: { lte: 1000 } } }, { term: { category: 'smartphones' } }],
      },
    },
  });
  const hits = result.hits.hits.map(h => ({ id: h._id, score: h._score, ...h._source }));
*/

/*
-----------------------------------------------------------------------------------------------
Q4: Keeping ES in sync with the DB (the eventual-consistency pattern)
-----------------------------------------------------------------------------------------------
Answer -> The DB is the source of truth; on every create/update/delete I sync the change to ES,
ideally ASYNCHRONOUSLY so indexing never slows the request.

  Options (best-first):
   - BACKGROUND JOB: after the DB write, enqueue a BullMQ job that (re)indexes the document. Keeps
     the request fast and retries on ES hiccups. (This is the Sidekiq approach from my Rails notes.)
   - CHANGE DATA CAPTURE: stream DB changes (Postgres logical decoding / Mongo change streams,
     Debezium/Logstash) into ES — decoupled and reliable at scale.
   - BULK API for big reindexes: es.bulk / the helpers.bulk to index thousands of docs per call
     (the same batch-instead-of-one-by-one principle as my EDI import).

  // reindex worker (idempotent — re-running just overwrites the doc)
  new Worker('es-index', async (job) => {
    const product = await Product.findById(job.data.id);
    if (!product) return es.delete({ index: 'products', id: job.data.id }).catch(() => {});
    await es.index({ index: 'products', id: String(product.id), document: toDoc(product) });
  }, { connection });

  "Eventual consistency means the index may lag the DB by moments after a write; I accept that
   trade-off for search performance and scalability, and I sync via background jobs so writes stay fast."
*/

/*
-----------------------------------------------------------------------------------------------
Q5: Why not just Postgres/Mongo full-text search?
-----------------------------------------------------------------------------------------------
Answer -> Postgres FTS (tsvector/GIN) and Mongo text indexes are fine for MODERATE datasets and
simple needs — and they avoid extra infrastructure. But Elasticsearch wins when you need:
  - relevance scoring + boosting, customizable analyzers, fuzzy/typo tolerance, autocomplete,
  - powerful aggregations, and horizontal scale for large, search-heavy apps.

  "For a small app I'd start with Postgres full-text search to avoid the operational cost. I'd
   reach for Elasticsearch when search becomes a core feature — e-commerce, job portals — and I
   need relevance, fuzziness, and scale."
*/

/*
-----------------------------------------------------------------------------------------------
Q6: When NOT to use ES / downsides
-----------------------------------------------------------------------------------------------
Answer -> Skip it when the dataset is small and search is simple. Downsides:
  - Operational complexity: cluster management, memory/JVM tuning, mappings, reindexing strategy.
  - Eventual consistency: unsuitable as the system of record for strict, real-time financial data.
  - Extra infra cost + another thing to monitor/keep in sync.
  "Only adopt ES when advanced search or scale is genuinely needed; otherwise it's complexity you
   pay for without benefit."
*/

/*
-----------------------------------------------------------------------------------------------
Q7: THE SCENARIO — Flipkart-style search across multiple models with no associations (Node version)
-----------------------------------------------------------------------------------------------
Answer -> (This is the exact multi-model search question from my Rails notes.) When search data
comes from several unrelated models (Product, Brand, Category) with no joins, I would NOT use SQL
UNIONs. I'd build ONE unified Elasticsearch index where documents from all models share a common
searchable structure, with a `recordType` field to distinguish them.

  Design:
   - A single index `global_search`; every indexed doc has { name, description, recordType, recordId }.
   - DB stays source of truth; on any change to Product/Brand/Category, a background job upserts
     that record's doc into global_search.
   - A search service queries the one index and returns mixed results ranked by relevance.

  // index docs from any model into the shared index
  function toGlobalDoc(record, type) {
    return { name: record.name ?? record.title, description: record.description ?? '',
             recordType: type, recordId: String(record.id) };
  }
  await es.index({ index: 'global_search', id: `${type}:${record.id}`, document: toGlobalDoc(record, type) });

  // unified search service (the GlobalSearchService equivalent)
  async function globalSearch(q) {
    const res = await es.search({
      index: 'global_search',
      query: { multi_match: { query: q, fields: ['name^2', 'description'] } },
    });
    return res.hits.hits.map(h => h._source);   // e.g. Product "iPhone 15", Brand "Apple", Category "Smartphones"
  }

  // Express route
  app.get('/search', async (req, res) => res.json(await globalSearch(req.query.q)));

  "One shared index with a recordType discriminator gives relevance ranking, typo tolerance,
   autocomplete, and filtering across unrelated models — far better than SQL UNIONs, and it scales.
   The DB stays authoritative and ES is synced asynchronously." (Same architecture as my Rails
   Searchable concern, just with the Node client + a BullMQ indexer instead of model callbacks.)
*/

module.exports = {};
