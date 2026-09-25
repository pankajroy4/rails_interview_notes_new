# Databases — Fundamentals

Ek database ko scale karne (`07_database_scaling.md`) ya failure ke under uski consistency guarantees (`08_cap_theorem_and_consistency.md`) ke baare mein reason karne se pehle, aapko ek solid model chahiye ki ek database actually aapse kya promise kar raha hai, aur different databases different cheezein kyun promise karte hain. Yeh file vocabulary cover karti hai: relational databases aur ACID, major NoSQL categories aur BASE, indexing, aur normalization — woh foundation jispar is folder mein baaki sab kuch build hota hai.

## Yeh important kyun hai

Database pick karna ek stylistic choice nahi hai — yeh aapke access patterns aur consistency requirements par ek bet hai jise baad mein unwind karna expensive hota hai. In fundamentals ko samjhe bina:

- Aap aisa database pick kar sakte ho jo aapke query patterns ko efficiently express nahi kar sakta (jaise, ek key-value store aise data ke liye jise complex joins aur ad-hoc queries chahiye), jisse painful application-level workarounds karne padte hain.
- Aap aise transactional guarantees assume kar sakte ho jo ek NoSQL store ne kabhi promise kiye hi nahi the, aur production mein paisa ya data integrity lose kar sakte ho (ek user ko double-charge karna kyunki do concurrent writes isolated nahi thi).
- Aap ek read-heavy system ko joins ke ek maze mein over-normalize kar sakte ho jo apni latency targets hit nahi kar paata, ya ek write-heavy system ko inconsistent duplicated data ke ek swamp mein under-normalize kar sakte ho.
- Aap sabse common system design interview question ka jawaab nahi de paoge: "aapne yeh database kyun choose kiya?"

## Relational (SQL) Databases aur ACID

Ek **relational database** data ko tables (**relations**) mein organize karta hai jinme rows aur columns hote hain, jahan tables ke beech relationships **foreign keys** ke through express hoti hain, aur data ek declarative language (SQL) ke through query hota hai jo aapko tables ke across join karne deta hai. Examples: PostgreSQL, MySQL, SQL Server, Oracle.

Isse "relational" banane wali cheez sirf "tables hain" nahi hai — yeh hai ki schema fixed aur enforced hota hai (ek table ki har row mein same columns hote hain, same declared types ke saath) aur entities ke beech relationships explicitly keys ke through model kiye jaate hain, jisse database engine referential integrity enforce kar sakta hai (aap ek order ko ek aise customer ki taraf point nahi kar sakte jo exist hi nahi karta) aur multi-table queries (joins) efficiently execute kar sakta hai.

Relational databases ki defining guarantee **ACID** hai — chaar properties jo ek database transaction (operations ka ek group jo ek unit ki tarah succeed ya fail hona chahiye) guarantee karta hai. Poore mein running example: **Alice ke account se Bob ke account mein $100 transfer karna** (do writes: Alice ko debit karna, Bob ko credit karna).

- **Atomicity**: transaction all-or-nothing hota hai. Agar Alice ke account se debit succeed ho jaaye lekin Bob ke account mein credit fail ho jaaye (server mid-transaction crash ho jaaye), toh *poora* transaction rollback ho jaata hai — Alice ka account uske original balance mein restore ho jaata hai. Aap kabhi aisi state mein nahi hote jahan paisa gayab ho gaya ho kyunki ek two-part operation ka aadha hissa complete hua tha.
- **Consistency**: transaction database ko ek valid state se doosri valid state mein le jaata hai, sabhi defined rules (constraints, triggers, foreign keys) respect karte hue. Agar ek constraint hai ki account balances kabhi negative nahi ho sakte, ek transfer jo Alice ke account ko overdraw kar de use poori tarah reject kar diya jaata hai — database kabhi bhi apne khud ke rules violate karne wali state allow nahi karta, chahe woh transiently ho.
- **Isolation**: concurrent transactions ek dusre ki intermediate, uncommitted state nahi dekhte. Agar Alice ka Bob ko transfer in-progress hai usi waqt jab ek separate transaction dono balances *read* kar raha hai (maan lo, ek bank statement ke liye), woh read ya toh transfer se poori tarah pehle ki state dekhta hai ya poori tarah baad ki — kabhi ek half-applied state nahi dekhta jahan Alice debit ho chuki ho lekin Bob abhi tak credit na hua ho.
- **Durability**: ek baar transaction commit ho jaaye (bank confirm kar de "aapka transfer successful hua"), woh kisi bhi subsequent crash ko survive karta hai — ek second baad power outage bhi ise un-commit nahi kar sakta. Yeh normally write-ahead logging ke through durable storage mein commit acknowledge karne se pehle achieve kiya jaata hai.

ACID hi wahi cheez hai jo aapko ek multi-step operation ko ek single logical unit ki tarah treat karne deti hai aur database par trust karne deti hai ki woh aapko kabhi ek partially-applied, inconsistent state mein nahi chhodega — jo exactly wahi cheez hai jo aapko money, inventory counts, ya kisi bhi aisi cheez ke liye chahiye jahan "half-done" "not done" se worse ho.

## NoSQL Database Types

**NoSQL** ("not only SQL") ek umbrella term hai un databases ke liye jo relational table/row/join model use nahi karte, typically SQL ki strict schema aur transactional guarantees ka kuch hissa flexibility, horizontal scalability, ya kisi specific access pattern par performance ke liye trade karte hain. Chaar major categories hain, har ek data aur access pattern ke ek different shape ke liye purpose-built — category kisi bhi individual product se zyada matter karta hai.

| Type | Definition | Example DB | Canonical use case |
|---|---|---|---|
| Key-Value | Data ek unique key se addressed opaque values ki tarah store hota hai, value ki structure ke andar query nahi ki ja sakti | Redis, DynamoDB | Session storage, caching, shopping carts — kuch bhi jo purely ID se look up hota hai |
| Document | Semi-structured documents (usually JSON/BSON) flexible, nested, per-record schemas ke saath | MongoDB | Content management, product catalogs, user profiles — data jo record se record shape mein vary karta hai |
| Column-family (wide-column) | Data rows ke bajaye column groups se store hota hai, massive writes aur ek partition key ke over range scans ke liye optimized | Cassandra, HBase | Write-heavy time-series data, logging, IoT sensor data bahut large scale par |
| Graph | Data nodes aur edges ki tarah model hota hai, relationships traverse karne ke liye optimized | Neo4j | Social graphs, recommendation engines, fraud-detection networks — data jahan *connections* hi point hain |

Har ek ke baare mein thoda aur:

- **Key-value stores** simplest possible model hain: `get(key)` aur `set(key, value)`, aur kuch nahi. Yehi simplicity point hai — isi wajah se yeh extremely fast aur trivially shardable hain (kisi value ko shard par route karne ke liye aapko uski structure samajhne ki zaroorat nahi). Aise data ke liye achha hai jo sirf ek known ID se access hota hai, kharab tab jab aapko value ke contents *se* query karni ho.
- **Document stores** fixed-schema requirement ko relax kar dete hain — same collection ke do "documents" mein different fields ho sakte hain. Yeh aise data ke liye suit karta hai jiski shape genuinely vary karti hai ya jaldi evolve hoti hai (ek product catalog jahan ek shoe ka "size" field hai aur ek book ka nahi) bina har change ke liye schema migration chahiye hue. Trade-off: koi enforced schema na hone ka matlab hai application us data consistency ka responsible hai jo database pehle guarantee karta tha.
- **Column-family stores** data ko physically row ke bajaye column se group karte hain, aur data ko nodes ke across ek partition key se partition karte hain data ko ek clustering key se ordered rakhte hue. Yehi cheez unhe high-volume sequential writes aur ek partition ke andar range scans mein exceptional banati hai (jaise, "device X ke sabhi sensor readings time A aur B ke beech") — ek pattern jise relational databases extreme write volume par kaafi kharab handle karte hain.
- **Graph databases** relationships ko first-class citizens ki tarah store karte hain (edges apni khud ki properties ke saath, query-time par compute hue foreign-key joins nahi). "Friends of friends of friends" traverse karna ek graph DB mein ek constant-time pointer-following operation hai versus ek relational DB mein ek expensive multi-way join — yehi poora reason hai ki yeh exist karte hain.

### BASE — NoSQL-World Ka ACID Ke Against Contrast

Kayi NoSQL systems (especially woh jo kayi nodes ke across horizontal scale ke liye bane hain) ACID ko **BASE** ke favor mein relax kar dete hain:

- **Basically Available**: system availability guarantee karta hai (har request ka ek response) even ek partial failure ke dauraan bhi, perfect correctness se zyada uptime ko prioritize karte hue.
- **Soft state**: system ki state time ke saath change ho sakti hai bina naye input ke bhi, kyunki replication background mein catch up kar rahi hoti hai — data ACID ke tehat wali tarah ek single fixed, immediately-consistent value nahi hai.
- **Eventually consistent**: koi naye writes na hone par enough time diya jaaye toh, sabhi replicas same value par converge ho jaayenge — lekin kisi bhi given instant par, different nodes different (stale) answers return kar sakte hain.

BASE ACID se "worse" nahi hai — yeh ek different goal ke liye ek different trade hai: BASE systems generally immediate consistency ko sacrifice karke availability aur horizontal write scalability gain karte hain jo strict ACID systems ko kayi distributed nodes ke across achieve karne mein struggle hoti hai. Is trade-off ka theoretical basis `08_cap_theorem_and_consistency.md` mein dekho.

## Indexing

Ek **index** ek auxiliary data structure hai jo database ko poori table scan kiye bina query matching rows dhundne deti hai. Index ke bina, 10 million rows mein se "email X wala user" dhundhne ka matlab hai up to 10 million rows ko ek-ek karke check karna (ek full table scan, O(n)).

Dominant structure **B-tree** hai (ya uska variant, B+tree): ek sorted, balanced tree structure jahan har node ke kayi children ho sakte hain, tree ko huge datasets ke liye bhi shallow rakhte hue. Conceptually, yeh binary search ka ek disk-friendly structure mein generalization hai — linearly scan karne ke bajaye, database tree ke har level par search space ko narrow karta hai, O(n) ke bajaye **O(log n)** lookups dete hue. Kyunki structure shallow rehta hai (millions rows ke over ek B-tree sirf 3-4 levels deep ho sakta hai), ek lookup potentially millions ke bajaye sirf handful disk reads leta hai.

```text
Bina index ke (full scan):        B-tree index ke saath:
[row1][row2][row3]...[row_n]         [root: ranges mein split hota hai]
  har row scan, O(n)                /        |         \
                                  [range]   [range]    [range]
                                    /  \       ...        ...
                               [leaf][leaf]  -> matching row(s), O(log n)
```

**Fundamental trade-off**: ek index reads ko dramatically fast bana deta hai, lekin har index ko har `INSERT`, `UPDATE`, ya `DELETE` par bhi update hona padta hai jo ek indexed column ko touch kare — isliye writes slow ho jaate hain, aur har index additional disk space consume karta hai. Ek table jiski paanch indexes hain use har write par un paanchon structures ko update karne ki write-amplification cost pay karni padti hai. Isi liye aap un columns ko index karte ho jinpar aap actually filter/sort/join karte ho, reflexively har column ko nahi — sab kuch index karna woh write performance trade away kar deta hai jo aapko chahiye ho sakta hai.

## Normalization vs Denormalization

**Normalization** relational data ko redundancy khatam karne ke liye structure karne ka process hai — har fact exactly ek jagah store hota hai, aur related data ko separate tables mein split kiya jaata hai jo foreign keys se linked hote hain. Iska purpose **update anomalies** prevent karna hai: agar ek user ka email different tables mein 50 rows mein redundantly store ho, use update karne ka matlab hai un sabhi 50 ko dhundhna aur update karna (ya ek miss kar dene par inconsistent copies ka risk lena). Normalization ise fix karta hai ise ek baar, ek `users` table mein store karke, aur baaki sab kuch use ID se reference kare.

**Denormalization** deliberately redundancy reintroduce karta hai — tables/documents ke across data duplicate karta hai — read time par join karne ki cost avoid karne ke liye. System design interviews frequently read-heavy systems ke liye denormalization favor karti hain, kyunki jo calculus normalization ko favor karta hai (storage minimize karo, anomalies avoid karo) scale par jo calculus matter karta hai uske secondary ho jaata hai (read latency aur query complexity minimize karo).

**Concrete example**: ek social feed ko har post ko uske author ke display name ke saath render karna hai. Normalized approach: `posts` table `author_id` store karta hai; har feed read `users` ke against ek `JOIN` karta hai naam fetch karne ke liye. Feed-rendering scale par (thousands of reads per second, har ek mein dozens of posts dikhte hue), yeh aise data ke liye constantly execute hone wala ek join hai jo rarely change hota hai. Denormalized approach: `author_name` ko directly post record (ya post document) par write time par store karo. Ek feed read karna ab bina join ke ek single query hai — faster, aur scale karna simpler (dekho `07_database_scaling.md` mein federation, jahan separately-scaled databases ke across joins possible hi nahi hote). Cost: agar ek user apna display name change karta hai, ab aapko use unki likhi har post par update karna padega (ya accept karna padega ki old posts old naam dikhaayenge jab tak koi backfill process catch up na kare) — classic update-anomaly risk jise prevent karne ke liye normalization exist karta hai, ab purposely reintroduce kiya gaya kyunki us field ke liye reads writes se kaafi zyada hain.

| | Normalization | Denormalization |
|---|---|---|
| Redundancy | Minimized — har fact ek baar store hota hai | Deliberately duplicate kiya gaya |
| Read performance | Slower (joins chahiye) | Faster (koi joins nahi chahiye) |
| Write/update complexity | Simple (ek jagah update karo) | Complex (har duplicate update karo, ya staleness tolerate karo) |
| Storage | Chhota | Bada |
| Best for | Write-heavy, consistency-critical data (financial records) | Read-heavy data jahan join cost dominate karta hai (feeds, catalogs) |

## SQL vs NoSQL — Decision Framework

| Yeh SQL choose karo jab... | Yeh NoSQL choose karo jab... |
|---|---|
| Data naturally structured/relational hai | Schema flexible hai ya frequently evolve karta hai |
| Aapko multi-row/multi-table transactions chahiye (ACID) | Access patterns simple aur advance mein known hain (key se lookup) |
| Strong consistency required hai (financial data, inventory counts) | Aapko massive horizontal write scale chahiye jo ek single-leader relational DB se zyada ho |
| Complex queries, joins, aur ad-hoc reporting common hain | Data naturally document-, graph-, ya wide-column-shaped hai |
| Data volume vertical scaling + read replicas mein comfortably fit ho jaata hai | Eventual consistency availability/throughput ke liye acceptable trade hai |

Practice mein, zyaadatar non-trivial systems **polyglot persistence** use karte hain — kayi database types, har ek us part of the system ke liye jise woh sabse achha fit karta hai, ek database ko har need serve karne ke liye force karne ke bajaye. Ek concrete example: ek e-commerce platform typically **orders aur inventory** ke liye ek relational database (PostgreSQL/MySQL) use karta hai, jahan ACID transactions matter karte hain (aap ek hi unit of inventory do baar nahi bech sakte, aur ek order + payment + inventory decrement ko saath succeed ya fail hona chahiye) — lekin **product catalog** ke liye ek document store (MongoDB) use karta hai, jahan har product category ke attributes wildly different hote hain (ek shirt ka "size" aur "color" hota hai, ek laptop ka "RAM" aur "screen size" hota hai) aur catalog reads catalog writes se kaafi zyada hote hain, jisse flexible schema aur simple key-based lookups rigid relational tables se better fit ban jaate hain.

## Trade-offs

| Decision | SQL / ACID | NoSQL / BASE |
|---|---|---|
| Consistency | Strong, immediate | Eventual (usually), kuch stores mein tunable |
| Schema | Fixed, enforced | Flexible, per-record |
| Horizontal write scale | Harder (sharding chahiye, dekho `07_database_scaling.md`) | Zyaadatar designs mein ground se hi built-in |
| Query flexibility | High (joins, ad-hoc SQL) | Low-to-medium, access patterns often upfront known hone chahiye |
| Transactional guarantees | Multi-row/table transactions | Usually single-document/single-key atomicity tak limited |

Inme se koi bhi abstractly "better" nahi hai — SQL ki rigidity ek feature hai jab correctness raw scale se zyada matter kare; NoSQL ki flexibility ek feature hai jab scale aur schema evolution multi-row transactional guarantees se zyada matter karein.

## Interview Tips

- "Yeh database kyun?" kisi bhi system design interview mein sabse commonly poocha jaane wala follow-up hai. Ek strong answer specific access pattern naam leta hai (read-heavy? write-heavy? joins chahiye? transactions chahiye?) aur use database category se tie karta hai — sirf ek product name nahi.
- "Main NoSQL use karunga kyunki yeh better scale karta hai" mat kaho bina *kyun* qualify kiye — interviewers sunna chahte hain ki aapko pata hai ki NoSQL certain access patterns ke liye better scale karta hai specific guarantees relax karke (schema rigidity, multi-row transactions, immediate consistency), na ki NoSQL unconditionally faster hai.
- Polyglot persistence defend karne ke liye ready raho — ek system ke different parts ke liye do ya teen different databases propose karna usually maturity ka sign hai, overengineering ka nahi, jab tak aap har choice ko individually justify kar sako.
- Jab ACID ke baare mein poocha jaaye, hamesha har property ko ek concrete failure mode mein ground karo jo woh prevent karti hai (jaise bank transfer example mein upar), definitions recite karne ke bajaye — interviewers check kar rahe hain ki aapko samajh hai ki *kyun* har property exist karti hai, na ki aapne acronym memorize kar liya hai.
- Agar aap denormalization propose karte ho, proactively write-side cost mention karo (duplicates ko sync mein rakhna, ya temporary staleness tolerate karna) — yehi exact type ki trade-off acknowledgment interviewers sunna chahte hain.

## Quick Recall — Self-Test

**1. Bank transfer example mein, kaunsi ACID property us state ko prevent karti hai jahan Alice debit ho jaaye lekin Bob ko kabhi credit na mile?**
Atomicity — transaction all-or-nothing hota hai, isliye agar Bob ko credit fail ho jaaye, Alice se debit bhi rollback ho jaata hai, transaction ko half-applied chhodne ke bajaye.

**2. Isolation aur durability mein kya difference hai?**
Isolation is baat se related hai ki concurrent transactions ek dusre ki uncommitted intermediate state na dekhein (koi bhi ek half-applied transfer nahi padhta). Durability is baat se related hai ki ek *committed* transaction subsequent failures jaise crash ya power loss ko survive kare — ek baar confirm hone ke baad, koi baad ki failure use undo nahi kar sakti.

**3. IoT sensor data ke liye aap ek column-family store jaise Cassandra ko ek document store jaise MongoDB se kyun choose karoge?**
Column-family stores extremely high write throughput aur ek partition key ke over range scans ke liye optimized hain (jaise, ek device ke sabhi readings ek time range ke across), jo exactly IoT/time-series data ka access pattern hai massive scale par — document stores zyada general-purpose hain aur specifically us write/range-scan pattern ke liye optimized nahi hain.

**4. "Eventually consistent" ko ek sentence mein explain karo, aur ek real symptom batao jo ek user notice kar sakta hai.**
Koi naye writes na hone diye jaayein toh, sabhi replicas eventually same value par converge ho jaayenge, lekin kisi bhi given instant par different nodes different (stale) data return kar sakte hain. Ek concrete symptom: ek user apni profile photo update karta hai, lekin ek second baad unki profile dekh raha friend still briefly old photo dekhta hai kyunki read ek aise replica ko hit karta hai jo abhi tak catch up nahi hua.

**5. Ek index reads ko fast kyun banata hai lekin writes ko slow kyun kar deta hai?**
Ek index ek separate sorted structure hai (typically ek B-tree) jo lookups ko table ke zyaadatar hisse ko skip karne deta hai (O(n) scan ke bajaye O(log n)). Lekin har insert/update/delete jo ek indexed column ko touch kare use bhi us structure ko update karna padta hai, isliye zyada indexes ka matlab hai per write zyada kaam aur zyada consume hui disk space.

**6. Denormalization ka ek concrete example do jo redundancy ko read speed ke liye trade karta hai.**
`author_name` ko directly ek post record par store karna instead of sirf `author_id` store karne ke aur har read par ek `users` table se join karne ke. Feed reads ab bina join ke ek single query ban jaate hain, is cost par ki ek user ke naam change hone par unki likhi har post update karni padti hai (ya temporary staleness accept karni padti hai).

**7. "Polyglot persistence" ka kya matlab hai, aur ek e-commerce system ise kyun use karega?**
Ek system ke andar multiple types of databases use karna, har ek us part ke liye chuna gaya jise woh sabse achha fit karta hai, ek database ko sab kuch ke liye use karne ke bajaye. Ek e-commerce system orders/inventory ke liye ek relational DB use kar sakta hai (overselling avoid karne ke liye ACID transactions chahiye) aur product catalog ke liye ek document store (flexible, per-category schema aur fast key-based reads chahiye).

**8. Ek candidate kehta hai "NoSQL hamesha SQL se zyada scalable hai." Iska more precise version kya hai?**
NoSQL databases typically ground se hi horizontal write scaling ke liye specific guarantees relax karke design kiye jaate hain — strict schema enforcement, multi-row ACID transactions, aur immediate consistency. Aisa nahi hai ki NoSQL unconditionally faster hai; yeh differently scale karta hai kyunki yeh specific cheezein chhod deta hai jo relational databases hold karti hain, aur woh trade-offs sirf certain access patterns ke liye hi worth hote hain.
