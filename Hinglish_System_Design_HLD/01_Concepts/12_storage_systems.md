# Storage Systems

## Why it matters

Wrong job ke liye galat storage type choose karna system design mein sabse common over-engineering *aur* under-engineering mistakes mein se ek hai:

- **Large binary files (images, videos, backups) ko directly relational database mein store karna** database ko bloat kar deta hai, backups ko slow aur expensive bana deta hai, aur ek expensive, latency-optimized system ko waste kar deta hai us cheez pe jise transactional guarantees ya indexes ki zaroorat hi nahi — object storage exist hi isi ke liye karta hai aur is kaam ke liye kaafi cheaper aur scalable hai.
- **Live production database ke against directly analytical/reporting queries chalana** (e.g., "2 saal ke order history ko aggregate karke ek report generate karo") un hi resources ke liye compete karta hai jo live application ko fast transactional reads/writes ke liye chahiye hote hain, aur ek bada report run production app ko degrade ya crash bhi kar sakta hai.
- **Aise design mein data lake/warehouse le aana jahan analytics maanga hi nahi gaya tha** real operational complexity add karta hai (ETL pipelines, tumhare saare data ki dusri copy, run karne ke liye ek doosra system) ek aisi requirement ke liye jo kisi ne bataya hi nahi — interview answer ko over-engineer karne ka classic sign hai ye.

Ye jaanna ki kaunsa storage system kis access pattern pe map hota hai — aur utna hi zaroori ye jaanna ki kab ek naya introduce *na* karein — core system design judgment hai.

## Block storage vs file storage vs object storage

Ye teen fundamentally alag models hain data store karne ke liye, jo is baat se differ karte hain ki data kaise address hota hai aur kis tarah ke access pattern ke liye ye bane hain.

- **Block storage**: raw storage volumes, jo machine ko present kiye jaate hain jaise ki wo ek physical disk ho. Machine ka apna OS ise ek filesystem se format karta hai aur manage karta hai — storage layer ko khud "files" ka koi concept nahi hota, sirf location se addressed fixed-size blocks hote hain. Example: AWS EBS (Elastic Block Store). Use hota hai un cheezon ke liye jinhe full filesystem control ke saath low-latency random I/O chahiye, especially databases — ek database engine chahta hai ki uska data disk pe kaise layout hoga is par direct, fast, low-level control ho.
- **File storage**: ek shared, hierarchical filesystem (directories aur files, bilkul local filesystem jaisa) jo **network ke over** multiple machines ek saath access kar sakti hain. Example: AWS EFS, NFS (Network File System). Use hota hai jab multiple machines ko same shared files concurrently read/write karne hain — e.g., application servers ki ek fleet jo uploaded files ya shared configuration share kar rahi ho.
- **Object storage**: immutable **objects** ka ek flat namespace, jahan har object ek unique key se identify hota hai, associated metadata ke saath store hota hai, aur HTTP API (filesystem mount nahi) ke through access hota hai — ek key pe `GET`, `PUT`, `DELETE`. Example: AWS S3. Use hota hai large, unstructured blobs ke liye — images, videos, backups, log archives, static assets — kuch bhi jo ek baar likha jaaye aur bahut baar padha jaaye, bina in-place kisi part ko modify kiye.

| | Block storage | File storage | Object storage |
|---|---|---|---|
| Access unit | Fixed-size blocks | Directory hierarchy mein files | HTTP API ke through poore objects |
| Latency | Sabse kam (near-local-disk) | Kam-moderate (network filesystem overhead) | Zyada (HTTP request overhead) |
| Scalability | Volume size tak limited; zyada volumes attach karke scale hota hai | Moderate — shared but filesystem service se bound | Effectively unlimited — horizontally scale karne ke liye designed |
| Typical access pattern | Random reads/writes, low-level, usually ek waqt mein ek machine | Shared concurrent access, POSIX-like file semantics | Write-once/read-many, large blobs, koi in-place partial edits nahi |
| Cost | Higher per GB | Higher per GB | Sabse kam per GB |
| Example use case | Database ka data directory | Shared home directories, server fleet mein shared app config | Images, videos, backups, static site assets, data lake files |

## Object storage actually scale kaise karta hai

Object storage systems jaise S3 effectively unlimited size tak scale karte hain kuch deliberate design choices ki wajah se jo flexibility trade karke scalability paate hain:

- **Flat key-namespace**: neeche koi real directory hierarchy hoti hi nahi — `photos/2024/vacation/img1.jpg` jaisi key sirf ek opaque string key hai, nested directory lookups ki chain nahi. UI/console mein jo "folder" structure dikhta hai wo sirf display ke liye keys ko `/` pe split karke banaya gaya ek cosmetic illusion hai — storage system khud kisi object ko dhoondhne ke liye directory tree walk nahi karta, wo directly key lookup karta hai. Isse ek real hierarchical filesystem wala scaling bottleneck avoid ho jaata hai (directory structures ko traverse/lock karna jaise-jaise wo badhte jaayen).
- **Objects immutable hote hain**: tum object ke kisi part ko in-place edit nahi karte — ek "update" actually ek full replace hota hai (same key ke neeche ek naya object upload karna, jo purane ko poori tarah replace kar de). Isse replication aur caching kaafi simplify ho jaate hain: kyunki ek object kabhi apni given version ke neeche change nahi hota, replicas ko complex in-place-edit coordination ki zaroorat nahi padti, aur ek baar cache ho jaane ke baad, cached copies valid rehti hain jab tak explicitly replace na ki jaayen.
- **Distributed aur replicated across many nodes**: har object (aur aksar object ka har piece) durability ke liye multiple physical nodes pe store hota hai, aur system storage aur request load dono ko bahut saare nodes pe spread kar sakta hai, ek machine ki capacity tak bound hue bina.
- **Consistency model**: historically, bahut saare object stores overwrites ke liye sirf **eventually consistent** the (update ke turant baad tumhe briefly stale data ya purani version dikh sakti thi, jab tak change saare replicas tak propagate na ho jaaye). Modern systems ne ye improve kar diya hai — S3, for example, ab new object PUTs aur overwrites/deletes dono ke liye **strong read-after-write consistency** deta hai. Ye jaanna abhi bhi worthwhile hai ki eventual-consistency model kyun exist karta tha (bahut saare replicated nodes tak propagation mein kuch non-zero time lagta hai), kyunki ye explain karta hai ki kyun kuch aur/purane object stores abhi bhi waise behave karte hain aur kyun tumhe hamesha check karna chahiye ki jis specific object store ko tum actually use kar rahe ho uski exact consistency guarantee kya hai.

Flat namespace (koi hierarchy nahi jisko traverse/lock karna pade) aur immutability (koi in-place-edit coordination nahi chahiye) ka combination hi exactly wo cheez hai jo object storage ko horizontally scale karne deta hai essentially unlimited size tak — har doosre storage model ki scaling limits structure ke around coordinate karne ki zaroorat se aati hain (ek filesystem tree) ya in-place mutation se (ek database row), aur object storage deliberately in dono mein se koi nahi rakhta.

### Storage classes / tiering

Zyaadatar object storage systems tumhe har object ke liye ek **storage class** assign karne dete hain, jisme retrieval latency/availability ko cost ke against trade kiya jaata hai — ye ek common practical detail hai jo interviewers probe karte hain ek baar basic object-storage answer establish ho jaaye:

| Class (S3 naming, representative) | Retrieval | Typical use | Relative cost |
|---|---|---|---|
| Standard | Instant | Frequently accessed objects (active user uploads, current assets) | Highest |
| Infrequent Access | Instant, but per retrieval charge | Backups, occasionally accessed older data | Lower storage cost |
| Glacier / cold archive | Retrieve karne mein minutes to hours | Long-term compliance archives, rarely touched | Lowest |

Ek **lifecycle policy** automatically objects ko classes ke beech move karti hai jaise-jaise wo age karte hain (e.g., "30 din baad Infrequent Access mein move karo, 180 din baad Glacier mein") — ye practical mechanism hai storage cost ko data ki actual "hotness" ke proportional rakhne ke liye, bina manual intervention ke.

## CDN se tie-in

Object storage commonly **origin** server ke roop mein use hoti hai jise ek CDN (Content Delivery Network) pull karta hai aur users ke paas edge locations pe cache karta hai (poori edge caching treatment ke liye `05_caching.md` ka CDN section dekho). Ek typical setup: images/videos S3 pe upload hoti hain, aur ek CDN S3 bucket ke saamne configure kiya jaata hai — kisi given object ke liye pehla request S3 se fetch hota hai aur nearest edge location pe cache ho jaata hai, aur us object ke liye baad ke har request, kisi bhi nearby user se, seedha edge cache se serve hote hain bina S3 (origin) ko dobara hit kiye. Ye combination — durable origin storage ke liye object storage, low-latency global delivery ke liye CDN — static assets aur media ko scale pe serve karne ka standard pattern hai.

```text
User --> CDN Edge (cache hit: serve directly)
              |
              v (cache miss: fetch once)
         Object Storage (origin, e.g. S3)
```

## Data lake vs data warehouse

Ye data store karne ke do alag approaches hain **analytics** ke liye, jaisa ki live application ko power karne ke liye data store karne se alag hai (uss distinction ke liye neeche OLTP vs OLAP dekho).

- **Data lake**: raw data — structured, semi-structured, ya fully unstructured — store karta hai as-is, cheaply, large scale pe, bina koi schema upfront impose kiye. Ye **schema-on-read** hai: structure ko query time pe interpret/apply kiya jaata hai, jo bhi job ya tool data padh raha hai wo karta hai, data likhe jaane ke waqt enforce hone ke bajaye. Use hota hai flexible, large-scale analytics aur machine learning workloads ke liye jahan tum sab kuch retain karna chahte ho (including wo data jiska eventual use abhi fully pata nahi) bina sab kuch pehle model aur clean karne ki upfront cost pay kiye.
- **Data warehouse**: structured, cleaned, aur modeled data store karta hai, schema data likhe jaane **se pehle** define aur enforce kiya jaata hai — **schema-on-write**. Fast, well-structured business queries (dashboards, reports, BI tools) ke liye optimized, aise data pe jo already ek known, query-friendly shape mein transform ho chuka hai.

| | Data lake | Data warehouse |
|---|---|---|
| Data shape | Raw, unstructured/semi-structured | Structured, cleaned, modeled |
| Schema | Schema-on-read (query time pe apply) | Schema-on-write (write time pe enforce) |
| Flexibility | High — kuch bhi store karo, structure baad mein figure out karo | Kam — predefined schema mein fit hona zaroori |
| Known business questions ke liye query speed | Slower — structure har query ke liye infer/parse karna padta hai | Fast — data exactly isi ke liye pre-shaped hai |
| Typical users | Data scientists, ML pipelines, exploratory analytics | Business analysts, BI dashboards, reporting |
| Cost | Cheap raw storage (aksar neeche object storage) | Zyada expensive — purpose-built query engines |

### OLTP vs OLAP

Ye zyada general pattern hai jispe data lakes/warehouses map hote hain:

- **OLTP (Online Transaction Processing)**: operational databases jo live application ko power karte hain — **bahut saare small, fast reads aur writes** ke liye optimized (e.g., "ye order insert karo," "is user ka address update karo"), typically normalized, row-oriented, aur low-latency point queries aur transactions ke liye tuned. Ye tumhara everyday application Postgres/MySQL/DynamoDB hai.
- **OLAP (Online Analytical Processing)**: **huge historical datasets pe complex aggregate queries** ke liye optimized (e.g., "pichle 3 saal mein region-wise, month-wise total revenue") — typically denormalized/columnar, large volumes of data ko efficiently scan aur aggregate karne ke liye tuned, fast individual-row lookups ke bajaye. Ek data warehouse classic OLAP system hai.

Ye usually **separate systems** kyun hote hain, ek database dono ka kaam karne ke bajaye: inke access patterns lagbhag opposite hote hain (OLTP ko bahut saari fast small transactions chahiye; OLAP ko huge amounts of data pe efficient scans chahiye) aur ek database engine ko ek ke liye achhe se optimize karna dusre ke against kaam karta hai — isliye data typically pehle OLTP store mein live application se likha jaata hai, phir periodically extract/transform/load (ETL/ELT) karke OLAP store (warehouse) mein daala jaata hai analytics ke liye, taaki dono workloads same resources ke liye compete na karein.

**ETL vs ELT**, us pipeline ke do orderings: **ETL (Extract, Transform, Load)** data ko destination mein load karne *se pehle* transform/clean karta hai — destination hamesha already-shaped data hi hold karta hai, jo traditional data-warehouse approach hai. **ELT (Extract, Load, Transform)** raw data ko pehle destination mein load karta hai aur baad mein transform karta hai, destination ke apne compute ka use karke — ye zyada common pattern hai data lakes aur modern cloud warehouses (e.g., Snowflake, BigQuery) ke saath jinke paas data ko in-place cheaply transform karne layak enough compute power hai. Object storage formats jo commonly use hote hain us raw lake data ko efficiently hold karne ke liye unme columnar formats jaise **Parquet** ya **ORC** shamil hain, jo achhe se compress hote hain aur analytical queries ko poori rows scan karne ke bajaye sirf zaroori columns padhne dete hain — worth naming agar koi question lake ke internals mein deep jaaye, but unprompted volunteer karne wali cheez nahi.

## System design interviews mein kaunsa storage type kab chahiye

Ek practical decision guide, aur — utna hi zaroori — un layers ko over-include karne ke against ek warning jo mange hi nahi gaye:

- **OLTP relational ya NoSQL database** — live application ke core state ke liye (user accounts, orders, posts, sessions). Ye almost har design question ke liye "app ka data kahaan rehta hai" ka default answer hai.
- **Object storage** — media/blobs ke liye (images, videos, file uploads, backups, exports). Agar design mein us media ko bahut saare users ko serve karna involve ho to CDN ke saath pair karo.
- **Data lake/warehouse** — **sirf** tab jab question explicitly analytics ya reporting at scale involve kare (e.g., "company ko 2 saal ke daily active users trends dikhane wala dashboard chahiye," ya "saare user activity pe ML training chalao"). Zyaadatar "design X app" interview questions (design Twitter, design an URL shortener, design an e-commerce checkout) ye kabhi nahi maangte, aur unprompted data lake/warehouse introduce karna over-engineering jaisa lagta hai — ye signal deta hai ki tum stated requirements ke against design karne ke bajaye buzzwords pe pattern-match kar rahe ho. Agar doubt ho, layer add karne se pehle interviewer se pooch lo ki analytics/reporting scope mein hai ya nahi.

## Trade-offs / When to use what

| Need | Storage choice |
|---|---|
| Database ki apni data directory, low-latency random I/O | Block storage |
| Multiple machines ko shared, concurrent file access chahiye | File storage (NFS/EFS) |
| Large unstructured blobs (images, video, backups), scale pe serve hote hue | Object storage (+ CDN) |
| Live application transactional state | OLTP database |
| Ad hoc, flexible, large-scale analytics/ML raw data pe | Data lake |
| Fast structured business reporting/BI dashboards | Data warehouse (OLAP) |
| "Design X app" question jisme koi analytics requirement nahi bataayi gayi | Sirf OLTP DB + object storage — lake/warehouse poori tarah skip karo |

## Interview Tips

- Agar design mein user-uploaded media (photos, videos, documents) involve ho, to turant object storage + CDN pe jao primary database mein store karne ke bajaye — ye ek most commonly expected answer hai aur ise skip karna ek red flag hai.
- Push hone pe justify karne ke liye ready raho ki object storage aise scale *kyun* karta hai (flat namespace, immutability) — "ye bas aise hi scale karne ke liye design kiya gaya hai" actual mechanism explain karne se ek weaker answer hai.
- Data lake/data warehouse/OLAP layer unprompted volunteer mat karo jab tak prompt explicitly analytics, reporting, ya ML mention na kare — agar unsure ho ki wo scope mein hai ya nahi, to assume karne ke bajaye interviewer se pooch lo. Ise unprompted add karna over-engineering ka ek common tell hai interview pressure ke neeche.
- Agar poocha jaaye "production database ke against directly analytics queries kyun nahi chalate," to expected answer resource contention hai: huge datasets pe OLAP-style aggregate queries live app ke OLTP workload ke saath same database resources ke liye compete karte hain, jisse production app degrade ho sakta hai — isliye ETL se connected separate OLTP/OLAP systems.
- S3 consistency model detail jaano (strong read-after-write, historically eventual) — ye ek common "gotcha" follow-up hota hai jab koi design "upload then immediately read" behavior pe rely karta hai.

## Quick Recall — Self-Test

**Q1: Block storage, file storage, aur object storage ke access pattern mein core difference kya hai?**
Block storage raw addressable blocks expose karta hai jinhe ek single machine ka OS khud format aur manage karta hai (low-latency random I/O ke liye, e.g. ek database ki disk). File storage ek shared hierarchical filesystem expose karta hai jo multiple machines network ke over access kar sakti hain. Object storage immutable objects ka flat namespace expose karta hai jo HTTP API se accessed hota hai, large blobs ke liye bana hai jo ek baar likhe jaate hain aur bahut baar padhe jaate hain.

**Q2: Kaunse do design choices object storage ko virtually unlimited size tak scale karne dete hain, aur har ek kyun matter karta hai?**
Ek flat key-namespace real directory hierarchy ko traverse ya lock karne ki zaroorat avoid karta hai jaise-jaise wo badhti hai (koi structural bottleneck nahi), aur immutability (updates full replaces hain, in-place edits nahi) concurrent in-place mutation ke liye chahiye coordination overhead avoid karta hai, jisse replicas aur caches complex synchronization ke bina simple aur valid reh sakte hain.

**Q3: S3 aaj new objects aur overwrites dono ke liye kaunsi consistency guarantee deta hai, aur ye jaanna kyun worthwhile hai ki ye time ke saath change hui?**
S3 ab new PUTs aur overwrites/deletes dono ke liye strong read-after-write consistency deta hai. History jaanna worthwhile hai kyunki bahut saare object stores historically overwrites ke liye sirf eventually consistent the (replicas mein propagation time leta hai), isliye tumhe hamesha verify karna chahiye ki jis specific object store pe koi design rely karta hai uski guarantee kya hai, har jagah strong consistency assume karne ke bajaye.

**Q4: Schema-on-read aur schema-on-write mein kya difference hai, aur kaunsa storage type kaunsa use karta hai?**
Schema-on-read ka matlab hai structure query time pe jo bhi data padh raha hai wo interpret karta hai — data lakes use karte hain, jo raw data ko as-is store karte hain. Schema-on-write ka matlab hai schema data likhe jaane se pehle define aur enforce kiya jaata hai — data warehouses use karte hain, jo already-cleaned, modeled data store karte hain.

**Q5: OLTP aur OLAP typically separate systems ke roop mein kyun implement hote hain, ek database dono serve karne ke bajaye?**
Inke access patterns lagbhag opposite hain: OLTP ko bahut saari small, fast transactional reads/writes chahiye, jabki OLAP ko huge historical datasets pe efficient aggregate scans chahiye. Ek database engine jo ek ke liye achhe se optimized ho wo dusre ke against kaam karta hai, isliye data live app se OLTP store mein likha jaata hai aur periodically ek separate OLAP store mein ETL kiya jaata hai analytics ke liye — taaki dono workloads same resources ke liye contend na karein.

**Q6: Typical "design X app" system design interview mein, data lake ya warehouse kab introduce karna chahiye?**
Sirf tab jab prompt explicitly analytics ya reporting at scale involve kare (e.g., historical trend dashboards, user activity pe ML training) — zyaadatar app-design questions mein is layer ki zaroorat hi nahi hoti, aur ise unprompted add karna ek common over-engineering mistake hai; agar unsure ho ki ye scope mein hai ya nahi, to interviewer se pooch lo.

**Q7: Object storage typically ek real architecture mein CDN se kaise related hota hai?**
Object storage commonly CDN ke origin ka kaam karta hai: kisi object ke liye pehla request object storage se fetch hota hai aur nearest edge location pe cache ho jaata hai, aur baad ke nearby requests us edge cache se serve hote hain bina origin ko dobara hit kiye — durable, cheap origin storage ko low-latency global delivery ke saath combine karte hue.

**Q8: Large uploaded videos ko directly relational database mein store karna ek mistake kyun hoga?**
Ye database ko large binary data se bloat kar deta hai jise handle karne ke liye wo efficiently bana hi nahi, backups ko slow aur expensive bana deta hai, aur ek expensive, latency-optimized transactional system ko us cheez pe waste karta hai jisme indexes ya transactional guarantees ki zaroorat nahi — object storage large blobs ke liye purpose-built hai aur kaafi cheaper/scalable hai.

**Q9: Storage class lifecycle policy kya karti hai, aur cost ke liye ye kyun matter karti hai?**
Ye automatically objects ko unki age ke hisaab se storage classes ke beech move karti hai (e.g., Standard se Infrequent Access se Glacier), rules ke basis pe jaise "30 din baad move karo." Isse storage cost data ki actual access frequency ke proportional rehti hai, bina aging data ko manually reclassify kiye.

**Q10: ETL aur ELT mein kya difference hai, aur modern data lakes/warehouses ke saath ELT zyada common kyun ho gaya hai?**
ETL data ko destination mein load karne se pehle transform karta hai, isliye destination hamesha already-shaped data hi hold karta hai. ELT pehle raw data load karta hai aur baad mein destination ke apne compute se transform karta hai. ELT zyada common ho gaya hai kyunki modern cloud warehouses aur lake-adjacent query engines ke paas data ko in-place cheaply transform karne layak enough compute power hai, load se pehle ek separate transformation stage avoid karte hue.
