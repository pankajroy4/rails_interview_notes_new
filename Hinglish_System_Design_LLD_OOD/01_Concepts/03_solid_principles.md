# SOLID Principles

SOLID paanch object-oriented design principles ka ek acronym hai, jo Robert
C. Martin ne coin kiya tha, jo describe karta hai ki classes ko kaise
structure karein taaki ek codebase grow karte waqt flexible aur maintainable
rahe. Har letter ek principle naam leta hai: **S**ingle Responsibility,
**O**pen/Closed, **L**iskov Substitution, **I**nterface Segregation,
**D**ependency Inversion. Inme se koi bhi ek Ruby-specific rule nahi hai —
yeh language-agnostic OOP design principles hain — lekin yeh file har ek
ko idiomatic Ruby ke saath dikhati hai.

## Why it matters

SOLID violations exactly wahi tarah ki cheez hain jo "this is fine, I'll
clean it up later" se shuru hoti hai aur aisi code mein compound ho jaati
hai jise koi touch nahi karna chahta. Ek class jo paanch cheezein karti hai
tab tak fine hai jab tak aapko un paanch mein se ek change nahi karni
hoti aur pata chalta hai ki aap baaki chaar ko risk kiye bina yeh nahi kar
sakte. Ek `case` statement fine hai jab tak koi 6th type add na kare jise
baaki 5 jagah jaise iske case exist karte hain uske baare mein nahi pata
tha. Inme se koi bhi problem ek toy example mein ek ya do types ke saath
visible nahi hoti — yeh exactly tab obvious hoti hain jab ek system grow
karta hai, jo precisely woh moment hai jise ek interviewer simulate karta
hai poochke "now add a new payment type" ya "now support a new vehicle"
turant aapke design ke first pass ke baad.

Ek interview mein, SOLID aapko design decisions justify karne ke liye ek
**vocabulary** deta hai instead of sirf good instincts hone ke. "I split
this into three classes because each one has a single reason to change"
"I just thought it looked cleaner" se kahin zyada strong answer hai. Yeh
naam le paana ki ek design choice kaunsa principle serve karti hai, khud
ek signal hai jise interviewer sunta hai — yeh dikhata hai ki decision
deliberate thi, accidental nahi.

## S — Single Responsibility Principle (SRP)

**Definition:** ek class ke paas change hone ki ek reason honi chahiye —
ek responsibility, jo poori tarah us class ki owned honi chahiye.

**Before (violates SRP — ek class validation, persistence, aur
notification teeno karti hai):**

```ruby
class UserRegistrar
  def register(params)
    # 1. Validation
    raise "invalid email" unless params[:email] =~ /\A[\w+\-.]+@[a-z\d\-]+\.[a-z]+\z/i
    raise "password too short" if params[:password].length < 8

    # 2. Persistence
    user = User.create!(email: params[:email], password_digest: BCrypt::Password.create(params[:password]))

    # 3. Notification
    EmailClient.new.send_mail(
      to: user.email,
      subject: "Welcome!",
      body: "Thanks for signing up, #{user.email}"
    )

    user
  end
end
```

Yeh exactly wahi type ki code hai jo time pressure mein likhi jaati hai —
yeh koi strawman nahi hai, yeh ek Tuesday hai. Yeh kaam karta hai. Problem
baad mein dikhti hai: validation rules mein ek change, users ko persist
karne ke tareeke mein ek change (shayad ek second data store), aur welcome
email template mein ek change — teeno ko ab isi class ko edit karna padta
hai, aur inme se kisi ek concern mein bug baaki ko break karne ka risk
rakhta hai (email step mein ek typo jab user already save ho chuka ho,
system ko ek half-done state mein chhod deta hai bina yeh clear owner ke
ki "kya registration actually succeed hua?").

**After (responsibility ke hisaab se split):**

```ruby
class UserValidator
  def validate!(params)
    raise "invalid email" unless params[:email] =~ /\A[\w+\-.]+@[a-z\d\-]+\.[a-z]+\z/i
    raise "password too short" if params[:password].length < 8
  end
end

class UserRepository
  def create(params)
    User.create!(email: params[:email], password_digest: BCrypt::Password.create(params[:password]))
  end
end

class WelcomeNotifier
  def notify(user)
    EmailClient.new.send_mail(to: user.email, subject: "Welcome!", body: "Thanks for signing up, #{user.email}")
  end
end

class UserRegistrar
  def initialize(validator: UserValidator.new, repository: UserRepository.new, notifier: WelcomeNotifier.new)
    @validator = validator
    @repository = repository
    @notifier = notifier
  end

  def register(params)
    @validator.validate!(params)
    user = @repository.create(params)
    @notifier.notify(user)
    user
  end
end
```

Ab har class exactly ek reason ke liye change ho sakti hai: validation
rules sirf `UserValidator` ko change karte hain, data stores switch karna
sirf `UserRepository` ko change karta hai, email template change karna
sirf `WelcomeNotifier` ko change karta hai. Yeh practice mein isliye
matter karta hai kyunki yeh har change ka blast radius shrink kar deta hai
— password rules edit kar raha ek developer accidentally persistence break
nahi kar sakta, aur har class ko isolation mein unit test kiya ja sakta
hai instead of har chhoti change ke liye ek full integration test
require karne ke.

## O — Open/Closed Principle (OCP)

**Definition:** classes extension ke liye open aur modification ke liye
closed honi chahiye — aapko naya behavior add karne ke liye existing,
already-working code edit nahi karna padna chahiye.

**Before (violates OCP — har naye type ke liye ek shared method edit karna
padta hai):**

```ruby
class ParkingLot
  def spots_needed(vehicle_type, spot_type)
    case vehicle_type
    when :bike
      spot_type == :bike_spot ? 1 : Float::INFINITY
    when :car
      spot_type == :car_spot ? 1 : Float::INFINITY
    when :van
      case spot_type
      when :van_spot then 1
      when :bike_spot then 3
      else Float::INFINITY
      end
    else
      raise "unknown vehicle type"
    end
  end
end
```

Ek `Truck` add karne ka matlab hai `ParkingLot` kholna aur is method ko edit
karna (aur likely har dusra method jisme aisa hi `case` ho). Ek
already-shipped, already-tested class ke har edit mein existing cases
break karne ka risk hota hai — aur code review ko poore method ko
re-verify karna padta hai, sirf naya branch nahi.

**After (polymorphic dispatch — yeh exactly parking lot example ki
`Vehicle` hierarchy hai):**

```ruby
class Vehicle
  def spots_required(spot_type)
    raise NotImplementedError
  end
end

class Bike < Vehicle
  def spots_required(spot_type) = spot_type == :bike_spot ? 1 : Float::INFINITY
end

class Car < Vehicle
  def spots_required(spot_type) = spot_type == :car_spot ? 1 : Float::INFINITY
end

class Van < Vehicle
  def spots_required(spot_type)
    case spot_type
    when :van_spot then 1
    when :bike_spot then 3
    else Float::INFINITY
    end
  end
end

# Adding Truck requires zero changes to ParkingLot or any existing Vehicle class:
class Truck < Vehicle
  def spots_required(spot_type) = spot_type == :car_spot ? 2 : Float::INFINITY
end
```

`ParkingLot` `vehicle.spots_required(spot_type)` call karta hai aur kabhi
vehicle type pe branch hi nahi karta — poora `ParkingLot#park`
implementation exactly isi pe built dekhne ke liye
`LLD_OOD/02_Interview_Questions/01_parking_lot.md` dekhiye. `Truck` add
karna ek naya class hai, ek working class ko edit karna nahi. Yeh isliye
matter karta hai kyunki "new class, zero edits to existing code" ka matlab
hai ki existing, already-tested code paths regress nahi kar sakte — naye
class ke alawa test karne ke liye kuch bhi nahi hai.

## L — Liskov Substitution Principle (LSP)

**Definition:** ek subclass ko jahan bhi uska parent expected ho wahan
usable hona chahiye, bina us correctness ko break kiye jo parent ne
promise kiya tha — ek subclass ko contract ko kabhi *stricter* ya
*different* nahi banana chahiye us cheez se jispe parent type ke callers
already rely karte hain.

**Before (classic Square-extends-Rectangle violation):**

```ruby
class Rectangle
  attr_accessor :width, :height

  def initialize(width, height)
    @width = width
    @height = height
  end

  def area = width * height
end

class Square < Rectangle
  def width=(value)
    @width = value
    @height = value   # keeps it "square" - but silently changes height too
  end

  def height=(value)
    @width = value
    @height = value
  end
end

def resize_and_check(rect)
  rect.width = 5
  rect.height = 10
  raise "broken!" unless rect.area == 50   # true for Rectangle, FALSE for Square
end

resize_and_check(Rectangle.new(2, 2))  # fine
resize_and_check(Square.new(2, 2))     # raises "broken!" - Square silently set both to 10, area = 100
```

`Square` mathematically ek `Rectangle` hai, lekin behaviorally nahi:
`Rectangle` ke contract ke against likhi gayi koi bhi code ("setting
`width` doesn't touch `height`") ek `Square` diye jaane pe silently break ho
jaati hai. Yeh ek crash se bhi worse hai — `resize_and_check` ek missing
method ki wajah se error nahi karta, yeh ek *wrong value* ki wajah se error
karta hai jo aisi code se produce hui jo `Rectangle` ke liye bilkul correct
dikh rahi thi.

**After (hierarchy ko aise restructure karein ki yeh behavior ke baare mein
jhooth na bole):**

```ruby
class Shape
  def area
    raise NotImplementedError
  end
end

class Rectangle < Shape
  def initialize(width, height)
    @width = width
    @height = height
  end

  def area = @width * @height
end

class Square < Shape
  def initialize(side)
    @side = side
  end

  def area = @side * @side
end
```

`Square` ab yeh pretend nahi karta ki yeh independently settable
`width`/`height` wala ek `Rectangle` hai — yeh apna khud ka `Shape` hai apne
khud ke contract ke saath (ek `side`, koi separate width/height nahi jo
desynchronize ho sake). `Shape` ke against likhi gayi koi bhi code sirf
`area` pe rely karti hai, jo dono hi correctly honor karte hain. Practical
lesson: agar B ko A ka subclass banana B ko ek method ko aise override
karne pe force karta hai jo A ka promised behavior change kar de, to B
really A nahi hai — usse ek sibling ki tarah model kariye instead.

## I — Interface Segregation Principle (ISP)

**Definition:** ek class ko aise methods implement karne ko force mat
kariye jo usko chahiye hi nahi — kai chhote, focused interfaces (Ruby mein:
modules) ko prefer kariye ek badi interface ke over jo unrelated behavior
ko bundle karti hai.

**Before (ek fat module ek implementer pe ek irrelevant method force karta
hai):**

```ruby
module Worker
  def work
    raise NotImplementedError
  end

  def eat
    raise NotImplementedError
  end
end

class HumanWorker
  include Worker
  def work = "assembling parts"
  def eat = "eating lunch"
end

class RobotWorker
  include Worker
  def work = "assembling parts, tirelessly"

  def eat
    raise "RobotWorker does not eat"   # forced to implement something meaningless for it
  end
end
```

`RobotWorker` `eat` define karne ko force hota hai sirf `Worker` module ki
shape satisfy karne ke liye, jabki "eating" ka ek robot ke liye koi matlab
hi nahi hai. Aur bhi worse, koi bhi caller jo trust karta hai "every
`Worker` responds meaningfully to `eat`" (kyunki module yeh promise karta
hai) usko specifically `RobotWorker` se ek runtime crash milega, jo LSP ke
describe kiye gaye same problem ka ek subtler version hai: ek implementer
jo technically interface ki method list satisfy karta hai lekin uske
behavioral contract ko nahi.

**After (chhote, focused modules mein split — sirf woh implement kariye jo
apply hota hai):**

```ruby
module Workable
  def work
    raise NotImplementedError
  end
end

module Eatable
  def eat
    raise NotImplementedError
  end
end

class HumanWorker
  include Workable
  include Eatable
  def work = "assembling parts"
  def eat = "eating lunch"
end

class RobotWorker
  include Workable
  def work = "assembling parts, tirelessly"
  # no eat method at all - and none is expected, since RobotWorker never included Eatable
end
```

Ab kuch bhi `RobotWorker` ko ek meaningless `eat` define karne ke liye force
nahi karta, aur koi bhi caller jise specifically "something that eats"
chahiye woh ek `Eatable` maangta hai (`worker.is_a?(Eatable)` ya, more
idiomatically Ruby mein, bas `eat` call karke duck typing ko sort out karne
deta hai) instead of yeh assume karne ke ki har `Workable` eat kar sakta
hai. Yeh practice mein isliye matter karta hai kyunki fat interfaces samay
ke saath sirf kuch implementers ke liye relevant methods accumulate karte
hain, aur har implementer un methods ko stub out karne ya unpe raise karne
ki cost pay karta hai jinki usko kabhi zaroorat hi nahi thi.

## D — Dependency Inversion Principle (DIP)

**Definition:** abstractions pe depend kariye, concrete implementations pe
nahi — high-level, business-logic classes ko directly specific low-level
classes instantiate ya call nahi karna chahiye; instead, ek dependency
(jo kisi expected contract se match karti ho) unhe handover ki jaani
chahiye, taaki concrete implementation ko high-level class ko edit kiye
bina swap kiya ja sake.

**Before (violates DIP — ek concrete low-level class ko hardcode karta
hai):**

```ruby
class EmailSender
  def send(message) = puts "Emailing: #{message}"
end

class NotificationService
  def initialize
    @sender = EmailSender.new   # hardcoded - NotificationService owns this decision
  end

  def notify(message)
    @sender.send(message)
  end
end
```

`NotificationService` (high-level: "notify someone") directly `EmailSender`
(low-level: "how to actually send") se coupled hai. SMS pe switch karna, ya
dono support karna, ka matlab hai `NotificationService` ko khud edit karna
— aur `NotificationService` ko isolation mein unit test karne ka matlab hai
ya to really emails bhejna ya `EmailSender` ko monkey-patch karna, kyunki
ek test double inject karne ke liye koi seam hi nahi hai.

**After (ek injected, duck-typed contract pe depend kariye):**

```ruby
class EmailSender
  def send(message) = puts "Emailing: #{message}"
end

class SmsSender
  def send(message) = puts "Texting: #{message}"
end

class NotificationService
  def initialize(sender)
    @sender = sender   # any object responding to #send works
  end

  def notify(message)
    @sender.send(message)
  end
end

NotificationService.new(EmailSender.new).notify("hello")
NotificationService.new(SmsSender.new).notify("hello")
```

`NotificationService` ab sirf "something with a `send` method" pe depend
karta hai — abstraction — specifically `EmailSender` pe nahi. Yeh
dependency **injection** hai us mechanism ki tarah jo dependency
**inversion** achieve karta hai: instead of high-level class ke apni khud
ki low-level dependency construct karne ke liye neeche reach karne ke,
dependency bahar se handover ki jaati hai. Concretely, yeh
`NotificationService` ko trivially testable banata hai (ek fake sender
inject kariye jo bas calls record kare) aur trivially extensible banata hai
(`PushNotificationSender` add kariye `NotificationService` mein zero
changes ke saath).

## Why LLD interviews specifically probe for SOLID

Paanchon principles woh concrete, nameable cheezein hain jinki taraf ek
interviewer point karta hai jab woh kehta hai "this design won't
scale/extend well" — aur yeh naam le paana ki ek design choice *kaunsa*
principle serve karti hai khud ek strong signal hai, code se independent.
"I made `Vehicle` an abstract base class with `spots_required` so adding a
new vehicle type doesn't require editing `ParkingLot` — that's Open/Closed"
interviewer ko batata hai ki aapne isko purpose se design kiya, similar
dikhne wali code pe accidentally pahunchne ke bajaye. Practice mein, most
LLD interview follow-ups ("now add a new type," "how would you test this
in isolation," "what if we need to swap this implementation") really in
paanch principles mein se ek respect hua ki nahi iske hi probes hote hain.
Vocabulary ke saath andar aana matlab aap follow-up ko poocha jaane se
pehle hi anticipate aur naam le sakte hain.

## Interview Tips

- Jab aap ek naya class specifically ek responsibility isolate karne ke
  liye introduce karein, letter ko out loud boliye: "I'm pulling
  validation into its own class — that's Single Responsibility, so a
  change to validation rules can't accidentally affect persistence."
- "Now add a new type" ko Open/Closed ke ek direct test ki tarah expect
  kariye. Agar aapke design mein naya type add karne ke liye ek existing
  class ka method body edit karna padta hai, yeh tell hai ki aap kahin
  polymorphism miss kar rahe hain.
- Agar ek subclass ek parent method ko aise override karta hai jo parent
  ke callers ko surprise kare (return type change karta hai, jahan parent
  nahi karta wahan raise karta hai, silently unrelated state change karta
  hai), interviewer se pehle khud isko ek possible LSP violation ki tarah
  flag kariye.
- ISP ko rarely apna dedicated question milta hai, lekin yeh
  module/interface design ke follow-up ki tarah dikhta hai: "does every
  implementer of this module actually need all these methods?" khud se
  proactively poochne layak hai.
- DIP woh principle hai jo testability se sabse directly tied hai — agar
  poocha jaaye "how would you test this without hitting a real
  database/API," answer almost hamesha "inject the dependency so I can
  substitute a test double" hota hai, jo DIP in action hai.
- Har design mein paanchon ko force mat kariye. Ek five-line parking spot
  class ko ek DIP-style injected collaborator ki zaroorat nahi hai. Har
  principle ko wahan apply kariye jahan yeh design ki koi actual problem
  solve karta ho, aur ready rahiye yeh explain karne ke liye ki aapko
  baaki kyun nahi chahiye the.

## Quick Recall — Self-Test

1. **Single Responsibility Principle ko ek sentence mein state kariye, aur
   ise violate karne ka concrete risk explain kariye.**
   Ek class ke paas change hone ki ek reason honi chahiye. Ise violate
   karne ka matlab hai unrelated concerns (e.g., validation, persistence,
   notification) ek class share karte hain, to kisi bhi ek concern mein
   change baaki ko break karne ka risk rakhta hai, aur class ko isolation
   mein test ya reason nahi kiya ja sakta.

2. **Open/Closed polymorphism se kaise relate karta hai, specifically
   parking lot example use karke?**
   Open/Closed polymorphism ke zariye achieve hota hai: `Vehicle`
   subclasses har ek `spots_required` implement karte hain, taaki
   `ParkingLot` kabhi vehicle type pe branch na kare. Ek naya vehicle type
   add karna (e.g., `Truck`) ka matlab hai ek naya class add karna —
   `ParkingLot` aur existing `Vehicle` subclasses kabhi edit nahi hote
   ("closed for modification, open for extension").

3. **Square-extends-Rectangle LSP violation explain kariye: specifically
   kya break hota hai, aur yeh ek simple crash se worse kyun hai?**
   `Square` `width=`/`height=` ko override karta hai dono dimensions ko
   equal rakhne ke liye, jo silently `height` ko change kar deta hai jab
   sirf `width` set hua ho. `Rectangle` ke contract ke against likhi gayi
   code (width set karna height ko touch nahi karta) ek `Square` diye
   jaane pe ek wrong `area` value produce karti hai — yeh ek crash se
   isliye worse hai kyunki code bina error ke chalti hai aur silently
   incorrect results return karti hai.

4. **Interface Segregation kis cheez ke against warn karta hai, aur yeh
   Single Responsibility se kaise different hai?**
   ISP ek implementer ko aise methods define karne se force hone ke
   against warn karta hai jo usko chahiye nahi, interfaces/modules ko
   zyada broad banake (ek `Worker` module jo `RobotWorker` pe `eat` force
   karta hai). SRP ek single class ke paas change hone ki sirf ek reason
   hone ke baare mein hai; ISP specifically unrelated method contracts ko
   ek interface mein bundle na karne ke baare mein hai jise saare
   implementers satisfy karein.

5. **Dependency Inversion kya hai, aur ise typically kaunsa Ruby mechanism
   implement karta hai?**
   DIP kehta hai high-level classes ko abstractions pe depend karna
   chahiye, concrete low-level classes pe nahi — e.g., ek
   `NotificationService` ko "anything that responds to `send`" pe depend
   karna chahiye, specifically `EmailSender` pe nahi. Yeh typically
   dependency injection ke zariye implement hota hai: collaborator object
   ko class ke andar instantiate karne ke bajaye constructor mein pass
   karke.

6. **DIP unit testing ko easier kyun banata hai? Ek concrete example
   dijiye.**
   Kyunki dependency inject hoti hai instead of hardcoded hone ke, ek test
   ek fake object substitute kar sakta hai (e.g., ek test double jo bas
   calls record karta hai instead of really email bhejne ke) bina class
   under test ko modify kiye. `NotificationService.new(fake_sender)` ko
   kisi bhi real email ya SMS infrastructure se complete isolation mein
   test kiya ja sakta hai.

7. **Ek candidate kehta hai "I split this into three classes because it
   looked cleaner." Yeh ek specific SOLID principle naam lene se weaker
   interview answer kyun hai?**
   "Looked cleaner" ek vague, subjective justification hai jo deliberate
   design reasoning demonstrate nahi karti. Principle ka naam lena ("I
   split this because each class should have a single reason to change —
   SRP") dikhata hai ki decision intentional thi aur ek recognized
   trade-off mein grounded thi, jo exactly wahi hai jise interviewers
   specifically sunte hain.

8. **Open/Closed aur Liskov Substitution kaise interact karte hain? Kya
   ek design Open/Closed satisfy karte hue Liskov violate kar sakta hai?**
   Haan — ek design extensible ho sakta hai (naye subclasses existing code
   edit kiye bina add hote hain, OCP satisfy karte hue) jabki unme se kuch
   subclasses apne parent ke behavioral contract ko abhi bhi violate karte
   hon (LSP violate karte hue), jaise ek naya `Vehicle` subclass jiska
   `spots_required` ek spot type ke liye ek nonsensical ya inconsistent
   value return karta ho aise tarike se jo silently
   `ParkingLot#park` ki assumptions ko break kar de. Extensibility aur
   substitution ke under behavioral correctness separate concerns hain.
