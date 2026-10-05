🔸Hotwire
    Hotwire stands for "HTML over the wire". It is the overall approach and toolkit introduced by Basecamp to build reactive apps without writing much JavaScript.

    Hotwire is a Rails approach to building modern apps using server-rendered HTML instead of heavy frontend frameworks. It includes Turbo for handling navigation and real-time DOM updates, and Stimulus for adding lightweight JavaScript behavior. Together, they allow us to build reactive applications with minimal JavaScript.

    The core idea of Hotwire is:
      Instead of sending JSON and rendering on the client (React style),
      send HTML from the server and update the DOM directly.

    Hotwire includes Turbo and Stimulus. Hotwire = Turbo + Stimulus

🔸Turbo
    Turbo Handles page updates without reloads. Turbo replaces traditional full-page reloads with fast partial updates.
    Turbo has 3 main parts: Turbo Drive, Turbo Frames and Turbo Streams

   🔹Turbo Drive:
      Turbo Drive offers SPA-like navigation.
      Turbo:
        Intercepts link clicks and form submissions
        Makes AJAX requests behind the scenes
        Replaces <body> without full reload
      
      So, in result it Feels like SPA, but no React needed.

    🔹Turbo Frames:
        Turbo frames are used for Partial page updates.
        We break page into independent sections using turbo frame tag.
        Only update specific parts
        Example:
          <turbo-frame id="comments">
            <%= render @comments %>
          </turbo-frame>
      
          Here, Only comments section reloads, not whole page

    🔹Turbo Streams:
        Turbo streams are used for Real-time updates.

        Turbo Streams use ActionCable under the hood to establish WebSocket connections. The client subscribes using turbo_stream_from, and the server broadcasts HTML fragments via Turbo Streams. These fragments are sent over WebSockets and directly applied to the DOM without requiring any client-side rendering logic.

        Turbo Streams allow you to asynchronously update parts of a webpage without requiring a full page reload. It allows for actions like appending, prepending, or replacing elements in the DOM.

        When an event happens on the server (e.g., a new comment is added), ActionCable will push a message (usually in the form of a Turbo Stream update) to the clients connected to the channel.
        On the client side, Turbo Streams will use this message to update the relevant part of the page without a full reload.

        Turbo streams used for Chat apps, Notifications, Live dashboard etc.

        NOTE: WebSocket is the underlying communication protocol, while Action Cable is Rails framework for managing WebSocket connections, channels, subscriptions, and broadcasting. Turbo Streams can use Action Cable to push real-time HTML updates to the browser.

        Working of Turbo streams internally:
          1.Client subscribes 
              <%= turbo_stream_from "messages" %>>

            Browser opens WebSocket connections via ActionCable

          2.Server broadcasts
              Turbo::StreamsChannel.broadcast_append_to(
                "messages",
                target: "messages",
                partial: "messages/message",
                locals: { message: @message }
              )

          3.ActionCable transmits
              Uses WebSocket connection
              Sends HTML payload (not JSON)

          4. Turbo processes response
              Browser receives:
                <turbo-stream action="append" target="messages">
                  <template>...</template>
                </turbo-stream>

              Turbo JS:
                Parses it
                Finds target
                Updates DOM

🔸Stimulus:
    Stimulus is a minimal Lightweight JavaScript framework for adding behavior to HTML.
    We attach behavior using data-* attributes like data-controller, data-action, data-value etc.

    Example: 
      <button data-controller="hello" data-action="click->hello#greet">
        Click me
      </button> 

      #app/javascript/controllers/hello_controller.js
      import { Controller } from "@hotwired/stimulus";

      export default class extends Controller {
        greet() {
          alert("Hello!");
        }
      }

=============================================================================================
🔸Turbo & Stimulus Interview Q&A

  Q1. How does Turbo handle form submission?
    Turbo Drive catches the form submit and sends it with fetch in the background, so there is no full page reload. What happens next depends on what the server sends back:
      - Create works: redirect. Turbo follows the redirect and swaps the page body.
      - Validation fails: render the form again with status 422. Turbo then swaps the page with the errors shown.

      def create
        @post = Post.new(post_params)
        if @post.save
          redirect_to @post, notice: "Post created"
        else
          render :new, status: :unprocessable_entity
        end
      end

    Interview tip: Without the 422 status, Turbo does not treat the response as a failed form, so the error page may not show up as expected.

  ------------------------------------------------------------------------------------------------------
  Q2. How does Turbo know which frame to replace?
    It matches by id. When a link or form is inside <turbo-frame id="comments">, Turbo requests the page, looks for a frame with the same id in the response, and replaces only that frame.
    If the link is outside the frame, use data-turbo-frame="comments" to point it at the right frame.
    data-turbo-frame="_top" means "do a full page visit instead of a frame update".

  ------------------------------------------------------------------------------------------------------
  Q3. How do you implement inline editing?
    Wrap each row in a frame with a unique id, usually dom_id(post):
      <%= turbo_frame_tag dom_id(post) do %>
        <%= render "post", post: post %>
        <%= link_to "Edit", edit_post_path(post) %>
      <% end %>

    The edit.html.erb page has a form wrapped in a frame with the same id. When the user clicks Edit, only that row changes into a form. After update, the controller redirects or renders the show partial, and only that row is replaced.
    Interview tip: The "Cancel" link should also be inside the same frame, so the user can get back to the normal row.

  ------------------------------------------------------------------------------------------------------
  Q4. How do you implement a modal with Turbo?
    Simple way:
      1. Put an empty <%= turbo_frame_tag "modal" %> at the bottom of the layout. >
      2. Link to the form with data-turbo-frame="modal". The form loads inside that frame.
      3. Style the frame as an overlay. A small Stimulus controller handles closing it (clicking the backdrop or pressing Esc).
    Closing it means replacing the frame with an empty one.
    Common bug: After a successful submit, if the controller redirects to a page that has no "modal" frame, Turbo shows a "content missing" error. Fix it by using a Turbo Stream response that clears the modal, or by setting data-turbo-frame="_top" on the form.

  ------------------------------------------------------------------------------------------------------
  Q5. How do Turbo Streams work?
    The server sends small HTML chunks wrapped in a <turbo-stream> tag. Each one says what to do and where:
      <turbo-stream action="append" target="comments">
        <template>...html...</template>
      </turbo-stream>

    Actions: append, prepend, before, after, replace, update, remove (and morph in newer Turbo versions).
    There are two ways to send them:
      - As a response to a form submit: create.turbo_stream.erb, or respond_to { format.turbo_stream }.
      - Over WebSockets, when something changes on the server (broadcasts).

  ------------------------------------------------------------------------------------------------------
  Q6. How do you broadcast Turbo Streams?
    The page subscribes to a stream with turbo_stream_from. The model broadcasts when a record changes:

      <%= turbo_stream_from @post %>

      class Comment < ApplicationRecord
        belongs_to :post
        after_create_commit -> { broadcast_append_to post, target: "comments", partial: "comments/comment", locals: { comment: self } }
      end

    Interview tip: Use after_create_commit, not after_create. Commit runs after the row is saved, so the page loads the right data. Turbo 8 also has broadcasts_refreshes, which tells the page to reload its data instead of sending HTML.

  ------------------------------------------------------------------------------------------------------
  Q7. How does Action Cable fit with Turbo?
    Action Cable is the WebSocket layer in Rails. turbo_stream_from creates a <turbo-cable-stream-source> tag, which connects through Action Cable (Turbo::StreamsChannel). When you broadcast, Turbo just sends HTML over that connection.
    Turbo signs stream names, so users cannot subscribe to streams they should not see.
    In production, Action Cable needs an adapter like Redis, so that broadcasts reach every app server.

  ------------------------------------------------------------------------------------------------------
  Q8. How do you update UI after a Sidekiq job?
    The Sidekiq job does the slow work and then broadcasts the result:

      class GenerateReportJob
        include Sidekiq::Job
        def perform(report_id)
          report = Report.find(report_id)
          report.generate!
          Turbo::StreamsChannel.broadcast_replace_to(
            report.user, target: dom_id(report),
            partial: "reports/report", locals: { report: report }
          )
        end
      end

    Interview tip: Pass ids to the job, not full objects. Run the broadcast after the data is saved. If the user was not on the page when the job finished, they miss the update, so the page should also load the latest data when it opens.

  ------------------------------------------------------------------------------------------------------
  Q9. How do you handle validation errors with Turbo?
    Two common ways:
      1. Full form response: render :new with status 422. Turbo swaps the form with the error messages.
      2. Only the form: wrap the form in turbo_frame_tag, so only the form area is replaced.
    You can also send a turbo_stream.replace for the form when you need to update more than one place.
  
  ------------------------------------------------------------------------------------------------------
  Q10. How do you disable Turbo for a particular link?
    Add data-turbo="false" to the link or form:
      <%= link_to "Download CSV", export_path, data: { turbo: false } %>  >

    You can also put it on a parent element to disable Turbo for a whole section.
    Use it for file downloads, pages that need a real reload, or JavaScript libraries that only run on a fresh page load.

  ------------------------------------------------------------------------------------------------------
  Q11. How would you implement real-time notifications?
    Give each user their own stream, so only that user gets their notifications:
      <%= turbo_stream_from current_user, :notifications %>

      class Notification < ApplicationRecord
        belongs_to :user
        after_create_commit -> {
          broadcast_prepend_to [user, :notifications], target: "notifications", partial: "notifications/notification", locals: { notification: self }
        }
      end

    Also update the unread count badge with a broadcast_update_to. When the user opens the page, load the latest notifications from the database, in case some were missed while they were offline.

  ------------------------------------------------------------------------------------------------------
  Q12. How would you prevent duplicate Turbo Stream updates?
    Why duplicates happen:
      - The page subscribes to the same stream twice (for example, once in the layout and again in the page).
      - Two callbacks broadcast for the same event.
      - A Sidekiq job retries and broadcasts again.
    How to fix it:
      - Use replace or update instead of append. Replacing the same element twice gives the same result, but appending adds a second copy.
      - Target elements with dom_id, so a repeated update finds the same element.
      - Broadcast from one place only, in after_commit.
      - Make jobs idempotent, so a retry does nothing new.

  ------------------------------------------------------------------------------------------------------
  Q13. How do you handle DOM IDs?
    dom_id gives you a consistent id:
      dom_id(post)          # "post_12"
      dom_id(post, :edit)   # "edit_post_12"
      dom_id(Post.new)      # "new_post"
    Turbo Frames and Turbo Streams use these ids as targets, so the server knows exactly which element to change.
    Interview tip: Each id must be unique on the page. If the same record appears twice (for example, in a list and in a sidebar), updates can change the wrong one.

  ------------------------------------------------------------------------------------------------------
  Q14. What happens to Stimulus controllers during Turbo navigation?
    When Turbo Drive swaps the page body, the old elements are removed and the new ones are added. Stimulus watches the DOM, so it automatically calls disconnect() on the old controllers and connect() on the new ones. You do not need to set them up again.
    Interview tip: Remove event listeners, timers, and subscriptions in disconnect(), so they do not leak between pages.

  ------------------------------------------------------------------------------------------------------
  Q15. connect() vs initialize()?
    initialize() runs once, when the controller object is first created. Use it for one-time setup that does not touch the DOM.
    connect() runs every time the controller is attached to an element. That includes each Turbo visit. Use it for adding listeners, starting timers, and reading targets or values.
    Simple rule: Put DOM work and listeners in connect(), and clean them up in disconnect().

  ------------------------------------------------------------------------------------------------------
  Q16. How do you preserve state across Turbo navigation?
    Options:
      - data-turbo-permanent: Turbo keeps the current element when it swaps the page (the new page must have the same id).
      - Turbo Frames: the frame state stays if the frame is not in the new page's ' changed area.
      - localStorage or sessionStorage: for small values like a selected tab or a draft text.
    Example: A music player in the layout, with a permanent id, keeps playing while the user moves between pages.

  ------------------------------------------------------------------------------------------------------
  Q17. data-turbo-permanent kya hai?
    It is an attribute you put on an element that needs to stay the same across page visits. When Turbo visits a new page, it looks for an element with the same id that has data-turbo-permanent. If it finds one, it keeps the current element instead of replacing it.

      <audio id="player" data-turbo-permanent controls src="..."></audio>

    Common uses: audio or video players, a sidebar that stays open, a chat input.

  ------------------------------------------------------------------------------------------------------
  Q18. What is Turbo morphing?
    Morphing is a Turbo 8 feature. Instead of replacing the whole body or element, Turbo compares the old DOM with the new HTML and changes only the parts that are different.
    Benefits: the scroll position, focus, and typed text in unchanged parts stay as they are.
    Turn it on with a meta tag in the layout:
      <meta name="turbo-refresh-method" content="morph">
    You can also use data-turbo-permanent together with morphing, for elements that must never change.

  ------------------------------------------------------------------------------------------------------
  Q19. When would you choose React over Hotwire?
    Hotwire is a good fit when:
      - The app is mostly server-rendered CRUD pages, forms, and lists.
      - You have a Rails monolith and a small team.
      - Real-time updates are simple, like chat messages or notifications.
    React is a better fit when:
      - The UI is very interactive, like a drawing canvas, a spreadsheet-style editor, or drag-and-drop boards.
      - There is a lot of complex client-side state that must work offline.
      - You need the same frontend logic for a mobile app, or you want a separate frontend that uses a JSON API.
    Interview tip: You do not have to pick only one. Many teams use Hotwire for most pages and add a small React component for one complex screen.

=================================================================================================
🔸Rails UJS (Unobtrusive JavaScript):
    Rails UJS (introduced in Rails 3.1) was a way to add JavaScript functionality to a Rails app while keeping the JavaScript code separate from the HTML.
    It provided client-side functionality for things like:
      Handling AJAX requests (form submissions, links, etc.).
      Updating parts of the page dynamically without a full page reload.
      Triggering remote requests, such as submitting forms via AJAX.

    UJS would hook into actions like data-remote="true" to send AJAX requests and update the page dynamically.

    In modern rails app, Turbo replaces the UJS.

    Example using UJS:
      Lets say you have a Comment model and want to submit a comment via AJAX using Rails UJS.

      #views/comments/create.html.erb
      <%= form_with model: @comment, data: { remote: true }, id: 'comment-form' do |f| %>
        <%= f.text_field :content %>
        <%= f.submit %>
      <% end %>

      Here:
        data: { remote: true } makes this form submit asynchronously (AJAX).
        When the form is submitted, Rails will make an AJAX request (via JavaScript) to the create action in your CommentsController.

    
      In the controller, we handle the form submission as usual, but we also need to account for the AJAX request and send back a response that the client can use to update the page dynamically.

        class CommentsController < ApplicationController
          def create
            @comment = Comment.new(comment_params)

            if @comment.save
              respond_to do |format|
                format.html { redirect_to comments_path }  # For non-AJAX requests
                format.js   # For AJAX requests, we render a JavaScript response
              end
            else
              render :new
            end
          end

          private

          def comment_params
            params.require(:comment).permit(:content)
          end
        end

      Since the form is submitted via AJAX, the server responds with JavaScript to update the page. This is where the UJS handler comes into play.

      // create.js.erb
        $("#comments").append("<%= j render(@comment) %>");
        $("#comment-form")[0].reset(); // clear the form after submission

      <!-- _comment.html.erb -->
        <div class="comment">
          <p><%= comment.content %></p>
        </div>

      <!-- _comment.html.erb -->
        <div id="comments">
          <%= render @comments %>
        </div>

    Turbo replaces Rails UJS by removing the need for client-side JavaScript responses. Instead of .js.erb, it relies on server-rendered HTML or Turbo Stream responses to update the DOM automatically.

      Example:
        <!-- create.html.erb -->
          <%= form_with model: @post %>

        <!-- create.turbo_stream.erb -->
          <turbo-stream action="append" target="posts">
            <template>
              <%= render @post %>
            </template>
          </turbo-stream>
      
=================================================================================================

🔸Key difference between Turbo and UJS:

  1.Declarative vs. Imperative:
      With Rails UJS, you needed to use a lot of JavaScript logic (e.g., data-remote="true", remote: true, jquery_ujs), and write event listeners to handle interactions.

      With Turbo, the approach is more declarative. You define the structure of your page using Turbo Frames and Turbo Streams, and Turbo automatically handles things like updating parts of the page or navigating without a reload.

  2.AJAX is Implicit:
      In Rails UJS, you manually marked links and forms to be remote (with data-remote attributes or remote: true), and wrote handlers for AJAX responses.

      In Turbo, much of the AJAX handling is done for you automatically without needing to define remote actions or custom JavaScript. Turbo Drive and Turbo Frames are automatic and intuitive.

  3.Real-Time Updates:
      Turbo Streams replace the need for client-side JavaScript to manually subscribe to WebSocket channels and handle real-time updates (which was possible using UJS combined with ActionCable).

      Turbo Streams are simpler and work declaratively, where the server pushes updates in real-time directly into the page.

  4.No Need for External JavaScript Libraries:
      Rails UJS often required you to rely on external JavaScript libraries (e.g., jQuery) to perform AJAX and DOM manipulations.

      Turbo is designed to work with minimal external JavaScript, relying mostly on the built-in functionality of Turbo and Stimulus (a small JavaScript framework for adding interactivity to pages).


  Example:
    Rails UJS (Using data-remote for AJAX):

      <%= form_with model: @comment, data: { remote: true } do |form| %>
        <%= form.text_field :content %>
        <%= form.submit %>
      <% end %>

      With Rails UJS, the form would be submitted via AJAX, and you would need to handle the response and update the page accordingly (using custom JavaScript).

    Turbo (Using Turbo Frames):

      <%= form_with model: @comment, data: { turbo_frame: "comments" } do |form| %>
        <%= form.text_field :content %>
        <%= form.submit %>
      <% end %>

      In this Turbo example, when the form is submitted, it only replaces the contents of the "comments" Turbo Frame with the updated content. You do not need to manually handle AJAX or write any custom JavaScript for this.


===============================
- Ruby on Rails ✅
- PostgreSQL ✅
- REST APIs. ✅
- OOP ✅
- Git ❌
- multi-tenant SaaS ❌
- RSpec ✅
- Redis ✅
- Sidekiq ✅
- AWS ❌
- Rails security ✅
- SQL/joins/relationships ✅
- DB partitioning ✅
- scaling Rails applications ✅

========================================

Priority 1 — Ruby/Rails 
- Ruby OOP ✅
- modules vs classes ✅
- blocks/procs/lambdas ✅
- metaprogramming ✅
- method_missing ✅
- Rails request lifecycle ✅
- MVC ✅
- ActiveRecord ✅
- associations ✅
- validations ✅
- callbacks ✅
- scopes ✅
- concerns ✅
- service objects ✅
- serializers ❌
- API-only Rails ❌ 
- authentication ❌
- authorization ✅
- Rails security ✅
- Hotwire ❌

🔥 Priority 2 — PostgreSQL
- joins ✅
- indexes ✅
- composite indexes ✅
- transactions ✅
- isolation levels ✅
- N+1 ✅
- query optimization ✅
- EXPLAIN ✅
- normalization ✅
- partitioning ✅
- locks ✅
- database scaling ✅


🔥 Priority 3 — Redis + Sidekiq
Tumse almost certainly questions aa sakte hain:
  Why Sidekiq? ✅
  How does Sidekiq work? ✅
  Redis ka role kya hai? ✅
  Job retry kaise hota hai? ✅
  Idempotency kya hoti hai? ✅
  Duplicate jobs ko kaise handle karoge? ✅

🔥 Priority 4 — System Design
Ye Product Engineer role hai, so:
  - scalable API design ✅
  - multi-tenancy ❌
  - caching ✅
  - background processing ✅
  - rate limiting ✅
  - database scaling ✅
  - horizontal scaling ✅
  - load balancing ✅ 
  - queues ✅
  - failure handling ❌


ProMobi Technologies is a SaaS product company that builds enterprise products around endpoint management, security and communication. Its flagship product is Scalefusion, a Unified Endpoint Management platform that helps organizations centrally manage and secure devices such as Android, iOS, Windows and macOS endpoints. The company also has products like OneIdP, Veltar and NuovoPay.
