1. Value Objects
2. Service Objects
3. Form Objects
4. Query Objects
5. View Objects
6. Policy Objects
7. Decorators

============

1. Value Objects
A Value Object represents a concept whose identity is based on its value rather than an ID. I use it when an attribute or small group of attributes has meaningful behavior of its own, such as Money, PhoneNumber or Address.

Suppose we have a user model:

class User < ApplicationRecord
  ...
end

Initialy, we only have : 
    user.phone_number
    # => "+919876543210"

Later, bussiness logic gets involved with the phone number, like country_code, valid?, formatted, internation? etc.
so we have to like this:

    class User < ApplicationRecord
        def phone_country_code
        end

        def valid_phone?
        end

        def formatted_phone
        end

        def international_phone?
        end
    end

So, these will unnecessarily grow the model.

The better approach is to extract the logic in a seperate class and use a custom Type:

In model:
class User < ApplicationRecord
    attribute :phone_number, PhoneNumberType.new
end


# Custom Type: 
class PhoneNumberType < ActiveRecord::Type::Value
  def cast(value)  # Will run when we read from db
    return if value.nil?
    return value if value.is_a?(PhoneNumber) # avoid double-wrapping if already PhoneNumber object.

    PhoneNumber.new(value)
  end

  def serialize(value) # Will run when we write to db
    return if value.nil?
    value.to_s
  end
end

#Class which holds the extacted logic.
class PhoneNumber
  def initialize(number)
    @number = number
  end

  def country_code
    ...
  end

  def formatted
    ...
  end

  def valid?
    ...
  end
end

Now: 
user.phone_number
# => PhoneNumber object

------------------------------------------------------------------------------------------------------
2.Service Objects
use service object in cases like: 
    a. The action/logic is complex.
    b. Multiple models are involved.
    c. External services involved
    d. There are multiple strategies to perfom the same action , for example: authentication
            Password authentication
            OR
            Access-token authentication

        here we can create a service like UserAuthenticator.

------------------------------------------------------------------------------------------------------
3.Form Objects
One form submission may coordinate multiple models, so represent that form as its own object.
Form Objects are useful when multiple ActiveRecord models are updated by a single form submission.

Suppose we have a signup form, when submitting this create user and company.
We have two model: User and Company

If we put the company creation logic inside the User like: 
class User < ApplicationRecord

  def signup
    company = Company.create(...)
    ...
  end

end

This is very bad idea.

Instead we should use a from object.
    class SignupForm
        include ActiveModel::Model

        attr_accessor :name, :email, :company_name

        def save
            ActiveRecord::Base.transaction do
                user = User.create!( name: name, email: email)

                company = Company.create!( name: company_name )
            end

            true
        rescue ActiveRecord::RecordInvalid =>
            e.record.errors.each do |error|
                errors.add(error.attribute, error.message)
            end
            # OR for API 
            errors.add(e.record.class.name.underscore, e.record.errors.full_messages)
            false
        end
    end

Then in the controller:
    class SignupsController < ApplicationController
      def new
        @signup_form = SignupForm.new
      end

      def create
        @form = SignupForm.new(form_params)

        if @form.save
            redirect_to dashboard_path
            # OR for API
            render json: { message: "Signup successful"}, status: :created
        else
            render :new
            # OR for API
            render json: { errors: form.errors.to_hash }, status: :unprocessable_entity
        end
      end
    end

  In Views: 
    <%= form_with model: @signup_form do |form| %>
      <%= form.text_field :name %>
      <%= form.email_field :email %>
      <%= form.text_field :company_name %>

      <%= form.submit "Sign Up" %>
    <% end %>

If the persistence logic of form object become complex then we can combine it with service object.

------------------------------------------------------------------------------------------------------
4.Query Objects
A Query Object encapsulates a complex query and is responsible for returning a result set based on specific business/query rules.

Suppose a model contains multiple scopes and class methods which consist some databses queries.
The problem started when the query become extremely complex.

In such cases we have to extarct the queries inside the Query object.

Example:
class AbandonedTrialsQuery

  def initialize(scope = User.all)
    @scope = scope
  end

  def call
    @scope
      .where(...)
      .joins(...)
      .where(...)
  end

end

We can use like this:
AbandonedTrialsQuery.new(User.all).call


An ActiveRecord::Relation can be sended as input to query object.
Example:

base = User.where(active: true)
query = AbandonedUsersQuery.new(base)
query.call

------------------------------------------------------------------------------------------------------
5. View Objects / Presentor

Suppose , we do like this in model:
    class User < ApplicationRecord

        def display_name
            "#{first_name} #{last_name}"
        end

        def status_color
            ...
        end

        def dashboard_label
            ...
        end

        def formatted_revenue
            ...
        end

    end

    If the logic is olny for UI or views, then this should not be present in the model.

    In such case we should extract the logic to a View Object:

    class UserView
        def initialize(user)
            @user = user
        end

        def display_name
            "#{@user.first_name} #{@user.last_name}"
        end

        def status_label
            @user.active? ? "Active" : "Inactive"
        end
    end


    In controller:

    class UsersController < ApplicationController
        def show
            @user = User.find(params[:id])
            @user_view = UserView.new(@user)
        end
    end


    In the view we can use like:
      <%= @user_view.display_name %>               

>------------------------------------------------------------------------------------------------------
6.Policy Objects
Policy Object primarily encapsulate read-side/domain rule.
We should use the policy object for the authorisation insated of writing complex logic in controllers.
The core bussiness rule of Policy object is: Who and Can. For exmaple: "Who is considered active?"  and "Can this user access this resource?"

class ActiveUserPolicy

  def initialize(user)
    @user = user
  end

  def active?
    @user.email_confirmed? &&
      @user.last_login_at > 2.weeks.ago
  end

end

Usage:
policy = ActiveUserPolicy.new(user)
policy.active?


------------------------------------------------------------------------------------------------------
7.Decorator.
Decorator wraps existing object with additional behavior.
It creates the additional responsibility layer over existing interface.

Suppose we have a Comment model:
This model normally creates the comments.
But in some cases, after creating the comment is also post it to facebook/instagram etc.

We can put this logic in model like  this:

class Comment < ApplicationRecord
  belongs_to :user
  belongs_to :post

  after_create :post_to_facebook

  validates :body, presence: true
end

But it increases the responsibilty of comment model.

As this is an extra functionality, so we can use the decorator.

In Model:

class Comment < ApplicationRecord
  belongs_to :user
  belongs_to :post

  validates :body, presence: true
end


In Decorator: #app/decorators/facebook_comment_notifier.rb

class FacebookCommentNotifier
  def initialize(comment)
    @comment = comment
  end

  def save
    result = @comment.save

    post_to_facebook if result

    result
  end

  private

  def post_to_facebook
    puts "Posting comment #{@comment.id} to Facebook..."

    # Facebook API call
    # FacebookClient.post(@comment.body)
  end
end


In Controller:

class CommentsController < ApplicationController
  def create
    comment = Comment.new(comment_params)

    if params[:post_to_facebook] == "true"
      comment = FacebookCommentNotifier.new(comment) # here we get the object of FacebookCommentNotifier
    end

    if comment.save  # this is not the Comment model object, this is FacebookCommentNotifier class object
      redirect_to post_path(comment.post)
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  def comment_params
    params.require(:comment).permit(:body, :post_id, :user_id)
  end
end


=======================================================================
Policy vs Query:
    Query object fetch the data from database.
    Policy Object evaluate the business rule on already loaded objects.

========================================================================
Agar interviewer tumse “7 Patterns to Refactor Fat ActiveRecord Models” ke baare mein poochta hai, to sirf seven names mat bolna.

Tumhe ye thought process dikhana hai:

    Fat ActiveRecord Model
            ↓
    Identify responsibilities
            ↓
    Is this persistence/entity behavior?
            |
        YES ──→ Keep in Model
            |
            NO
            ↓
    What kind of responsibility?
            |
            +── Value → Value Object
            |
            +── Workflow → Service Object
            |
            +── Multiple-model form → Form Object
            |
            +── Complex SQL → Query Object
            |
            +── Presentation → View Object
            |
            +── Business rule/decision → Policy Object
            |
            +── Extra layered behavior → Decorator