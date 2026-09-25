# Search and Indexing

## Why it matters

Almost har product ko eventually "is text ko match karne wali cheez dhoondho" chahiye hota hai — ek product catalog search karo, messages search karo, users search karo, search box mein autocomplete. Ek naive implementation (`LIKE '%query%'` relational table ke against) small scale pe kaam karta hai aur phir fail ho jaata hai: ye results ko relevance se rank nahi kar sakta, ye full table scan force karta hai (ya near-full scan even B-tree index ke saath, kyunki B-tree indexes ek column pe equality/range lookups ke liye bane hain, "kya is text ke blob mein ye word hai" ke liye nahi), aur iske paas "in words mein se kuch match karo, match kitna achha hai us se rank karo" ke liye koi vocabulary hi nahi. Elasticsearch jaise search engines exist hi isi liye karte hain ki scale pe full-text search solve kar sakein, aur unke neeche ki data structure (inverted index) samajhna hi tumhe unka behavior — indexing lag, relevance, sharding — reason karne deta hai, unhe black box treat karne ke bajaye.

Ye file typeahead/autocomplete bhi cover karti hai, jo ek alag problem hai (ek chhote, ranked set of strings ke against prefix matching, jo user ke type karte hi milliseconds mein answer hota hai) jo apne aap mein ek interview question ki tarah baar-baar aata hai.

## Regular database mein text search karne ki problem

Ek relational database ka index (typically ek B-tree) "find rows where `column = X`" ya "find rows where `column` is between X and Y" ke liye excellent hai, kyunki ek B-tree sorted keys store karta hai aur unhe binary-search kar sakta hai. Ye "find rows where ye large text column ye kuch words mein se ek *contain* karta hai, kitna achha match hai us se rank karo" answer karne ke liye nahi bana. Ek leading wildcard wali `LIKE '%word%'` query B-tree index bilkul use nahi kar sakti — database ko har row scan karni padti hai aur har ek check karna padta hai, jo rows ki count mein O(n) hai aur corpus badhne ke saath slower hota jaata hai.

Full-text search ko ek completely different structure chahiye: rows ko ek value se index karne ke bajaye, tum text ke *andar ke individual words* ko index karte ho, aur store karte ho ki har word kaun se documents mein appear karta hai. Wo structure inverted index hai.

## Inverted index: core data structure

Ek **forward index** documents → unme jo terms (words) hain unko map karta hai — ye basically... document khud hai, ya ek simple `doc_id -> [word1, word2, ...]` table. Ye wo cheez hai jo tum naturally banaoge, aur ye search ke liye useless hai: "kaunse documents mein 'redis' hai" answer karne ke liye, tumhe har document ki word list scan karni padegi.

Ek **inverted index** ise flip kar deta hai: ye har term → us term ko contain karne wale documents ki list (jise **postings list** kehte hain) map karta hai. Ye forward index ka "opposite" (inverse) hai, isiliye ye naam. Ye "kaunse documents mein ye word hai" ko ek full scan se ek single hash/tree lookup mein badal deta hai.

### Worked example

Chaar chhote documents:

```text
Doc 1: "redis is a fast cache"
Doc 2: "postgres is a durable database"
Doc 3: "redis is used as a cache and a queue"
Doc 4: "elasticsearch is a fast search database"
```

Step 1 — har document ko **tokenize** karo (words mein split karo, lowercase karo, usually common "stopwords" jaise "a," "is," "as," "and" strip karo — yahaan clarity ke liye omit kiye gaye hain but real system unhe drop ya down-weight karega):

```text
Doc 1: [redis, fast, cache]
Doc 2: [postgres, durable, database]
Doc 3: [redis, used, cache, queue]
Doc 4: [elasticsearch, fast, search, database]
```

Step 2 — **invert** karo: har term se us term wale doc IDs ki list tak ek map banao.

```text
cache         -> [1, 3]
database      -> [2, 4]
durable       -> [2]
elasticsearch -> [4]
fast          -> [1, 4]
postgres      -> [2]
queue         -> [3]
redis         -> [1, 3]
search        -> [4]
used          -> [3]
```

Step 3 — **query** karo. `"redis cache"` ke liye ek search (dono terms match karne wale documents dhoondo) ye ban jaata hai:

1. `redis` lookup karo → `[1, 3]`
2. `cache` lookup karo → `[1, 3]`
3. Dono postings lists ko intersect karo → `[1, 3]`

Koi document scan nahi hua. Poori query do hash lookups plus ek list intersection hai, aur ye fast rehta hai chahe corpus mein 4 documents hon ya 4 billion — postings lists typically doc ID se sorted bhi hoti hain, jisse intersection khud ek fast linear merge ban jaata hai (do sorted arrays ko merge karne jaisa) nested-loop comparison ke bajaye.

Real inverted indexes har postings list entry mein sirf doc IDs se zyada store karte hain — commonly term frequency (us doc mein term kitni baar appear hota hai, ranking ke liye use hota hai, neeche dekho) aur wo positions jahan wo appear hota hai (phrase queries jaise `"fast cache"` support karne ke liye zaroori hai, jo tabhi match kare jab words adjacent hon).

## Elasticsearch / Lucene basics

**Lucene** underlying Java library hai jo ek single machine ke liye inverted index (plus query engine, scoring, aur on-disk storage format) implement karti hai. **Elasticsearch** Lucene ke upar bana ek distributed system hai — ye Lucene ke single-node index ke around horizontal scaling, replication, ek JSON HTTP API, aur cluster management add karta hai. (**Solr** ek aur well-known Lucene-based search server hai; interview-relevant point dono cases mein same hai: ek Lucene-style inverted index ko wrap karta ek distributed system.)

Interview mein reason karne ke liye itna kaafi hai:

- **Documents shards mein index hote hain.** Ek Elasticsearch "index" (roughly: ek table) multiple **shards** mein split hota hai, jinme se har ek self-contained Lucene inverted index hai jo documents ka ek subset hold karta hai. Ye same horizontal-partitioning idea hai jo database sharding mein hai (`07_database_scaling.md` dekho) — ye tumhe ek logical index ke storage aur query load dono ko bahut saari machines pe spread karne deta hai, aur ek query relevant shards mein fan out hokar results merge karti hai.
- **Near-real-time (NRT) search, instant nahi.** Jab ek document likha jaata hai, wo turant searchable nahi hota. Elasticsearch writes ko ek in-memory buffer mein batch karta hai aur periodically use ek searchable Lucene segment mein "refresh" karta hai (by default roughly har second). Iska matlab hai ki "write acknowledged" aur "document search results mein dikhna" ke beech ek chhota window hota hai (typically ek second se kam, but tunable aur kabhi kabhi load ke neeche zyada bhi). Ye ek important trade-off hai jo interview mein explicitly naam lena chahiye: search read-heavy, writes-pe-latency-tolerant use cases ke liye great fit hai, aur us cheez ke liye poor fit hai jise searcher ko write turant dikhna chahiye (e.g., "maine abhi ek comment post kiya, aur wo same request cycle mein search results mein dikhna hi chahiye").
- **Relevance scoring (TF-IDF / BM25), conceptually.** Ek baar jab multiple documents ek query match karte hain, unhe relevance se rank karna padta hai, sirf koi arbitrary order mein return karne ke bajaye. Classic intuition (TF-IDF — Term Frequency, Inverse Document Frequency — aur BM25, isi idea ka ek refined, zyada modern version jo default mein Elasticsearch/Lucene use karta hai) ye hai:
  - Ek term jo **kisi specific document mein often** appear karta hai, probably us document ke liye important hai (term frequency).
  - Ek term jo **corpus ke almost har document mein** appear karta hai (jaise "the" ya "is") bahut kam distinguishing signal carry karta hai, isliye ise kam count karna chahiye (inverse document frequency — corpus mein rare terms ko zyada weight milta hai, common ones ko kam).
  - Dono ko combine karo: ek document ek query term ke liye tab sabse highest score karta hai jab wo term *usme* frequent ho but *poore corpus mein* rare ho. Interview ke liye exact formula ki zaroorat nahi — intuition ("rare-but-locally-frequent terms zyada score karte hain") hi matter karta hai.

```text
                     ┌──────────────┐
  client query  ───► │ Elasticsearch │
                     │  coordinator  │
                     └───────┬──────┘
              fan out to relevant shards
        ┌────────────┬───────┴───────┬────────────┐
        ▼             ▼               ▼            ▼
   Shard 1        Shard 2         Shard 3       Shard 4
 (Lucene idx)   (Lucene idx)    (Lucene idx)  (Lucene idx)
        │             │               │            │
        └────────────┴───────┬───────┴────────────┘
                  merge + rank results
                              ▼
                     results returned
```

## Typeahead / autocomplete, conceptually

Typeahead full-text search se ek alag problem hai: "documents dhoondho jinme ye words kahin bhi hon" ke bajaye, ye hai "jaise user character by character type kare, complete strings suggest karo jo abhi tak type kiye gaye se start hoti hain, likely relevance se ranked" — aur ye har keystroke ke milliseconds ke andar respond karna chahiye.

- **Trie ke through prefix matching.** Ek **trie** (prefix tree) ek tree hai jahan har node ek character represent karta hai, aur root se ek path ek string spell karta hai. Trie ko ek-ek character type karte hue neeche walk karna naturally matching strings ke set ko exactly un pe narrow kar deta hai jo wo prefix share karte hain — jis moment tum `"ca"` wale node pe ho, us node ke neeche reachable har string `"ca"` se start hoti hai. Ye ek achha structural fit hai kyunki ye "is prefix se start hone wali har cheez do" ko strings ki poori list ke filter ke bajaye ek direct tree traversal banata hai.

```text
        (root)
        /    \
       c      d
       |      |
       a      o
      / \      \
     r   t      g
     |   |
     e   ...
   "care"      "cat"
```

- **Suggestions ko sirf prefix match se nahi, popularity se rank karna.** Ek prefix hazaaron strings match kar sakta hai (har product name jo "c" se start hota hai), isliye tum bas "sab kuch" return nahi kar sakte — tumhe kisi cheez jaise search frequency/popularity se rank karna padta hai. Har keystroke pe "is prefix ke top-k most popular completions" recompute karne ke bajaye (expensive agar popularity data large ho), ek common approach ye hai ki **har trie node pe top-k suggestions precompute aur cache** kiye jaayein (offline ya periodically), taaki ek given prefix ke liye request bas "us node tak walk karo, uski cached top-k list return karo" ban jaaye — O(prefix length) plus ek cache read, live ranking computation nahi.

- **Ye sirf ek conceptual sketch hai.** Full worked design — kaise suggestion popularity ko near-real-time update rakha jaaye jaise-jaise nayi searches aati hain, personalization (har user ke liye alag ranking), aur high request volume survive karne ke liye hot prefixes ko kaise cache kiya jaaye — ye sab **`02_Interview_Questions/04_typeahead_autocomplete.md`** mein end-to-end worked through hai. Is section ko us file mein jaane se pehle chahiye vocabulary maan lo, full design nahi.

## Analyzers: index hone se pehle text ke saath kya hota hai

Upar wale worked example mein tokenization step ("words mein split karo, lowercase karo") actually Lucene/Elasticsearch terms mein ek pipeline hai jise **analyzer** kehte hain, aur ise explicitly naam lena worthwhile hai kyunki yahin par real search quality kaafi hadd tak win ya lose hoti hai:

- **Tokenization** — raw text ko individual terms mein split karna (usually whitespace/punctuation pe).
- **Lowercasing** — taaki `"Redis"` aur `"redis"` same postings list entry match karein.
- **Stopword removal** — extremely common, low-signal words ("a," "the," "is") ko drop karna taaki wo postings lists ko bloat na karein ya relevance scoring ko dilute na karein.
- **Stemming/lemmatization** — words ko unke root form mein reduce karna (`"running"`, `"ran"` → `"run"`) taaki ek form ke liye search dusra form use karne wale documents ko match kare.

Same query string analyzer configuration ke hisaab se bahut alag results de sakta hai — isiliye do search systems "same" data index karte hue bhi alag behave kar sakte hain, aur agar interviewer search quality/relevance tuning ke baare mein pooche to ye mention karna reasonable hai.

## Search shards ke liye replication

Bilkul ek sharded database ki tarah, har Elasticsearch shard normally ek ya zyada **replica shards** se backed hota hai — us shard ke data ki full copies dusre nodes pe. Replicas do purposes serve karte hain: fault tolerance (agar primary shard wala node mar jaaye, ek replica promote ho jaata hai aur koi data lost nahi hota) aur read throughput (queries kisi bhi in-sync replica se serve ho sakti hain, read load spread karte hue). Ye `07_database_scaling.md` ki primary/replica vocabulary mirror karta hai — same underlying idea (durability aur read scale ke liye nodes ke across data copy karna) jo relational database ke bajaye ek search cluster ke andar apply ho rahi hai.

## Index types compared

Jab interviewer poochta hai "in mein se X hi kyun use nahi karte," uske liye ek quick reference:

| Structure | Answers | Weak at |
|---|---|---|
| B-tree (relational DB index) | Ek column pe equality/range lookups (`WHERE price BETWEEN 10 AND 50`) | Text blob ke andar full-text search |
| Hash index | Exact-match lookup (`WHERE id = X`) | Range queries, prefix queries, text search |
| Inverted index | "In words ko contain karne wale documents kaunse hain," relevance se ranked | Numeric fields pe range queries (Elasticsearch iske liye doosri structures layer karta hai) |
| Trie | Prefix matching (autocomplete, IP routing tables) | Full-text "kahin bhi ye word hai" search, relevance ranking |

## Trade-offs

| Approach | Good for | Bad for |
|---|---|---|
| Tumhare primary DB mein `LIKE '%x%'` | Tiny datasets, infrequent search, zero extra infra | Kisi bhi real scale ke liye — full scan, koi relevance ranking nahi, koi fuzzy/prefix features nahi |
| Tumhare DB mein full-text index (e.g., Postgres `tsvector`/GIN index) | Medium scale, ek separate search cluster chalane se bachna, data ko source of truth ke saath consistent rakhna | Ranking aur query features ek dedicated engine se kam sophisticated hain; abhi bhi tumhare primary DB ke hardware pe rehta hai aur transactional load se compete karta hai |
| Dedicated search engine (Elasticsearch/Solr) | Large scale, rich relevance ranking, faceting/aggregations, shards ke through horizontal scale | Chalane aur sync mein rakhne ke liye extra system (usually source of truth se ek change-data-capture ya dual-write pipeline ke through), near-real-time instant nahi, DB aur index ke beech eventual consistency |
| Trie-based prefix index | Autocomplete/typeahead — prefix queries fast aur ranked hone chahiye | "Kahin bhi ye word hai" full-text search ke liye galat tool |

## When to use what

- Chhota dataset, infrequent search, exact-ish matches acceptable → search system mat banao, ek DB query kaafi hai.
- Ek large, growing corpus pe relevance-ranked full-text search chahiye → dedicated search engine (Elasticsearch-style), source-of-truth DB aur index ke beech sync lag accept karo.
- User ke type karte hi instant, ranked, prefix-based suggestions chahiye → trie (ya search engine ka built-in "completion suggester," jo same idea ka productionized version hai) precomputed/cached top-k per prefix ke saath, per keystroke live full-text query nahi.

## Interview Tips

- Agar ek question mein "search" involve ho, turant clarify karo ki iska matlab full-text search hai (relevance se rank) ya exact lookup (ek plain index ya key-value store kaafi hai) — candidates aksar Elasticsearch pe pahunch jaate hain jab ek simple indexed column kaam kar deta.
- Consistency trade-off explicitly naam lo: search index source-of-truth data ki ek derived, denormalized copy hai, asynchronously update hoti hai, isliye ek write ko searchable hone mein thoda time lag sakta hai. Ye state karo, ye imply karne ke bajaye ki search writes ke saath transactionally consistent hai.
- Shard count ko database sharding ke baare mein jo tum pehle se jaante ho usse tie back karo: same idea (data ko nodes ke across split karo reads/writes/storage horizontally scale karne ke liye), same problems (uneven shard sizes, query pe fan out aur merge karne ki zaroorat).
- Typeahead ke specifically liye, interview ke is section mein over-explain mat karo — bolo "trie with precomputed top-k per node, periodically ya write-behind update se refresh hota hai," aur deep detail (real-time popularity updates, personalization, hot-prefix caching) tab ke liye save karo jab interviewer deeper jaana chahe.

## Quick Recall — Self-Test

**Q1: Inverted index kya hai, aur ye forward index se kaise alag hai?**
Ek inverted index har term ko us term wale documents ki list (term → doc IDs) se map karta hai. Ek forward index har document ko usme wale terms se map karta hai (doc → terms), jo natural representation hai but fast search ke liye useless, kyunki "kaunse docs mein X hai" answer karne ke liye har document ki term list scan karni padegi.

**Q2: Ek standard relational B-tree index efficiently "kya is text column mein ye word hai" answer kyun nahi kar sakta?**
Ek B-tree sorted keys pe equality aur range lookups ke liye bana hai, ye test karne ke liye nahi ki ek large text blob ke andar ek substring/word appear karta hai ya nahi. Ek leading wildcard wali `LIKE '%word%'` query ise use nahi kar sakti aur har row scan karne pe fall back kar jaati hai.

**Q3: Elasticsearch mein "near-real-time search" ka matlab kya hai, aur ye ek design ke liye kyun matter karta hai?**
Newly written documents turant searchable nahi hote — wo ek in-memory buffer mein baithe rehte hain jab tak ek periodic refresh (aksar roughly ek second mein ek baar) unhe queryable na bana de. Ye matter karta hai kyunki ek aisa design jise ek write ka turant search results mein reflect hona chahiye (same request cycle) is refresh delay pe rely nahi kar sakta.

**Q4: TF-IDF/BM25 relevance scoring ke peeche kya intuition hai, formula ke bina?**
Ek term ek document ke relevance score mein zyada contribute karta hai jab wo us specific document mein frequently appear kare (term frequency) but poore corpus mein rarely appear kare (inverse document frequency) — common words jaise "the" har jagah low score karte hain, jabki ek rare term jo ek document mein frequent hai ek strong signal hai ki wo document match karta hai.

**Q5: Elasticsearch mein sharding tumhe pehle se pata database sharding se kaise related hai?**
Same underlying idea: ek logical index ke data ko multiple machines (shards) ke across split karo taaki storage aur query load horizontally scale ho. Ek query relevant shards mein fan out karti hai aur coordinator results merge karta hai, bilkul jaise ek sharded database query (ya scatter-gather) karti.

**Q6: Trie autocomplete ke liye ek achha structural fit kyun hai?**
Har node ek character represent karta hai, aur root se ek node tak ka path ek prefix spell karta hai — isliye us prefix ko share karne wali saari strings us node ke neeche wale subtree mein rehti hain. User ke type karte hi trie ko walk karna directly har keystroke ke saath candidate set ko narrow karta hai, prefix length ke proportional time mein, poore dataset ke size ke proportional nahi.

**Q7: Har trie node pe top-k suggestions kyun precompute karte hain, har request pe live rank karne ke bajaye?**
"Is prefix ke most popular completions" scratch se har keystroke pe rank karna expensive hai jab bahut saare matches hon aur popularity data large ho. Precomputing (periodically ya write-behind updates se) ka matlab hai ek request bas node tak ek tree walk plus ek cached-list read hai — fast aur cheap, even heavy keystroke-driven request volume ke neeche.

**Q8: Full end-to-end typeahead design kahaan dekhna chahiye, aur is file ka coverage kahaan tak rukta hai?**
`02_Interview_Questions/04_typeahead_autocomplete.md` full design cover karti hai — real-time popularity updates, personalization, aur hot prefixes ko cache karna. Ye file sirf conceptual building blocks deti hai (trie, precomputed ranking) jo us design ko follow karne ke liye chahiye.
