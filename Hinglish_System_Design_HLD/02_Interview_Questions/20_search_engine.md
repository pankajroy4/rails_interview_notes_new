# Design a Web Search Engine

## Problem Statement

"Design a simplified web search engine, like Google Search. Given a text query,
return a ranked list of the most relevant web pages out of an index covering a
large fraction of the public web, in well under a second." Ye question
deliberately do subsystems ko compose karta hai jo tumne shayad already alag-alag
design kiye honge — content acquire karne ke liye ek web crawler, aur ise
retrieve karne ke liye ek inverted index pe built search/indexing system — isliye
ek strong candidate ko unhe re-derive karne mein kam time spend karna chahiye aur
iske bajaye focus karna chahiye ki iss scale pe genuinely naya kya hai: index ko
machines ki fleet ke across kaise shard kiya jaaye, aur results ko us scale pe
achhe se, cheaply kaise rank kiya jaaye.

## Step 1: Clarify Requirements

**Functional Requirements**

- Free-text search queries accept karo aur relevant web page results (URL,
  title, snippet) ki ek ranked list return karo.
- Poore web se continuously naye aur updated pages discover aur index karo.
- Standard query features support karo: multi-word queries (implicit AND of
  terms), phrase queries, basic operators.
- Results ko genuine relevance se rank karo, sirf keyword match se nahi —
  textual relevance ko page authority/quality signals ke saath combine karke.
- Secondary feature ke roop mein autosuggest/typeahead support karo (briefly —
  is design ka focus nahi hai).

**Non-Functional Requirements**

- Query latency: end-to-end vast majority queries ke liye ~200-300ms se kam,
  kyunki search ek synchronous, user-facing, latency-sensitive product hai.
- Massive read scale: query path ko high availability ke saath ek bahut high,
  globally distributed QPS serve karna hoga.
- Massive index scale: corpus tens se hundreds of billions pages ke order pe
  hai.
- Freshness: new/changed content ko full corpus reindex ki requirement ke bina
  ek reasonable window (most pages ke liye minutes se hours, breaking news
  jaise high-priority sources ke liye faster) ke andar searchable ho jaana
  chahiye.
- Consistency relaxed hai: ek brand-new page ke results mein appear hone mein
  kuch time lagna acceptable hai (eventual, immediate nahi, consistency) — ye ek
  read-heavy system hai jo strict freshness guarantees ke bajaye availability
  aur latency ko favor karta hai.
- Scale pe cost efficiency: itne bade corpus size aur query volume ko dekhte
  hue index storage aur per-query compute cost, dono ko control karna zaroori
  hai.

## Step 2: Back-of-Envelope Estimation

**Assumptions**

- Indexed corpus: 50 billion web pages (ek large web search engine ke liye ek
  reasonable order-of-magnitude).
- Average page, HTML stripping aur text extraction ke baad, roughly 1,000
  indexable terms contain karta hai (repetition ke saath; per page distinct
  terms kam hote hain).
- Query volume: globally average 50,000 queries/sec, jo roughly 150,000
  queries/sec pe peak karta hai.

**Index size**

- Ek classic inverted index entry (ek "posting") per (term, document) pair, kam
  se kam ek document ID aur typically ranking ke liye position/frequency
  information store karta hai — compression ke baad ise roughly 8-12 bytes per
  posting maan lete hain (real search engines posting-list compression
  techniques mein heavily invest karte hain; compressed assume karte hain).
- Total postings, agar har page ne ~1,000 term occurrences contribute kiye aur
  hum conservatively assume karein ki stopword removal aur dedup ke baad per
  page ~300 non-trivial distinct indexed terms hain: 50 billion pages x 300
  distinct terms ≈ 15 trillion postings.
- ~10 bytes/posting compressed pe: 15 trillion x 10 bytes = 150 TB sirf core
  postings data ke liye. Term dictionary add karo (terms ko posting-list
  locations pe map karna — postings ke relative small, tens of GB), aur ye
  confirm karta hai ki index ek machine pe nahi reh sakta; ise ek large fleet
  ke across shard karna hoga (Step 6 dekho).

**Query fan-out cost**

- Document-partitioning ke under (jo approach ye design adopt karta hai, Step 6
  dekho), har query har shard tak fan out hoti hai. Agar index ko, say, 1,000
  shards mein split kiya gaya hai, to ek query 1,000 parallel sub-queries ban
  jaati hai.
- 150,000 queries/sec peak x 1,000 shards = peak pe system-wide 150,000,000
  sub-query operations/sec. Ye wo number hai jo justify karta hai ki har shard
  apni local sub-query ko extremely cheaply (kuch milliseconds mein) answer kar
  paaye, kyunki ye enormous aggregate rate pe kar raha hai.

**Crawl and ingestion volume** (briefly — full detail `05_web_crawler.md` mein
hai)

- Maan lete hain crawler 50-billion-page corpus ko reasonably fresh rakhne ke
  liye roughly 5 billion pages/day refresh/discover karta hai (high- aur
  low-churn content ke across blended ~1% daily refresh rate). Average page size
  100 KB raw HTML pe: 5 billion x 100 KB = 500 TB/day of raw crawl bandwidth —
  ek bahut bada number, jo bilkul isi wajah se `05_web_crawler.md` ke design
  (politeness limits, distributed fetching, page-change-frequency ke hisaab se
  prioritization) ko apne aap mein ek subsystem ki tarah treat kiya jaata hai
  yahan re-derive karne ke bajaye.

**Ranking compute cost**

- Agar retrieval (Step 6) 50 billion pages ko narrow karke, say, top 10,000
  candidates per query tak la deta hai expensive ranking apply hone se pehle,
  aur expensive ranking roughly per candidate 1ms compute cost karti hai:
  10,000 x 1ms = 10 seconds ranking compute per query agar serially kiya jaaye
  — clearly sub-300ms latency budget hit karne ke liye per query many machines/
  cores ke across heavy parallelization chahiye, jo reinforce karta hai ki
  two-stage retrieve-then-rank split (Step 6) iss scale pe optional nahi hai.

**Index shard fleet sizing**

- 150 TB compressed postings ke saath (Step 6 mein aage worked out) aur ye
  target rakhte hue ki har shard ka data comfortably fast local storage/memory
  se servable rahe — say 150 GB postings per shard, ek size jo per-shard query
  latency ko low rakhta hai aur ek well-provisioned host pe reasonably fit ho
  jaata hai — iska matlab hai roughly 150 TB / 150 GB = 1,000 shards, jo upar
  use ki gayi fan-out assumption ke consistent hai. Har shard ko availability
  aur query-serving capacity dono ke liye replicas chahiye (ek single replica
  per shard 150,000 QPS x 1 sub-query each = 150,000,000 sub-queries/sec akele
  absorb nahi kar sakta); assume karte hain har shard replica roughly
  2,000-5,000 cheap local sub-queries/sec serve kar sakta hai, to peak pe full
  fan-out load serve karne ke liye roughly 150,000,000 / 3,000 ≈ 50,000
  shard-replica instances system-wide chahiye — genuinely ek large fleet, aur
  poore design mein ye clearest illustration hai ki document-partitioning ka
  "predictable, parallelizable" fan-out cost (Step 6) kyun matter karta hai:
  ye bahut saari machines hain, lekin ye bahut saari *identical, independently
  scalable* machines hain, na ki bahut saari *specialized, hard-to-balance*
  machines.

## Step 3: High-Level Design

Ye system do subsystems compose karta hai jo already iss question bank mein
alag se cover kiye ja chuke hain, plus ek ranking layer jo yahan naya hai:

- **Crawler** (full design `05_web_crawler.md` mein hai): URLs discover karta
  hai, robots.txt/politeness respect karta hai, pages fetch karta hai, aur raw
  content downstream hand karta hai. Yahan detail mein re-derive nahi kiya gaya.
- **Content processing pipeline**: raw HTML ko clean text mein parse karta hai,
  link graph extract karta hai (kaunse pages kaunse pages ko link karte hain —
  authority/PageRank-style signal feed karta hai), near-identical content
  deduplicate karta hai, aur text ko indexable terms mein tokenize karta hai.
- **Indexer**: processed content se inverted index build karta hai (core
  structure `13_search_and_indexing.md` mein cover kiya gaya hai), jo bahut
  saari machines ke across sharded hai (Step 6).
- **Link-graph / authority processor**: ek periodic, large batch job jo crawled
  link graph se poore corpus ke across page-authority scores (conceptually
  PageRank-like) compute karta hai (Step 6).
- **Query service (retrieval tier)**: ek query receive karta hai, ise saare
  index shards tak fan out karta hai, cheap relevance scores ke saath matching
  documents ka ek candidate set wapas leta hai, aur results merge karta hai.
- **Ranking service**: merged candidate set (ab kaafi chhota — thousands, na ki
  billions) leta hai aur ek zyada expensive, higher-quality ranking model apply
  karta hai, text relevance ko authority aur other signals ke saath blend
  karke, taaki final ordered result list produce ho.
- **Serving cache**: bahut common/repeated queries ke liye results cache karta
  hai taaki identical popular queries ke liye poora retrieve-and-rank work
  dobara na karna pade.

```text
                         CRAWLING & INDEXING (offline/near-line)
  +-----------+     +-------------------+     +-----------------+
  |  Crawler   |---->| Content Processing |---->|   Indexer        |
  | (see doc   |     | (parse, dedup,     |     | (builds sharded    |
  |  05)       |     |  tokenize, extract |     |  inverted index,   |
  +-----------+     |  link graph)        |     |  see doc 13)       |
                      +---------+---------+     +--------+---------+
                                |                          |
                                v                          v
                      +-------------------+       +------------------+
                      | Link-Graph /       |       | Index Shards      |
                      | Authority Batch Job |------>| (doc-partitioned, |
                      | (PageRank-style,     |       |  ~1000 shards)    |
                      |  periodic, whole-     |       +------------------+
                      |  corpus)              |
                      +-------------------+

                         QUERY PATH (online, latency-critical)
   User Query
       |
       v
 +--------------+     fan out to ALL shards      +------------------+
 | Query Service |-------------------------------->| Index Shard 1..N |
 | (retrieval)   |<--------------------------------|  (cheap TF-IDF/   |
 +------+--------+     merged candidate list        |   BM25 scoring)   |
        |                                            +------------------+
        v
 +----------------+
 | Ranking Service |   <- blends text relevance + authority score
 | (expensive model|      + freshness + other signals, applied ONLY
 |  on top-K only) |         to the small candidate set
 +--------+--------+
          |
          v
 +----------------+
 | Serving Cache    |  (hot/repeated queries)
 +--------+--------+
          |
          v
      Ranked Results -> User
```

## Step 4: API Design

**Search query (primary, latency-critical endpoint)**
```
GET /search?q=best+ramen+in+sf&page=1&pageSize=10
<- {
     query: "best ramen in sf",
     totalEstimated: 4820000,
     results: [
       { url: "https://...", title: "...", snippet: "...", rank: 1 },
       ...
     ],
     latencyMs: 187
   }
```

**Internal: shard-local retrieval (Query Service -> each Index Shard)**
```
POST /shard/{shardId}/retrieve
{ terms: ["ramen", "sf"], topK: 200 }
-> { candidates: [{ docId, termScore }], shardId }
```

**Internal: ranking request (Query Service -> Ranking Service)**
```
POST /rank
{ query: "best ramen in sf", candidateDocIds: [ ...merged top ~2000 from all shards ] }
-> { rankedResults: [{ docId, finalScore }] }
```

**Autosuggest (secondary feature)**
```
GET /suggest?prefix=best+ram
<- { suggestions: ["best ramen in sf", "best ramen recipe", ...] }
```

**Admin/internal: trigger reindex of a specific URL (incremental update path)**
```
POST /internal/index/update { url: "https://example.com/page", content: "...", crawledAt: "..." }
-> 202 Accepted
```

## Step 5: Data Model

**Inverted index (core retrieval structure, `13_search_and_indexing.md` mein
detail mein diya gaya hai)**: ek specialized search index structure (e.g.
Lucene/Elasticsearch-style segments, ya ek custom-built structure), koi
general-purpose database nahi, kyunki read pattern hamesha "ek term diya, uski
posting list lo" hota hai, relational access nahi.

```
term_dictionary (per shard)
  term            string   -- e.g. "ramen"
  postingListPtr  offset   -- location of this term's posting list

posting_list (per term)
  [ { docId, termFrequency, positions[], fieldWeight }, ... ]  -- sorted by docId within a shard
```

**Document store (raw/processed content, snippet generation aur re-ranking
features ke liye)**: docId se keyed ek distributed key-value ya wide-column
store, kyunki access hamesha ID se ek direct lookup hoti hai, kabhi scan ya
join nahi.

```
documents (key: docId)
  url            string
  title          string
  cleanedText    text
  outboundLinks  [url]
  crawledAt      timestamp
  authorityScore float     -- last computed by the batch link-graph job
```

**Link graph (authority batch job ka input)**: naturally ek graph structure;
ya to ek distributed store mein edge list ki tarah stored hoti hai ya batch
computation ke dauran directly ek graph-processing framework ki apni storage
mein, kyunki access pattern (poore corpus ke across nodes ke beech links
traverse karna) graph-shaped hai, relational ya key-value nahi.

```
links (edge list)
  fromDocId
  toDocId
```

## Step 6: Deep Dive

### Inverted index ko sharding karna: term-partitioning vs document-partitioning

150 TB compressed postings pe (Step 2), index ek single machine pe nahi reh
sakta, aur ise machines ke across kaise split kiya jaata hai iske query cost
aur ingestion cost dono pe first-order consequences hain.

**Term-partitioning**: har shard *poore* corpus ke across terms ki ek range ke
complete posting lists own karta hai (e.g. shard 1 A-C terms ke saare postings
own karta hai, shard 2 D-F own karta hai, aur so on). Ek single-term query
cheap aur clean hoti hai — ye exactly ek shard hit karti hai, jo us term ke
liye complete, authoritative posting list return karta hai. Problem multi-term
queries pe dikhti hai, jo real search traffic ka overwhelming majority hain: 
"best ramen sf" ki query ko teen terms ki posting lists chahiye jo likely teen
alag shards pe rehti hain, aur unka intersection compute karna (kaunse
documents mein sabhi teen terms hain) potentially bahut large posting lists ko
network ke across ek coordinating node tak khinchne ki zaroorat padti hai, ya
complex distributed intersection logic karni padti hai — dono hi cases mein, ek
significant coordination cost jo query term count badhne ke saath poorly scale
karti hai, aur ek term ki posting list doosre ke relative enormous aur
imbalanced ho sakti hai ("the" jaise term ki posting list ek rare term se
astronomically badi hoti hai), jisse shard load inherently uneven ho jaata hai.

**Document-partitioning**: iske bajaye har shard document corpus ke ek *subset*
ke liye complete inverted index own karta hai — e.g. shard 1 ke paas documents
1 se 50 million ke liye ek full mini-inverted-index (saare terms, saare
postings) hota hai, shard 2 ke paas next 50 million ke liye, aur so on. Har
shard apni documents ki slice ke liye KISI BHI query ko independently answer
kar sakta hai, kyunki uske paas jo bhi documents own karta hai unka ek complete
index hota hai. Iska matlab hai har query ko har shard tak fan out hona padta
hai (jaisa Step 2 ke estimation mein reflect hua), har shard apna local
term-intersection aur scoring entirely independently karta hai, aur Query
Service per-shard result lists ko merge karta hai (typically har shard ka local
top-K lekar ek global top-K mein merge karta hai).

**Document-partitioning wahi hai jo large real-world search engines actually
use karte hain, do concrete reasons ke liye.** Pehla, naye documents ingest
karna kahin zyada evenly scale karta hai: ek newly-crawled page add karne ka
matlab hai bas usse jis bhi document shard ke paas abhi jagah hai (ya ek
simple rotation/consistent-hash scheme se chose kiye gaye shard) mein insert
karna, jo ek local, independent operation hai — jabki term-partitioning ke
under, ek single naya document index karne se potentially hundreds alag
term-owning shards touch hote hain (naye document mein jitne bhi distinct terms
hain unme se har ek ke liye ek shard), kyunki us document ke postings ko unn
saare shards ke across distribute karna padta hai jo uske har term ko own
karte hain. Dusra, document-partitioning ke under query fan-out cost
predictable aur embarrassingly parallel hai: har query same amount of work
karti hai (saare N shards ko query karo, har ek apne bounded document slice pe
ek bounded amount of local work karta hai), jo term-partitioning ke highly
variable, data-dependent coordination cost se ek kahin zyada aasan capacity-
planning aur latency-tail problem hai, jo unpredictably spike karta hai iss
basis pe ki ek query kaunse specific terms combine karti hai.

### Two-stage retrieve-then-rank architecture

"best ramen in sf" jaisa query 50-billion-page corpus ke across tens of
millions pages ke saath textually match kar sakta hai (Step 2 ke API example
mein `totalEstimated: 4,820,000`). Agar ek high-quality ranking model — jo
dozens ya hundreds features consider karta hai (click-through history, page
quality signals, personalization, freshness, raw term matching se aage semantic
relevance) — har single matching document ke against run kiya jaaye, to compute
cost sub-300ms latency budget ke andar entirely infeasible ho jaayega; per query
millions documents ke against ek expensive model run karna, peak pe 150,000
queries/sec ke across multiply kiya jaaye to, kisi bhi reasonably-sized fleet ke
absorb karne layak compute quantity nahi hai.

Solution hai ranking ko do stages mein split karna jinke bahut alag cost
profiles hain:

1. **Retrieval (cheap, broad)**: har index shard apne local matching
   documents ko ek relatively simple, fast text-relevance function se score
   karta hai, conceptually TF-IDF ya BM25 — ye score karta hai iss basis pe ki
   koi term poore corpus mein kitna rare hai (jo term few documents mein
   appear karta hai, wo common term se stronger signal hai) *iss* document mein
   kitni frequently appear karta hai iske against weighted (aur BM25 ke case
   mein, document length ke liye normalized). Ye har matching document ke
   against run karne ke liye kaafi cheap hai, kyunki iske liye sirf posting
   lists mein already baithe statistics chahiye (term frequency, document
   frequency) bina kisi external model inference ke. Har shard sirf apna local
   top-K (e.g. top 200) candidates iss cheap score ke hisaab se return karta
   hai, apna full match set nahi — jo per shard potentially millions matches
   ko shard se bahar nikalne se pehle hi kuch sau tak collapse kar deta hai.
2. **Ranking (expensive, narrow)**: Query Service har shard ka top-K ek combined
   candidate set mein merge karta hai — ab system-wide roughly kuch thousand
   documents ke order pe, chahe total mein kitne bhi millions match hue hon —
   aur SIRF isi kaafi chhote set ko expensive ranking model ko diya jaata hai,
   jo ab per candidate rich, costly features compute karna afford kar sakta hai
   (authority score, freshness, personalization, aur zyada blend karke),
   kyunki wo thousands documents ke liye ye kar raha hai, millions ke liye
   nahi.

Ye retrieve-then-rank split "ranking model ko good results produce karne ke
liye sophisticated hona chahiye" ko "system ko 300ms se kam mein answer karna
hai" ke saath reconcile karne ka standard tareeka hai — pehle cheap-and-broad se
problem ko shrink karo, phir expensive-and-narrow se usse achhe se solve karo.

**Ek worked BM25-style example, "cheap retrieval scoring" ko concrete banane ke
liye.** Maan lo query hai "ramen sf" aur ek candidate document ek chhota blog
post hai. BM25, per query term, term ki inverse document frequency (poore
corpus mein rarer terms zyada score karte hain) ko iss specific document ke
andar uski frequency ke saath combine karta hai (saturating hoti hai, linear
nahi, isliye jo document "ramen" 50 baar repeat karta hai wo usse 50x zyada
score nahi karta jo ek baar contain karta hai), document length ke against
normalized (isliye ek short, focused document ek long document ke against
unfairly penalize nahi hota jo sirf zyada words hone ki wajah se term ko zyada
baar contain karta hai). Concretely: agar "ramen" 50 billion indexed documents
mein se 2 million mein appear karta hai (rare — high inverse-document-frequency
weight) aur "sf" 4 billion documents mein appear karta hai (common — low
weight, kyunki ye ek weak discriminator hai), to ek 200-word post jisme "ramen"
3 baar appear karta hai, wo ek 5,000-word document se "ramen" term pe kahin
zyada score karega jisme "ramen" sirf ek baar hai, "sf" ko factor karne se
pehle hi — aur critically, ye saare numbers (term frequency, document
frequency, document length) already directly shard ki local posting lists aur
term dictionary mein baithe hain, isliye ye score bina kisi network call, model
inference, ya per-query training data lookup ke computable hai, jo bilkul isi
wajah se ye kaafi cheap hai ki isse smaller candidate set ke liye reserve karne
ke bajaye shard ke har local match ke against run kiya ja sake.

### Text relevance ko link-graph authority ke saath blend karna

TF-IDF/BM25 retrieval scores measure karte hain ki ek document ka *text* query
se kitna achha match karta hai, lekin ye kuch nahi batate ki page trustworthy,
authoritative, ya high-quality hai ya nahi — ek page "best ramen in sf" ke liye
textually perfect keyword match ho sakta hai jabki wo ek low-quality spam page
ho jise ek well-established, widely-cited restaurant review site se upar kabhi
nahi dikhaana chahiye. Isi wajah se ranking mein signal ki ek second, independent
family blend ki jaati hai: page authority, jo conceptually PageRank jaisi cheez
se capture hoti hai — ye idea ki ek page zyada authoritative hai agar bahut
saare *other* authoritative pages usse link karte hain, jo crawled link graph
ki structure se poore corpus ke across compute kiya jaata hai (ek approach
conceptually graph-centrality algorithms jaisi; interview-relevant point ye hai
ki authority links ke through propagate hota hai, exact linear-algebra
derivation nahi). Text relevance (ye page jo poocha gaya usse match karta hai
ya nahi) aur authority (ye generally ek trustworthy/important page hai ya
nahi) ko deliberately do distinct signals ki tarah rakha jaata hai — ek page
highly relevant lekin low authority ho sakta hai (ek brand-new, accurate blog
post) ya highly authoritative lekin ek specific query ke liye low relevance
(ek major news homepage, kisi unrelated query ke liye) — aur final ranking
model ka kaam hai inhe (plus freshness, click-through data, personalization
jaise other signals) ek final score mein combine karna, unhe premature ek
single measure mein collapse karne ke bajaye.

### Freshness vs full reindexing

Web constantly change hota hai — pages edit hote hain, create hote hain, delete
hote hain — lekin corpus enormous hai (tens of billions documents, ~150 TB
postings), isliye jab bhi kahin content change ho poora index scratch se
rebuild karna completely infeasible hai; iss scale pe ek full reindex ek large,
expensive, slow batch operation hai jo realistically kisi per-change basis pe
nahi chal sakta. Isliye design updates ko do bahut alag cadences mein split
karta hai, iss basis pe ki kaunsa signal change ho raha hai:

- **Incremental, fast updates**: jab koi specific page newly crawl hota hai ya
  change hota hai, sirf uska entry apne owning shard ke andar update karna
  padta hai — uske postings ko us ek document-partitioned shard ke local index
  mein insert/update karo (Step 4 ka `POST /internal/index/update` endpoint),
  bina kisi aur shard ya document ko touch kiye. Ye text-relevance freshness
  (ek changed page ka *content* searchable ho jaana) ko fast rakhta hai —
  minutes se hours mein achievable — kyunki ye ek small, localized, independent
  write hai, jo upar describe kiye gaye document-partitioning ke ingestion
  advantage ke consistent hai.
- **Periodic, batch recomputation**: authority/link-graph scores, iske
  contrast mein, inherently ek whole-corpus property hain — ek page ko naya
  inbound link, principle mein, ek tiny input hai us computation mein jo
  stable authority scores tak converge hone ke liye poore crawled web ki
  entire link structure consider karta hai. Har single link change pe ise
  exactly recompute karna sirf expensive nahi hai, ye ek incremental operation
  ki tarah sense hi nahi banata jaisa ek document ka apna text content banata
  hai. Isliye authority scores iske bajaye periodically recompute kiye jaate
  hain (e.g. ek large batch job ki tarah kisi regular cadence pe run kiya
  jaata hai, engine ke freshness/cost trade-off ke hisaab se daily se weekly
  tak), ek big offline processing framework pe jo full link graph pe operate
  karta hai, aur results ko push karke har document ke stored
  `authorityScore` field ko update kiya jaata hai, jo agli ranking pass pick
  kar leti hai, bina postings ko khud reindex kiye.

Ye split — content-specific signals ke liye fast/local/incremental,
corpus-wide structural signals ke liye slow/global/batch — wahi hai jo system
ko un signals pe reasonably fresh rehne deta hai jo cheaply aur independently
update ho sakte hain, jabki fir bhi expensive signals afford kar paata hai
jinhe fundamentally poore-corpus context chahiye.

### Query understanding: tokenization, stemming, aur query expansion

Ek raw query string index tak pahunch paaye usse pehle, ise usi tarah ki
normalized term representation mein convert karna padta hai jaisi documents ko
index time pe kiya gaya tha — yahan mismatches silently retrieval break kar
dete hain chahe downstream ranking model kitna bhi achha ho. Isme kai concrete
steps involve hote hain, jo documents pe index time pe aur queries pe query
time pe consistently apply kiye jaate hain: **tokenization** (text ko discrete
terms mein split karna, punctuation, casing, aur language-specific rules
handle karna — "SF" aur "sf" same indexed term mein normalize hone chahiye, aur
word boundaries languages ke across alag hoti hain); **stemming/lemmatization**
(words ko ek common root tak reduce karna, taaki "ran" ya "running" waala
document "run" waali query ke liye bhi retrieve ho, kyunki indexing aur
querying same normalized stem ke against ki jaati hai); aur **stopword
handling** (bahut common, low-signal words jaise "the" ya "in" ko often index
se entirely exclude kar diya jaata hai, dono Step 7 mein mentioned storage cost
bachaane ke liye aur kyunki unki posting lists enormous hoti hain aur documents
ko discriminate karne mein bahut kam contribute karti hain, upar BM25 intuition
ke hisaab se).

Straightforward normalization se aage, **query expansion** retrieval net ko
without user ke perfectly phrase kiye widen karta hai: search karte waqt
transparently synonyms ya closely related terms include karna ("sf" ko expand
karke "san francisco" bhi consider karna, ya "cheap" ko "affordable" /
"budget" bhi consider karna), taaki relevant documents jo different lekin
equivalent wording use karte hain, ek overly literal term match se miss na ho
jaayein. Ye expansion carefully aur conservatively hona chahiye — over-
aggressive expansion irrelevant results khinch laata hai aur precision ko
undermine karta hai — aur typically curated synonym dictionaries aur large
query logs aur corpus text se mined statistical co-occurrence signals ke
combination se inform kiya jaata hai, purely ek static dictionary se expand
karne ke bajaye. Interview-relevant point ye hai ki ye poori layer retrieval
hone se *pehle* baithi hoti hai, aur documents ko index time pe kaise
tokenize/stem kiya gaya aur incoming query ko query time pe kaise process kiya
jaata hai, unke beech koi bhi inconsistency silently aur invisibly recall ko
degrade kar degi — ek document jo logically match karta hai wo simply kabhi
found nahi hota, koi error problem surface karne ke liye nahi hota, isi wajah
se real systems tokenization/query-processing consistency ko utni hi rigorously
test karte hain jitna ranking logic ko.

## Step 7: Bottlenecks & Trade-offs

- **Query fan-out ka matlab hai slowest shard hi query ki latency determine
  karta hai** (tail latency amplification): ~1,000 shards per request query
  hone ke saath, ek small per-shard chance bhi slow response ka (GC pause,
  disk hiccup, transient overload) ek kahin zyada large chance banata hai ki
  kisi bhi given query mein involve 1,000 shards mein se *kam se kam ek* slow
  ho. Ise aggressive per-shard timeouts aur "good enough" partial results se
  mitigate kiya jaata hai (jo shards time pe respond kar chuke unse best
  possible answer return karo, poori query ko stragglers pe block karne ke
  bajaye) — ek availability/completeness trade-off, koi free fix nahi.
- **Document-partitioning ka matlab hai har query har shard ko touch karti
  hai**, isliye total system query cost (queries/sec x shard count) ke saath
  scale karta hai, sirf queries/sec ke saath nahi — corpus growth accommodate
  karne ke liye zyada shards add karna directly per-query fan-out cost badha
  deta hai, jisse per shard retrieval stage ko cheap rehna padta hai (bounded
  top-K, simple scoring) jaise-jaise corpus aur shard count dono grow karte
  hain.
- **Hot/viral queries same set of documents/shards pe baar-baar
  thundering-herd load create karte hain** — serving cache popular, repeated
  queries ke liye iska kaafi hissa absorb kar leta hai, lekin cache unique ya
  rare queries ki long tail ke liye kahin kam effective hai, jo har baar full
  retrieve-then-rank cost pay karti rehti hain.
- **Authority-score staleness ek accepted trade-off hai**: kyunki ye ek
  periodic batch job mein compute hota hai, ek page ka authority score uske
  true, current standing se batch cadence jitna lag ho sakta hai (e.g. ek
  week tak) — acceptable hai kyunki authority vast majority pages ke liye
  slowly aur gradually change hota hai, lekin kisi bhi cheez ke liye poor fit
  hai jise instant authority signal chahiye (agar zaroorat pade to separately
  mitigate kiya jaata hai, bahut recent/breaking content ko sirf authority pe
  rely karne ke bajaye apna hi freshness-weighted ranking boost dekar).
- **150+ TB compressed pe index storage cost real infrastructure decisions
  drive karta hai**: posting-list compression techniques aur low-value terms
  ko drop karna (extremely common stopwords, jo apni storage cost ke relative
  kaafi kam discriminative signal contribute karte hain) standard levers hain,
  jo retrieval completeness ka thoda amount materially lower storage aur
  faster shard-local scans ke liye trade karte hain.

## Follow-up Questions an Interviewer Might Ask

**Phrase queries kaise support karoge (e.g. "best ramen in sf" ek exact phrase
ki tarah, na ki sirf chaaro terms kahin bhi present hon)?** Posting lists ko
extend karo taaki har document ke andar term *positions* store hon (data model
mein `positions[]` field mein already reflect hota hai), taaki retrieval stage
sirf ye check na kare ki phrase ke saare terms ek candidate document mein
present hain, balki ye bhi ki wo sahi consecutive positions mein appear hote
hain — ye ek plain multi-term AND match se per candidate zyada expensive hai,
jo isi wajah ka hissa hai ki ye still cheap retrieval stage pe posting-list
data pe apply kiya jaata hai, expensive ranking stage tak defer nahi kiya
jaata.

**Aap results ko per user kaise personalize karoge?** Personalization ko sirf
ek aur signal ki tarah add karo jo expensive ranking stage mein blend hota hai
(cheap retrieval stage mein kabhi nahi, jo generic aur users ke across
cacheable rehna chahiye) — e.g. candidates ko user ki location, search
history, ya similar queries pe prior click behavior ke basis pe boost karna,
usi small merged candidate set pe apply kiya jaata hai jispe base ranking
model already operate karta hai.

**Spam aur low-quality content jo ranking ko game karta hai (e.g. link farms
jo artificially authority scores inflate karte hain) use aap kaise handle
karoge?** Ye apne aap mein ek bada topic hai; system-design level pe, answer
ye hai ki link-graph authority computation aur content-processing/dedup
pipeline dono ko spam-detection heuristics chahiye (unnatural linking
patterns detect karna, near-duplicate spam clusters, thin/auto-generated
content) jo manipulated signals ko discount ya exclude kar dein unke ranking
model tak pahunchne se pehle, sirf query time pe spam pakadne ki koshish karne
ke bajaye.

**Har request ke liye saare 1,000 shards query karne se hone waali tail
latency aap kaise reduce karoge?** Per-shard timeouts aur partial-result
tolerance (Step 7 mein mentioned) ke aage, ek cheap pre-filtering/routing layer
consider karo jo bahut selective queries ke liye un shards ko skip kar sake
jinme relevant documents hone ki possibility nahi hai (e.g. lightweight
per-shard Bloom filters ya term-presence summaries ke through), jo ek skipped
shard pe kisi rare match miss hone ki small chance ko meaningfully lower
average fan-out ke liye trade karta hai.

**Ye design ek niche vertical search engine (e.g. sirf ek company ke product
catalog ke andar search karna) ke liye general web search ke against kaise
change hota hai?** Smaller corpus scale pe, term-partitioning ke downsides
(uneven shard load, complex multi-term coordination) kaafi kam painful ho
jaate hain kyunki posting lists aur shard counts dono dramatically chhote hote
hain, isliye ye ek zyada viable alternative ban jaata hai — Step 6 mein
document-partitioning recommendation explicitly web-scale corpus size aur
ingestion rate ka ek consequence hai, koi universal rule nahi.

**Aap autosuggest/typeahead ko efficiently kaise support karoge?** Briefly: ek
separate, kaafi chhota index structure (e.g. ek trie ya query logs aur popular
terms se built prefix ke hisaab se keyed ek precomputed top-N-completions
table), jo main document index se distinct ek small, fast, heavily-cached
store se serve kiya jaata hai — full-text document retrieval se ek different
problem shape (query strings ke ek bounded vocabulary ke over prefix
matching), isi wajah se ise core index design mein fold karne ke bajaye ek
secondary feature ki tarah call out kiya gaya hai.
