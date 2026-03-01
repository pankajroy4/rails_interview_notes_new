Controllers
===========
➤In MVC, Controller is the middleman between Model (data) and View (UI). It receives requests, interacts with the model, and renders a response.

➤Controller Filters (before_action, after_action, around_action)
  🔸around_action:
     →Wraps around an action.

      around_action :time_logger
      def time_logger
        start = Time.now
        yield
        Rails.logger.info "Action took #{Time.now - start} seconds"
      end

     →We should use around_action when we need both before and after logic around the action (e.g., benchmarking, database transactions).
    
    NOTE:

    The filter 'around_action' wraps around the 'controller-action' and all other callbacks (except after_action).
    Think of it like a block that executes before and after the action.
    You must yield inside the filter callback, otherwise the controller-action never runs.

    class PaymentsController < ApplicationController
      around_action :wrap_in_transaction

      def create
        # If something fails, transaction will rollback
        Payment.create!(payment_params)
      end

      private

      def wrap_in_transaction
        ActiveRecord::Base.transaction do
          #we can do some stuff here.
          yield   # This yield statement will runs the PaymentsController#create action here. So technically create action will runs inside a transaction block.
        end
      end
    end

    So, around_action filter runs efore and after the controller-action

➤Strong Parameters
  Prevents Mass Assignment Vulnerabilities.
  we use Strong Parameters to whitelist allowed attributes and protect against malicious users updating sensitive fields (like role or admin).

  def book_params
    params.require(:book).permit(:title, :author, :price)
  end

➤Rendering & Redirecting
 🔸Rendering
    render :edit       # renders edit.html.erb
    render json: @book # returns JSON response
    render plain: "OK" # returns plain text

 🔸Redirecting
    redirect_to books_path
    redirect_to @book, notice: "Book created!"

➤Difference between render and redirect_to?”
  render → just shows a view (no new request).
  redirect_to → issues a new request to another URL (client-side).

➤Sessions & Flash
  Sessions → store data across requests.
  Flash → store temporary messages.

  session[:user_id] = @user.id
  flash[:notice] = "Logged in successfully"
  flash[:alert] = "Invalid email or password"

➤Difference between flash and flash.now?”
  flash → persists for the next request.
  flash.now → available only for the current request.

➤How do we handle errors in controllers?”
  Using rescue_from in controller or ApplicationController for global handling.
  rescue_from ActiveRecord::RecordNotFound, with: :not_found

➤Namespacing Controllers
  namespace :admin do
    resources :users
  end

  This maps to Admin::UsersController

➤Advanced Controller Patterns
 🔸Service Objects:
   - Keep controller thin.
   - Move business logic to service.

  class PaymentsController < ApplicationController
    def create
      result = PaymentProcessor.call(params[:amount], current_user)
      if result.success?
        redirect_to dashboard_path, notice: "Payment successful"
      else
        redirect_to checkout_path, alert: result.error
      end
    end
  end

  Move business logic into Service Objects / Models.
  Use Concerns for shared controller logic.
  Keep controllers focused on request handling only.
  This keeps controllers clean.

➤Prevent CSRF attacks in Rails controllers:
  Rails includes CSRF protection by default. Rails inserts a hidden token (authenticity_token) in every form.
    protect_from_forgery with: :exception
  It uses a hidden token in forms (authenticity_token). If token does not match, request is rejected.

➤When to skip CSRF protection
  Some actions (like payment callbacks or webhooks) receive requests from external services (Stripe, Razorpay, PayPal, etc.).
  These requests do not include Rails authenticity_token.
  If CSRF is enforced, such requests would always fail.
  So we skip CSRF check for only those actions:

  class PaymentsController < ApplicationController
    skip_before_action :verify_authenticity_token, only: [:callback_handler, :webhook_handler, :get_payment_status]
  end
  Important: Always validate these requests using HMAC signatures, API keys, or provider verification (since CSRF is disabled).

➤Performance optimizations in controllers:
  Use eager loading (includes) to prevent N+1 queries.
  Use fragment caching in views (but controlled from controllers).
  Use pagination (Kaminari, Pagy) for large records.
  Offload background jobs (e.g. emails) to Sidekiq.

