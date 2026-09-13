# Design a Library Management System (Object-Oriented Design)

## Problem Statement

"Design a library management system. Members can search the catalog,
check out books, and return them. The library may own multiple physical
copies of the same title. If every copy of a book is checked out, a member
should be able to place a hold and get notified when a copy becomes
available. Members also accrue fines for overdue books, and the fine
policy differs by member type."

This question quietly tests whether a candidate notices that **"a book"**
is actually two different things: the abstract work ("The Pragmatic
Programmer, ISBN 978-0135957059") and a specific physical object on a
shelf that can only be in one member's hands at a time. Candidates who
model just one `Book` class inevitably get stuck when asked "the library
owns 3 copies of this book, 2 are checked out — is it available?" because
availability is a property of copies, not of the title. That distinction
is the main teaching point of this file.

## Step 1: Clarify Requirements

**Functional Requirements**
- Catalog books by title/author/ISBN; the library may hold multiple
  physical copies of the same title.
- A member checks out an available copy and returns it later.
- Members have a borrowing limit (max number of concurrent loans).
- If no copy of a title is available, a member can place a hold; when a
  copy is returned, the next member in that title's hold queue is
  notified.
- Overdue loans accrue fines; the fine calculation differs by member type
  (e.g., student vs faculty).

**Non-Functional Requirements**
- **Model the title/copy distinction explicitly.** Availability,
  check-out, and hold logic all operate on individual copies, not on the
  abstract title — conflating them makes "is this specific copy
  available" unanswerable without ad hoc bookkeeping.
- **Single responsibility**: fine calculation should not live inside
  `Loan` as an `if member.type == :student` branch — it's a policy that
  varies independently of loan tracking, and should be swappable per
  member type without touching `Loan`.
- **Explicit association objects over cross-mutation**: checking out a
  book should not directly poke a flag on both `Member` and `BookCopy`
  from scattered call sites — mirror the Parking Lot's `ParkingTicket`
  pattern with an explicit `Loan` object that owns the relationship.
- **Extensibility**: adding new member types, new fine policies, or new
  copy formats (e.g., ebooks) should not require editing `Library`'s core
  checkout/return flow.

## Step 2: Identify Core Objects / Entities

- **Book** — the catalog-level entry for a title: title, author, ISBN.
  There is exactly one `Book` per ISBN regardless of how many physical
  copies the library owns.
- **BookCopy** — one physical, checkoutable instance of a `Book`; has its
  own copy ID and availability status. A library with 3 copies of the same
  `Book` has 3 `BookCopy` objects referencing that one `Book`.
- **Member** — a library patron: has a borrowing limit and a member type
  (used to select a fine policy).
- **Loan** — an active (or historical) record of one `Member` holding one
  `BookCopy`, with checkout date and due date. This is the association
  object — mirrors `ParkingTicket` from the Parking Lot example exactly:
  instead of mutating `member.borrowed_copies` and `copy.holder`
  separately from every call site, one `Loan` object owns the fact of the
  relationship, and both queries and returns go through it.
- **Hold** — a `Member`'s place in line for a `Book` that currently has no
  available copies; the library keeps a hold queue per `Book`.
- **FineCalculator** (interface) → `StudentFinePolicy`, `FacultyFinePolicy`
  — computes the fine owed on an overdue `Loan`, chosen by the member's
  type. A Strategy object, deliberately kept outside `Loan`.
- **Library** — orchestrates the catalog, checkout, return, and hold flow;
  owns the collections of `Book`s, `BookCopy`s, and active `Loan`s.

## Step 3: Identify Relationships (Class Diagram)

```text
  Book
  - isbn, title, author
       ^ (referenced by, not owned by — a Book outlives any one copy)
       |
  BookCopy                          Loan
  - copy_id                         - member ------> Member
  - book ---------> Book            - copy --------> BookCopy
  - status: :available|:checked_out - checkout_date
  + available?                      - due_date
                                     + overdue?(as_of)
  Member                            + days_overdue(as_of)
  - id, name, member_type
  - active_loans: [Loan]
  + can_borrow?

  Hold
  - member -------> Member
  - book ---------> Book

  FineCalculator (interface)
  + fine_for(loan) : Money            [abstract]
       ^
       |______________________
       |                       |
  StudentFinePolicy       FacultyFinePolicy

  Library
  - books: { isbn => Book }                 (composition)
  - copies: { isbn => [BookCopy] }          (composition)
  - hold_queues: { isbn => [Hold] }         (composition, FIFO per book)
  - active_loans: { copy_id => Loan }
  - fine_calculator: FineCalculator         (injected strategy)
  + checkout(member, isbn) : Loan
  + return_copy(copy) : Loan
  + place_hold(member, isbn) : Hold
```

Relationship types:
- `BookCopy` **associates** with `Book` (many copies reference one title;
  copies don't inherit from `Book` — a copy *has-a* book, it is not
  *a kind of* book).
- `Library` **composes** `Book`, `BookCopy`, and `Hold` collections — they
  have no existence independent of the library that catalogs them.
- `Loan` **associates** a `Member` with a `BookCopy` — same pattern as
  `ParkingTicket` associating a `Vehicle` with `ParkingSpot`s.
- `StudentFinePolicy`/`FacultyFinePolicy` **inherit** from
  `FineCalculator` (is-a); `Library` **uses** a `FineCalculator` via
  composition/dependency injection, not inheritance — the library isn't
  "a kind of" fine calculator, it delegates to one.

## Step 4: Design Decisions & Patterns Used

**Why `Book` and `BookCopy` must be separate classes.** If you model only
`Book` with an `available: Boolean` flag, owning 3 copies means either (a)
three separate `Book` objects with the same ISBN — now "the book" has no
single identity, and updating the title requires updating 3 records — or
(b) one `Book` with a `copies_available: Integer` counter, which answers
"how many are free" but not "which specific copy did member X borrow, and
when is *that one* due." The moment you need per-copy checkout state
(condition, due date, which member has it), you need per-copy objects.
`Book` stays the single source of truth for title-level metadata;
`BookCopy` is the thing that actually gets checked out.

**Why `Loan` instead of mutating `Member` and `BookCopy` directly.**
Exactly the `ParkingTicket` reasoning from the Parking Lot example: without
a `Loan` object, "return this copy" means finding which member has it by
searching, and "how many books does this member have" means scanning every
copy for `holder == member`. A `Loan` makes both directions O(1) lookups
and gives you one natural place to hang `due_date`, `renewed_count`, and
fine computation — all without touching `Member` or `BookCopy` internals.

**Why fine calculation is a separate `FineCalculator` strategy, not
`if member.type == :student` inside `Loan`.** Fine policy is a business
rule that changes independently of what a loan *is* — a library might add
a "senior citizen" discount or waive fines during a grace period, and none
of that should require editing `Loan`. Injecting a `FineCalculator` into
`Library` (or even per-`Member`) keeps `Loan` a pure data/state object and
makes policies independently testable and swappable — this is the same
shape as the Parking Lot's suggested `PricingStrategy` follow-up, applied
here as a first-class part of the design rather than an afterthought.

**Why returns trigger hold notification via Observer, not a polling
check.** When a copy is returned, the library needs to tell the *next*
person in that book's hold queue that a copy is now free. Rather than
having every part of the system that might care poll `Book#available?`,
`return_copy` explicitly notifies the head of the hold queue at the moment
of return — the natural Observer relationship (the hold queue "observes"
copies of its book becoming available). At small scale this is just a
direct method call; at larger scale the same seam is where you'd plug in
an email/SMS notifier without changing `Library#return_copy`'s logic.

## Step 5: Code

```ruby
class Book
  attr_reader :isbn, :title, :author

  def initialize(isbn, title, author)
    @isbn = isbn
    @title = title
    @author = author
  end
end

class BookCopy
  attr_reader :copy_id, :book
  attr_accessor :status # :available or :checked_out

  def initialize(copy_id, book)
    @copy_id = copy_id
    @book = book
    @status = :available
  end

  def available? = @status == :available
end

class Member
  BORROW_LIMIT = 5

  attr_reader :id, :name, :member_type, :active_loans

  def initialize(id, name, member_type:)
    @id = id
    @name = name
    @member_type = member_type # :student or :faculty
    @active_loans = []
  end

  def can_borrow? = @active_loans.size < BORROW_LIMIT
end

class Loan
  LOAN_PERIOD_DAYS = 14

  attr_reader :member, :copy, :checkout_date
  attr_accessor :due_date, :returned_date

  def initialize(member, copy, checkout_date: Date.today)
    @member = member
    @copy = copy
    @checkout_date = checkout_date
    @due_date = checkout_date + LOAN_PERIOD_DAYS
  end

  def overdue?(as_of = Date.today) = returned_date.nil? && as_of > due_date

  def days_overdue(as_of = Date.today)
    return 0 unless overdue?(as_of)

    (as_of - due_date).to_i
  end
end

class Hold
  attr_reader :member, :book, :requested_at

  def initialize(member, book, requested_at: Time.now)
    @member = member
    @book = book
    @requested_at = requested_at
  end
end

# --- Fine policies (Strategy) ---------------------------------------------

class FineCalculator
  def fine_for(loan, as_of = Date.today)
    raise NotImplementedError
  end
end

class StudentFinePolicy < FineCalculator
  RATE_PER_DAY = 0.25

  def fine_for(loan, as_of = Date.today)
    loan.days_overdue(as_of) * RATE_PER_DAY
  end
end

class FacultyFinePolicy < FineCalculator
  RATE_PER_DAY = 0.10
  GRACE_DAYS = 7 # faculty get a week's grace before fines start

  def fine_for(loan, as_of = Date.today)
    billable_days = [loan.days_overdue(as_of) - GRACE_DAYS, 0].max
    billable_days * RATE_PER_DAY
  end
end

# --- Library orchestration --------------------------------------------------

class Library
  def initialize
    @books = {}                              # isbn => Book
    @copies = Hash.new { |h, k| h[k] = [] }   # isbn => [BookCopy]
    @hold_queues = Hash.new { |h, k| h[k] = [] } # isbn => [Hold] (FIFO)
    @active_loans = {}                        # copy_id => Loan
    @fine_policies = {
      student: StudentFinePolicy.new,
      faculty: FacultyFinePolicy.new
    }
  end

  def add_book(book) = @books[book.isbn] = book

  def add_copy(isbn, copy_id)
    @copies[isbn] << BookCopy.new(copy_id, @books.fetch(isbn))
  end

  def checkout(member, isbn)
    raise "borrow limit reached" unless member.can_borrow?

    copy = @copies[isbn].find(&:available?)
    raise "no copies available" unless copy

    copy.status = :checked_out
    loan = Loan.new(member, copy)
    @active_loans[copy.copy_id] = loan
    member.active_loans << loan
    loan
  end

  def return_copy(copy)
    loan = @active_loans.delete(copy.copy_id)
    return nil unless loan

    loan.returned_date = Date.today
    copy.status = :available
    loan.member.active_loans.delete(loan)

    notify_next_hold(copy.book.isbn)
    loan
  end

  def place_hold(member, isbn)
    raise "copies are available, no need to hold" if @copies[isbn].any?(&:available?)

    hold = Hold.new(member, @books.fetch(isbn))
    @hold_queues[isbn] << hold
    hold
  end

  def fine_for(loan)
    @fine_policies.fetch(loan.member.member_type).fine_for(loan)
  end

  private

  # Observer-style notification: the next member in line for this title
  # gets told a copy is free. A real system would push this to an email/SMS
  # notifier instead of returning it, without changing checkout/return.
  def notify_next_hold(isbn)
    next_hold = @hold_queues[isbn].shift
    return unless next_hold

    puts "Notifying #{next_hold.member.name}: a copy of '#{next_hold.book.title}' is available."
  end
end
```

**Using it:**

```ruby
library = Library.new
book = Book.new("978-0135957059", "The Pragmatic Programmer", "Hunt & Thomas")
library.add_book(book)
library.add_copy(book.isbn, "COPY-1")
library.add_copy(book.isbn, "COPY-2")

alice = Member.new(1, "Alice", member_type: :student)
bob   = Member.new(2, "Bob",   member_type: :student)
carol = Member.new(3, "Carol", member_type: :faculty)

library.checkout(alice, book.isbn) # takes COPY-1
library.checkout(bob, book.isbn)   # takes COPY-2

# No copies left — Carol places a hold instead of checking out.
hold = library.place_hold(carol, book.isbn)

loan = library.checkout(alice, book.isbn) rescue nil
loan.nil? # => true, no copies available for a third checkout

returned_loan = library.return_copy(library.instance_variable_get(:@copies)[book.isbn].first)
# => prints "Notifying Carol: a copy of 'The Pragmatic Programmer' is available."

library.fine_for(returned_loan) # => 0.0 if returned on time
```

## Step 6: Edge Cases & Extensibility

- **Reserving a book with zero copies owned at all** (not just zero
  available — the library never bought a copy). `place_hold` as written
  assumes `@books`/`@copies` already have entries; a real system should
  distinguish "title not in catalog" from "title in catalog, all copies
  out" — worth calling out as a validation gap even if not fully coded.
- **A member at their borrowing limit tries to check out another book.**
  `checkout` raises before touching any copy state — `can_borrow?` is
  checked first, so no copy is ever incorrectly marked unavailable on a
  rejected checkout. This ordering matters: checking availability before
  the borrow limit would let a copy get "reserved" in someone's head even
  though the checkout ultimately fails.
- **Renewing a loan when someone else holds it.** This is a genuine policy
  trade-off, not a bug to just fix: allowing renewal keeps the current
  borrower happy but makes the hold queue meaningless (the person waiting
  never gets served); blocking renewal when a hold exists is fairer to
  the queue but surprises the borrower. The right answer in an interview
  is to state the trade-off and pick one explicitly — e.g., "block
  renewal if `@hold_queues[isbn]` is non-empty" — rather than silently
  picking a behavior.
- **A member returns a copy that was never checked out to them** (or a
  copy already returned). `return_copy` should validate `loan.member ==
  member` if you want to catch someone returning another person's book
  incorrectly, and returns a stable `nil` for a copy with no active loan —
  a good defensive-programming point to raise.
- **Lost/damaged copies.** A copy that's lost shouldn't silently become
  "available" again — add a `:lost` status alongside `:available`/
  `:checked_out` so `available?` and the checkout flow correctly exclude
  it, and route it to a replacement-fee policy rather than a fine policy.

## Follow-up Questions an Interviewer Might Ask

1. **"How would you support multiple library branches sharing one
   catalog?"** Keep `Book` global (one catalog, one ISBN → one `Book`),
   but scope `BookCopy` to a branch (`copy.branch_id`). Checkout and holds
   then either operate per-branch or, for a richer system, holds can
   specify "any branch" and the notification picks the nearest branch with
   an available copy — `Library` becomes `Branch`, and a `LibrarySystem`
   aggregates branches the same way `ElevatorController` aggregates cars.
2. **"How would you support ebooks, which don't have physical scarcity?"**
   Introduce an `EbookCopy` (or a `Copyable` interface `Book` implements)
   where `available?` is not capacity-limited — typically "unlimited
   concurrent copies" or a publisher-licensed concurrent-checkout cap
   instead of a fixed physical count. The `Loan`/return flow stays
   identical; only the availability rule for that copy type changes,
   which is exactly why keeping availability logic on `BookCopy` (not
   hardcoded into `Library`) pays off.
3. **"How do you prevent double-booking the same copy under concurrent
   checkouts?"** Same class of problem as the Parking Lot's concurrency
   follow-up: `checkout`'s find-then-mark-unavailable is a race under
   concurrent access; the fix is a lock/atomic compare-and-swap on
   `copy.status`, or a unique DB constraint at the persistence layer if
   this were backed by a database.
4. **"What if a member wants to place a hold on a book they've already
   checked out a copy of?"** Reject it — being both a current borrower and
   in the hold queue for the same title is almost always a UX bug to
   prevent explicitly, not a state the system should allow silently.
5. **"How would you test this?"** Unit-test `StudentFinePolicy`/
   `FacultyFinePolicy#fine_for` against a stub `Loan` in isolation (pure
   calculation, no `Library` needed); integration-test `Library#checkout`/
   `#return_copy`/`#place_hold` for the full flow, including the
   "all copies out → hold → return triggers notification" sequence.
6. **"How does this differ from designing this for millions of members and
   a distributed catalog?"** That's the HLD version — catalog search at
   scale (likely a dedicated search index rather than `@books` hash
   lookups), and hold-queue notification becoming an asynchronous
   message/event rather than a synchronous method call. Worth naming
   explicitly as the LLD/HLD boundary, the same way the Parking Lot
   example bridges to `System_Design/01_Concepts/09_distributed_systems_core.md`.
