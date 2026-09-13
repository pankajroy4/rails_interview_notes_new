# Design a Logging Framework (Object-Oriented Design)

## Problem Statement

"Design a logging framework. It should support multiple log levels (DEBUG,
INFO, WARN, ERROR, FATAL) so that a logger configured at, say, INFO level
silently ignores DEBUG calls. It should be able to write logs to more than
one destination at the same time — console and a file, say — and different
destinations might need different formats. Design the class structure."

This is essentially "design Log4j/Logback/Python's `logging` module, but
small." The interviewer isn't looking for a toy `puts` wrapper — they're
looking for whether you recognize that "write to multiple places, possibly
in different formats" is two separate axes of variation (destination vs.
format) that should NOT be tangled into one class, and whether you know
when Singleton is actually appropriate for the top-level logger versus when
it's a testability trap.

## Step 1: Clarify Requirements

**Functional Requirements**
- Support standard log levels with a strict ordering: `DEBUG < INFO < WARN
  < ERROR < FATAL`.
- A `Logger` configured at a given minimum level drops any call below that
  level — e.g. `logger.debug(...)` is a no-op when the logger is set to
  `INFO`.
- Write to **multiple destinations simultaneously** (console, file, remote
  log aggregator) from a single log call.
- Different destinations may need **different output formats** (plain text
  for console, structured JSON for a remote aggregator) — independent of
  which destinations are active.
- One destination failing (e.g. a network call timing out) must not stop
  the log from reaching the other destinations.

**Non-Functional Requirements**
- **Cheap filtering**: a log call below the configured threshold must be
  near-free — specifically, must not do expensive work (string
  interpolation, formatting) before the level check happens.
- **Open/Closed for both axes independently**: adding a new destination
  type (e.g. `SlackAppender`) shouldn't require touching formatting code,
  and adding a new format shouldn't require touching any appender.
- **Testability**: the design should not force a single unconfigurable
  global logger instance on every caller, since that makes tests that
  assert on log output (or that want silence) awkward to isolate.

## Step 2: Identify Core Objects / Entities

- **LogLevel** — an ordered value (DEBUG/INFO/WARN/ERROR/FATAL) that
  supports comparison (`>=`), which is what makes filtering a one-line
  check instead of a lookup table.
- **LogMessage** — a small immutable value object capturing one log event:
  timestamp, level, message text, and optionally a source (class/module
  name). This is what gets handed to formatters and appenders — neither of
  them re-derives this data themselves.
- **LogFormatter** (interface) — turns a `LogMessage` into a `String` for
  output. `PlainTextFormatter` and `JSONFormatter` are two implementations
  behind the same interface.
- **Appender** (interface) — knows how to deliver an already-formatted
  string to one destination. `ConsoleAppender`, `FileAppender`,
  `RemoteAppender` are implementations; each owns (or is configured with)
  one `LogFormatter`.
- **Logger** — the entry point callers use (`logger.info("...")`, etc.).
  Holds a minimum `LogLevel` and a list of `Appender`s; filters by level,
  then dispatches to every appender.

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
- `PlainTextFormatter`/`JSONFormatter` **implement** `LogFormatter`
  (interface implementation — duck-typed in Ruby, both respond to
  `#format`).
- `ConsoleAppender`/`FileAppender`/`RemoteAppender` **implement**
  `Appender` (same pattern, both respond to `#write`).
- Each `Appender` **uses-a** `LogFormatter` (association, injected at
  construction) — this is the second Strategy axis, independent of which
  `Appender` it is.
- `Logger` **composes** its list of `Appender`s (owns them; they don't
  meaningfully exist detached from the logger that dispatches to them) and
  **uses-a** `LogLevel` for its threshold.

## Step 4: Design Decisions & Patterns Used

**Why `Appender` is a Strategy, and why `Logger` holds a LIST of them, not
one.** The naive design gives `Logger` a single `output_target` and an
`if/elsif` chain over "console vs file vs remote." That fails the
"multiple destinations simultaneously" requirement outright — you can't
express "log to console AND file AND remote" with a single target field
without hacking in a special multi-target mode. Instead, `Logger` holds
`@appenders = []` and a log call loops over all of them, calling `#write`
on each. Adding a `SlackAppender` later is: write the class, `logger.
add_appender(SlackAppender.new)` — zero changes to `Logger`. This mirrors
how real frameworks are shaped — Log4j/Logback literally call this concept
an "appender" for exactly this reason, and naming that precedent in an
interview is a credibility signal, not just decoration.

**Why `LogFormatter` is pulled out as a SEPARATE Strategy from
`Appender`, instead of each appender formatting its own output.** This is
the central design insight of this file. The requirement "console gets
plain text, remote aggregator gets JSON" sounds like it belongs to the
appender — "the file appender knows how to write files, so let it also
know how to format text." But that conflates two independent axes of
variation: *where* a log goes and *how* it's rendered. If formatting logic
lives inside each `Appender` subclass, then "now I also want the FILE
appender to emit JSON instead of plain text" means editing
`FileAppender`'s internals — even though nothing about "writing to a file"
changed. By making `LogFormatter` its own interface that any `Appender` is
constructed with (`FileAppender.new(path, formatter: JSONFormatter.new)`),
destination and format vary independently: 3 appender types x 2 formatter
types is 6 behaviors from 5 small classes, not 6 hardcoded classes. This is
Strategy composed with Strategy, and it's exactly the kind of "spot the
two independent axes" thinking an LLD interviewer is scoring for.

**Why Singleton is tempting here, and why it's named as a trade-off rather
than defaulted to.** A logging framework's most common real-world shape is
`Logger.instance.info(...)` callable from literally anywhere — which makes
Singleton attractive since you rarely want two independently-configured
top-level loggers. But per the caution in
`LLD_OOD/01_Concepts/05_design_patterns_creational.md`, a Singleton is
hidden global state: any code, anywhere, can reach it, tests can leak
appenders/state into each other unless carefully reset, and code that
depends on `Logger.instance` directly is harder to test in isolation than
code that receives a `Logger` via dependency injection. The stronger
answer in an interview is to keep `Logger` an ordinary class (instantiable,
injectable, easy to swap for a null/spy logger in tests) and, if a single
shared instance is genuinely wanted app-wide, wire that up ONE level above
`Logger` itself (e.g. a `LoggerRegistry` or simply `AppConfig.logger`) —
so `Logger` the class never forces singleton-ness on every caller. Naming
this trade-off out loud, rather than reaching for `include Singleton`
unreflectively, is what separates a strong answer here.

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

**Using it:**

```ruby
logger = Logger.new(min_level: LogLevel.new(:info))
logger.add_appender(ConsoleAppender.new) # plain text, default
logger.add_appender(FileAppender.new("app.log", formatter: JSONFormatter.new))

logger.debug("connection pool stats")  # dropped, below :info threshold
logger.info("user signed in", source: "SessionsController")
# => console: 2026-09-13T10:02:11+00:00 INFO [SessionsController]: user signed in
# => app.log: {"ts":"2026-09-13T10:02:11+00:00","level":"INFO","source":"SessionsController","message":"user signed in"}
```

Same `LogMessage`, two different renderings, delivered to two different
destinations, from one `logger.info` call — the composition from Step 4
made concrete.

## Step 6: Edge Cases & Extensibility

- **A call below the configured threshold must stay cheap.** The `log`
  private method checks `level >= @min_level` and returns immediately
  *before* constructing a `LogMessage` or calling any formatter — real
  frameworks care about this because building a rich message (e.g. calling
  `#to_s` on a large object, interpolating a big string) can be expensive,
  and doing that work only to throw the result away on every `debug` call
  in a production app running at `INFO` would be wasteful. A further
  refinement callers often want: pass a block (`logger.debug { expensive_
  string }`) so even the message *construction* is deferred until after
  the level check — worth mentioning as a follow-on optimization even if
  the code above uses plain arguments for clarity.
- **One appender fails.** `RemoteAppender#write` might raise (network
  timeout, DNS failure). The `each` loop in `Logger#log` wraps each
  `appender.write` call individually in `begin/rescue`, so a
  `RemoteAppender` exception never prevents `ConsoleAppender` or
  `FileAppender` from still receiving the message — this is the direct
  payoff of the "one destination failing shouldn't affect others"
  requirement.
- **No appenders configured.** `Logger.new` with an empty `appenders` list
  should filter and silently no-op rather than error — useful for a "null
  logger" in tests.
- **Adding a brand-new destination, e.g. `SlackAppender`.** Implement
  `#write(log_message)`, optionally accept a `formatter:`, and
  `logger.add_appender(SlackAppender.new(webhook_url))` — no change to
  `Logger`, `LogMessage`, or any existing appender/formatter.
- **Adding a brand-new format, e.g. `LogfmtFormatter`.** Implement
  `#format(log_message)` — usable by any existing appender immediately,
  since appenders are coded against the `LogFormatter` interface, not a
  concrete class.

## Follow-up Questions an Interviewer Might Ask

1. **"How would you make logging asynchronous so a slow appender (like a
   network call) doesn't block the application's hot path?"** Put a
   thread-safe queue between `Logger#log` and the appenders: the log call
   pushes a `LogMessage` onto the queue and returns immediately, while a
   background thread (or small worker pool) pops messages and dispatches
   them to appenders. The trade-off to name explicitly: buffered messages
   still sitting in the queue are lost if the process crashes before the
   worker drains them, so a production version usually needs a bounded
   queue with an overflow policy (drop oldest, block the caller, or flush
   synchronously past a threshold) rather than an unbounded one.
2. **"How would you support per-module or per-class log level overrides
   instead of one global level?"** Give `Logger` a map of
   `source => LogLevel` overrides checked before falling back to
   `@min_level` — e.g. `ActiveRecord` logs at `WARN` while
   `PaymentsService` logs at `DEBUG` in the same process. This only
   requires threading `source` through to the filtering check, which the
   code above already captures on `LogMessage`.
3. **"Why not have `Appender` do its own formatting instead of a separate
   `LogFormatter`?"** Answered in Step 4 — conflating them means changing
   a destination's format requires editing that destination's class, and
   you lose the ability to reuse one formatter across multiple appender
   types (e.g. `JSONFormatter` used by both `RemoteAppender` and a
   `FileAppender` writing structured logs for later ingestion).
4. **"Would you make `Logger` a Singleton?"** Name the trade-off (Step 4):
   Singleton gives convenient global access but hidden state and weaker
   testability; prefer an injectable `Logger` instance, with at most a thin
   registry/config layer providing a shared default if the app genuinely
   wants one globally-accessible logger.
5. **"How would you test this?"** Unit-test `LogLevel` ordering and each
   `LogFormatter#format` in isolation (pure functions, no I/O). For
   `Appender`s, inject a fake/spy client (`RemoteAppender.new(fake_client)`)
   and assert on what was sent, rather than hitting real I/O. For `Logger`,
   inject an in-memory "recording" appender and assert filtering behavior
   (below-threshold calls produce zero writes; above-threshold calls
   dispatch to every configured appender) without touching a real console
   or filesystem.
6. **"What if the same log message needs to be sampled — e.g. only log 1%
   of DEBUG-level events in production?"** A `SamplingAppender` decorator
   wrapping another `Appender` (or a sampling check inside `Logger#log`
   keyed by level) — worth noting this is naturally expressible as another
   Strategy/decorator layered on the existing appender interface rather
   than a special case bolted onto `Logger`.
