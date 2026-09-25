# Design a Library Management System (Object-Oriented Design)

## Problem Statement

"Design a library management system. Members can search the catalog,
check out books, and return them. The library may own multiple physical
copies of the same title. If every copy of a book is checked out, a member
should be able to place a hold and get notified when a copy becomes
available. Members also accrue fines for overdue books, and the fine
policy differs by member type."

Ye question chupke se test karta hai ki kya candidate ye notice karta hai ki
**"a book"** actually do alag cheezein hain: abstract work (jaise, "The
Pragmatic Programmer, ISBN 978-0135957059") aur ek specific physical object
jo shelf par hai aur jo ek time par sirf ek member ke haath mein ho sakta hai.
Jo candidates sirf ek `Book` class model karte hain wo hamesha atak jaate hain
jab pucha jaata hai "library ke paas is book ki 3 copies hain, 2 checked out
hain — kya ye available hai?" kyunki availability copies ki property hai,
title ki nahi. Yahi distinction is file ka main teaching point hai.

## Step 1: Clarify Requirements

**Functional Requirements**
- Books ko title/author/ISBN se catalog karna; library ek hi title ki
  multiple physical copies rakh sakti hai.
- Ek member ek available copy check out karta hai aur baad mein return karta
  hai.
- Members ki ek borrowing limit hoti hai (max number of concurrent loans).
- Agar kisi title ki koi copy available nahi hai, to member hold place kar
  sakta hai; jab ek copy return hoti hai, to us title ki hold queue mein
  agla member notify hota hai.
- Overdue loans par fines accrue hote hain, aur fine calculation member type
  ke hisaab se different hota hai (jaise student vs faculty).

**Non-Functional Requirements**
- **Title/copy distinction ko explicitly model karo.** Availability,
  check-out, aur hold logic sab individual copies par operate karte hain,
  abstract title par nahi — inhe conflate karne se "kya ye specific copy
  available hai" ka jawaab dena ad hoc bookkeeping ke bina namumkin ho
  jaata hai.
- **Single responsibility**: fine calculation `Loan` ke andar ek
  `if member.type == :student` branch ki tarah nahi rehna chahiye — ye ek
  policy hai jo loan tracking se independently vary karti hai, aur
  `Loan` ko touch kiye bina member type ke hisaab se swappable honi chahiye.
- **Cross-mutation ki jagah explicit association objects**: book check out
  karna directly `Member` aur `BookCopy` dono par scattered call sites se
  flag poke nahi karna chahiye — Parking Lot ke `ParkingTicket` pattern ko
  mirror karo, ek explicit `Loan` object ke saath jo relationship ko own
  kare.
- **Extensibility**: naye member types, naye fine policies, ya naye copy
  formats (jaise ebooks) add karna `Library` ke core checkout/return flow ko
  edit kiye bina hona chahiye.

## Step 2: Identify Core Objects / Entities

- **Book** — ek title ke liye catalog-level entry: title, author, ISBN.
  Har ISBN ke liye exactly ek `Book` hota hai, chahe library ke paas kitni
  bhi physical copies hon.
- **BookCopy** — ek `Book` ka ek physical, checkoutable instance; iska apna
  copy ID aur availability status hota hai. Agar library ke paas ek hi
  `Book` ki 3 copies hain to us ek `Book` ko reference karne wale 3
  `BookCopy` objects honge.
- **Member** — ek library patron: iski ek borrowing limit aur member type
  hota hai (jo fine policy select karne ke liye use hota hai).
- **Loan** — ek `Member` ke ek `BookCopy` hold karne ka active (ya
  historical) record, checkout date aur due date ke saath. Ye association
  object hai — bilkul Parking Lot example ke `ParkingTicket` jaisa: har call
  site se `member.borrowed_copies` aur `copy.holder` ko separately mutate
  karne ke bajaye, ek `Loan` object relationship ke fact ko own karta hai,
  aur queries aur returns dono usi se guzarte hain.
- **Hold** — ek `Member` ki ek `Book` ke liye line mein jagah jiski abhi koi
  available copy nahi hai; library har `Book` ke liye ek hold queue
  maintain karti hai.
- **FineCalculator** (interface) → `StudentFinePolicy`, `FacultyFinePolicy`
  — ek overdue `Loan` par kitna fine banta hai ye calculate karta hai, jo
  member ke type ke hisaab se choose hota hai. Ek Strategy object, jise
  deliberately `Loan` se bahar rakha gaya hai.
- **Library** — catalog, checkout, return, aur hold flow ko orchestrate
  karta hai; `Book`s, `BookCopy`s, aur active `Loan`s ke collections ko own
  karta hai.

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
- `BookCopy`, `Book` se **associate** hota hai (kayi copies ek title ko
  reference karti hain; copies `Book` se inherit nahi karti — ek copy ke
  paas ek book *hai*, wo khud ek *kind of* book *nahi* hai).
- `Library`, `Book`, `BookCopy`, aur `Hold` collections ko **compose** karti
  hai — inka koi existence library ke bina nahi hota jo unhe catalog karti
  hai.
- `Loan`, ek `Member` ko ek `BookCopy` se **associate** karta hai — bilkul
  wahi pattern jo `ParkingTicket` ek `Vehicle` ko `ParkingSpot`s se associate
  karta hai.
- `StudentFinePolicy`/`FacultyFinePolicy`, `FineCalculator` se **inherit**
  karte hain (is-a); `Library`, `FineCalculator` ko composition/dependency
  injection ke through **use** karti hai, inheritance se nahi — library
  khud "a kind of" fine calculator nahi hai, wo bas ek ko delegate karti
  hai.

## Step 4: Design Decisions & Patterns Used

**`Book` aur `BookCopy` ko alag classes hona kyun zaroori hai.** Agar aap
sirf ek `available: Boolean` flag ke saath `Book` model karo, to 3 copies
own karne ka matlab hoga ya to (a) same ISBN ke saath teen alag `Book`
objects — ab "the book" ki koi single identity nahi hai, aur title update
karne ke liye 3 records update karne padenge — ya (b) ek `Book` jisme
`copies_available: Integer` counter ho, jo "kitni free hain" ka jawaab de
deta hai lekin "member X ne exactly kaunsi copy borrow ki, aur *wo* kab due
hai" ka nahi. Jaise hi aapko per-copy checkout state chahiye hoti hai
(condition, due date, kaunse member ke paas hai), aapko per-copy objects
chahiye hote hain. `Book`, title-level metadata ka single source of truth
rehta hai; `BookCopy` wo cheez hai jo actually check out hoti hai.

**`Member` aur `BookCopy` ko directly mutate karne ke bajaye `Loan` kyun.**
Bilkul Parking Lot example ka wahi `ParkingTicket` wala reasoning: `Loan`
object ke bina, "ye copy return karo" ka matlab hai search karke pata karna
ki kis member ke paas hai, aur "is member ke paas kitni books hain" ka
matlab hai har copy scan karke `holder == member` dhundhna. Ek `Loan` dono
directions ko O(1) lookups bana deta hai aur `due_date`, `renewed_count`, aur
fine computation ko latkane ke liye ek natural jagah deta hai — wo bhi
`Member` ya `BookCopy` ke internals ko touch kiye bina.

**Fine calculation ek alag `FineCalculator` strategy kyun hai, `Loan` ke
andar `if member.type == :student` nahi.** Fine policy ek business rule hai
jo independently change hoti hai is se ki loan actually *kya hai* — ek
library "senior citizen" discount add kar sakti hai ya grace period ke
dauraan fines waive kar sakti hai, aur inme se kisi ke liye bhi `Loan` edit
karne ki zaroorat nahi honi chahiye. `FineCalculator` ko `Library` mein (ya
har `Member` ke liye) inject karna `Loan` ko ek pure data/state object
banaye rakhta hai aur policies ko independently testable aur swappable
banata hai — ye Parking Lot ke suggested `PricingStrategy` follow-up jaisa
hi shape hai, bas yahan ise afterthought ki jagah design ka first-class part
banaya gaya hai.

**Returns par hold notification Observer se kyun trigger hoti hai, polling
check se nahi.** Jab ek copy return hoti hai, library ko us book ki hold
queue mein *agle* person ko batana hota hai ki ek copy ab free hai. System
ka har wo part jise ye matter kar sakta hai `Book#available?` poll karne ke
bajaye, `return_copy` return hone ke exact moment par explicitly hold queue
ke head ko notify karta hai — ye ek natural Observer relationship hai (hold
queue apni book ki copies ko available hone ke liye "observe" karti hai).
Chhote scale par ye ek direct method call hi hai; bade scale par yahi seam
hai jahan aap `Library#return_copy` ka logic change kiye bina ek email/SMS
notifier plug in kar sakte ho.

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

**Isko use karte hue:**

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

- **Ek aisi book reserve karna jiski koi bhi copy library ke paas nahi hai**
  (sirf zero available nahi — library ne kabhi ek bhi copy khareedi hi
  nahi). `place_hold` jaisa likha gaya hai wo assume karta hai ki
  `@books`/`@copies` mein pehle se entries hain; ek real system ko "title
  catalog mein nahi hai" aur "title catalog mein hai, saari copies out hain"
  ko distinguish karna chahiye — agar fully code na bhi karo, ek validation
  gap ki tarah call out karne layak baat hai.
- **Ek member apni borrowing limit par doosri book check out karne ki
  koshish kare.** `checkout` kisi bhi copy state ko touch karne se pehle
  hi raise kar deta hai — `can_borrow?` pehle check hota hai, isliye ek
  rejected checkout par koi copy galat tarike se unavailable mark nahi
  hoti. Ye ordering matter karti hai: agar borrow limit se pehle
  availability check ki jaaye to ek copy kisi ke "head mein reserved" ho
  sakti hai jabki checkout ultimately fail ho jaaye.
- **Loan renew karna jab koi aur us par hold rakhe ho.** Ye ek genuine
  policy trade-off hai, koi bug nahi jise bas fix karna hai: renewal allow
  karne se current borrower khush rehta hai lekin hold queue meaningless ho
  jaati hai (jo wait kar raha hai use kabhi serve nahi hota); hold hone par
  renewal block karna queue ke liye fairer hai lekin borrower ko surprise
  karta hai. Interview mein sahi jawaab ye hai ki trade-off state karo aur
  ek explicitly pick karo — jaise "agar `@hold_queues[isbn]` non-empty hai
  to renewal block karo" — silently ek behavior pick karne ke bajaye.
- **Ek member ek aisi copy return kare jo unhe kabhi check out hui hi nahi
  thi** (ya ek copy jo already return ho chuki hai). `return_copy` ko
  `loan.member == member` validate karna chahiye agar aap catch karna
  chahte ho ki koi kisi aur ka book galat tarike se return kar raha hai,
  aur agar koi copy active loan ke bina hai to ek stable `nil` return karta
  hai — ek achha defensive-programming point raise karne ke liye.
- **Lost/damaged copies.** Ek lost copy silently "available" wapas nahi
  ban jaani chahiye — `:available`/`:checked_out` ke saath ek `:lost` status
  add karo taaki `available?` aur checkout flow ise correctly exclude
  karein, aur ise fine policy ki jagah ek replacement-fee policy ki taraf
  route karo.

## Follow-up Questions an Interviewer Might Ask

1. **"Multiple library branches ek catalog share karein to kaise support
   karoge?"** `Book` ko global rakho (ek catalog, ek ISBN → ek `Book`),
   lekin `BookCopy` ko ek branch ke scope mein rakho (`copy.branch_id`).
   Checkout aur holds phir ya to per-branch operate karte hain, ya, ek
   richer system ke liye, holds "any branch" specify kar sakte hain aur
   notification available copy wali nearest branch pick karti hai —
   `Library` `Branch` ban jaati hai, aur ek `LibrarySystem` branches ko
   aggregate karta hai bilkul waise jaise `ElevatorController` cars ko
   aggregate karta hai.
2. **"Ebooks ka support kaise doge, jinki physical scarcity nahi hoti?"**
   Ek `EbookCopy` introduce karo (ya ek `Copyable` interface jo `Book`
   implement kare) jisme `available?` capacity-limited na ho — typically
   "unlimited concurrent copies" ya fixed physical count ki jagah ek
   publisher-licensed concurrent-checkout cap. `Loan`/return flow bilkul
   same rehta hai; sirf us copy type ke liye availability rule change hota
   hai, jo exactly wahi reason hai ki availability logic ko `BookCopy` par
   rakhna (hardcode `Library` mein nahi) fayda deta hai.
3. **"Concurrent checkouts ke under ek hi copy ka double-booking kaise
   prevent karoge?"** Parking Lot ke concurrency follow-up jaisi hi
   problem class hai: `checkout` ka find-then-mark-unavailable concurrent
   access ke under ek race hai; fix hai `copy.status` par lock/atomic
   compare-and-swap, ya agar ye ek database backed hota to persistence
   layer par ek unique DB constraint.
4. **"Agar ek member ek aisi book par hold place karna chahe jiski copy wo
   already check out kar chuka hai to?"** Reject karo — ek hi title ke liye
   current borrower bhi hona aur hold queue mein bhi hona almost hamesha ek
   UX bug hota hai jise explicitly prevent karna chahiye, koi state nahi
   jise system silently allow kare.
5. **"Isko kaise test karoge?"** `StudentFinePolicy`/`FacultyFinePolicy#fine_for`
   ko ek stub `Loan` ke against isolation mein unit-test karo (pure
   calculation, `Library` ki zaroorat nahi); `Library#checkout`/
   `#return_copy`/`#place_hold` ko full flow ke liye integration-test karo,
   jisme "saari copies out → hold → return notification trigger karta hai"
   wala sequence bhi shamil ho.
6. **"Millions of members aur ek distributed catalog ke liye design karna
   isse kaise different hoga?"** Ye HLD version hai — scale par catalog
   search (likely `@books` hash lookups ki jagah ek dedicated search
   index), aur hold-queue notification ek synchronous method call ki jagah
   ek asynchronous message/event ban jaana. Ise explicitly LLD/HLD boundary
   ki tarah naam lena worth hai, bilkul waise hi jaise Parking Lot example
   `System_Design/01_Concepts/09_distributed_systems_core.md` se bridge
   karta hai.
