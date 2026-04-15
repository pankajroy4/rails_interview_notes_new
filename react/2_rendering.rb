What is rendering in React?
  Answer -> In React, rendering is the process where React figures out what the UI should look like at any given point in time.

  When a component renders, React first calls the component function, which executes the logic inside it. That function returns JSX, which React converts into a Virtual DOM representation.

  Then React compares this newly generated output with the previous render output to understand what has changed.

  Based on this comparison, React prepares updates for the real DOM—but an important point is that rendering itself does not mean the DOM is updated immediately.

  So rendering is mainly a calculation phase, where React determines what should change, while the actual DOM updates happen later during the commit phase.

  In short, rendering is React figuring out the UI, not actually painting it on the screen.

  Rendering ≠ DOM update
  Rendering = calculation phase

---------------------------------------------------------------------------------------------------