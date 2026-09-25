# Design a Logging Framework (Object-Oriented Design)

## Problem Statement

"Design a logging framework. Isme multiple log levels (DEBUG, INFO, WARN,
ERROR, FATAL) support hone chahiye taaki ek logger jo, kaho, INFO level par
configured hai, DEBUG calls ko silently ignore kare. Isse ek se zyada
destinations par ek saath logs likh paana chahiye — console aur ek file,
kaho — aur alag alag destinations ko alag formats chahiye ho sakte hain.
Class structure design karo."

Yeh essentially "Log4j/Logback/Python ke `logging` module jaisa design
karo, bas chhota" hai. Interviewer koi toy `puts` wrapper nahi dhoondh raha
— woh yeh dekhna chahte hain ki kya aap recognize karte ho ki "multiple
jagah likho, possibly alag formats mein" variation ke do alag axes hain
(destination vs. format) jo ek class mein tangle NAHI hone chahiye, aur kya
aapko pata hai top-level logger ke liye Singleton kab actually appropriate
hai versus kab yeh ek testability trap ban jaata hai.

## Step 1: Clarify Requirements

**Functional Requirements**
- Standard log levels ko strict ordering ke saath support karo: `DEBUG <
  INFO < WARN < ERROR < FATAL`.
- Ek diye gaye minimum level par configured `Logger` us level se neeche
  koi bhi call drop kar de — jaise `logger.debug(...)` ek no-op hai jab
  logger `INFO` par set ho.
- **Multiple destinations** (console, file, remote log aggregator) par
  **simultaneously** ek single log call se likho.
- Alag alag destinations ko alag alag output **formats** chahiye ho sakte
  hain (console ke liye plain text, remote aggregator ke liye structured
  JSON) — independent isse ki kaunse destinations active hain.
- Ek destination fail hone se (jaise ek network call timeout hone se) log
  ka doosre destinations tak pahunchna nahi rukna chahiye.

**Non-Functional Requirements**
- **Cheap filtering**: configured threshold se neeche ka log call near-free
  hona chahiye — specifically, level check hone se pehle koi expensive kaam
  (string interpolation, formatting) nahi karna chahiye.
- **Dono axes ke liye independently Open/Closed**: ek naya destination
  type add karna (jaise `SlackAppender`) formatting code ko touch nahi
  karna chahiye, aur ek naya format add karna kisi bhi appender ko touch
  nahi karna chahiye.
- **Testability**: design har caller par ek single unconfigurable global
  logger instance force nahi karna chahiye, kyunki isse log output par
  assert karne wale tests (ya jo silence chahte hain) isolate karna
  awkward ho jaata hai.

## Step 2: Identify Core Objects / Entities

- **LogLevel** — ek ordered value (DEBUG/INFO/WARN/ERROR/FATAL) jo
  comparison support karta hai (`>=`), jo filtering ko ek lookup table ke
  bajaye ek one-line check bana deta hai.
- **LogMessage** — ek chhota immutable value object jo ek log event
  capture karta hai: timestamp, level, message text, aur optionally ek
  source (class/module name). Yahi formatters aur appenders ko handover
  kiya jaata hai — dono mein se koi bhi khud yeh data re-derive nahi karta.
- **LogFormatter** (interface) — ek `LogMessage` ko output ke liye ek
  `String` mein badalta hai. `PlainTextFormatter` aur `JSONFormatter` isi
  interface ke peeche do implementations hain.
- **Appender** (interface) — jaanta hai ki ek already-formatted string ko
  ek destination tak kaise deliver karna hai. `ConsoleAppender`,
  `FileAppender`, `RemoteAppender` implementations hain; har ek apna ek
  `LogFormatter` owns karta hai (ya usse configured hota hai).
- **Logger** — entry point jo callers use karte hain (`logger.info("...")`,
  waghera). Ek minimum `LogLevel` aur `Appender`s ki ek list hold karta hai;
  level se filter karta hai, phir har appender ko dispatch karta hai.

## Step 3: Identify Relationships (Class Diagram)

```text
  LogLevel (ordered: DEBUG < INFO < WARN < ERROR < FATAL)

  LogMessage
  - timestamp, level, message, source

  LogFormatter (interface)             PlainTextFormatter    JSONFormatter
  + format(log_message) : String   <----------  both implement  ----------

  Appender (interface)                 ConsoleAppender   FileAppender   RemoteAppender
  + write(log_message)             <---------------  all implement  --------------
  - formatter ---uses-a---> LogFormatter        (each appender owns one formatter)

  Logger
  - min_level: LogLevel
  - appenders: [Appender]     ---composes--->  Appender (list, owns them)
  + debug(msg) / info(msg) / warn(msg) / error(msg) / fatal(msg)
  - log(level, msg)     [shared filtering + dispatch logic]
```

Relationship types:
- `PlainTextFormatter`/`JSONFormatter` `LogFormatter` ko **implement**
  karte hain (interface implementation — Ruby mein duck-typed, dono
  `#format` ko respond karte hain).
- `ConsoleAppender`/`FileAppender`/`RemoteAppender` `Appender` ko
  **implement** karte hain (same pattern, dono `#write` ko respond karte
  hain).
- Har `Appender` ek `LogFormatter` **uses-a** hai (association, construction
  time par injected) — yeh second Strategy axis hai, is baat se independent
  ki kaunsa `Appender` hai.
- `Logger` apne `Appender`s ki list ko **composes** karta hai (unko owns
  karta hai; woh us logger se detached meaningfully exist nahi karte jo
  unhe dispatch karta hai) aur apne threshold ke liye `LogLevel` **uses-a**
  hai.

## Step 4: Design Decisions & Patterns Used

**`Appender` Strategy kyun hai, aur `Logger` inki ek LIST kyun hold karta
hai, ek nahi.** Naive design `Logger` ko ek single `output_target` aur
"console vs file vs remote" ke upar ek `if/elsif` chain deta hai. Yeh
"multiple destinations simultaneously" requirement ko outright fail kar
deta hai — aap ek single target field se "console AND file AND remote
mein log karo" express nahi kar sakte bina ek special multi-target mode
hack kiye. Iske bajaye, `Logger` `@appenders = []` hold karta hai aur ek
log call sab par loop karta hai, har ek par `#write` call karte hue. Baad
mein ek `SlackAppender` add karna hai: class likho, `logger.
add_appender(SlackAppender.new)` — `Logger` mein zero changes. Yeh mirror
karta hai ki real frameworks kaise shaped hote hain — Log4j/Logback isi
concept ko literally exact isi wajah se "appender" bolte hain, aur interview
mein yeh precedent naam lena decoration nahi, credibility signal hai.

**`LogFormatter` ko `Appender` se ALAG ek Strategy ke roop mein kyun pull
out kiya, har appender ko apna khud ka output format karne dene ke bajaye.**
Yeh is file ka central design insight hai. Requirement "console ko plain
text milega, remote aggregator ko JSON" sunne mein aisa lagta hai jaise yeh
appender ka hai — "file appender ko pata hai files kaise likhni hain, toh
usse text bhi format karna aane do." Lekin yeh variation ke do independent
axes ko conflate karta hai: log *kahan* jaata hai aur *kaise* render hota
hai. Agar formatting logic har `Appender` subclass ke andar rehti hai, toh
"ab main FILE appender se bhi JSON emit karwana chahta hoon plain text ke
bajaye" ka matlab hai `FileAppender` ke internals edit karna — jabki "file
mein likhna" ke baare mein kuch bhi change nahi hua. `LogFormatter` ko apna
alag interface banakar jisse koi bhi `Appender` construct hota hai
(`FileAppender.new(path, formatter: JSONFormatter.new)`), destination aur
format independently vary karte hain: 3 appender types x 2 formatter types
= 6 behaviors, 5 chhoti classes se, 6 hardcoded classes se nahi. Yeh
Strategy hai jo Strategy ke saath compose hui hai, aur yahi exactly "do
independent axes spot karo" wali thinking hai jo ek LLD interviewer score
kar raha hota hai.

**Singleton yahan kyun tempting hai, aur ise defaulted karne ke bajaye ek
trade-off ki tarah kyun naam diya jaata hai.** Ek logging framework ka
sabse common real-world shape hai `Logger.instance.info(...)` jo literally
kahin se bhi callable ho — jo Singleton ko attractive banata hai kyunki
rarely aap do independently-configured top-level loggers chahte ho. Lekin
`LLD_OOD/01_Concepts/05_design_patterns_creational.md` ki caution ke
mutabiq, ek Singleton hidden global state hai: koi bhi code, kahin se bhi,
usse reach kar sakta hai, tests carefully reset kiye bina ek doosre mein
appenders/state leak kar sakte hain, aur jo code seedha `Logger.instance`
par depend karta hai woh us code se test karna zyada mushkil hai jo ek
`Logger` dependency injection ke through receive karta hai. Interview mein
stronger answer hai `Logger` ko ek ordinary class rakhna (instantiable,
injectable, tests mein null/spy logger se swap karna easy), aur agar ek
single shared instance genuinely app-wide chahiye, toh usse `Logger` ke
ek level upar wire karo (jaise ek `LoggerRegistry` ya simply
`AppConfig.logger`) — taaki `Logger` class khud kabhi har caller par
singleton-ness force na kare. Bina soche `include Singleton` reach karne
ke bajaye is trade-off ko zubaan se naam dena hi hai jo yahan strong answer
ko alag banata hai.

## Step 5: Code

```ruby
class LogLevel
  ORDER = { debug: 0, info: 1, warn: 2, error: 3, fatal: 4 }.freeze

  attr_reader :name

  def initialize(name)
    raise ArgumentError, "unknown level #{name}" unless ORDER.key?(name)

    @name = name
  end

  def >=(other) = ORDER[@name] >= ORDER[other.name]
  def to_s = @name.to_s.upcase
end

class LogMessage
  attr_reader :timestamp, :level, :message, :source

  def initialize(level, message, source: nil, timestamp: Time.now)
    @level = level
    @message = message
    @source = source
    @timestamp = timestamp
  end
end

# --- Formatters (Strategy: HOW a message is rendered) ---

class PlainTextFormatter
  def format(log_message)
    src = log_message.source ? " [#{log_message.source}]" : ""
    "#{log_message.timestamp.iso8601} #{log_message.level}#{src}: #{log_message.message}"
  end
end

class JSONFormatter
  def format(log_message)
    require "json"
    {
      ts: log_message.timestamp.iso8601,
      level: log_message.level.to_s,
      source: log_message.source,
      message: log_message.message,
    }.to_json
  end
end

# --- Appenders (Strategy: WHERE a message is delivered) ---

class ConsoleAppender
  def initialize(formatter: PlainTextFormatter.new)
    @formatter = formatter
  end

  def write(log_message)
    puts @formatter.format(log_message)
  end
end

class FileAppender
  def initialize(path, formatter: PlainTextFormatter.new)
    @path = path
    @formatter = formatter
  end

  def write(log_message)
    File.open(@path, "a") { |f| f.puts @formatter.format(log_message) }
  end
end

class RemoteAppender
  def initialize(client, formatter: JSONFormatter.new)
    @client = client # anything responding to #send(string) — injected, not hardcoded
    @formatter = formatter
  end

  def write(log_message)
    @client.send(@formatter.format(log_message))
  end
end

# --- Logger: filters by level, then dispatches to every appender ---

class Logger
  def initialize(min_level: LogLevel.new(:info), appenders: [])
    @min_level = min_level
    @appenders = appenders
  end

  def add_appender(appender)
    @appenders << appender
  end

  def debug(message, source: nil) = log(:debug, message, source)
  def info(message, source: nil)  = log(:info, message, source)
  def warn(message, source: nil)  = log(:warn, message, source)
  def error(message, source: nil) = log(:error, message, source)
  def fatal(message, source: nil) = log(:fatal, message, source)

  private

  def log(level_name, message, source)
    level = LogLevel.new(level_name)
    return unless level >= @min_level # filter BEFORE building the LogMessage

    log_message = LogMessage.new(level, message, source: source)
    @appenders.each do |appender|
      begin
        appender.write(log_message)
      rescue StandardError => e
        # One appender failing (e.g. RemoteAppender's network call) must
        # not stop the others from receiving the log.
        warn "logger: appender #{appender.class} failed: #{e.message}"
      end
    end
  end
end
```

**Isse use karna:**

```ruby
logger = Logger.new(min_level: LogLevel.new(:info))
logger.add_appender(ConsoleAppender.new) # plain text, default
logger.add_appender(FileAppender.new("app.log", formatter: JSONFormatter.new))

logger.debug("connection pool stats")  # dropped, below :info threshold
logger.info("user signed in", source: "SessionsController")
# => console: 2026-09-13T10:02:11+00:00 INFO [SessionsController]: user signed in
# => app.log: {"ts":"2026-09-13T10:02:11+00:00","level":"INFO","source":"SessionsController","message":"user signed in"}
```

Same `LogMessage`, do alag renderings, do alag destinations par delivered,
ek `logger.info` call se — Step 4 wali composition concrete form mein.

## Step 6: Edge Cases & Extensibility

- **Configured threshold se neeche ka call cheap rehna chahiye.** Private
  `log` method `level >= @min_level` check karta hai aur kisi bhi
  `LogMessage` construct karne ya kisi formatter ko call karne *se pehle*
  turant return kar deta hai — real frameworks isse isliye care karte hain
  kyunki ek rich message banana (jaise ek badi object par `#to_s` call
  karna, ek badi string interpolate karna) expensive ho sakta hai, aur yeh
  kaam sirf result ko throw away karne ke liye karna — production app mein
  jo `INFO` par chal raha hai, har `debug` call par — wasteful hoga. Ek
  aur refinement jo callers often chahte hain: ek block pass karo
  (`logger.debug { expensive_string }`) taaki message ki *construction*
  bhi level check ke baad tak defer ho — yeh ek follow-on optimization ke
  roop mein mention karna worth hai, chahe upar ka code clarity ke liye
  plain arguments use karta ho.
- **Ek appender fail ho jaata hai.** `RemoteAppender#write` raise kar sakta
  hai (network timeout, DNS failure). `Logger#log` mein `each` loop har
  `appender.write` call ko individually `begin/rescue` mein wrap karta
  hai, isliye ek `RemoteAppender` exception kabhi `ConsoleAppender` ya
  `FileAppender` ko message receive karne se nahi rokta — yeh "ek
  destination fail hone se doosre affect nahi hone chahiye" requirement ka
  direct payoff hai.
- **Koi appender configured nahi hai.** `Logger.new` ek empty `appenders`
  list ke saath filter kare aur silently no-op kare, error na de —
  tests mein ek "null logger" ke liye useful.
- **Ek bilkul naya destination add karna, jaise `SlackAppender`.**
  `#write(log_message)` implement karo, optionally ek `formatter:` accept
  karo, aur `logger.add_appender(SlackAppender.new(webhook_url))` —
  `Logger`, `LogMessage`, ya kisi existing appender/formatter mein koi
  change nahi.
- **Ek bilkul naya format add karna, jaise `LogfmtFormatter`.**
  `#format(log_message)` implement karo — turant kisi bhi existing
  appender se usable, kyunki appenders `LogFormatter` interface ke against
  code hote hain, kisi concrete class ke against nahi.

## Follow-up Questions an Interviewer Might Ask

1. **"Logging ko asynchronous kaise banaoge taaki ek slow appender (jaise
   ek network call) application ke hot path ko block na kare?"**
   `Logger#log` aur appenders ke beech ek thread-safe queue lagao: log call
   ek `LogMessage` ko queue par push karta hai aur turant return kar jaata
   hai, jabki ek background thread (ya ek chhota worker pool) messages ko
   pop karke appenders ko dispatch karta hai. Trade-off jo explicitly naam
   lena chahiye: agar process crash ho jaaye worker ke drain karne se
   pehle, toh queue mein baithe buffered messages lost ho jaate hain,
   isliye production version ko usually ek bounded queue chahiye hoti hai
   ek overflow policy ke saath (oldest drop karo, caller ko block karo, ya
   ek threshold ke baad synchronously flush karo), unbounded ki jagah.
2. **"Per-module ya per-class log level overrides kaise support karoge, ek
   global level ki jagah?"** `Logger` ko `source => LogLevel` overrides ka
   ek map do jo `@min_level` par fallback karne se pehle check ho — jaise
   `ActiveRecord` `WARN` par log kare jabki `PaymentsService` usi process
   mein `DEBUG` par log kare. Isme sirf `source` ko filtering check tak
   thread karna hai, jo upar ka code already `LogMessage` par capture kar
   raha hai.
3. **"`Appender` apni khud ki formatting kyun na kare, ek alag
   `LogFormatter` ke bajaye?"** Step 4 mein answer ho chuka hai — inhe
   conflate karne ka matlab hai ek destination ka format change karne ke
   liye us destination ki class edit karni pade, aur aap ek formatter ko
   multiple appender types ke across reuse karne ki ability kho dete ho
   (jaise `JSONFormatter` jo `RemoteAppender` aur ek structured logs likhne
   wale `FileAppender` dono use karte hain later ingestion ke liye).
4. **"Kya aap `Logger` ko Singleton banaoge?"** Trade-off naam lo (Step 4):
   Singleton convenient global access deta hai lekin hidden state aur
   weaker testability ke saath; ek injectable `Logger` instance prefer
   karo, at most ek thin registry/config layer ke saath jo shared default
   provide kare agar app genuinely ek globally-accessible logger chahta
   hai.
5. **"Isse test kaise karoge?"** `LogLevel` ordering aur har
   `LogFormatter#format` ko isolation mein unit-test karo (pure functions,
   no I/O). `Appender`s ke liye, ek fake/spy client inject karo
   (`RemoteAppender.new(fake_client)`) aur assert karo ki kya bheja gaya,
   real I/O hit karne ke bajaye. `Logger` ke liye, ek in-memory "recording"
   appender inject karo aur filtering behavior par assert karo
   (below-threshold calls zero writes produce karte hain; above-threshold
   calls har configured appender ko dispatch karte hain) bina kisi real
   console ya filesystem ko touch kiye.
6. **"Agar same log message ko sample karna ho — jaise, production mein
   sirf 1% DEBUG-level events log karo?"** Ek `SamplingAppender` decorator
   jo doosre `Appender` ko wrap karta hai (ya `Logger#log` ke andar level
   se keyed ek sampling check) — yeh note karna worth hai ki yeh naturally
   ek aur Strategy/decorator layer ke roop mein express hota hai existing
   appender interface par, `Logger` par ek special case bolt karne ke
   bajaye.
