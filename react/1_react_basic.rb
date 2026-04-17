What is React?
  Answer -> React is a declarative, component-based JavaScript UI library that builds user interfaces by efficiently updating the DOM using a virtual representation.

---------------------------------------------------------------------------------------------------
Why React exists?
  Answer -> Before React, developers mostly relied on direct DOM manipulation, often using libraries like jQuery. While jQuery was powerful for manipulating the DOM, it became pretty messy and inefficient as applications grew in complexity. When you manually update the DOM based on changes in application state, it is easy for things to get out of sync, and the whole process becomes slow and difficult to manage.

  The core problem React aimed to solve was the inconsistency between UI and state. In traditional approaches, syncing the UI to reflect changes in state was a tedious task, especially when the application became more dynamic. The UI essentially became a function of the state, but manually keeping that sync was hard to scale.

  So, React came in with this very simple but powerful idea: UI = a function of state. What that means is that instead of manually manipulating the DOM to reflect changes in the UI, React abstracts away that complexity. Whenever the state changes, React automatically re-renders the UI to match the current state, making the whole process more declarative and much easier to manage. This approach allows developers to think in terms of components and states, improving both performance and maintainability.

---------------------------------------------------------------------------------------------------
How React works internally?
  Answer -> The core idea behind React is that it allows you to describe the UI using JSX, which is a syntax extension for JavaScript that looks like HTML but is actually JavaScript. You use JSX to define how the UI should look based on the current state of your application.

  Internally, React does not directly manipulate the DOM every time there is a state change. Instead, it creates a Virtual DOM, which is an in-memory representation of the actual DOM. When something in your application state changes, React does the following:

    It creates a new Virtual DOM based on the updated state.
    Then, it compares this new Virtual DOM with the previous one, a process called diffing.
    Finally, React updates only the parts of the actual DOM that have changed (this process is called reconciliation), which makes updates super efficient and avoids unnecessary re-renders.

  For example, if you look at this simple Counter component:

    function Counter() {
      const [count, setCount] = useState(0);

      return (
        <button onClick={() => setCount(count + 1)}>
          {count}
        </button>
      );
    }

  Every time the button is clicked, the state count changes, triggering a re-render. However, React does not re-render the entire page. It just updates the button text because it only changes that specific part of the DOM, thanks to the Virtual DOM and reconciliation process.

  The beauty of this is that you, as a developer, never need to manually manipulate the DOM. React handles all the updates efficiently for you, ensuring both performance and ease of development.

---------------------------------------------------------------------------------------------------
What is the Real DOM, and what problems does it have?
  Answer -> The Real DOM refers to the actual Document Object Model that the browser creates from your HTML. It is basically a tree structure where each node represents an element on the page, and this is what the browser uses to render the UI.

  The challenge with the Real DOM is that operations on it are quite expensive. Whenever you make a change—like updating text or modifying an element — it can trigger processes like reflow, which is recalculating the layout, and repaint, which updates the visual appearance on the screen.

  The issue is that even small changes can sometimes cause the browser to recalculate large parts of the DOM tree, which impacts performance, especially in complex or dynamic applications.

  For example, if you directly update something like:
    document.getElementById("counter").innerText = count;

  you are directly manipulating the DOM every time the value changes. This might be fine for small apps, but in larger UIs with frequent updates, it becomes slow and hard to manage efficiently.

  That is exactly the problem React tries to solve by minimizing direct interaction with the Real DOM and optimizing updates.

---------------------------------------------------------------------------------------------------
What is the Virtual DOM and why does React use it?
  Answer -> The Virtual DOM is a lightweight JavaScript representation of the actual DOM. It is not the real DOM you see in the browser — instead, it is just a plain JavaScript object that describes what the UI should look like.

  For example, a simple button in the Virtual DOM might look something like an object with a type and props, representing its structure and content.

  Now, the reason the Virtual DOM exists is to solve a key problem: how to update the UI efficiently when the application state changes.

  If we directly updated the Real DOM every time state changes, it would be slow and inefficient because DOM operations are expensive. So instead, React takes a smarter approach.

  Whenever the state changes, React:
    Creates a new Virtual DOM
    Compares it with the previous version (this is called diffing)
    And then updates only the parts of the Real DOM that actually changed

  This way, React avoids unnecessary DOM operations and makes updates much faster and more efficient.

  So in short, the Virtual DOM acts as an optimization layer that helps React update the UI in a performant and scalable way.

---------------------------------------------------------------------------------------------------
Explain React internal working step by step?
  Answer -> React internal working can be understood in two main phases: the initial render and what happens when the state changes.

  During the initial render, React takes the JSX we write and converts it into a Virtual DOM, which is a JavaScript object representation of the UI. Then, React uses that Virtual DOM to create and render the actual Real DOM in the browser.

  Now, when there is a state change, React does not directly update the Real DOM. Instead, it follows a smart process:
    First, it creates a new Virtual DOM based on the updated state.
    
    Then comes diffing, also known as reconciliation, where React compares the new Virtual DOM with the previous one to identify what has changed.

    After identifying the differences, React performs a patch update, meaning it updates only the specific parts of the Real DOM that actually changed, instead of re-rendering everything.

  This approach makes React very efficient because it minimizes expensive DOM operations and ensures optimal performance.

  So overall, React follows this flow: JSX → Virtual DOM → Real DOM initially, and on updates, it uses diffing and reconciliation to update only what is necessary.

---------------------------------------------------------------------------------------------------
Explain Reacts reconciliation algorithm?
  Answer -> Reacts reconciliation algorithm is the process it uses to efficiently update the UI when the state changes.

  Instead of doing a full comparison of the entire DOM tree — which would be very slow — React uses a set of heuristics, or smart assumptions, to optimize the process.

  There are a few key rules React follows:

    First, if two elements are of different types, React assumes they are completely different. For example, if a <div> changes to a <span>, React will remove the entire old subtree and create a new one from scratch.

    Second, if the elements are of the same type, React does not recreate them. Instead, it only updates the changed attributes or props. For example, if a buttons className changes, React will just update that class without touching the rest of the element.

    The third and very important concept is keys in lists. When rendering lists, React uses keys to uniquely identify each element. This helps React understand which items have changed, been added, or removed.

    Without keys, React might re-render unnecessary elements, performance issues, bugs in input fields. But with proper keys, it can efficiently update only the affected items, improving performance.

  So overall, reconciliation is Reacts smart way of minimizing DOM operations by making assumptions and updating only what is truly necessary.

---------------------------------------------------------------------------------------------------
Is Virtual DOM always faster? Why is React considered performant?
  Answer -> The Virtual DOM itself is not always faster than directly updating the Real DOM.

  React is actually fast because of a combination of optimizations, not just the Virtual DOM.

  First, React uses batching, which means it groups multiple state updates together and processes them in a single render cycle instead of updating the DOM repeatedly.

  Second, it uses efficient diffing through its reconciliation algorithm, where it compares the previous and current Virtual DOM and figures out the minimal set of changes needed.

  And third, React avoids unnecessary DOM operations, which are the most expensive part of UI updates. Instead of blindly updating everything, it updates only what actually changed.

  So, the real performance benefit comes from reducing costly DOM manipulations and intelligently managing updates—not just from having a Virtual DOM.

---------------------------------------------------------------------------------------------------
Can you talk about some edge cases or performance limitations in React?
  Answer -> While React is highly optimized, there are certain edge cases where performance can still become a concern.

  One common scenario is large lists, say rendering 10,000 items. Even though React uses the Virtual DOM, diffing such a large tree can still be computationally expensive. In these cases, we typically use a technique called windowing or virtualization, with libraries like react-window. This ensures that only the visible portion of the list is rendered at any given time, significantly improving performance.

  Another scenario is frequent re-renders. Every time a component re-renders, React has to recreate the Virtual DOM, which also has a CPU cost. If this happens too often, it can impact performance.

  To handle this, we use memoization techniques like React.memo for components and useMemo or useCallback for values and functions. These help prevent unnecessary re-renders by caching results and only recalculating when dependencies actually change.

---------------------------------------------------------------------------------------------------
When is the Virtual DOM not enough?
  Answer ->  While the Virtual DOM is a powerful optimization, it is not ideal for all use cases — especially scenarios involving high-frequency updates, like animations or real-time visualizations.

  In such cases, even the overhead of creating and diffing the Virtual DOM can become a bottleneck, because updates are happening many times per second.

  For example, in complex animations, games, or data visualizations, you need very fine-grained control and extremely fast rendering. Here, relying on Reacts reconciliation process can introduce unnecessary overhead.

  So instead, we typically use lower-level rendering approaches like Canvas or WebGL, which allow direct drawing and better performance for these kinds of tasks.

---------------------------------------------------------------------------------------------------
What is React Fiber?
  Answer -> React Fiber is the reconciliation engine introduced in React 16 that enables incremental rendering, prioritization, and interruptible work.
  In simple terms: It is the new internal algorithm React uses to render UI efficiently.

  React Fiber is the core reconciliation algorithm introduced in React 16 to improve rendering performance and responsiveness. In older React versions, rendering was synchronous and blocking, meaning large updates could freeze the UI.

  Fiber solves this by breaking rendering work into small units called fibers, which are essentially JavaScript objects representing components. This allows React to pause, resume, and prioritize rendering tasks.

  The process is divided into two phases: the render phase, which is interruptible and builds the new tree, and the commit phase, which applies changes to the DOM and runs effects synchronously.

  Fiber also introduces priority-based scheduling, so high-priority updates like user input can be processed before lower-priority tasks like background rendering.

  This architecture is the foundation for modern React features like concurrent rendering and Suspense.

---------------------------------------------------------------------------------------------------
Why was React Fiber introduced?
  Answer -> React Fiber was introduced to solve limitations in the old React rendering system, which is often called the Stack Reconciler.

  In the older approach, rendering was completely synchronous. That means once React started rendering a component tree, it had to finish the entire process without any interruption. It could not pause, stop, or prioritize anything in between.

  This became a problem for large or complex UI updates. For example, if you had to render a big list or perform a heavy update, it would block the main thread. As a result, the UI could freeze, causing jank and making the app unresponsive — even simple actions like scrolling or clicking could feel laggy.

  To solve this, the React team introduced Fiber with a new goal: make rendering more flexible and controllable.

  With Fiber, React can break rendering work into smaller units. This allows React to pause and resume rendering work, prioritize more important updates like user interactions, and continue less important work later.

  So instead of rendering being a single blocking process, Fiber makes it incremental and interruptible, meaning React can work in chunks rather than all at once.

---------------------------------------------------------------------------------------------------
What is a Fiber Node in React?
  Answer -> In React Fiber architecture, everything is broken down into small units of work, and each of these units is called a Fiber node.

  So essentially, a Fiber node is a JavaScript object that represents a single component or element in the React tree, along with all the information React needs to manage rendering and updates for that part of the UI.

  You can think of it as an enhanced version of a Virtual DOM node, but with extra metadata that helps React control rendering more efficiently.

  Each Fiber node contains key properties. For example:
    The type represents what kind of element or component it is, like a div or a custom component.
    The stateNode points to the actual DOM node when it exists.
    The child points to the first child Fiber,
    The sibling points to the next sibling node,
    And the return points to the parent Fiber node.

  Together, these pointers form a linked tree structure instead of a simple static tree.

  This structure is what allows React Fiber to pause, resume, and prioritize rendering work, because React can traverse and manage the tree in small, controllable units rather than processing everything at once.

  Example Simplified structure:
      {
        type: 'div',
        stateNode: DOMNode,
        child: Fiber,
        sibling: Fiber,
        return: Fiber,
      }

---------------------------------------------------------------------------------------------------
Explain the two phases of React Fiber?
  Answer -> In React Fiber, rendering is split into two main phases: the Render phase and the Commit phase.

  The first one is the Render phase, also known as reconciliation. In this phase, React builds a new Fiber tree based on the updated state and figures out what changes need to happen compared to the previous tree. This is where diffing happens.

  A key point about the Render phase is that it is interruptible. React can pause it, resume it, or even discard work if a higher-priority update comes in. That is why this phase runs in the background and is optimized for scheduling work efficiently.

  The second phase is the Commit phase. In this phase, React takes all the calculated changes from the Render phase and applies them to the actual DOM. This is where the UI is updated on the screen.

  Unlike the Render phase, the Commit phase is synchronous and cannot be interrupted, because the DOM needs to stay consistent. React also runs lifecycle methods and effects during this phase.

  So in short, the Render phase calculates what needs to change, and the Commit phase actually applies those changes to the DOM in a fast and controlled way.

  Virtual DOM = WHAT to render
  Fiber = HOW & WHEN to render

---------------------------------------------------------------------------------------------------
What is scheduling and priority in React Fiber?
  Answer -> React Fiber introduces a concept called priority-based scheduling, which allows React to decide which updates are more important and should be handled first.

  Not all updates in a React application have the same urgency. For example, a user typing in an input field or clicking a button is very high priority because it directly affects user interaction. On the other hand, things like background data updates or rendering non-visible components are lower priority.

  So React assigns priorities to different types of updates. High-priority tasks like user input are handled immediately, while low-priority work can be delayed or even paused.

  The key advantage of this system is that React can pause low-priority rendering work and switch to high-priority updates when needed. This ensures that the application remains responsive and smooth, even when there is heavy rendering happening in the background.

  So overall, scheduling in Fiber is what enables React to be responsive by intelligently managing and prioritizing work instead of treating all updates equally.

---------------------------------------------------------------------------------------------------
How does React Fiber enable a smooth user interface?
  Answer -> React Fiber improves UI smoothness by allowing React to intelligently manage and prioritize rendering work instead of blocking the main thread.

  For example, imagine a scenario where a user is typing into an input field while a large list is being rendered in the background.

  Without Fiber, React would try to complete the entire list rendering in one go because rendering was synchronous. During that time, the main thread gets blocked, and the input becomes laggy or unresponsive.

  But with Fiber, React can break rendering into small units and schedule work based on priority. So when the user types in the input, that interaction is considered high priority.

  React can pause the low-priority task, like rendering the big list, immediately handle the input update, and then resume the list rendering afterward.

  This ensures that high-priority user interactions are always smooth and responsive, even when heavy rendering work is happening in the background.

  So overall, Fiber makes the UI smooth by enabling interruptible rendering and priority-based scheduling.

---------------------------------------------------------------------------------------------------
What is double buffering in React Fiber?

  Answer -> In React Fiber, double buffering is a technique used to ensure smooth and consistent UI updates.

  React maintains two versions of the Fiber tree at any given time. One is the current tree, which represents the UI that is currently visible on the screen. The other is the work-in-progress tree, which React uses to calculate updates in the background during the render phase.

  So when a state change happens, React does not directly modify the current UI. Instead, it builds and updates the work-in-progress tree, applies all reconciliation there, and figures out what needs to change.

  Once the render phase is complete and everything is ready, React enters the commit phase, where it swaps the work-in-progress tree with the current tree and applies the final changes to the DOM.

  This process is called double buffering, and it helps React avoid inconsistent UI states and ensures updates appear smooth and atomic from the users perspective.

---------------------------------------------------------------------------------------------------
What are some edge cases or limitations in React Fiber?
  Answer -> Even though React Fiber significantly improves rendering and scheduling, there are still some important edge cases and limitations to understand.

  First, infinite updates inside render. If we accidentally trigger state updates continuously during rendering, it can create a loop in the Fiber work, leading to repeated re-render cycles. React detects this in many cases and throws an error like "maximum update depth exceeded" to prevent the app from crashing.

  Second is the long commit phase. Even though the render phase is interruptible, the commit phase is not. It runs synchronously because React needs to apply DOM updates in a consistent way. So if the commit work is heavy, it can still block the main thread and cause UI jank.

  Third is too many high-priority updates. Since React prioritizes urgent tasks like user input, if we constantly trigger high-priority updates, it can lead to starvation of low-priority work, meaning background rendering gets delayed indefinitely.

  And lastly, improper usage of useEffect. If effects are not managed correctly, they can trigger unnecessary re-renders or continuous updates, which again causes Reacts scheduler to keep re-running work and impacts performance.

  So overall, Fiber improves scheduling and responsiveness, but developers still need to be careful with how updates and side effects are designed to avoid these edge cases.

---------------------------------------------------------------------------------------------------
What is the real impact of Fiber in React 18+?
  Answer -> React Fiber becomes even more important in React 18 and beyond because it enables modern features like concurrent rendering, transitions, and improved Suspense behavior.

  With concurrent rendering, React can work on multiple UI updates at the same time and pause work when higher-priority updates come in. This makes applications feel more responsive.

  Features like Transitions allow React to distinguish between urgent updates, like typing or clicking, and non-urgent updates, like filtering a large list. This helps keep the UI smooth without blocking user interactions.

  And Suspense improvements rely heavily on Fibers ability to pause rendering while waiting for asynchronous data, making loading states more seamless.

  So overall, Fiber is the foundation that enables React 18s modern rendering capabilities.

---------------------------------------------------------------------------------------------------
What is the difference between state and props?
  Answer -> At a basic level, props are inputs to a component, and state is internal data managed by the component. But beyond that, the real difference is in ownership and control of data flow in React.

  Props are read-only and controlled by the parent component. They are used to pass data down the component tree, which makes them part of Reacts unidirectional data flow. So if props change, it means the parent has re-rendered and passed new values down.

  State, on the other hand, is owned and managed within the component itself. It represents data that can change over time based on user interaction or internal logic. When state changes, the component re-renders itself.

  The key conceptual difference is:
    Props are for communication between components
    State is for managing internal behavior of a component

  Another important point is mutability control. Props should never be mutated inside a child component, while state is mutable — but only through Reacts state setters like setState or useState.

  And at a deeper level, props help build reusable components, because you can configure them from the outside, while state makes a component interactive and dynamic.

  So in real applications, props define how components connect, and state defines how components behave internally.

---------------------------------------------------------------------------------------------------
In React, keys are used to uniquely identify elements in a list during reconciliation. When the state changes, React compares the previous and next virtual DOM. Keys help React determine which elements are added, removed, or updated, allowing efficient DOM updates. Without proper keys, React may re-render incorrectly or reuse DOM elements improperly, leading to performance issues and UI bugs.

React.memo is a higher-order component that prevents unnecessary re-renders by doing a shallow comparison of props. If props do not change, the component will not re-render.

API calls in React are typically handled inside useEffect. It is important to handle cleanup to avoid memory leaks, especially if the component unmounts before the API call completes. We also need to manage loading and error states properly