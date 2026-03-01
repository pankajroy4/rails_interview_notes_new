1:What is TypeScript?
  TypeScript = JavaScript + Static Types
  It is a superset of JavaScript created by Microsoft.
  That means:
    Every valid JavaScript file is valid TypeScript
    TypeScript adds type safety and extra tooling features
    It compiles to plain JavaScript

  In TypeScript:
    let name: string = "Pankaj";
  In JavaScript:
    let name = "Pankaj";

2:Why TypeScript is Used?
  As applications grow, JavaScript starts causing problems.
  Problems in JavaScript:
    Wrong data type passed to function
    API response shape mismatch
    Undefined access errors
    Hard to refactor safely
    Hard to understand large codebases

  Example with JavaScript:
    function add(a, b) {
      return a + b;
    }

    add(2, "3");    //returns "23" => No error. Bug in production.

  Example with TypeScript:
    function add(a: number, b: number): number {
      return a + b;
    }

    add(2, "3");     //Compile-time error

  Now error happens before running the code.
  That is the biggest reason companies use TypeScript: catch bugs during development, not production.

3:Static Typing vs Dynamic Typing
  JavaScript → dynamically typed
  TypeScript → statically typed (at compile time)

  Static typing means: Variable types are known before execution.

4:Basic Types in TypeScript
  🔸Primitive Types:
    let age: number = 25;
    let name: string = "Pankaj";
    let isActive: boolean = true;

  🔸Any Type (Danger Zone)
    let data: any = "hello";
    data = 10;
    data = {};

    any disables type checking.
    Avoid using it unless absolutely necessary.

  🔸Unknown (Safer Alternative of any Type)
    let value: unknown = "hello";
    You must check before using:
      if (typeof value === "string") {
        console.log(value.toUpperCase());
      }

    It is dafer than any type.

  🔸Arrays:
    let numbers: number[] = [1, 2, 3];
    let names: string[] = ["A", "B"];

  🔸Alternative syntax for arrays:
    let numbers: Array<number> = [1, 2, 3];

  🔸Objects:
    let user: { name: string; age: number } = {
      name: "Pankaj",
      age: 25
    };

    If you miss a field → error
    If wrong type → error

    ➤Optional Properties & Readonly
      type User = {
        name: string;
        age?: number;          // optional property
        readonly id: number;   // Readonly property
      }

5:Generics Types:
  function MyFun<T>(value: T): T {
    return value;
  }

  Now it works for all types.
  Used heavily in API wrapper, React hook, Reusable components.

  ➤Generics are like type variables.
    Just like:
      function add(a, b)  
      Here a and b are value variables.

    Similarly:
      function MyFun<T>()
      Here T is a type variable.

      If you call:
        MyFun("Hello");

        Then TypeScript infers:
          T = string
        Function Becomes:
          function MyFun(value: string): string { 
          }

      If you call:
        MyFun(100);

        Then TypeScript infers:
          T = number

        Function becomes:
          function MyFun(value: number): number {
          }

      🔸Real World exaample:
         Imagine you are writing an API helper:

          async function fetchData<T>(url: string): Promise<T> {
            const res = await fetch(url);
            return res.json();
          }

          Usage:
            type User = {
              id: number;
              name: string;
            };

            const user = await fetchData<User>("/api/user");

          Now:
            user.name  // typed correctly
            Without generics, you would get any.

  ➤Generics with Multiple Types:
    function pair<T, U>(first: T, second: U) {
      return { first, second };
    }

    Usage:
      const result = pair<string, number>("Pankaj", 25);
    Now:
      result.first  // string
      result.second // number

      TypeScript keeps full type information.

  ➤Generics with Arrays:
    function getFirst<T>(arr: T[]): T {
      return arr[0];
    }

    Now:
      const num = getFirst([1, 2, 3]); // number
      const str = getFirst(["a", "b"]); // string

      Type preserved.

  ➤Generic Constraints:
    Sometimes you want to restrict T.

      function printLength<T>(value: T) {
        console.log(value.length);
      }

      Here -> “T can be anything.”
      This might cause errors.
      For example There will be error when T is number, boolean etc. Because numbers and booleans do not have .length. 

    So you constrain it:
      function printLength<T extends { length: number }>(value: T) {
        console.log(value.length);
      }

      Here -> T can be anything that has a length property.
      This means:
        T must be at least something that has a "length: number" property.
        Works for: string, array, custom objects with length

6:Type Inference:
  You do not always need to write types.
  If TypeScript can clearly see the value, it can infer the type.
  If TypeScript cannot clearly see the future shape, you must help it.
  
  let age = 25; 
  TypeScript automatically infers:
  
  let age: number
  This is called type inference.

  🔹How TypeScript Automatically Infers Types:
      TypeScript has a type inference engine inside the compiler.
      When you write:
        let age = 25;
      The compiler:
        Looks at the right-hand side → (25)
        Determines its type → number
        Assigns that type to the variable

      From that point onward, age is treated as number
      So internally, it behaves like:
        let age: number = 25;
      But you did not write it manually.

    ➤Simple Inference
      let name = "Pankaj";
      Compiler sees "Pankaj" → string literal → infers string.

      Now: name = 10; // Error because TypeScript already locked the type as string.

    ➤Inference With Functions
      function add(a: number, b: number) {
        return a + b;
      }

      We did not define return type.
      TypeScript infers:
        function add(a: number, b: number): number
      Because a + b results in number.

    ➤Inference with arrow Function
      const multiply = (a: number, b: number) => {
        return a * b;
      };

      Return type automatically inferred as number.

    ➤Inference With Objects
      const user = {
        name: "Pankaj",
        age: 25
      };

      Inferred as:
        const user: {
          name: string;
          age: number;
        }

      Now:
        user.age = "30";     // Error

    ➤Inference With Arrays
      const numbers = [1, 2, 3];

      Inferred as:
        const numbers: number[]
      If you do:
        numbers.push("hello"); // Error

    ➤

  🔹Contextual Typing:
      TypeScript also infers types based on context.

      Example:
        const numbers = [1, 2, 3];

        numbers.map((num) => {
          return num * 2;
        });

        You did NOT type num.
        TypeScript automatically infers:
          numbers is number[]
          Therefore num is number
        That is called contextual typing.


  🔹When Should You NOT Rely on Inference:
    You should write types manually in these cases:
      1.Function Parameters
        Always type parameters.

        Bad example:
          function greet(name) {
            return "Hello " + name;
          }
        Here name becomes any.

        Good example:
          function greet(name: string) {
            return "Hello " + name;
          }
      
      2.Public APIs (Contracts)
        If you are defining:
          API response types
          React component props
          Service return types
          Shared utility functions

        You should explicitly define types.

        Example:
          type User = {
            id: number;
            name: string;
          };

          function getUser(): User {
            ...
          }

          Because this becomes a contract.
      
      3.When Type Becomes Too Broad
        Example:
          let status = "success";

          Here status inferred as string
          But maybe you want only -> "success" | "error" | "loading"

          Then you must write it:
            let status: "success" | "error" | "loading" = "success";
      
      4.Empty Arrays:
          const users = [];

          Here typeScript infers users as any[] , It is dangerous.
          So you must define:
            const users: User[] = [];

7:let vs const Inference Difference
  let status = "success";
    Inferred type → string

  But:
    const status = "success";
      Inferred type → "success" (literal type), Because const cannot change.
      That is why in modern TypeScript projects, const is preferred.

 🔸Object properties are mutable even if object is const:
   Example:
    const obj = {
      status: "success",
      code: 200
    };

    Even though the obj is const, the object properties are still mutable.
    It means:
      obj.status = "failed";  // This is allowed.
    Because properties inside a const object can still change.
    So TypeScript widens "success" to string. This is called type widening.
  
 🔸What Is Type Widening?
    When TypeScript sees:
      let name = "John";
      It infers it as string, not as "John", because name can change later.
      Same logic applies to object properties. This is Type Widening.
  
 🔸How To Prevent Widening (Literal Types)
    const obj = {
      status: "success",
      code: 200
    };

    If you want TypeScript infers as -> status: "success"
      You must use:
        const obj = {
          status: "success",
          code: 200
        } as const;

      Now the inferred type becomes:
        {
          readonly status: "success";
          readonly code: 200;
        }

      Now:
        obj.status = "failed"; // It is Error, Because it is readonly. Literal type is preserved.
      Similarily we can do:
        const arr = ["success", "error"] as const;
        const currentStatus = "success" as const;

8:Functions in TypeScript:
  Syntax:
    function functionName(param: Type): ReturnType {
    }
  
  Examples:
    function greet(name: string): string {
      return `Hello ${name}`;
    }

 🔸Arrow Function:
    const greet = (name: string): string => {
      return `Hello ${name}`;
    };

 🔸Optional Parameters:
    function greet(name: string, age?: number) {
      console.log(name, age);
    }

    age is optional.
  
9:Type Aliases (Very Important)
  Instead of writing object types again and again:

  type User = {
    name: string;
    age: number;
  };

  const user: User = {
    name: "Pankaj",
    age: 25
  };

10:Union Types:
  Sometimes a value can be multiple types.

  let id: string | number;
  id = 10;
  id = "abc";

  Type Narrowing: 
   We can perform narrowing using: typeof, instanceof, "in" operator, Discriminated unions etc.

  TypeScript will only allow an operation if it is valid for every member of the union. For example, if you have the union string | number, you can not use methods that are only available on string.

  function printId(id: number | string) {
    console.log(id.toUpperCase());  // This wil give error
  }

  Solution for this is "narrow the union with code". Narrowing occurs when TypeScript can deduce a more specific type for a value based on the structure of the code.
  Type narrowing is the process by which TypeScript reduces a broad type into a more specific type based on runtime checks.

   function printId(id: number | string) {
    if(typeof id === "string"){
      console.log(id.toUpperCase()); 
    }else {
      console.log(id)
    }
  }

  🔸Discriminated Unions:
    This is where narrowing becomes powerful.
    Example:

      type Loading = { status: "loading" };
      type Success = { status: "success"; data: string };
      type Error = { status: "error"; message: string };

      type ApiState = Loading | Success | Error;

      Now:

        function render(state: ApiState) {
          if (state.status === "success") {
            state.data; // safe
          }
        }

      Why does this work?
        Because status is a literal type.
        TypeScript sees:
          status === "success"

        So it narrows:
          ApiState
            ↓
          Success

11:Literal Types:
  let status: "success" | "error" | "loading";

  Now only these 3 values are allowed.
  Very useful for UI states.

12:Intersection Types:
  Combine multiple types.

  type User = {
    name: string;
  };

  type Admin = {
    role: string;
  };

  type AdminUser = User & Admin;

  const admin: AdminUser = {
    name: "Pankaj",
    role: "superadmin"
  };

13:Interfaces:
  Interface is similar to type.

  interface User {
    name: string;
    age: number;
  }

  Difference between Type and Interface:
    
    |       type             |       interface          |
    | ---------------------- | ------------------------ |
    | Can use unions         | Cannot use unions        |
    | More flexible          | Better for object shapes |
    | Used for complex types | Common in React props    |



14:Generic Interfaces:
    interface ApiResponse<T> {
      data: T;
      status: number;
    }

    Usage:
      type User = { name: string };

      const response: ApiResponse<User> = {
        data: { name: "Pankaj" },
        status: 200
      };

15:Generic Type Alias
    type Nullable<T> = T | null;

    Usage:
      type User = { name: string };
      let user: Nullable<User>;

      This becomes:
        User | null

16: Difference between Type and Interface.
    Type aliases and interfaces are very similar, and in many cases you can choose between them freely. Almost all features of an interface are available in type, the key distinction is that a type cannot be re-opened to add new properties vs an interface which is always extendable

   🔸Extending an interface:
      interface Animal {
        name: string;
      }

      interface Bear extends Animal {
        honey: boolean;
      }

      const bear = getBear();
      bear.name;
      bear.honey;
              
   🔸Extending a type via intersections:
      type Animal = {
        name: string;
      }

      type Bear = Animal & { 
        honey: boolean;
      }

      const bear = getBear();
      bear.name;
      bear.honey;
              
   🔸Adding new fields to an existing interface:
      interface Window {
        title: string;
      }

      interface Window {
        ts: TypeScriptAPI;
      }

      const src = 'const a = "Hello World"';
      window.ts.transpileModule(src, {});
              
   🔸A type cannot be changed after being created:

        type Window = {
          title: string;
        }

        type Window = {
          ts: TypeScriptAPI;
        }

        // Error: Duplicate identifier 'Window'.

                

===========================================================
Topic Covered:

What is Type Script? 
why TypeScript is used? 
What is primitive types? - Number, String, Boolean
Array Types, Objects types. 
Type Inference, Contextual Typing, Optional parameter

let vs const Inference Difference in Type inference 
Type Aliases, 
Union Types, Literal Types,
Intersection Types, 
any type, 
unknown type


Interfaces
Generic Interfaces
Generic Type Alias
Difference between Type and Interface.



EOD Update - 25-Feb-2026
Task 1: Learning TypeScript
Status: In progress
TOPICS: Interfaces
        Generic Interfaces
        Generic Type Alias
        Difference between Type and Interface
        Strict Mode Understanding
Spend Time: 8H



Day Plan - 26-Feb-2026
Task 1: Learning TypeScript
Status: In progress
TOPICS: Interfaces
        Generic Interfaces
        Generic Type Alias
        Difference between Type and Interface.

