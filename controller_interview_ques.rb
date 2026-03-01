Scenario-Based Controller Questions:
=====================================
1. Authentication / Authorization
   Scenario: You have an Admin::UsersController where only admins should access. How would you enforce this?
   Answer:
    Use a before_action for authentication + authorization.

    class Admin::UsersController < ApplicationController
      before_action :authenticate_user!
      before_action :authorize_admin!

      def index
        @users = User.all
      end

      private
      def authorize_admin!
        redirect_to root_path, alert: "Access denied" unless current_user.admin?
      end
    end

    In a large app → move logic to Pundit/CanCanCan policies.
    Best Practice: Keep controllers clean → do not mix business rules inside.

2. Rescue & Error Handling
   Scenario: Your controller needs to return a JSON error when a record is not found. How do you handle it?
   Answer:
    Use rescue_from in controller or ApplicationController.

    class ApplicationController < ActionController::Base
      rescue_from ActiveRecord::RecordNotFound, with: :render_not_found

      private
      def render_not_found(exception)
        respond_to do |format|
          format.html { redirect_to root_path, alert: "Not Found" }
          format.json { render json: { error: exception.message }, status: :not_found }
        end
      end
    end

    This ensures consistent error responses across HTML & API.

3. Preventing N+1 Queries
   Scenario: Your UsersController#index lists all users and their posts. Performance is slow. How do you fix it?
   Answer:

    def index
      @users = User.includes(:posts).all
    end

4. Callbacks in Webhooks
   Scenario: You are receiving a Stripe webhook in PaymentsController#callback. The request fails because of missing authenticity token. What do you do?
   Answer:

    class PaymentsController < ApplicationController
      skip_before_action :verify_authenticity_token, only: [:callback]

      def callback
        # Verify using Stripe signature instead
        payload = request.body.read
        sig_header = request.env['HTTP_STRIPE_SIGNATURE']
        event = Stripe::Webhook.construct_event(payload, sig_header, ENV['STRIPE_SECRET'])
        # Process event
      end
    end

    Key Point → Skip CSRF only for external callbacks, validate using HMAC/API signature.

5. Double Render Error
   Scenario: You accidentally wrote this in your controller:

    def show
      render :edit
      redirect_to users_path
    end

6. Transactions with around_action
   Scenario: You want all create actions in OrdersController to run inside a DB transaction. How would you implement it?
   Answer:

    class OrdersController < ApplicationController
      around_action :wrap_in_transaction, only: :create

      def create
        @order = Order.create!(order_params)
        # more DB logic...
      end

      private
      def wrap_in_transaction
        ActiveRecord::Base.transaction do
          yield
        end
      end
    end

    This ensures either all DB changes succeed or all rollback.

7. Different Response Formats
   Scenario: You want BooksController#show to return HTML, JSON, or XML depending on request. How do you do it?
   Answer:

    def show
      @book = Book.find(params[:id])
      respond_to do |format|
        format.html
        format.json { render json: @book }
        format.xml  { render xml: @book }
      end
    end

    Useful for apps that support both browser + API clients.

8. Pagination in Controllers
   Scenario: Your API endpoint /users returns thousands of users and clients complain about response size. How do you fix it?
   Answer:

    def index
      @users = User.page(params[:page]).per(50)  # Kaminari or Pagy
      render json: @users
    end

    Large datasets → always paginate, never return all.

9. Service Object Usage
   Scenario: Your OrdersController#create has too much logic (discounts, inventory, payment). How do you refactor?
   Answer:

    def create
      result = OrderProcessor.call(order_params, current_user)
      if result.success?
        redirect_to order_path(result.order), notice: "Order placed!"
      else
        redirect_to checkout_path, alert: result.error
      end
    end

    OrderProcessor is a PORO service object → keeps controller thin.

10. Security Concern
    Scenario: User tries to update their account and sneaks in admin: true in params. How do you protect against this?
    Answer:
    Use Strong Parameters:

    def user_params
      params.require(:user).permit(:name, :email, :password) # no admin!
    end

    Never allow sensitive fields in params.

11. Rate Limiting
    Scenario: A public API controller is being spammed with requests. How do you protect it?
    Answer:
    Use Rack::Attack or throttling in Nginx/Cloudflare.

    before_action :check_rate_limit
    def check_rate_limit
      if too_many_requests?(request.remote_ip)
        render json: { error: "Rate limit exceeded" }, status: :too_many_requests
      end
    end

12. Interview Curveball
    Scenario: You are asked — What is the difference between using before_action :set_user vs calling User.find(params[:id]) directly inside each action?
    Answer:

    before_action → DRY (Do not Repeat Yourself), centralizes logic.
    Each action only focuses on business logic.
    Improves maintainability and avoids duplication.