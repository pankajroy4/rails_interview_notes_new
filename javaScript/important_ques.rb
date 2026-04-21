Question 1: What is closure in JavaScript?

Answer ->  A closure is when a function remembers variables from its outer scope even after that outer function has finished executing.
Example:

  function outer() {
    let count = 0;

    return function inner() {
      count++;
      return count;
    };
  }

  const counter = outer();
  console.log(counter()); // 1
  console.log(counter()); // 2

Here, inner function still has access to count even after outer has executed.

In real-world, closures are heavily used in things like:
  data privacy
  event handlers
  custom hooks in React

--------------------------------------------------------------------------------------------------------
Question 2: What is event loop?

Answer -> JavaScript is single-threaded, meaning it can execute only one task at a time using a single call stack. But in real applications, we still handle asynchronous operations like API calls, timers, and promises. That is where the event loop comes in.

The event loop is basically a mechanism that coordinates between the call stack, the browsers Web APIs, and different queues to make async behavior possible without blocking the main thread.

Here is how it works step by step:
  First, all synchronous code is executed on the call stack. So anything like normal function calls or console logs will run immediately.

  When JavaScript encounters asynchronous operations like setTimeout or a Promise, it delegates them to the browsers Web APIs. These APIs handle the async work in the background.

  "Once those tasks are completed", their callbacks are placed into queues:
    Promises go into the microtask queue
    setTimeout and setInterval callbacks go into the macrotask queue

  Now, the event loop continuously checks if the call stack is empty. When it is empty then:
    It first processes all microtasks
    Then it moves to macrotasks

  That is why Promises always execute before setTimeout, even if the timeout is zero.

  For example:

    console.log("start");
    setTimeout(() => console.log("timeout"), 0);
    Promise.resolve().then(() => console.log("promise"));
    console.log("end");

  The output will be:
    start, end, promise, timeout

  Because synchronous code runs first, then microtasks like promises, and finally macrotasks like setTimeout.

NOTE: Microtasks are given priority to ensure immediate consistency of the program state. They are typically used for Promise resolution and internal cleanup, so JavaScript guarantees they run before moving to the next macrotask, preventing delays and inconsistent behavior.

                               --------------------------------------

NOTE: In above answer , we have used "Once those tasks are completed ...", what does thoes tasks means here?
      Answer -> Those tasks are completed means: All asynchronous operations - handled outside the JS engine, like:
                setTimeout
                setInterval
                fetch / API calls
                DOM events (click, scroll)
                Promise resolution

      Exmaple 1:
        setTimeout(() => {
          console.log("timeout done");
        }, 2000);

        What actually happens:
          JS sees setTimeout, an asynchronous operation.
          It hands it over to the browser (Web API)

          The “task” here is: “Wait for 2 seconds”
        
        After 2 seconds:
          That waiting work is completed
          Now the callback: () => console.log("timeout done"), gets pushed into the macrotask queue

      Exmaple 2: 
        Promise.resolve().then(() => {
          console.log("promise done");
        });

        Here, The “task” is: resolving the promise.
        Since it is already resolved, it completes immediately.
        Then its callback goes into the microtask queue.

      So:
        “Task” = the "async work" - handled outside the call stack
        “Callback” = what runs after the task finishes

      By "tasks", We mean asynchronous operations like timers, API calls, or promise resolutions that are handled by the browsers web APIs. Once they complete, their callbacks are queued for execution.

--------------------------------------------------------------------------------------------------------
Question 3: What is hoisting?

Answer -> Hoisting means variable and function declarations are moved to the top of their scope during compilation.
With var,  variables are hoisted and initialized with undefined during the memory creation phase.

But with let and const, variables are hoisted but stay in temporal dead zone i.e not gets initialized during the memory creation phase, so accessing them before declaration throws error.

--------------------------------------------------------------------------------------------------------
Question 4: Difference between var, let, const

Answer -> var is function-scoped, allows redeclaration, allow reassignment, and is hoisted and initialized with undefined during the memory creation phase.

let is block-scoped, do not allow redeclaration,  allow reassignment,  and are hoisted but stay in the Temporal Dead Zone i.e on hoisting not gets initialized with undefined during the memory creation phase.

const is also block-scoped, do not allow redeclaration, do not allow reassignment, and are hoisted but stay in the Temporal Dead Zone i.e on hoisting not gets initialized with undefined during the memory creation phase.

So, let and const are hoisted but remain uninitialized, causing a Temporal Dead Zone(TDZ).

    +-----------------------------------------------------------------------------------------------------+
    |      Feature      |           var                        |      let           |       const         |
    |-------------------|--------------------------------------|--------------------|---------------------|
    |   Scope           |        Function-scoped               | Block-scoped       | Block-scoped        |
    |   Redeclaration   |        Allowed                       | Not allowed        | Not allowed         |
    |   Reassignment    |        Allowed                       | Allowed            | Not allowed         |
    |   Hoisting        | Hoisted + initialized with undefined | Hoisted but in TDZ | Hoisted but in TDZ  |
    +-----------------------------------------------------------------------------------------------------+

  Example - scope:

    function test() {
      if (true) {
        var a = 10;
        let b = 20;
        const c = 30;
      }

      console.log(a); // 10
      console.log(b); // error
      console.log(c); // error
    }

  Example - Hoisting:
    console.log(a);  // output will be "undefined". No error.
    var a = 10;

    console.log(b);  // ReferenceError because of TDZ
    let b = 10;

    console.log(c);  // ReferenceError because of TDZ
    const c = 10;

  Exmaple - Redeclaration:
    var x = 10;
    var x = 20;   // allowed

    let y = 10;
    let y = 20;   // error

    const z = 10;
    const z = 20; // error

  Example - Reassignment:
    var a = 10;
    a = 20;       // allowed

    let b = 10;
    b = 20;       // allowed

    const c = 10;
    c = 20;       // error

  NOTE: const with Object:

    const obj = { name: "PK" };

    obj.name = "Roy"; // allowed
    obj.age = 25;     // allowed
    obj = {};         // error

    const protects reference, not internal data.

--------------------------------------------------------------------------------------------------------
Question 5:

--------------------------------------------------------------------------------------------------------
Question 6:

--------------------------------------------------------------------------------------------------------
Question 7:

--------------------------------------------------------------------------------------------------------
Question 8:

