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
  Q. In the above example , why we have updated the "coutRef.current = count" inside the useEffect hook and not direclty.

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
                                8. 🔸 Routing
==========================================================================================================
Question 54: How to call APIs in React?

Answer -> 

--------------------------------------------------------------------------------------------------------
Question 55:

--------------------------------------------------------------------------------------------------------
Question 56:

--------------------------------------------------------------------------------------------------------
Question 57:

--------------------------------------------------------------------------------------------------------
Question 58:

--------------------------------------------------------------------------------------------------------
Question 59:

--------------------------------------------------------------------------------------------------------
Question 60:

--------------------------------------------------------------------------------------------------------
Question 61:

--------------------------------------------------------------------------------------------------------
Question 62:

--------------------------------------------------------------------------------------------------------
Question 63:

--------------------------------------------------------------------------------------------------------
Question 64:

--------------------------------------------------------------------------------------------------------
Question 65:

--------------------------------------------------------------------------------------------------------
Question 66:

--------------------------------------------------------------------------------------------------------
Question 67:

--------------------------------------------------------------------------------------------------------
Question 68:

--------------------------------------------------------------------------------------------------------
Question 69:

--------------------------------------------------------------------------------------------------------
Question 70:

--------------------------------------------------------------------------------------------------------
Question 71:

