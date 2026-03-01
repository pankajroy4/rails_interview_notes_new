=================================== SOLID Principle ==================================================

Question 1: What are SOLID principles?

Answer: -> SOLID is a set of five object-oriented design principles that help us write clean, maintainable, and scalable code. These principles guide how we design classes and modules so that changes in one part of the system do not break other parts.
SOLID is very valuable because Rails apps can become “fat models / fat controllers” over time, and SOLID gives you the mindset + patterns to keep the code maintainable.

SOLID stands for Single Responsibility, Open-Closed, Liskov Substitution, Interface Segregation, and Dependency Inversion.

So SOLID principles help you to write code that is:
  easier to change
  easier to test
  easier to extend
  less likely to break when requirements change

------------------------------------------------------------------------------------------------------
Question 2: What is Single Responsibility Principle ( S ) ?

Answer: -> The Single Responsibility Principle states that a class should have only one reason to change. In simple terms, a class should do one thing and do it well.

In Rails context:
A User model should not contain: payment logic ,report generation ,API integrations ,email formatting ,etc
Those are separate responsibilities.

Good Rails approach is to move logic out into: Service objects (app/services), Query objects, Form objects, Policies, Jobs, Decorators / Presenters, etc
------------------------------------------------------------------------------------------------------
Question 3: Can you explain SRP with a real example?

Answer: -> If a class is responsible for business logic, database operations, and email notifications, it violates SRP. A better approach is to separate these into a model, a service object, and a mailer. This makes each class easier to understand and maintain.

------------------------------------------------------------------------------------------------------
Question 4: What are common SRP violations in Rails?

Answer: Fat controllers, fat models, and callbacks doing too much logic are common SRP violations. When a model starts handling external API calls or complex workflows, it’s usually a sign SRP is being broken.

------------------------------------------------------------------------------------------------------
Question 5: What is the Open/Closed Principle(O)?

Answer: -> The Open/Closed Principle says that software-entities i.e code should be open for extension but closed for modification. That means we should be able to add new behavior and features without changing existing code.

Example: Discount calculation
  Bad:
    def discount_for(order)
      if order.coupon?
        ...
      elsif order.vip_customer?
        ...
      elsif order.seasonal_sale?
        ...
      end
    end

  This method grows forever.

  Better: Strategy pattern / polymorphism
    class Discounts::Base
      def apply(order); end
    end

    class Discounts::Coupon < Discounts::Base
      def apply(order)
        ...
      end
    end

    class Discounts::Vip < Discounts::Base
      def apply(order)
        ...
      end
    end

  Now if tomorrow you add “Employee Discount”, you create a new class — no need to modify old ones.

------------------------------------------------------------------------------------------------------
Question 6: Can you give an example of OCP?

Answer: ->  If we have a payment system and later add new payment methods like UPI or PayPal, we should not keep modifying a single if-else block. Instead, we can introduce new classes that implement a common interface.

------------------------------------------------------------------------------------------------------
Question 7: How do you achieve OCP in Rails?

Answer: -> In Rails, OCP is often achieved using polymorphism, service objects, and strategy patterns. For example, using different service classes for different behaviors instead of condition-heavy logic.

------------------------------------------------------------------------------------------------------
Question 8: What happens if OCP is violated?

Answer: ->: If OCP is violated, every new feature requires modifying existing code, increasing the risk of bugs and regressions. The system becomes fragile over time.

------------------------------------------------------------------------------------------------------
Question 9: What is the Liskov Substitution Principle(L - LSP)?

Answer: -> The Liskov Substitution Principle states that objects of a superclass should be replaceable with objects of its subclasses without breaking the application.
If a child class changes the expected behavior of a parent class, it violates LSP. Subclasses should honor the contract defined by the parent class.
If a base class method promises to return a value, but a subclass raises an exception instead, that violates LSP. Any code using the base class would break when the subclass is substituted.

So inheritance must not change the meaning of the parent contract.
In very practical terms:
  A subclass must not:
  🔸remove a behavior the parent promised
  🔸change return types in a surprising way
  🔸raise new errors for normal valid usage
  🔸require extra conditions that the parent did not require
  So the subclass should behave like a “true version” of the parent, not a different thing.

In Rails, LSP mainly matters when we use inheritance like STI. If code expects a base model and calls methods defined in the base class, then every subclass must honor the same behavior contract. A subclass should not override a method and change its meaning—for example raising exceptions or restricting valid input. Otherwise, it breaks substitutability and causes runtime bugs.

Real-world Rails symptoms of LSP violation
These are common cases:
  STI base class provides method ship!, but one child raises “cannot ship”
  Base model validates amount >= 0, subclass adds validation amount > 1000 and breaks existing flows
  Controller/service expects .to_json to return same shape, but subclass changes keys/format

------------------------------------------------------------------------------------------------------
Question 10: Interface Segregation Principle (I- ISP). What is Interface Segregation Principle?

Answer: -> The principle says: Don't force a class to implement methods it doesn't need.
The Interface Segregation Principle says that clients(Tte subclass or the class which is including other module) should not be forced to depend on methods they do not use. Instead of one large interface, we should have multiple smaller, focused interfaces.
If a module contains methods for email, SMS, and push notifications, but a class only needs email, forcing it to implement all methods violates ISP.

If you make a big interface with many methods, then:
 🔸some classes will be forced to implement “irrelevant” methods
 🔸they will add dummy code like raise NotImplementedError
 🔸your code becomes harder to maintain

So ISP says: Create small, focused interfaces, so each client depends only on what it uses.

Example:Imagine one big interface:
  module Worker
    def work; end
    def eat; end
    def fly; end
  end

Now:
  Humans can work, eat
  Birds can eat, fly
  But humans can not fly so they would be forced to implement fly with useless code.That violates ISP.

ISP fix: split interfaces
  module Workable
    def work; end
  end

  module Eatable
    def eat; end
  end

  module Flyable
    def fly; end
  end

Now each class includes only what it needs.

------------------------------------------------------------------------------------------------------
Question 11: Dependency Inversion Principle (D - DIP). What is Dependency Inversion Principle?

Answer: -> The Dependency Inversion Principle says that high-level modules should not depend on low-level modules. Both should depend on abstractions, not concrete implementations.

High-level module: High-level = business logic / rules / workflow
  What the system should do
    Example: CheckoutService, PlaceOrderService, InvoiceService
    It represents your product logic.

  Low-level module: Low-level = technical details / external integration / infrastructure
    How it is done
    Example: RazorpayGateway, StripeGateway, S3Uploader, TwilioSmsSender, Net::HTTP

  So:
    High-level code is the “decision maker” (business rules)
    Low-level code is the “tool” (implementation detail)

  What DIP says: 
    Bad design:
      If your business logic directly depends on a specific tool, then your business logic becomes tightly coupled.
      Example:

      class CheckoutService
        def initialize(user)
          @user = user
          @gateway = StripeGateway.new
        end

        def pay(amount)
          @gateway.charge(@user, amount)
        end
      end

    Here CheckoutService depends directly on StripeGateway. This breaks DIP.
    Because now:
      if you want Razorpay instead of Stripe → must modify CheckoutService
      Unit testing becomes hard (you must hit Stripe or heavily mock)
      Business logic becomes tied to vendor choice

    DIP says: “depend on abstraction”
      Instead of:
        CheckoutService → StripeGateway
      Do:
        CheckoutService → PaymentGateway interface (contract)
        StripeGateway / RazorpayGateway → implement that contract

DIP using Ruby style:
  Step 1: define expectation (abstraction)
    Not a Java interface — just a contract like:
    “anything used as payment gateway must respond to charge(user, amount)”

  Step 2: inject dependency
    class CheckoutService
      def initialize(user, gateway:)
        @user = user
        @gateway = gateway
      end

      def pay(amount)
        @gateway.charge(@user, amount)
      end
    end

  Now:
    High-level module (CheckoutService) does NOT know about Stripe/Razorpay
    It only knows: “I have a gateway that can charge”

  Then you can plug anything:
    CheckoutService.new(user, gateway: StripeGateway.new)
    CheckoutService.new(user, gateway: RazorpayGateway.new)

  Why it is called “Dependency Inversion”?
    Normally people think: High-level depends on low-level
    DIP says:
      No — invert this.
      Both depend on a contract / abstraction.
    Meaning:
      Checkout depends on PaymentGateway contract
      Stripe depends on PaymentGateway contract too (by implementing it)
      So the dependency direction changes.

------------------------------------------------------------------------------------------------------
Question 12: How do SOLID principles help in microservices?

Answer: -> SOLID principles help define clear service boundaries, reduce coupling, and make services easier to evolve independently, which is essential in microservice architectures.