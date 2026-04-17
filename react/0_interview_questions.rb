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
                                Core React Fundamentals
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

--------------------------------------------------------------------------------------------------------
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
  Q. In the above example , why we have updated the coutRef.current = count inside the useEffect hook and not direclty.

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
Question 13:

--------------------------------------------------------------------------------------------------------
Question 14:

--------------------------------------------------------------------------------------------------------
Question 15:

--------------------------------------------------------------------------------------------------------
Question 16:

--------------------------------------------------------------------------------------------------------
Question 17:

--------------------------------------------------------------------------------------------------------
Question 18:

--------------------------------------------------------------------------------------------------------
Question 19:

--------------------------------------------------------------------------------------------------------
Question 20:

