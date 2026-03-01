Question 1: What is RSpec?
Answer: RSpec is a behavior-driven development (BDD) testing framework for Ruby and Rails. It allows us to write human-readable tests that describe how the system should behave. Instead of focusing on implementation details, it focuses on expected behavior.

In Rails projects, we use RSpec to test models, controllers, APIs, background jobs, and integrations. It provides a DSL like describe, context, and it, along with powerful mocking, stubbing ans spy capabilities.

--------------------------------------------------------------------------------------------------------
Question 2: Difference Between Unit Test & Integration Test?
Answer: A unit test verifies a single unit of code in isolation — for example, a model method. It should not depend on external systems.

An integration test verifies how multiple components work together — for example, controller + model + database interaction.
In Rails, model specs are unit tests, and request specs are integration tests

--------------------------------------------------------------------------------------------------------
Question 3: What is describe, context, it?
Answer: Describe defines the class or method being tested.
Context defines a specific scenario or condition.
It defines an individual test example — basically the expected behavior.

So the structure reads like documentation: "Describe User, context when email is missing, it is invalid."
Example:
  describe User do
    describe "#active?" do
      context "when status is active" do
        it "returns true" do
          user = User.new(status: "active")
          expect(user.active?).to eq(true)
        end
      end
    end
  end

--------------------------------------------------------------------------------------------------------
Question 4: What is before, let, let!, subject?
Answer: Before is used for setup logic that runs before each example.
  before do
    @user = User.create!(...)
  end
Let defines a memoized helper variable. It is lazy-loaded, meaning it runs only when called.
  let(:user) { User.create!(...) }

Let! is eager-loaded — it runs before each test regardless of usage.

Subject represents the main object under test, and it improves readability when writing expectations.
subject represents the primary object under test and integrates with RSpecs DSL, enabling implicit expectations like is_expected.

RSpec automatically defines subject as described_class.new

  subject { User.new(name: "Test") }

  it "is valid" do
    expect(subject).to be_valid
  end

"I prefer let over before for variable definitions because it makes the test more readable and avoids unnecessary DB creation."

--------------------------------------------------------------------------------------------------------
Question 5:What is FactoryBot?
Answer: FactoryBot is a test data generation library. Instead of manually creating records in every test, we define reusable factories.

It keeps specs clean, avoids duplication, and makes test setup maintainable.
  We define: 

    FactoryBot.define do
      factory :user do
        name { "Pankaj" }
        email { "test@example.com" }
      end
    end

  And then we use: 
    let(:user) { create(:user) }

--------------------------------------------------------------------------------------------------------
Quesion 6: What is Faker?
Answer: Faker is a Ruby library used to generate fake but realistic test data.
It helps us create random names, emails, phone numbers, addresses, and other attributes in factories.
This makes test data more realistic and prevents issues like uniqueness validation failures.

It helps avoid hardcoded values and reduces duplication.
It is especially useful when we need unique fields like emails or usernames.

Example:
  FactoryBot.define do
    factory :user do
      name  { Faker::Name.name }
      email { Faker::Internet.unique.email }
    end
  end

One thing to be careful about is randomness.
If overused, Faker can make tests flaky or non-deterministic.
So for critical specs, I prefer predictable values unless randomness is necessary.

--------------------------------------------------------------------------------------------------------
Quesion 7: What is a trait in FactoryBot?
Answer: A trait in FactoryBot is a way to define reusable variations of a factory.
Instead of creating multiple factories for small differences, we define traits inside a factory and apply them when needed.
It helps avoid duplication and keeps factories clean and flexible.
Traits are composable. We can combine multiple traits to build complex test data without creating many separate factories.

Example:
    FactoryBot.define do
      factory :user do
        name { "Pankaj" }
        role { "user" }

        trait :admin do
          role { "admin" }
        end

        trait :inactive do
          active { false }
        end
      end
    end

    We can use like:
      create(:user, :admin)
      create(:user, :inactive)
      create(:user, :admin, :inactive)

--------------------------------------------------------------------------------------------------------
Question 8: What is DatabaseCleaner?
Answer: DatabaseCleaner ensures that the database is cleaned between tests to maintain isolation.
It supports strategies like transaction and truncation.

However, in modern Rails applications, transactional fixtures are usually sufficient unless we are testing JavaScript or multi-threaded behavior.

-------------------------------------------------------------------------------------------------------
Question 9:How do you test validations?
Answer: I test validations either using shoulda-matchers for concise syntax or manually by creating invalid objects and checking that they are not valid.
  example: it { should validate_presence_of(:sms_quantity) }
  Here we do not need to manually creating the object, but Shoulda does it internally.

I prefer manual testing when business logic is complex.
  Example:
    RSpec.describe SmsPlan, type: :model do
      describe "validation" do
        it "is invalid without sms_quantity" do
          sms_plan = SmsPlan.new(sms_quantity: nil)

          expect(sms_plan).not_to be_valid
          expect(sms_plan.errors[:sms_quantity]).to include("can't be blank")
        end
      end
    end

    OR, we can also do like this:
      RSpec.describe SmsPlan, type: :model do
        describe "validation" do
          subject { build(:sms_plan) }  # factory includes company

          it { should validate_presence_of(:sms_quantity) }
        end
      end
-------------------------------------------------------------------------------------------------------
Question 10:How do you test callbacks?
Answer: I do not test callbacks directly. I test the side effects of the callback.
For example, if a before_save generates a token, I verify that the token exists after saving.
I focus on behavior, not implementation details.

Example: If we have before_save :generate_token
  it "generates token before save" do
    user = create(:user)
    expect(user.token).not_to be_nil
  end

-------------------------------------------------------------------------------------------------------
Question 11:How do you test background jobs?
Answer: If using ActiveJob, I verify that the job is enqueued using have_enqueued_job matcher.
If using Sidekiq, I check whether the job is pushed into the queue.
I do not test Rails internals — I test that my application enqueues the job correctly.

  If using ActiveJob:
    it "enqueues job" do
      expect {
        UserMailerJob.perform_later(user.id)
      }.to have_enqueued_job(UserMailerJob)
    end

  For Sidekiq:
    expect {
      MyJob.perform_async(1)
    }.to change(MyJob.jobs, :size).by(1)

-------------------------------------------------------------------------------------------------------
Question 12: How do you test APIs?
Answer: I use request specs because they test the full stack — routing, controller, middleware, and database.
I send HTTP requests and assert on status code and JSON response structure.
Example:

  describe "GET /users" do
    it "returns users" do
      get "/users"
      expect(response).to have_http_status(:ok)
    end
  end

-------------------------------------------------------------------------------------------------------
Question 13: How do you stub external APIs?
Answer: I stub external API calls to avoid real HTTP requests during tests.
I use WebMock or allow with receive to mock the response.
This keeps tests fast and deterministic.

Examples: Using allow:
  allow(ExternalService).to receive(:call).and_return("success")
  allow(Net::HTTP).to receive(:get).and_return("success")

Examples: WebMock (For HTTP calls)
  To use WebMock, we have to install the gem: gem 'webmock'
  
  Enable WebMock in RSpec: spec/rails_helper.rb
    require 'webmock/rspec'
  By default, WebMock disables real HTTP connections in test environment.
    So, if needed:
        WebMock.disable_net_connect!(allow_localhost: true)

  stub_request(:get, "https://api.test.com").to_return(status: 200, body: "ok")
  stub_request(:get, "https://api.example.com/users/1").to_return(status: 500, body: "Internal Server Error")
  stub_request(:get, "https://api.example.com/users/1").to_timeout

-------------------------------------------------------------------------------------------------------
Question 14: Mock vs Stub
Answer: A stub replaces a method and returns a predefined value.
A mock sets an expectation that a method must be called.

Stubs test output.
Mocks test interaction.

-------------------------------------------------------------------------------------------------------
Question 15: How do you test private methods?
Answer: I do not test private methods directly.
I test them indirectly through public methods.

If I feel the need to test a private method directly, it usually means the method should be extracted into a separate class.

However if it is absolutely required then we can use send method.
example: object.send(:private_method)
But using send for private methods is considered as bad practice.
-------------------------------------------------------------------------------------------------------
Question 16: What is shared_examples?
Answer: Shared examples allow us to reuse test logic across multiple specs.
It helps when multiple models share the same behavior.

Example:
  RSpec.describe EventCustomers::Create do
    describe "some_method_name" do
  
      RSpec.shared_examples "a payable model" do
        subject { build(:order) }

        it "calculates tax" do
          expect(order.tax).to be > 0
        end
      end

      context "pay rent with tax" do 
        it_behaves_like "a payable model"
      end

      context "pay bill with tax" do 
        it_behaves_like "a payable model"
      end 
    end
  end

-------------------------------------------------------------------------------------------------------
Question 17: How do you test JSON response?
Answer: I parse the response body using JSON.parse and assert on specific keys and values.
I also verify the HTTP status code and response structure.
Example: 
  get "/users"
  json = JSON.parse(response.body)
  expect(json["data"]).not_to be_empty

-------------------------------------------------------------------------------------------------------
Question 18: Why are tests slow?
Answer: Tests become slow mainly due to excessive database usage, unnecessary FactoryBot record creation, N+1 queries, truncation cleaning strategy, or real external API calls.

Feature specs are also slow because they load the full browser stack.

-------------------------------------------------------------------------------------------------------
Question 19: How do you optimize test suite?
Answer: I minimize database usage by using build instead of create where possible.
I avoid unnecessary callbacks.
I stub external services.
I use transactional fixtures.
And in larger projects, I enable parallel testing.

-------------------------------------------------------------------------------------------------------
Question 20: How to avoid N+1 in specs?
Answer: If N+1 appears during test execution, I fix it in the application code using includes or eager loading.
I also use Bullet gem in test mode to detect N+1 issues.

-------------------------------------------------------------------------------------------------------
Question 21: What is transactional fixtures?
Answer: Transactional fixtures wrap each test inside a database transaction and roll it back after execution.
This makes tests fast and isolated.
We can enable this inside spec/rails_helper.rb:
  config.use_transactional_fixtures = true

-------------------------------------------------------------------------------------------------------
Question 22: How to Test Multi-threaded Code?
Answer: Testing multi-threaded code is mainly about verifying thread safety and preventing race conditions, rather than testing the threads themselves.

First, I focus on testing the behavior under concurrency. For example, if multiple threads try to create the same record, I verify that only one record is created.
In Rails, if the test involves the database, I usually disable transactional fixtures, because each thread uses a separate database connection and will not share the same transaction. Instead, I rely on proper database cleaning strategies.

In the test itself, I create multiple threads, trigger the concurrent action, and then always call join on each thread to ensure the test waits for them to finish. After that, I assert the final state — like checking the record count or ensuring data consistency.

I also make sure concurrency safety is enforced at the database level, such as using unique indexes, not just Rails validations. That is critical because validations alone are not safe under race conditions.

If I want to simulate a real race condition, I sometimes use synchronization tools like a barrier or queue to make threads start at the same time, instead of relying on sleep, which can make tests flaky.

So overall, my approach is:
  Test the outcome, not the threading implementation
  Use real database constraints
  Wait for threads properly
  Make tests deterministic and repeatable
-------------------------------------------------------------------------------------------------------
Question 23: Request spec vs Controller spec?
Answer: Controller specs test the controller in isolation. It mocks routing and middleware.
It is faster but less realistic.

Request specs test the full Rails stack. Goes through routing + middleware
Modern Rails prefers request specs because they are closer to real-world behavior.”

-------------------------------------------------------------------------------------------------------
Question 24: Why feature specs are slower?
Answer: Feature specs use Capybara and sometimes a JavaScript driver, which loads the browser environment.
They test full end-to-end behavior, so naturally they are slower.

-------------------------------------------------------------------------------------------------------
Question 25: How do you test a Rails controller that returns JSON?
Answer: I write a request spec.
I send a GET or POST request to the endpoint.
Then I assert the HTTP status and parse the JSON response to verify structure and values.
If authentication is required, I pass headers accordingly.

Example:
  describe "GET /api/users" do
    let!(:user) { create(:user) }

    it "returns JSON response" do
      headers = { "Authorization" => "Bearer token" }
      get "/api/users", headers: headers

      expect(response).to have_http_status(:ok)

      json = JSON.parse(response.body)

      expect(json.first["email"]).to eq(user.email)
    end
  end

-------------------------------------------------------------------------------------------------------
Question 26: What is double in RSpec?
Answer: Double in RSpec is a test double — a fake object used to replace real dependencies during unit testing. It allows us to isolate the class under test by preventing calls to external services, databases, or other classes. We control its behavior using stubs or mocks. This makes tests faster, deterministic, and focused only on the logic we are testing.

A double is a test double — a fake object that stands in for a real object during testing.
It simulates behavior without using the real implementation.
Basic fake object. Does not check real class.

Think of it as: A lightweight fake object that you fully control.
  When you write:
    gateway = double("PaymentGateway")

  You get:
    A blank object
    That has no real methods
    Unless you explicitly define them

🔸instance_double
  It is Safer version.
    gateway = instance_double(PaymentGateway)
  This ensures:
    Only real methods of PaymentGateway can be stubbed.
    If you stub a non-existing method → test fails.
    This prevents false positives.
  In production Rails apps, you should prefer instance_double.

🔸class_double
  Used when mocking class methods.

-------------------------------------------------------------------------------------------------------
Question 27: Why Do We Need double?
Answer: Because in unit testing We want to test one class in isolation
        We do NOT want to:
            Call external APIs
            Hit the database
            Run expensive logic
            Depend on other classes correctness

      So we replace real dependencies with controlled fake objects.
      That fake object is created using double.

-------------------------------------------------------------------------------------------------------
Question 28: Stub and Mock. 
  Suppose we have:
    class PaymentGateway
      def charge(amount)
        # Calls external API
      end
    end

    class OrderProcessor
      def initialize(gateway = PaymentGateway.new)
        @gateway = gateway
      end

      def process(order)
        @gateway.charge(order.total)
        order.update(status: "paid")
      end
    end

  🔸Stub: A stub replaces a method and returns a predefined value, but does NOT verify whether it was called.
    Example:
      RSpec.describe OrderProcessor do
        it "updates order status to paid" do
          order = double("Order", total: 100)
          allow(order).to receive(:update)

          gateway = double("PaymentGateway")
          allow(gateway).to receive(:charge).and_return(true)

          processor = OrderProcessor.new(gateway)
          processor.process(order)

          expect(order).to have_received(:update).with(status: "paid")
        end
      end

      Here:
        allow(gateway).to receive(:charge).and_return(true)

        → We replaced the real charge method.
        → It will return true.
        → We did NOT require it to be called.

      If charge is never called, the test will still pass. That is a stub.

  🔸Mock: A mock sets an expectation that a method MUST be called.
    Example:
      RSpec.describe OrderProcessor do
        it "charges the payment gateway" do
          order = double("Order", total: 100, update: true)

          gateway = double("PaymentGateway")
          expect(gateway).to receive(:charge).with(100)

          processor = OrderProcessor.new(gateway)
          processor.process(order)
        end
      end
    
      Here:
        expect(gateway).to receive(:charge).with(100)
        
        → We are asserting:
            charge MUST be called
            with argument 100
            If it is not called → test fails.
            If called with wrong argument → test fails.
        That is a mock (behavior verification).


  In modern RSpec:
    allow(...).to receive and return  → Stub
    expect(...).to receive            → Mock
  RSpec uses test doubles for both.

-------------------------------------------------------------------------------------------------------
Question 29: What is difference between Stub, Mock and Spy in RSpec?
Answer:
      Stub is used to control the return value of a method.
      Mock is used to set expectations before execution and verifies interaction.
      Spy is a stub that allows us to verify method calls after execution.


=========================== Stub, Mock and  Spy - Hindi me  =====================================
Stub, Mock, Spy - Ye teeno doubles use karte hain, but intention alag hota hai.

🔸Stub: (Behaviour Control)
    Stub ka kaam hota hai method ka return value control karna.
    Matlab "Real method call mat karo, main jo bolu wo return karo."
    Stub Focus on: Control the output, not verify interaction.

    Example:
      allow(User).to receive(:find).and_return(double(name: "Pankaj"))

      Yaha kya ho raha hai?
        User.find actual DB hit nahi karega
        Wo fake object return karega
        Hum sirf return value control kar rahe hain

    Real Example:
      allow(gateway).to receive(:charge).and_return(true)

      Matlab:
        Chahe real gateway fail kare ya external API ho
        Test me hamesha true return karo

      Important:
        Stub verify nahi karta ki method call hua ya nahi.
        Sirf behaviour override karta hai.

🔸Mock: (Expectation + Verification)
    Mock ka kaam hota hai ye verify karna ki method call hua ya nahi.
    Yeh behaviour se zyada interaction verify karta hai.

    Example:
      expect(order).to receive(:update).with(status: "paid")
      processor.process(order)

      Iska matlab:
        Mujhe expect hai ki update method call hoga hi hoga with this argument.
        Agar call nahi hua → test fail.

      Test pehle hi bol deta hai: “update call hona hi chahiye”
      Agar call nahi hua → immediately fail
      Iska issue kya hai? -> Yeh test ko implementation-coupled bana deta hai.

    Difference between Stub and Mock:
      Stub: allow(order).to receive(:update)
      Mock: expect(order).to receive(:update)

🔸Spy: (Post Verification)
  Spy basically ek stub + later verification hota hai.

  Matlab:
    Pehle allow karo
    Baad me check karo ki call hua ya nahi
  
  Example:
    allow(order).to receive(:update)
    processor.process(order)
    expect(order).to have_received(:update)
    
    expect(order).not_to have_received(:update) -> For negative case.

    Yaha:
      Pehle stub kiya
      Code run hua
      Baad me verify kiya ki call hua ya nahi
      tum positive aur negative dono scenarios easily test kar sakte ho. This is benifit of spy.

  Difference between Spy vs Mock: 
    Mock:
      expect(order).to receive(:update)
      processor.process(order)

    Spy:
      allow(order).to receive(:update)
      processor.process(order)
      expect(order).to have_received(:update)


    +-------------------------------------------------------------+
    |           Mock               |          Spy                 |
    |------------------------------+------------------------------|
    | Expectation BEFORE execution | Verification AFTER execution |
    | Strict behaviour             | Flexible                     |
    | Mostly legacy style          | Recommended modern style     |
    +-------------------------------------------------------------+