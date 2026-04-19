🔹1.Core React Fundamentals:

  Ques 1. What is React? Why is it used?
  Ques 2. What is JSX? How is it different from HTML?
  Ques 3. What is the Virtual DOM and how does React use it?
  Ques 4. Explain reconciliation in React.
  Ques 5. What are components? Functional vs Class components?
  Ques 6. What are props and state? Difference?
  Ques 7. What is one-way data binding?
  Ques 8. What are keys in React? Why are they important?
  Ques 9. What are fragments?
  Ques 10. Why should keys be stable and unique? What happens if you use index as key?

🔹2.Hooks (For 2-3 years experienced reactJs developer):
  Ques 1. What are React Hooks? Why were they introduced?
    Explain:
      useState
      useEffect
      useContext
      useRef
      useMemo
      useCallback

  Deep questions:
    Ques 2. Difference between useMemo and useCallback
    Ques 3. When does useEffect run?
    Ques 4. What is dependency array in useEffect?
    Ques 5. How to avoid infinite loops in useEffect?

  Scenario based questions:
  Ques 6. How do you fetch API data using hooks?
  Ques 7. How do you clean up side effects?
        
🔹3.Component Lifecycle (Even for Hooks)
  Ques 1. Lifecycle methods in class components
  Ques 2. Equivalent of lifecycle in hooks

  Example mapping:
    Ques 3. componentDidMount → useEffect(() => {}, [])
    Ques 4. componentWillUnmount → cleanup function

  Ques 5. What problems can happen if cleanup is not done?

🔹4.State Management
  Ques 1. How does React manage state internally?
  Ques 2. Lifting state up - what and why?
  Ques 3. Controlled vs uncontrolled components
  Ques 4. Prop drilling problem

  Advanced Questions:
    Ques 5. How does Context API solve prop drilling?
    Ques 6. When NOT to use Context?
        
🔹5.Performance Optimization
  Ques 1. What is memoization in React?
  Ques 2. What is React.memo?
  Ques 3. When to use useMemo vs useCallback?

  Real-world questions:
    Ques 4. Why is your component re-rendering unnecessarily?
    Ques 5. How to debug performance issues?
  
🔹6.Forms & Events
  Ques 1. Controlled components vs uncontrolled
  Ques 2. Handling form inputs
  Ques 3. Synthetic events in React
  Ques 4. Why do we use event.preventDefault()?
        
🔹7.Routing
  Ques 1. What is client-side routing?
  Ques 2. How does routing work in React apps?
  Ques 3. Difference between:
              BrowserRouter
              HashRouter

  Practical question:
    Ques 4. How to pass data between routes?

🔹8.API Handling
  Ques 1. How to call APIs in React?
  Ques 2. Where do you place API calls?
  Ques 3. How do you handle loading and error states?

  Advanced question:
    Ques 4. How to cancel API requests?
    Ques 5. What happens if component unmounts before API resolves?

🔹9.Architecture & Best Practices
  Ques 1. Folder structure of a React app
  Ques 2. Smart vs dumb components
  Ques 3. Reusable components design

  Real-world question:
    Ques 4. How do you structure a scalable React project?

🔹10.Advanced Concepts (Expected at 2-3 years experience in react):
  Ques 1. What is Higher Order Component (HOC)?
  Ques 2. What are render props?
  Ques 3. What is code splitting?
  Ques 4. What is lazy loading?

  Important question:
    Ques 5. React.lazy and Suspense

🔹11.Error Handling
  Ques 1. What are Error Boundaries?
  Ques 2. Can functional components act as error boundaries?

  Tricky question:
    Ques 3. Why error boundaries do not catch async errors?

🔹12.Testing (Basic)
  Ques 1. How do you test React components?
  Ques 2. What is unit testing in React?

🔹13.Real-World Scenario Questions (VERY IMPORTANT)
  Ques 1. How do you optimize a slow React app?
  Ques 2. How do you handle large lists?
  Ques 3. How do you manage global state?
  Ques 4. How do you avoid unnecessary re-renders?
  Ques 5. How do you design a reusable component?

🔹14.Rapid-Fire / Tricky Questions
  Ques 1. Why is setState asynchronous?
  Ques 2. Can we update state directly?
  Ques 3. What happens if you mutate state?
  Ques 4. Difference between == and === in React rendering?
  Ques 5. Why hooks cannot be used inside loops or conditions?

==========================================================================================================
                                1. 🔸 Core React Fundamentals
==========================================================================================================

Question 1: What is React? Why is it used?

Answer -> React is a declaritive, component based JavaScript UI library used for building user interfaces, especially for single-page applications.

The core idea behind React is that the UI should be a function of state. Instead of manually manipulating the DOM like we used to do with jQuery, in React we just describe what the UI should look like for a given state, and React handles the updates efficiently.

We use React mainly because:
  It makes UI predictable and easier to debug
  It improves performance using Virtual DOM
  It promotes reusable components

For example, if I have a dashboard with multiple widgets like charts, tables, and filters, I can build each as a separate component. If one component updates, React only re-renders that part instead of the whole page, which improves performance.

--------------------------------------------------------------------------------------------------------
Question 2: What is JSX? How is it different from HTML?

Answer -> JSX stands for JavaScript XML or Javascript syntax extension. It allows us to write HTML-like syntax inside JavaScript.

But it is not exactly HTML. Under the hood, JSX gets converted into React.createElement calls.

There are a few key differences:
  For example, in JSX we use className instead of class, and we use camelCase for attributes like onClick instead of onclick.

  Also, JSX allows us to embed JavaScript expressions directly inside curly braces. For example, I can write {user.name} inside JSX, which is not possible in plain HTML.

    const name = "Pankaj";
    return <h1 className = "userName"> Hello, {name}</h1>;

--------------------------------------------------------------------------------------------------------
Question 3: What is the Virtual DOM and how does React use it?

Answer -> The Virtual DOM is a lightweight JavaScript representation of the real DOM.

Whenever the state or props change, React creates a new Virtual DOM tree and compares it with the previous one. This process is called diffing.

Instead of updating the entire real DOM, React calculates the minimal set of changes and updates only those node parts. This process is called reconciliation.

For example, if I update a single item in a list, React will only update that specific DOM node instead of re-rendering the whole list.

--------------------------------------------------------------------------------------------------------
Question 4: Explain reconciliation in React

Answer -> Reconciliation is the process React uses to update the DOM efficiently.

When state or props change, React compares the previous Virtual DOM with the new one. It uses a diffing algorithm to identify what has changed.

When state changes:
  React creates a new Virtual DOM tree
  It compares it with the previous one
  It calculates the minimum number of changes needed
  Then updates only those parts in the real DOM
This process is also called "diffing".

Based on that, React updates only the necessary parts in the real DOM.
React uses some heuristics(अनुमानी):
  If element type changes → destroy and recreate
  If same type → update attributes
  For lists → uses keys to track changes

For example, if I conditionally render a component and toggle it, React will compare both versions and only mount or unmount that specific component instead of touching the entire UI

--------------------------------------------------------------------------------------------------------
Question 5: What are components? Functional vs Class components?

Answer -> Components are the building blocks of a React application. Each component represents a part of the UI.

There are two types: functional and class components.

Functional components are just JavaScript functions that return JSX. They are simpler and now more commonly used because of hooks like useState and useEffect.

Class components are ES6 classes that extend React.Component. They use lifecycle methods like componentDidMount.

In modern React, we mostly prefer functional components because they are easier to read, test, and manage.

--------------------------------------------------------------------------------------------------------
Question 6: What are props and state? Difference?

Answer -> Props and state are both used to manage data in React, but they serve different purposes.

Props are read-only and are passed from parent to child components. A child component cannot modify props. It is used for communication.

State, on the other hand, is managed within the component and can be updated using functions like setState or useState. It is used for dynamic data.

For example, if I pass a title from a parent to a child, that is a prop. But if I have a counter inside a component that changes on button click, that is state.

Here 'title' is a prop:
  function Child({ title }) {
    return <h1>{title}</h1>;
  }

Here 'count' is state:
  const [count, setCount] = useState(0);

--------------------------------------------------------------------------------------------------------
Question 7: What is one-way data binding?

Answer -> React follows one-way data binding, meaning data flows in a single direction — from parent to child.

The parent controls the data and passes it via props. The child cannot directly modify it.

This makes the application more predictable and easier to debug.

For example, if I pass a value as a prop to a child component, the child cannot directly modify it. If it needs to update something, it has to call a function passed from the parent.

--------------------------------------------------------------------------------------------------------
Question 8: What are keys in React? Why are they important?

Answer -> In React, Keys are special attributes used when rendering lists of elements. 

Keys are used to uniquely identify elements in a list during reconciliation. When the state changes, React compares the previous and next virtual DOM. Keys help React determine which elements are added, removed, or updated, allowing efficient DOM updates. 

Without proper keys, React may re-render incorrectly or reuse DOM elements improperly, leading to performance issues and UI bugs.

--------------------------------------------------------------------------------------------------------
Question 9: What are fragments?

Answer -> Fragments are used to group multiple elements without adding extra nodes to the DOM.

Instead of wrapping everything in a <div>, we can use <></>.
This helps keep the DOM clean and avoids unnecessary nesting.

For example, if a component needs to return multiple <td> elements inside a table row, fragments are very useful.

--------------------------------------------------------------------------------------------------------
Question 10: Why should keys be stable and unique? What happens if you use index as key?

Answer -> Keys should be stable and unique because React relies on them during reconciliation to track elements.
React use keys to uniquely identify the list items.

If keys change between renders, React may unnecessarily re-render components or even cause bugs.

Using index as a key can lead to problems, especially when the list is dynamic.

For example, if I have a list of items and I insert a new item at the top, all indexes shift. React will think all items have changed and re-render everything, which can lead to performance issues and even incorrect UI behavior like losing input focus.

So it is always better to use a unique identifier like an ID from the database.

==========================================================================================================
                                2. 🔸 Core React Hooks
==========================================================================================================

Question 11: What are React Hooks? Why were they introduced?

Answer -> React Hooks are functions that allow us to use state and lifecycle features inside functional components.

Before hooks, we had to use class components for things like state and lifecycle methods. Hooks were introduced to simplify code, improve reusability, and avoid complex class logic.

For example, instead of using componentDidMount, componentDidUpdate, and componentWillUnmount, we can handle everything using useEffect.

--------------------------------------------------------------------------------------------------------
Question 12: Explain useState.

Answer -> useState is used to manage local component state in a functional component. It returns a state variable and a setter function. When we update the state using the setter, React schedules a re-render.

One important thing is that state updates are asynchronous and batched, so we should not rely on immediate updated values after calling the setter.

Example:  
  const [count, setCount] = useState(0);
  const increment = () => {
    setCount(prev => prev + 1); // safe update
  };

Key points:
  Triggers re-render
  Async updates
  Functional update avoids stale state

--------------------------------------------------------------------------------------------------------
Question 13: Explain useEffect.

Answer -> useEffect is used to handle side effects in functional components, like API calls, subscriptions, DOM updates, etc.

It runs after render, and we can control when it should runs using the dependency array.
Example:
  useEffect(() => {
    fetchData();
  }, []); // runs only once (on mount)

Variation of useEffect:
  [] → run once (componentDidMount)
  [dep] → run when dependency changes
  No dependencies, not even empty array → run on every render
  cleanup → for unsubscribing, prevents memory leaks

NOTE: API calls are not always inside useEffect. 
For API call, useEffect is used when the API call depends on component lifecycle, like fetching data on mount. 
But for user-triggered actions like delete or submit, the API call should be inside event handlers.

  Example:
      import Button from "./components/Button";
      const Login = () => {
        const handleLogin = async () => {
          console.log("Login clicked");
          //call backend api here
        };

        return (
          <Button onClick={handleLogin} variant="primary">
            Login
          </Button>
        );
      };

NOTE:
  Anything that belongs to outside the Reacts world, should go inside useEffect.
  Anything that is Tied to rendering / state change, should go inside useEffect - because rending phase must be pure.
--------------------------------------------------------------------------------------------------------
Question 14: Explain useContext.

Answer -> useContext is used to consume values from a React Context, mainly to avoid prop drilling. 
But internally, it is not just a global store — it is tightly coupled with Reacts render cycle.

Whenever the context value changes, all components using that context re-render, even if they only use a small part of the value. React does a reference comparison on the value passed to the provider.

Example:  
  const AuthContext = createContext();

  function App() {
    const [user, setUser] = useState(null);

    return (
      <AuthContext.Provider value={{ user }}>
        <Dashboard />
      </AuthContext.Provider>
    );
  }

  function Dashboard() {
    const { user } = useContext(AuthContext);
    return <div>{user?.name}</div>;
  }

  The Re-render problem:
    <AuthContext.Provider value={{ user }}>
  This creates a new object on every render, so all consumers re-render unnecessarily.

  Fixing Re-render problem:
    const value = useMemo(() => ({ user }), [user]);
    <AuthContext.Provider value={value}>

  useContext is good for low-frequency global state like auth or theme, but not for high-frequency updates because it can cause unnecessary re-renders

--------------------------------------------------------------------------------------------------------
Question 15: Explain useRef.

Answer -> useRef gives a mutable container that persists across renders without triggering re-renders.
Internally, React keeps the same ref object between renders, so updating .current does not cause re-dender.

So, it is used to persist a mutable value across renders without causing re-renders.
useRef is useful when I need persistence without re-render, like DOM access or storing mutable values across renders

It is commonly used for:
  Accessing DOM elements
  Storing previous values 

Example of accessing DOM:

  const inputRef = useRef();

  const focusInput = () => {
    inputRef.current.focus();
  };

Example of storing value:

  const renderCount = useRef(0);

  useEffect(() => {
    renderCount.current += 1;
  });

  NOTE: Stale Closure Fix - Used inside async callbacks to avoid stale state.
      Example: 
        const latestValue = useRef(value);
        useEffect(() => {
          latestValue.current = value;
        }, [value]);


  When not to use useRef:
    Do not replace state with ref just to avoid re-render
    Avoid storing UI state in ref

  -------------------------
  Q. What is stale Closure?
  Answer: In React, functions capture variables from the render phase in which they were created.
  So inside async callbacks (like setTimeout, API calls i.e useEffect, event listeners), you might get an old value of state.

  Example(Bug):
    const [count, setCount] = useState(0);

    const handleClick = () => {
      setTimeout(() => {
        console.log(count); // might print OLD value
      }, 2000);
    };

    If count changes before 2 seconds, this still logs the old count.

    This happens because of closures:
      The setTimeout callback "remembers" the count value from when handleClick ran
      It does NOT automatically get the latest state.

  Solution: useRef to always hold latest value

    const [count, setCount] = useState(0);
    const countRef = useRef(count);

    // keep ref updated
    useEffect(() => {
      countRef.current = count;
    }, [count]);

    const handleClick = () => {
      setTimeout(() => {
        console.log(countRef.current); // always latest value
      }, 2000);
    };

    What is happening internally here:
      useRef gives a stable object → { current: ... }
      That object does not change across renders
      We manually keep updating .current
      Async callback always reads latest .current


    So, In async callbacks, React state can become stale due to closures. I use useRef to keep a mutable reference of the latest value, so the callback always reads the current state instead of the captured one.

  -------------------------------------------------------------------------------------------------------------
  Q. In the above example , why we have updated the "coutRef.current = count" inside the useEffect hook and not direclty?

    useEffect(() => {
      countRef.current = count;
    }, [count]);

  Answer: We use useEffect to keep the ref in sync with the latest state after every render. Since refs do not automatically update when state changes, we manually assign the latest value inside an effect.

  You might think that we can get latest value without useEffect, so why we can not just do this without useEffect, like below:
    countRef.current = count; 

  This actually runs during render, which is not ideal.
  As per react, React rendering should be pure - no side effects, no mutation.

  If you do:
    const countRef = useRef(count);
    countRef.current = count; // this is side effect inside render as it is a mutation.

  Issues:
    Breaks Reacts mental model
    Can cause bugs in concurrent rendering (React 18+)
    Not predictable

  So, we used useEffect:
    useEffect(() => {
      countRef.current = count;
    }, [count]);

    As we know, useEffect runs after render is committed, i.e in commit phase after DOM updation.
    So flow becomes:
      Render happens with count
      DOM updates
      useEffect runs → updates ref.current

  We use useEffect not just to get the latest value, but to update the ref after render, because React render phase should remain pure. Updating ref inside render would be a side effect, so we sync it in useEffect which runs after the DOM update.

  We use useEffect to update the ref after render because updating it during render would introduce side effects and can break Reacts rendering behavior, especially in concurrent mode.

--------------------------------------------------------------------------------------------------------
Question 16: Explain useMemo.

Answer -> useMemo is used to memoize the result of a computation so that it does not run on every render. It only recomputes when dependencies change.

But it is not just about performance — it is also about referential stability, especially when passing objects/arrays to child components.

useMemo is used to memoize expensive computations so they are only recalculated when dependencies change. It helps in performance optimization by avoiding unnecessary recalculations.

Example:
  const sortedList = useMemo(() => {
    return items.sort((a, b) => a.price - b.price);
  }, [items]);

NOTE: useMemo is a performance hint, not a guarantee.
      React may discard memoized value in some cases.

  Referential Equality Problem:
    const obj = { a: 1 }; // new object every render. This breaks React.memo used inside child components.

  Fix for Referential Equality Problem:
    const obj = useMemo(() => ({ a: 1 }), []);

  When NOT to use useMemo:
    Simple calculations
    Premature optimization
    When dependencies change frequently anyway

  Interview question: 
    Parent re-render causing child re-render:
      <Child data={{ value: count }} />
    Child re-renders every time. How do you fix that?

    I will use referential equality and use useMemo to fix unnecessary rendering of child: 
      const data = useMemo(() => ({ value: count }), [count]);
      <Child data={data} />

  Tricky: useMemo vs useRef
      +--------------------------------------------+
      | Hook    |         Purpose                  |
      |---------|----------------------------------|
      | useMemo | Recompute value when deps change |
      | useRef  | Store value without re-render    |
      +--------------------------------------------+

--------------------------------------------------------------------------------------------------------
Question 17: Explain useCallback.

Answer -> useCallback is used to memoize function references so that they are not recreated on every render. This is especially useful when passing functions to memoized child components. Memoized component child means - a child component which is using React.memo.

useCallback returns memoized function.

Example:
  Memoized child component.
    const Child = React.memo(({ onClick }) => {
      console.log("Child re-rendered");
      return <button onClick={onClick}>Click</button>;
    });
  
  Parent component:
    function Parent() {
      const [count, setCount] = useState(0);

      // Using useCallback to created memoized i.e stable function.
      const handleClick = useCallback(() => {
        console.log("clicked");
      }, []);

      return (
        <div>
          <button onClick={() => setCount(count + 1)}>Increment</button>
          <Child onClick={handleClick} />
        </div>
      );
    }

  Without useCallback, a new function is created every render, which can cause unnecessary child re-renders.

--------------------------------------------------------------------------------------------------------
Question 18: Difference between useMemo and useCallback?

Answer -> Both are used for performance optimization, but they serve slightly different purposes.
useMemo memoizes the result of a function, while useCallback memoizes the function itself.

For example, if I have a heavy calculation, I use useMemo to cache the result.
But if I am passing a function to a child component and want to prevent re-render, I use useCallback.

In short:
  useMemo → value optimization
  useCallback → function optimization

--------------------------------------------------------------------------------------------------------
Question 19: When does useEffect run?

Answer -> useEffect runs after the component renders.
By default, it runs AFTER every render. But we can control it using the dependency array.

There are three cases:
  If no dependency array → runs after every render
  If empty array → runs only once (on mount)
  If dependencies are provided → runs when those values change

--------------------------------------------------------------------------------------------------------
Question 20: What is dependency array in useEffect?

Answer -> The dependency array tells React when to re-run the effect.
It contains variables that the effect depends on.

For example:
  useEffect(() => {
    fetchData(userId);
  }, [userId]);

Here, the effect will only run when userId changes.
If we do not include dependencies properly, it can lead to bugs like stale data or unnecessary re-renders.

--------------------------------------------------------------------------------------------------------
Question 21: How to avoid infinite loops in useEffect?

Answer -> Infinite loops usually happen when:
            We update state inside useEffect.
            And that state is also in dependency array.

For example:
  useEffect(() => {
    setCount(count + 1);
  }, [count]);

This will keep running forever.

To avoid this:
  Make sure dependencies are correct
  Avoid updating state unnecessarily inside effect
  Use conditions if needed
  Sometimes use functional updates:
  setCount(prev => prev + 1);

Also, avoid passing non-memoized functions or objects in dependency array because they change on every render.

--------------------------------------------------------------------------------------------------------
Question 22: How do you fetch API data using hooks?

Answer -> Typically, we use useEffect for API calls.
For example:
  const [data, setData] = useState([]);

  useEffect(() => {
    const fetchData = async () => {
      const res = await fetch("/api/users");
      const result = await res.json();
      setData(result);
    };

    fetchData();
  }, []);

The empty array dependency ensures the API is called only once when the component mounts.
In real projects, I also handle loading and error states, and sometimes use custom hooks to reuse logic.

--------------------------------------------------------------------------------------------------------
Question 23: How do you clean up side effects?

Answer -> Cleanup is done by returning a function from useEffect.
This is useful for things like:
  Removing event listeners
  Clearing timers
  Cancelling API subscriptions

For example:
  useEffect(() => {
    const interval = setInterval(() => {
      console.log("running");
    }, 1000);

    return () => {
      clearInterval(interval);
    };
  }, []);

This prevents memory leaks and ensures proper resource management.

==========================================================================================================
                                3. 🔸 Component Lifecycle
==========================================================================================================

Question 24: What is lifecycle methods in class components?

Answer -> In class components, React provides lifecycle methods that let us hook into different phases of a components life — like mounting, updating, and unmounting.

During mounting, we have methods like constructor, componentDidMount.
For example, componentDidMount is typically used for API calls or setting up subscriptions.

During updating, we have componentDidUpdate, which runs when props or state change.

During unmounting, we have componentWillUnmount, which is used for cleanup like removing event listeners or clearing timers.

So overall, lifecycle methods help us control what happens at each stage of a components existence.

--------------------------------------------------------------------------------------------------------
Question 25: Equivalent of lifecycle in hooks i.e in functional components?

Answer -> In functional components, we do not have separate lifecycle methods. Instead, we use useEffect to handle all lifecycle-related logic.

So instead of splitting logic across multiple lifecycle methods, we write side effects inside useEffect and control when it runs using the dependency array.

This actually makes the code more readable because related logic stays together instead of being split across different methods.

--------------------------------------------------------------------------------------------------------
Question 26: What is the equivalent of componentDidMount in functional component?

Answer -> The equivalent of componentDidMount in functional component is:

  useEffect(() => {
    // code runs once after initial render
  }, []);

The empty dependency array ensures that the effect runs only once when the component mounts.
For example, fetching initial data from an API or initializing a library.

--------------------------------------------------------------------------------------------------------
Question 27: What is the equivalent of componentWillUnmount in functional component?

Answer -> In functional component we use cleanup function as componentWillUnmount. Cleanup is handled by returning a function from useEffect.

Example:
  useEffect(() => {
    const subscription = someService.subscribe();

    return () => {
      subscription.unsubscribe();
    };
  }, []);

  This cleanup function runs when the component unmounts.

NOTE: Cleanup function is also triggered before the effect re-runs if dependencies change, which is an important detail.

--------------------------------------------------------------------------------------------------------
Question 28: What problems can happen if cleanup is not done?

Answer -> If cleanup is not handled properly, it can lead to multiple issues.

The most common one is memory leaks. For example, if a component sets an interval or event listener and does not remove it, it will keep running even after the component is unmounted.

Another issue is unexpected behavior or duplicate executions. For example, if an event listener is added multiple times without cleanup, it can trigger multiple times for a single event.

Also, in API calls, if the component unmounts before the response comes back and we try to update state, it can lead to warnings like “state update on unmounted component”.

In real-world applications, especially with subscriptions, sockets, or timers, missing cleanup can cause serious performance issues over time.

NOTE: One important thing is that cleanup does not just run on unmount — it also runs before the next effect execution if dependencies change. So it is important to design effects carefully to avoid unintended side effects.

==========================================================================================================
                                4. 🔸 State Management
==========================================================================================================

Question 29: How does React manage state internally?

Answer -> Internally, React manages state using a concept called a fiber tree, where each component instance stores its own state.

When we call something like setState or a state updater from useState, React does not update the state immediately. It schedules an update.

React then batches multiple updates together and performs a re-render. During this process, it creates a new Virtual DOM, compares it with the previous one, and updates only the changed parts in the real DOM.

Also, state is logically immutable in nature (should only be updated using setSate or useState), meaning we should not modify it directly. Instead, we always create a new value, which helps React detect changes efficiently.

Example: state.count = state.count + 1  => This is mutating the state directly which is wrong.

         setCount(count + 1)  => Here, We are not modifying existing state, We are creating a new state value.
                                 So internally:
                                    old state → replaced with new state.

Updating an object directly, will not trigger proper re-rendering, but creating a new object will.

--------------------------------------------------------------------------------------------------------
Question 30: Lifting state up — what and why?

Answer -> Lifting state up means moving state from a child component to a common parent so that multiple components can share it.

We do this when two or more components need to stay in sync.

For example, if I have two sibling components — one for input and one for displaying filtered results — instead of managing state separately, I lift the state to the parent and pass it down via props.

This ensures a single source of truth, which makes the data flow predictable and easier to debug.

--------------------------------------------------------------------------------------------------------
Question 31: Controlled vs uncontrolled components?

Answer -> In controlled components, form data is managed by React state. The input value is controlled using state and updated via onChange. This gives full control over the form but can cause performance overhead in large forms.
Controlled components gives better control, validation, and predictability.

Example: 
  const [name, setName] = useState("");
  <input value={name} onChange={(e) => setName(e.target.value)} />

Edge case:
  Large forms → performance issue
  On every input change → render

In uncontrolled components, form data is handled by the DOM itself. We use refs to access the value when needed. This approach avoids frequent re-renders but gives less control compared to controlled components.

Example:
  const inputRef = useRef();
  let value = inputRef.current // accessing.
  <input ref={inputRef} />

--------------------------------------------------------------------------------------------------------
Question 32: What is prop drilling problem?

Answer -> Prop drilling happens when we pass data from a parent to deeply nested child components through multiple intermediate components.

Even if intermediate components do not need the data, they still have to pass it down.
This makes the code harder to maintain and tightly coupled.

For example, passing user data from a top-level component to a deeply nested component through 4-5 layers is a classic prop drilling issue.

--------------------------------------------------------------------------------------------------------
Question 33: How does Context API solve prop drilling?

Answer -> Context API allows us to share data globally without passing props manually at every level.
We create a context, wrap the component tree with a provider, and then access the data anywhere using useContext.

For example, things like authentication data, theme, or language settings are good use cases.
This removes the need to pass props through multiple layers.

However, one important detail is that when context value changes, all consuming components re-render, so we need to use it carefully. In such case we use use memoization technique like useMemo.

--------------------------------------------------------------------------------------------------------
Question 34: When NOT to use Context?

Answer -> Context is not ideal for frequently changing data or large-scale state management.
Because whenever the context value updates, all components consuming that context will re-render, which can impact performance.

For example, if I store something like frequently updating form input or real-time data in context, it can cause unnecessary re-renders across the app.

In such cases, it is better to use state management libraries like Redux or Zustand, or even local component state if the scope is small.

Also, for simple parent-child communication, using props is actually cleaner and more explicit than introducing context.

==========================================================================================================
                                5. 🔸 Performance Optimization
==========================================================================================================

Question 35: What is memoization in React?

Answer -> Memoization is an optimization technique where we cache the result of a computation and reuse it instead of recalculating it on every render.

In React, this is important because functional components re-run on every render. So if we have expensive calculations or derived data, we can avoid recomputing them unnecessarily.

For example, if I am filtering or sorting a large list based on some input, instead of recalculating it every time, I can memoize the result using useMemo.

So overall, memoization helps reduce unnecessary computations and improves performance.

--------------------------------------------------------------------------------------------------------
Question 36: What is React.memo?

Answer -> React.memo is a higher-order component that prevents unnecessary re-renders of a component.

It does a shallow comparison of props. If props have not changed, React skips rendering that component.

For example, if I have a child component that receives props but those props are not changing, wrapping it with React.memo ensures it does not re-render when the parent re-renders.

But one important thing is — it only works properly if props are stable. If we pass new object or function references every time, React.memo will not be effective.

--------------------------------------------------------------------------------------------------------
Question 37: When to use useMemo vs useCallback?

Answer -> Both are used for memoization, but they solve different problems.

I use useMemo when I want to memoize a computed value, especially if it is expensive.

I use useCallback when I want to memoize a function, usually when passing it to a child component to prevent unnecessary re-renders.

For example, if I pass a function as a prop to a memoized child component, without useCallback, that function gets recreated on every render and breaks memoization.

So:
  useMemo → optimize values
  useCallback → optimize function references

--------------------------------------------------------------------------------------------------------
Question 38: Why is your component re-rendering unnecessarily?

Answer -> There can be multiple reasons for unnecessary re-renders.
The most common one is parent re-rendering, because when a parent renders, all children render by default.

Another big reason is unstable references — like creating new objects, arrays, or functions inside render. Even if the data is same, the reference changes, so React treats it as new.

For example:
  <Child data={{ name: "Pankaj" }} />

  This creates a new object on every render, so the child re-renders whenever parent gets rendered.

Also, state updates — even if the value is the same — can trigger re-renders depending on how they are handled.

Another reason is improper usage of context, where context updates cause all consumers to re-render.

--------------------------------------------------------------------------------------------------------
Question 39: How to debug performance issues?

Answer -> First thing I use is React DevTools Profiler.
It shows which components are re-rendering, how often, and how much time they take.

Then I check:
  Are props changing unnecessarily?
  Are functions or objects being recreated?
  Is state placed at the right level?

Sometimes I also use console.log or custom hooks to track renders.

If needed, I apply optimizations like:
  React.memo for components
  useMemo for heavy computations
  useCallback for stable function references

But one important thing is — I do not optimize prematurely. I first identify the bottleneck, then optimize only where needed.

==========================================================================================================
                                6. 🔸 Core React Fundamentals
==========================================================================================================

Question 40: How do you handle form inputs?

Answer -> In React, form inputs are typically handled using controlled components.

We use onChange to update state whenever the user types. For multiple fields, a common pattern is to use a single state object and update fields dynamically.

Example:
  const [form, setForm] = useState({ email: "", password: "" });

  const handleChange = (e) => {
    setForm({
      ...form,
      [e.target.name]: e.target.value
    });
  };


  <input name="email" value={form.email} onChange={handleChange} />
  <input name="password" value={form.password} onChange={handleChange} />

--------------------------------------------------------------------------------------------------------
Question 41: What is Synthetic events in React?

Answer -> React uses something called Synthetic Events, which is basically a wrapper around the browsers native events.

It provides a consistent API across different browsers, so we do not have to worry about cross-browser compatibility.

For example, whether it is Chrome or Firefox, onClick or onChange behaves consistently in React.

Also, earlier React versions used event pooling for performance, but in modern React, that is no longer an issue.

So overall, synthetic events simplify event handling and make behavior predictable.

--------------------------------------------------------------------------------------------------------
Question 42: Why do we use event.preventDefault()?

Answer -> We use event.preventDefault() to stop the default behavior of an event.
The most common example is form submission.

By default, when a form is submitted, the page reloads. In React, we usually want to handle submission using JavaScript without refreshing the page.

So we call:
  const handleSubmit = (e) => {
    e.preventDefault();
    // custom logic
  };

This allows us to control what happens on submit, like calling an API or validating data.

In larger applications, I usually combine controlled components with validation libraries like React Hook Form or Formik to optimize performance and reduce boilerplate.

==========================================================================================================
                                7. 🔸 Routing
==========================================================================================================
Question 43: What is client-side routing?

Answer -> Client-side routing means handling navigation inside the browser without making a full page reload.
In traditional applications, when we click a link, the browser sends a request to the server and loads a new HTML page.

But in React, we load a single HTML file once, and then JavaScript takes over. When the route changes, React dynamically updates the UI instead of reloading the page.

This makes the application faster and gives a smoother user experience, similar to native apps.

--------------------------------------------------------------------------------------------------------
Question 44: How does routing work in React apps?

Answer -> In React, routing is usually handled using libraries like react-router-dom.
It works by listening to changes in the URL and rendering different components based on the path.

For example, we define routes like:
  <Route path="/home" element={<Home />} />
  <Route path="/about" element={<About />} />

When the URL changes to /about, React renders the About component without refreshing the page.
Internally, it uses the browsers History API to manage navigation.

--------------------------------------------------------------------------------------------------------
Question 45: Difference between BrowserRouter and HashRouter

Answer -> BrowserRouter uses the HTML5 History API to keep the UI in sync with the URL. 
It gives clean URLs like:
  /home
  /about

But it requires proper server configuration. If the user refreshes the page, the server must know how to handle that route.

HashRouter, on the other hand, uses the URL hash portion:
/#/home

The part after # is not sent to the server, so it works without any backend configuration.

In real-world applications, we usually prefer BrowserRouter. HashRouter is mainly used in static environments where we can not control the server.

--------------------------------------------------------------------------------------------------------
Question 46: How to pass data between routes?

Answer -> There are multiple ways to pass data between routes.

  1.One common way is using state in navigation:
      navigate("/profile", { state: { userId: 1 } });
    
    Then in the target component:
      const location = useLocation();
      const userId = location.state?.userId;

  2.Another way is using URL params:
      <Route path="/user/:id" element={<User />} />

    Then access it using:
      const { id } = useParams();
    
      We can also use query params, global state (like Context or Redux), depending on the use case.

  In real projects:
    For identifiers → I prefer URL params
    For temporary data → navigation state
    For shared/global data → Context or store

  I usually choose the data-passing method based on whether the data should persist in the URL or not. If it needs to be shareable or bookmarkable, I prefer URL params.

--------------------------------------------------------------------------------------------------------
Question 47: What are protected routes? How do you implement them?

Answer -> Protected routes are routes that should only be accessible to authenticated users.
For example, pages like dashboard, profile, or admin panel should not be accessible if the user is not logged in.

In React, we usually implement this by creating a wrapper component that checks authentication before rendering the route.

For example:
  const ProtectedRoute = ({ children }) => {
    const isAuthenticated = !!localStorage.getItem("token");

    return isAuthenticated ? children : <Navigate to="/login" />;
  };

  OR, we can have like:
    const ProtectedRoute = ({ children }) => {
      const { user, loading } = useAuth();

      if (loading) return <div>Checking auth...</div>;
      return user ? children : <Navigate to="/login" />;
    };

    Here, we should validate token with backend:
      useEffect(() => {
        const checkAuth = async () => {
          try {
            const res = await fetch("/api/me", {
              headers: {
                Authorization: `Bearer ${localStorage.getItem("token")}`
              }
            });

            if (!res.ok) throw new Error();

            const userData = await res.json();
            setUser(userData);
          } catch {
            setUser(null);
          } finally {
            setLoading(false);
          }
        };

        checkAuth();
      }, []);

  Then we use it like:
    <Route path="/dashboard" element={
      <ProtectedRoute>
        <Dashboard />
      </ProtectedRoute>
    } />

--------------------------------------------------------------------------------------------------------
Question 48: What is lazy loading in React routing? Why use it?

Answer -> Lazy loading means loading components only when they are needed, instead of loading everything upfront.
This improves initial load time and performance.

In React, we use React.lazy and Suspense for this.

For example:
  const Dashboard = React.lazy(() => import("./Dashboard"));

  <Suspense fallback={<div>Loading...</div>}>
    <Route path="/dashboard" element={<Dashboard />} />
  </Suspense>

  So the Dashboard component will only be loaded when the user navigates to that route.

In large applications, this significantly reduces bundle size and improves performance.

--------------------------------------------------------------------------------------------------------
Question 49: How do you handle 404 (Not Found) routes?

Answer -> In React Router, we handle 404 using a wildcard route.

For example:
  <Route path="*" element={<NotFound />} />
  
  This route matches any path that is not defined earlier.

So if a user enters an invalid URL, the NotFound component is rendered.
In real-world applications, I usually place this route at the end of all routes.

For better user experience, I usually combine lazy loading with route-based code splitting and also handle loading states properly using Suspense.

MORE CONCEPTS: Lazy loading + Suspense (Better UX for routing)
--------------
  Use route-level lazy loading to reduce initial bundle size, and Suspense to show a fallback UI while the component is loading, so users do not experience blank screens.

 🔸Problem - without lazy loading:
    If you import all pages normally:
      import Home from "./Home";
      import Dashboard from "./Dashboard";
      import Settings from "./Settings";
    
    Then:
      All pages get bundled together
      Even if user only visits /home, dashboard code is still downloaded
      Slower initial load → bad UX

    Solution: Route-based lazy loading

      import React, { Suspense } from "react";
      import { Routes, Route } from "react-router-dom";

      const Home = React.lazy(() => import("./Home"));  // this is oute-based code splitting
      const Dashboard = React.lazy(() => import("./Dashboard")); // this is oute-based code splitting
      const NotFound = React.lazy(() => import("./NotFound"));  // this is oute-based code splitting

      function App() {
        return (
          <Suspense fallback={<div>Loading page...</div>}>
            <Routes>
              <Route path="/" element={<Home />} />
              <Route path="/dashboard" element={<Dashboard />} />
              <Route path="*" element={<NotFound />} />
            </Routes>
          </Suspense>
        );
      }

    What is happening here?
      When user visits /
        Only Home component is loaded
      
      When user visits /dashboard
        React dynamically loads Dashboard bundle
      
      While loading:
        <Suspense fallback="Loading page..." /> is shown

    Here, Without Suspense - User may see blank screen. With Suspense - User sees loading UI immediately.

--------------------------------------------------------------------------------------------------------
Question 50: How do you persist auth after refresh?

Answer -> After a page refresh, React state resets, so we need a way to persist authentication.
The common approach is to store the token in something like localStorage, sessionStorage, or cookies.

When the app loads, we read that token and restore the auth state.

For example, in a top-level component or auth context:

  const token = localStorage.getItem("token");
  if (token) {
    setUser({ isAuthenticated: true });
  }

In more robust applications, we also call a “get current user” API using that token to validate it and fetch user details.

Personally, I prefer combining localStorage with a backend validation call, because just having a token in storage does not guarantee it is valid.

--------------------------------------------------------------------------------------------------------
Question 51: How do you handle token expiry?

Answer -> Token expiry is usually handled in two ways: proactively and reactively.

Reactively, we handle it when an API call fails with something like a 401 Unauthorized response. At that point, we clear auth state and redirect the user to login.

Proactively, if we are using JWT, we can decode the token and check its expiry time before making requests.

In more advanced setups, we use refresh tokens:
  Access token is short-lived
  Refresh token is used to get a new access token

So if the access token expires, we silently refresh it without logging the user out.
In real projects, I usually implement this using an Axios interceptor to handle 401 errors globally.

--------------------------------------------------------------------------------------------------------
Question 52: How do you prevent flicker in protected routes?

Answer -> Flicker happens when the app briefly renders a protected page before redirecting, especially during initial load.

This usually happens because authentication state is not initialized yet.
To prevent this, we introduce a loading or “auth-check” state.

For example:
  if (isLoading) return <Loader />;

We only render routes after we confirm whether the user is authenticated or not.
So instead of immediately rendering or redirecting, we wait until auth state is resolved.
In larger apps, this logic is usually handled in an AuthProvider or at the routing level.

--------------------------------------------------------------------------------------------------------
Question 53: Difference between route-level vs component-level lazy loading

Answer -> Route-level lazy loading means we load entire pages or route components only when the user navigates to that route.

For example, loading the Dashboard only when /dashboard is accessed.
This is the most common and impactful optimization because it reduces initial bundle size.

Component-level lazy loading means we lazy load smaller parts inside a page.
For example, loading a heavy chart or modal only when it is needed.

So the difference is mainly in granularity:
  Route-level → page-based splitting
  Component-level → feature-based splitting

In real-world applications, I usually start with route-level lazy loading and then optimize further with component-level lazy loading if needed.

==========================================================================================================
                                8. 🔸 Routing and API calls
==========================================================================================================
Question 54: How to call APIs in React?

Answer -> In React, we usually call APIs inside useEffect, especially for data fetching when a component mounts.
Example:
  const [data, setData] = useState([]);

  useEffect(() => {
    const fetchData = async () => {
      const res = await fetch("/api/users");
      const result = await res.json();
      setData(result);
    };

    fetchData();
  }, []);

This ensures the API is called once after the component renders.
In real-world applications, I often use libraries like Axios for better control, and sometimes React Query or SWR for caching and synchronization.

--------------------------------------------------------------------------------------------------------
Question 55: Where do you place API calls?

Answer -> It depends on the application structure, but generally:
For small components, API calls can be placed directly inside useEffect.
But in scalable applications, I prefer separating API logic into service files or custom hooks.
Example:
  api/userService.js → contains API functions
  useUsers.js → custom hook for fetching and managing users

This improves reusability, testability, and keeps components clean.

--------------------------------------------------------------------------------------------------------
Question 56: How do you handle loading and error states?

Answer -> I usually maintain separate state variables for loading and error.
Example:
  const [data, setData] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);

  useEffect(() => {
    const fetchData = async () => {
      try {
        const res = await fetch("/api/users");
        const result = await res.json();
        setData(result);
      } catch (err) {
        setError(err.message);
      } finally {
        setLoading(false);
      }
    };

    fetchData();
  }, []);

Then in UI:
  Show loader when loading is true
  Show error message if error exists
  Otherwise show data

--------------------------------------------------------------------------------------------------------
Question 57: How to cancel API requests?

Answer -> We can cancel API requests using AbortController.
This is useful when a component unmounts or when a new request replaces the previous one.
Example:
  useEffect(() => {
    const controller = new AbortController();

    const fetchData = async () => {
      try {
        const res = await fetch("/api/users", {
          signal: controller.signal
        });
        const data = await res.json();
        setData(data);
      } catch (err) {
        if (err.name !== "AbortError") {
          console.error(err);
        }
      }
    };

    fetchData();

    return () => {
      controller.abort();
    };
  }, []);

This prevents unnecessary work and avoids errors.

--------------------------------------------------------------------------------------------------------
Question 58: What happens if component unmounts before API resolves?

Answer -> If the component unmounts before the API response comes back and we try to update state, React will show a warning like: “Can not perform a React state update on an unmounted component.”
This can lead to memory leaks or unexpected behavior.

To avoid this:
  We cancel the request using AbortController
  Or track a flag like isMounted (though AbortController is preferred)
In real-world apps, especially with multiple API calls or fast navigation, this scenario happens often, so proper cleanup is important.
In production, I usually prefer React Query or similar libraries because they handle caching, background updates, request deduplication, and cancellation automatically, which reduces a lot of manual boilerplate.

--------------------------------------------------------------------------------------------------------
Question 59: How do you handle race conditions in API calls?

Answer -> Race conditions happen when multiple API requests are fired, and responses come back in a different order than expected.
For example, in a search input:
  User types “a” → API call 1
  Then types “ab” → API call 2

If API 1 responds after API 2, it can overwrite the latest data with stale results.

To handle this, I usually use one of these approaches:
  First, AbortController — cancel previous requests when a new one is triggered. This ensures only the latest request is active.

  Second, I track a request ID or sequence:

    let currentRequestId = 0;

    const fetchData = async () => {
      const requestId = ++currentRequestId;

      const res = await fetch("/api");
      const data = await res.json();

      if (requestId === currentRequestId) {
        setData(data);
      }
    };

  This ensures only the latest response updates the UI.

In real-world apps, libraries like React Query handle this automatically, which is why I prefer them for complex cases.

--------------------------------------------------------------------------------------------------------
Question 60: How do you retry failed requests?

Answer -> Retrying can be done manually or using libraries.
Manually, we can implement retry logic with a loop or recursion:
  const fetchWithRetry = async (retries = 3) => {
    try {
      const res = await fetch("/api");
      return await res.json();
    } catch (err) {
      if (retries > 0) {
        return fetchWithRetry(retries - 1);
      }
      throw err;
    }
  };

But in production, I prefer controlled retries:
  Retry only for network errors or 5xx errors
  Avoid retrying for 4xx errors
With libraries like React Query, retry is built-in and configurable, which is much cleaner.

--------------------------------------------------------------------------------------------------------
Question 61: How do you cache API responses?

Answer -> Caching is used to avoid unnecessary API calls and improve performance.
At a basic level, we can store responses in state or a global store and reuse them.

But for scalable applications, I prefer dedicated tools like React Query or SWR, which provide:
  Automatic caching
  Background refetching
  Cache invalidation
  Request deduplication

For example, React Query caches data based on a query key: useQuery(["users"], fetchUsers);

If the same query is requested again, it returns cached data instead of making a new API call.
We can also control cache duration using things like staleTime.

In real-world applications, I try to avoid reinventing the wheel for things like caching, retries, and race conditions. I prefer using tools like React Query because they handle these concerns in a scalable and reliable way.

==========================================================================================================
                                9. 🔸 Architecture & Best Practices
==========================================================================================================

Question 62: Folder structure of a React app

Answer -> There is no strict rule for folder structure, but the goal is to keep things organized, scalable, and easy to navigate.
In smaller apps, a simple structure works:
  components
  pages
  services
  hooks

But in larger applications, I prefer a feature-based or domain-based structure.
For example:
  src/
    features/
      auth/
        components/
        hooks/
        api.js
      dashboard/
        components/
        hooks/
        api.js
    shared/
      components/
      hooks/
    services/
    utils/

  This way, everything related to a feature is grouped together, which improves maintainability and scalability.

--------------------------------------------------------------------------------------------------------
Question 63: Smart vs dumb components.

Answer ->Smart components, also called container components, handle business logic, API calls, and state management.
Dumb components, also called presentational components, are mainly responsible for UI and rendering.
Example:
  A smart component fetches user data
  A dumb component just displays the user data via props

This separation improves reusability and testability.
In modern React, the distinction is not always strict because hooks allow us to share logic easily, but the concept still helps in structuring code properly.

--------------------------------------------------------------------------------------------------------
Question 64: Reusable components design

Answer -> Reusable components should be generic, configurable, and decoupled from business logic.
For example, instead of creating a button specifically for login, I create a generic Button component that accepts props like onClick, variant, and children.
Also, I avoid tightly coupling components with specific data structures.

Example:
    import React from "react";

    const Button = ({ onClick, variant = "primary", children, disabled = false }) => {
      const baseStyle = "px-4 py-2 rounded font-medium";

      const variants = {
        primary: "bg-blue-500 text-white",
        secondary: "bg-gray-500 text-white",
        danger: "bg-red-500 text-white",
      };

      return (
        <button
          onClick={onClick}
          disabled={disabled}
          className={`${baseStyle} ${variants[variant]} ${disabled ? "opacity-50 cursor-not-allowed" : ""}`}
        >
          {children}
        </button>
      );
    };
    export default Button;

  Now we can use it in various cases:
  case 1:
    import Button from "./components/Button";
    const Login = () => {
      const handleLogin = async () => {
        console.log("Login clicked");
        //call backend api here
      };

      return (
        <Button onClick={handleLogin} variant="primary">
          Login
        </Button>
      );
    };

  case 2: 
    import Button from "./components/Button";
    const DeleteUser = () => {
      const handleDelete =  async () => {
        console.log("Delete clicked");
        //call backend api here
      };

      return (
        <Button onClick={handleDelete} variant="danger">
          Delete User
        </Button>
      );
    };

Another important aspect is composition over inheritance. Instead of creating multiple similar components, I prefer composing them using props and children.

Example:
  <Card>
    <Header />
    <Body />
  </Card>

This makes components flexible and reusable across the application.

--------------------------------------------------------------------------------------------------------
Question 65: How do you structure a scalable React project?

Answer -> In scalable applications, I focus on a few key principles:

1.First, feature-based structure, so related code stays together.
2.Second, separation of concerns:
  UI in components
  business logic in hooks
  API calls in service layer

3.Third, state management strategy:
  local state for component-level
  context or external libraries for global state

4.Fourth, performance considerations:
  lazy loading for routes
  memoization where needed

5.Fifth, consistency and conventions:
  naming conventions
  reusable patterns
  linting and formatting

Scalability is less about choosing a perfect structure upfront and more about keeping the code modular, predictable, and easy to evolve as requirements grow.

--------------------------------------------------------------------------------------------------------
Question 66: How do you handle shared state across features?

Answer -> I usually decide this based on scope and frequency of updates.

For small shared state, like theme or auth user, I use Context API.

But for larger applications or frequently changing data, I prefer a dedicated state management solution like Redux Toolkit or Zustand. This gives better control, debugging, and avoids unnecessary re-renders.

I also try to avoid putting everything in global state. If the state is only needed within a feature, I keep it local or within that features scope.

So my approach is:
  Local state → component-level
  Context → lightweight global
  External store → complex shared state

This keeps the architecture clean and avoids over-complication.

--------------------------------------------------------------------------------------------------------
Question 67: How do you avoid tight coupling?

Answer -> To avoid tight coupling, I focus on separation of concerns and abstraction.
Example:
  I keep API logic separate from UI components
  I avoid hardcoding dependencies inside components
  I pass data and behavior via props instead of directly importing everything

Also, I design components to be reusable and independent of specific business logic.

Another important technique is using custom hooks to extract logic.
For example, instead of mixing API logic inside a component, I create something like useUsers() and reuse it wherever needed.
This way, components remain clean and loosely coupled.

--------------------------------------------------------------------------------------------------------
Question 68: How do you design a design system?

Answer -> A design system is about creating a consistent and reusable UI foundation.
I usually start by identifying common UI elements like buttons, inputs, modals, typography, and spacing.
Then I build reusable components with consistent APIs.

For example, a Button component might support variants like primary, secondary, disabled, etc.

I also define:
  color palette
  typography scale
  spacing system

In larger teams, we often use tools like Storybook to document components and make them reusable across the team.
The goal is consistency, reusability, and faster development.

--------------------------------------------------------------------------------------------------------
Question 69: How do you handle large forms or dashboards?

Answer -> For large forms, managing state manually becomes complex, so I usually use libraries like React Hook Form or Formik.
They help with:
  form state management
  validation
  performance optimization

I also break large forms into smaller components and sometimes use multi-step forms to improve UX.

For dashboards, I focus on:
  breaking UI into smaller reusable components
  lazy loading heavy components like charts
  optimizing re-renders using memoization

Also, I carefully decide where state should live, because dashboards often have shared filters or data.
In real-world apps, performance and data flow become very important in dashboards.

==========================================================================================================
                                10. 🔸 Advanced Concepts and System Design
==========================================================================================================

Question 70: What is Higher Order Component(HOC)?

Answer -> A Higher Order Component is a function that takes a component and returns a new enhanced component.

It is mainly used to reuse logic across multiple components.
For example, if I want to add authentication logic to multiple components, I can create an HOC:

We have a Dashboard component:
  const Dashboard = () => {
    return <h1>Welcome to Dashboard</h1>;
  };
  export default withAuth(Dashboard);

We have a HOC:
  const withAuth = (Component) => {
    return (props) => {
      const isAuthenticated = !!localStorage.getItem("token");

      if (!isAuthenticated) {
        return <Navigate to="/login" />;
      }

      return <Component {...props} />;
    };
  };

And then we can use:
  import Dashboard from "./Dashboard";
  <Dashboard />

Alternative, Instead of exporting wrapped components, you can wrap them when defining routes:
  <Route path="/dashboard" element={withAuth(Dashboard)()} />

In modern React, we often replace HOCs with custom hooks, but HOCs are still used in some libraries and legacy codebases.

--------------------------------------------------------------------------------------------------------
Question 71: What are render props?

Answer -> Render props is a pattern where a component receives a function as a prop and uses that function to render something.
This allows sharing logic in a flexible way.
Example:
  <DataFetcher
    render={(data) => <div>{data.name}</div>}
  />

Inside DataFetcher, it calls that function and passes data.
Like HOCs, render props were used before hooks became popular. Now, most of the same problems are solved using custom hooks, which are simpler and cleaner.

--------------------------------------------------------------------------------------------------------
Question 72: What is code splitting?

Answer -> Code splitting is a technique where we split the application bundle into smaller chunks and load them only when needed.
Instead of loading the entire app at once, we load parts of it on demand.
This improves initial load time and performance.
For example, instead of loading all pages upfront, we load only the current page and fetch others when the user navigates.

--------------------------------------------------------------------------------------------------------
Question 73: What is lazy loading?

Answer -> Lazy loading is a way to implement code splitting.
It means loading components only when they are required.
For example, if a user never visits the dashboard page, there is no need to load its code initially.
This helps reduce bundle size and improves performance.

--------------------------------------------------------------------------------------------------------
Question 74: React.lazy and Suspense

Answer -> In React, we implement lazy loading using React.lazy and Suspense.
React.lazy is used to dynamically import a component:
  const Dashboard = React.lazy(() => import("./Dashboard"));

But since the component is loaded asynchronously, we need to show a fallback UI while it is loading. That is where Suspense comes in.

  <Suspense fallback={<div>Loading...</div>}>
    <Dashboard />
  </Suspense>

So:
  React.lazy → loads the component dynamically
  Suspense → shows fallback UI while loading

In real-world apps, we usually combine this with routing for route-based code splitting.

Earlier patterns like HOC and render props were mainly used for code reuse, but with the introduction of hooks, most of those use cases are now handled more cleanly using custom hooks.

--------------------------------------------------------------------------------------------------------
Question 75: Limitations of React.lazy

Answer -> React.lazy is useful, but it has some limitations.
First, it only works for default exports. If a module has named exports, we need extra handling.

Second, it works only for client-side rendering. It is not suitable for SSR out of the box. For SSR setups, we usually use libraries like loadable-components.

Third, error handling is limited. If the lazy-loaded component fails to load, we need to wrap it with an Error Boundary, otherwise the app can crash.

Also, overusing lazy loading can actually hurt performance because it increases the number of network requests.

So it is important to use it strategically, mostly for route-level splitting.

--------------------------------------------------------------------------------------------------------
Question 76: Can Suspense be used for data fetching?

Answer -> Yes, but with some conditions.
Traditionally, Suspense was only used for lazy loading components. But in modern React, especially with concurrent features, Suspense can also be used for data fetching.

However, it does not work with normal fetch directly. It requires a library or framework support like React Query, Relay, or frameworks like Next.js that integrate Suspense.

In those cases, Suspense can pause rendering until data is ready and show a fallback UI.

In most production apps today, data fetching is still handled using hooks like useEffect or libraries, and Suspense for data fetching is used in more advanced setups.

--------------------------------------------------------------------------------------------------------
Question 77: Difference between dynamic import and lazy loading

Answer -> Dynamic import is a JavaScript feature:
            import("./Dashboard");
          It allows loading a module asynchronously.

Lazy loading is a broader concept — it means loading something only when it is needed.
React.lazy actually uses dynamic import under the hood to implement lazy loading for components.

So:
  Dynamic import → low-level JS feature
  Lazy loading → high-level concept
  React.lazy → Reacts implementation using dynamic import

--------------------------------------------------------------------------------------------------------
Question 78: When NOT to use lazy loading?

Answer -> Lazy loading is useful, but not always the right choice.
First, for small components, lazy loading adds unnecessary complexity and extra network requests.
Second, for critical UI, like above-the-fold content, we should not lazy load because it can delay rendering and hurt user experience.
Third, if a component is used very frequently across the app, lazy loading may not give much benefit.

Also, overusing lazy loading can lead to too many small bundles, which increases network overhead.
So I usually use lazy loading mainly for:
  routes
  large components
  rarely used features

I treat lazy loading as a performance optimization tool, not a default pattern. I use it selectively where it improves initial load time without hurting user experience.

--------------------------------------------------------------------------------------------------------
Question 79: What is bundle splitting strategy?

Answer ->Bundle splitting strategy is about deciding how to divide your application code into smaller chunks so that users do not download everything upfront.

The goal is to optimize initial load time vs subsequent navigation performance.

The most common strategy is route-based splitting — each route gets its own bundle. So when the user visits /dashboard, only the dashboard code is loaded.

Then there is component-level splitting, where heavy components like charts or editors are loaded only when needed.

Another important strategy is vendor splitting — separating third-party libraries into a different bundle so they can be cached effectively.

In real-world apps, I usually combine:
  route-level splitting for pages
  component-level splitting for heavy UI
  vendor chunking for better caching

--------------------------------------------------------------------------------------------------------
Question 80: What is prefetching vs preloading?

Answer -> Both are techniques to load resources early, but they differ in priority and intent.
Prefetching means loading resources that might be needed in the future.
It happens with low priority, usually when the browser is idle.

For example, if a user is on the home page, I can prefetch the dashboard bundle assuming they might navigate there next.

Preloading means loading resources that are needed soon, with higher priority.
For example, if I know a component will definitely be needed in the next interaction, I preload it to reduce delay.

So:
  Prefetch → future use, low priority
  Preload → immediate need, high priority

In React apps, tools like Webpack or frameworks like Next.js handle this automatically in many cases.

--------------------------------------------------------------------------------------------------------
Question 81: How do you measure performance improvement?

Answer -> I do not rely on assumptions — I measure performance using tools.

First, I use Chrome DevTools, especially:
  Network tab → to check bundle size and load time
  Performance tab → to analyze rendering and scripting

Second, I use Lighthouse to get metrics like:
  First Contentful Paint (FCP)
  Largest Contentful Paint (LCP)
  Time to Interactive (TTI)

Third, React-specific tool:
  React DevTools Profiler → to see component re-renders and render time

In production, we can also use monitoring tools like Sentry or New Relic for real user metrics.

The key thing is:
  Identify bottleneck
  Apply optimization
  Measure before and after

I focus on data-driven optimization — I first identify bottlenecks using tools like Lighthouse or React Profiler, then apply targeted optimizations like code splitting or memoization, and finally verify the improvement.

--------------------------------------------------------------------------------------------------------
Question 82: What is LCP and why is it important?

Answer -> LCP stands for Largest Contentful Paint. It measures the time it takes for the largest visible element on the screen to render — usually something like a big image, banner, or main heading.

It is important because it directly reflects how fast the user perceives the page to load.

For example, even if smaller elements load quickly, if the main content takes time, the user feels the app is slow.

Google recommends keeping LCP under 2.5 seconds for a good user experience.

In React apps, LCP can be affected by:
  large bundle size
  slow API calls
  heavy images

So improving LCP usually involves:
  code splitting
  optimizing images
  reducing render-blocking resources

--------------------------------------------------------------------------------------------------------
Question 83: How do you reduce bundle size?

Answer -> Reducing bundle size is about sending less JavaScript to the browser.
Some common techniques I use:
  1.First, code splitting — load only what is needed.
  2.Second, removing unused dependencies — sometimes libraries are large but only partially used.
  3.Third, tree shaking — removing unused code during build.
  4.Fourth, using lighter alternatives — for example, using smaller utility libraries instead of heavy ones.
  5.Fifth, lazy loading for large components.

Also, I check bundle size using tools like Webpack Bundle Analyzer to identify what is taking space.

--------------------------------------------------------------------------------------------------------
Question 84: What is tree shaking?

Answer -> Tree shaking is a build optimization technique where unused code is removed from the final bundle.

It works with ES modules because they have static imports, which allows bundlers to analyze which parts of the code are actually used.

For example, if I import a utility library but use only one function, tree shaking ensures that only that function is included in the final bundle.

This helps reduce bundle size and improve performance.

--------------------------------------------------------------------------------------------------------
Question 85: How does caching affect performance?

Answer -> Caching improves performance by storing previously loaded resources so they do not need to be fetched again.

For example, if a user visits the app again, cached JavaScript files or API responses can be reused, making the app load faster.

There are different levels of caching:
  Browser caching → static assets like JS, CSS
  API caching → storing responses
  CDN caching → serving content closer to the user

In React apps, caching is especially useful for:
  static assets (via proper cache headers)
  API data (via tools like React Query)

But it is also important to handle cache invalidation properly, otherwise users might see stale data.

Performance is about balancing load time and freshness of data — using techniques like caching, code splitting, and bundle optimization while ensuring the user always sees relevant and up-to-date information.

==========================================================================================================
                                10. 🔸 Error Handling
==========================================================================================================

Question 86: What are Error Boundaries?

Answer -> Error Boundaries are special React components used to catch JavaScript errors in the component tree during rendering.
They prevent the whole application from crashing and instead allow us to show a fallback UI.

In class components, we implement them using lifecycle methods like:
  componentDidCatch
  getDerivedStateFromError

For example, if a child component throws an error during render, the error boundary catches it and shows something like “Something went wrong” instead of breaking the entire UI.

In real-world apps, we usually wrap critical parts of the UI, like dashboards or sections, with error boundaries.

--------------------------------------------------------------------------------------------------------
Question 87: Can functional components act as error boundaries?

Answer -> No, functional components cannot directly act as error boundaries.
Error boundaries currently require class components because they depend on specific lifecycle methods.

However, in functional components, we can still use error boundaries by wrapping them.
Also, in modern React, libraries and patterns are evolving, but as of now, error boundaries are still class-based.

--------------------------------------------------------------------------------------------------------
Question 88: Why error boundaries do not catch async errors?

Answer -> Error boundaries only catch errors that happen during:
              rendering
              lifecycle methods
              constructors

They do not catch errors in:
  asynchronous code (like API calls, setTimeout)
  event handlers

The reason is that async code runs outside Reacts render cycle. Error boundaries are designed to handle errors during rendering, not during arbitrary async execution.

For example, if an API call fails inside useEffect, the error boundary will not catch it. We need to handle it manually using try-catch.

==========================================================================================================
                                11. 🔸 Real-World Scenario Questions
==========================================================================================================

Question 89: How do you optimize a slow React app?

Answer -> First, I do not jump into optimization blindly. I start by identifying the bottleneck using tools like React DevTools Profiler or Chrome DevTools.

Once I know the problem, I apply targeted optimizations.

If it is due to unnecessary re-renders, I look at component structure, props, and state placement. I may use React.memo, useMemo, or useCallback where needed.

If the issue is large bundle size, I apply code splitting and lazy loading.

If it is API-related, I optimize by caching, debouncing, or reducing redundant calls.

Also, I check for heavy computations inside render and move them to memoized logic.

So overall, my approach is: measure → identify → optimize → verify

--------------------------------------------------------------------------------------------------------
Question 90: How do you handle large lists?

Answer ->  Rendering large lists directly can cause performance issues.
The most effective solution is virtualization.
Using libraries like react-window or react-virtualized, we render only the visible items instead of the entire list.

For example, if we have 10,000 items, only 20-30 visible items are rendered at a time.

Other optimizations include:
  using proper keys
  pagination or infinite scroll
  memoizing list items if needed

In real-world dashboards, virtualization makes a huge difference.

--------------------------------------------------------------------------------------------------------
Question 91: How do you manage global state?

Answer -> I decide based on complexity and scale.
For small global state like theme or auth, I use Context API.
For complex applications with frequent updates or shared state across many features, I prefer Redux Toolkit or Zustand.
I also avoid putting everything in global state. If data is only needed locally, I keep it in component state.

So my approach is:
  local state → default
  context → lightweight global
  external store → complex global state

--------------------------------------------------------------------------------------------------------
Question 92: How do you avoid unnecessary re-renders?

Answer -> First, I understand why re-renders are happening.
Common causes are:
  parent re-renders
  new object or function references
  state updates

To optimize:
  I use React.memo for components
  useCallback for functions
  useMemo for computed values

Also, I make sure not to create inline objects or functions unnecessarily.
Another important thing is placing state correctly — if state is too high in the tree, it causes more re-renders.

So it is a combination of correct structure + memoization.

--------------------------------------------------------------------------------------------------------
Question 93: How do you design a reusable component?

Answer -> I focus on making components generic, flexible, and decoupled from business logic.
For example, instead of building a “LoginButton”, I create a generic “Button” component that accepts props like onClick, variant, and children.
I also use composition instead of hardcoding behavior.

For example:
  <Card>
    <Header />
    <Body />
  </Card>

I avoid assumptions about data and keep components configurable through props.

Also, I think about reusability early, but I do not over-generalize unnecessarily.

==========================================================================================================
                                12. 🔸 Testing (Basic)
==========================================================================================================

Question 94: In React, I usually test components using libraries like Jest and React Testing Library.

Answer -> My approach is to test components from a users perspective, not implementation details.
For example, instead of checking internal state, I test what the user sees and interacts with.

If I have a button:
  I render the component
  simulate a click
  and verify if the expected UI change happens

  Something like:
    render(<Button />);
    fireEvent.click(screen.getByText("Submit"));
    expect(screen.getByText("Success")).toBeInTheDocument();

In real-world projects, I focus on:
  rendering correctness
  user interactions
  API behavior (mocked)

I avoid testing internal implementation because it makes tests fragile.

--------------------------------------------------------------------------------------------------------
Question 95: What is unit testing in React?

Answer -> Unit testing means testing small, isolated pieces of code, like a single component or function.
In React, it usually means testing:
  one component at a time
  with mocked dependencies

For example, if I have a LoginForm component, I test:
  input behavior
  validation
  form submission

But I mock API calls so that I am only testing the component logic, not external systems.
The goal is to ensure that each unit works correctly in isolation.

==========================================================================================================
                                13. 🔸 Rapid-Fire : Tricky 
==========================================================================================================
Question 96: Why is setState asynchronous?

Answer -> setState is asynchronous because React batches multiple state updates together for performance.
Instead of updating the state immediately on every call, React schedules the update and processes them in a single render cycle.
This reduces unnecessary re-renders and improves performance.

Also, in modern React, batching happens even across async boundaries, so we should not rely on immediate state updates and instead use functional updates when needed.

--------------------------------------------------------------------------------------------------------
Question 97: Can we update state directly?

Answer ->No, we should never update state directly.
For example: state.count = 5; // wrong

React will not detect this change properly because it relies on state updates through its APIs.
Instead, we should use setState or state updater functions so React knows when to re-render.

--------------------------------------------------------------------------------------------------------
Question 98: What happens if you mutate state?

Answer -> If we mutate state directly, React may not trigger a re-render because the reference does not change.
Also, it can lead to unpredictable bugs because React relies on immutability to compare previous and next state.

For example, modifying an object directly can cause stale UI or inconsistent behavior.
That is why we always create a new copy when updating state.

--------------------------------------------------------------------------------------------------------
Question 99: Difference between == and === in React rendering?

Answer -> == checks for value equality with type coercion, while === checks for strict equality without type conversion.

In React, we should always use === because it avoids unexpected behavior due to type coercion.
For example:
  "5" == 5   // true
  "5" === 5  // false

Using strict equality makes conditions predictable and safer in rendering logic.

--------------------------------------------------------------------------------------------------------
Question 100: Why hooks cannot be used inside loops or conditions?

Answer -> Hooks must be called in the same order on every render.
React relies on the order of hook calls to map state and effects correctly.

If we use hooks inside loops or conditions, the order may change between renders, which breaks Reacts internal tracking and can cause bugs.
That is why hooks must always be called at the top level of the component.

--------------------------------------------------------------------------------------------------------
Question 101:

--------------------------------------------------------------------------------------------------------
Question 102:

--------------------------------------------------------------------------------------------------------
Question 103:

--------------------------------------------------------------------------------------------------------
Question 104:

--------------------------------------------------------------------------------------------------------
Question 105:

--------------------------------------------------------------------------------------------------------
Question 106:

--------------------------------------------------------------------------------------------------------
Question 107:

--------------------------------------------------------------------------------------------------------
Question 108:

--------------------------------------------------------------------------------------------------------
Question 109:

--------------------------------------------------------------------------------------------------------
Question 110:

--------------------------------------------------------------------------------------------------------
Question 111:

--------------------------------------------------------------------------------------------------------
Question 112:



State Management
----------------
How does React batching work?

routing
---------
“How to preload next route?”

API handling
--------------
“What is stale data?”
“How do you invalidate cache?”
“What is optimistic update?”
“How do you handle pagination with caching?”

Architecture
---------------
“How do you design reusable hooks?”
“How do you manage cross-feature communication?”
“How do you version a design system?”
“How do you optimize large dashboards?”

Advanced Concepts and System Design
-----------------------------------------
“What is TTI vs LCP?”
“What is service worker caching?”
“How does CDN help performance?”

Error Handling
----------------
“Where should you place error boundaries?”
“Can you have multiple error boundaries?”
“How do you log errors in production?”
“How do you recover from errors?”


  Patse these above question in these chat of chatgpt: (React questions-answers)
  https://chatgpt.com/share/69e3bd05-86b4-8321-91f8-b044e5ca2df8