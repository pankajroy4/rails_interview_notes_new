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

        Working of Turbo streams internally:
          1.Client subscribes 
              <%= turbo_stream_from "messages" %>>

            Browser opens WebSocket via ActionCable

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