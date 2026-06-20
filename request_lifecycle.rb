How Rails Loads a Request (Request Lifecycle)
=============================================
  ➤ Browser sends HTTP request
  ➤ Hits the Rack middleware
  ➤ Enters Rails router (routes.rb)
  ➤ Routes to the correct controller + action
  ➤ Executes before_action filters
  ➤ Calls the action method
  ➤ Returns HTML/JSON response
  ➤ Runs after_action filters
  ➤ Response sent back to Rack → Web Server → Browser


Senior-Level interview Explanation:
Answer -> I usually explain it in layers, from the outside world down to Rails internals.

    1.Browser Sends an HTTP Request:
      A user types a URL or clicks a link.
      At this point, the browser sends an HTTP request over the network.
      Rails is not involved yet.

    2.Request First Hits the Web Server (Nginx/Apache):
      In production, the request always hits a web server first, usually Nginx (most common) or Apache (less common nowadays).

      What Nginx does here:
        Terminates SSL (HTTPS → HTTP internally)
        Handles static assets (CSS, JS, images)
        Acts as a reverse proxy
        Forwards dynamic requests to the app server

        Example: Browser → Nginx → Puma

      If the request is for a static file like /assets/app.css,
      Nginx serves it directly and Rails is never invoked. (If configured)

    3.Nginx Forwards the Request to the App Server (Puma / Unicorn):
      For dynamic requests, Nginx forwards the request to a Rack-compatible app server, usually Puma (default and most common) or Unicorn / Passenger (older setups)

      The app server is responsible for:
        Managing Ruby processes / threads
        Passing the request into the Rack stack

    4.Request Enters the Rack Layer:

      Rails is a Rack application, so every request goes through Rack first.
      At this point, the request becomes a Rack environment hash (env).

      Example responsibilities of Rack middleware:
        Session handling
        Cookies
        Logging
        Request ID generation
        Parameter parsing
        Exception handling

      Common middleware examples:
        ActionDispatch::Cookies
        ActionDispatch::Session
        Rack::Runtime
        ActionDispatch::ShowExceptions

      This layer is framework-agnostic and happens before Rails routing.

    5.Rails Router (routes.rb) Matches the Request:
      Now Rails takes over.
        The router:
          Matches HTTP method + path
          Determines controller, action, and params

        If no route matches → 404 Not Found

    6.Controller instantiation (इन्स-टैन-शी-एशन):
      Rails:
        instantiates (इन्स-टैन-शिएट्स) the controller class
        Injects request, response, params, session, cookies

      At this stage:
        No action code has run yet
        Filters and callbacks are prepared

    7.before_action Filters Run:
      Before the action method executes, Rails runs filters like:
        Authentication (authenticate_user!)
        Authorization (authorize @post)
        Parameter sanitization
        Setup logic

      If a before_action:
        Redirects
        Renders
        Raises an exception

      Then the actual action never runs.

    8.Controller Action Executes:
      Now the action method runs. 

      This is where:
        Business logic runs
        Database queries happen via Active Record
        Service objects may be invoked

    9.Rendering or Response Building:
      After the action:
        If render is called → view is rendered
        If redirect_to → response is prepared
        If API → JSON is serialized

      Rails builds an ActionDispatch::Response object containing: Status code ,Headers, Body

    10.after_action and around_action Filters Run
        After the response is prepared:
          Logging
          Metrics
          Auditing
          Cleanup tasks
          around_action wraps the entire request lifecycle.

    11.Response Goes Back Through Rack Middleware
        The response now travels back up the middleware stack.
        At this stage:
          Headers may be modified
          Cookies are written
          Sessions are committed
          Exceptions are logged

    12.App Server Sends Response to Web Server:
      Puma sends the HTTP response back to Nginx.

    13.Nginx Sends Response to Browser:
      Nginx:
        Adds final headers
        Compresses response (gzip / brotli)
        Sends it back to the browser

    14.Browser Renders the Response
      The browser:
        Parses HTML
        Loads assets
        Executes JavaScript
        Displays the page

One-Line Summary:
  In production, a Rails request flows from the browser to Nginx, then to the app server like Puma, through Rack middleware, into the Rails router, controller filters, and action, and then back out through the same layers before reaching the browser.