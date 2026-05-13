1. Find 3rd heighest salary from emplyees table.

Answer 1:

  SELECT DISTINCT salary
  FROM employees
  ORDER BY salary DESC
  Limit 1 OFFSET 2;

Answer 2: 

    SELECT salary FROM
      (
        SELECT DISTINCT salary FROM employees
        ORDER BY salary DESC
        LIMIT 3
      ) as top_salary
    ORDER_BY salary ASC 
    LIMIT 1;

Answer 3: 
  SELECT salary FROM (
    SELECT salary, 
      DENSE_RANK() OVER(ORDER_BY salary DESC) as rank 
    FROM employees
  ) as ranked_tbl
  WHERE rank = 3
  LIMIT 1;

Answer 4:

  WITH ranked_tbl AS (
     SELECT salary, 
      DENSE_RANK() OVER(ORDER_BY salary DESC) as rank 
     FROM employees
  )

  SELECT salary FROM ranked_tbl
  WHERE rank = 3
  LIMIT 1;

------------------------------------------------------------------------------------------
What is the differecne between select and join ?
Answer -> In Rails, select and joins serve very different purposes, although both are used while querying data.

select is used to control which columns we want to fetch from the database. By default, Rails selects all columns using SELECT *, but with select, we can limit that to only required fields, which improves performance.
  For example:
    User.select(:id, :email)

  This will only fetch id and email, instead of loading the full user object with all columns.

On the other hand, joins is used to combine data from multiple tables based on associations. It generates an SQL INNER JOIN.
  For example:
    User.joins(:posts)
    
    This will return users who have associated posts by joining the users and posts tables.

We often use them together. For example:
  User.joins(:posts).select('users.name, posts.title')
  
  Here, we are joining tables and selecting only specific fields from both.

one important point is:
  🔸joins does not load associated records like includes does. It is mainly used for filtering or querying.
  🔸select can return partial objects, so accessing non-selected attributes can raise errors.

-----------------------------------------------------------------------------------------------
What is the differecne between find, find_by, find_each and where? Can we pass an array in find method?
Answer -> In Rails, find, find_by, and find_each are all used to retrieve records, but they behave quite differently.

🔸find is used to fetch records by primary key (usually id). Example: User.find(1)
It raises an error (ActiveRecord::RecordNotFound) if the record is not found.
It always expects an ID (or IDs).

We can also pass an array to find method. Example: User.find([1, 2, 3])
This returns multiple records - an array of objects.
But important point: If any one ID is missing, it will raise an error.

🔸find_by is used to fetch a record based on conditions or by columns.
  Example: User.find_by(email: "test@example.com")

  It returns the first matching record.
  If nothing is found, it returns nil (no exception).
  So compared to find, it is safer when we are not sure the record exists.

  I usually use find_by! if I want behavior similar to find but with custom conditions, because it raises an exception if no record is found.

  NOTE: We can pass an array, but not like find([1,2,3]).
        Instead, we pass it as a condition:
          User.find_by(id: [1, 2, 3])
        This generates a query like WHERE id IN (1,2,3)
        But important point: It still returns only the first matching record, not all
        So even if multiple IDs match, you will get just one object.

🔸find_each is used for batch processing over the large datasets.
  Example:
    User.find_each do |user|
      puts user.email
    end

  It loads records in batches (default 1000) to avoid memory issues.
  It is ideal for background jobs, data migrations, or scripts.
  Internally, it uses LIMIT and OFFSET (actually primary key batching).

  Custom batch size example:
    User.find_each(batch_size: 500) do |user|
      puts user.email
    end

🔸where is used to filter records based on conditions and it returns an ActiveRecord::Relation.
  Example:
    User.where(active: true)
  
  Key points:
    It returns a relation, even if only one record matches
    It is chainable, so we can build complex queries: User.where(active: true).where(role: 'admin')
    It does not raise error if no records are found — returns an empty relation
    The query is executed only when we actually need the data, like calling .to_a, .each, .first, etc.

  So, where is mainly used for building flexible, chainable, and lazy database queries, especially when dealing with multiple records.

-----------------------------------------------------------------------------------------------------------
What is scope in rails?
Answer -> In Rails, a scope is a way to define reusable and chainable query logic inside a model. It helps keep our code clean and avoids repeating the same query conditions in multiple places.
We usually define scopes in the model using the scope method along with a lambda.

Examples: 
  class User < ApplicationRecord
    scope :active, -> { where(active: true) }
    scope :admins, -> { where(role: 'admin') }
    scope :created_after, ->(date) { where('created_at > ?', date) }
  end

  Usages:
    User.active
    User.active.where(role: 'admin')
    User.active.admins
    User.created_after(1.week.ago)

NOTE:
  Scopes always return an ActiveRecord::Relation, not an array
  They are lazy, meaning query runs only when needed
  They should be side-effect free (only querying, no updates)
  Scope chaining can fail or behave unexpectedly when it returns nil
    
I use scopes for simple query logic. If the logic becomes complex or involves conditionals, I prefer a class method for better readability.

--------------------------------------------------------------------------------------------------------
What is the difference between scope and class method?
Answer -> In Rails, both scope and class methods are used to define reusable query logic, but there are some important differences in behavior and flexibility.

A scope always returns an ActiveRecord::Relation, even if the condition results in no records.
A class method can return anything — relation, array, nil, or even a boolean.
Scopes are guaranteed to be chainable
Class methods are chainable only if they return a relation

Example:
  scope :active, -> { where(active: true) }

  def self.active
    where(active: true)
  end

-----------------------------------------------------------------------------------------------------------
What is rack?
Answer -> Rack is a middleware interface in Ruby that sits between the Rack-compatible app server (like puma) and the Ruby web application, like Rails. It provides a standard way for app servers and Ruby frameworks to communicate.

When a request comes from the browser, it first goes through Rack, then reaches the Rails application, and the response goes back through Rack to the client.
Rack allows us to insert middleware between the request and response cycle. For example Logging, Authentication, Rate limiting etc.
In Rails, middleware is configured in config/application.rb

Rack defines a very simple contract:
  A request is represented as an env hash
  The application returns a response as an array: [status_code, headers, body]
  Example:
    [200, { "Content-Type" => "text/html" }, ["Hello World"]]

Example of Rack middleware flow:
  Request → Logger → Auth → Rails App → Response
Each middleware can: Modify request, Modify response, Or even stop the request early.

--------------------------------------------------------------------------------------------------------------
What is block, proc, lambda and yield?
Answer -> In Ruby, blocks, procs, and lambdas are all ways to represent executable code

🔸A block is a piece of code passed to a method. It is not an object by default and is commonly used with iterators.
It can not be stored in a variable directly. We can pass only one block to a method.
Example: [1, 2, 3].each { |n| puts n }

🔸A Proc is an object version of a block, so we can store it and pass it around.
In ruby, Both proc and lambda are instance i.e object of inbuilt Proc class.
Proc is flexible for arguments — it will not raise an error if you pass the wrong number of arguments.
In Proc, return exit from the enclosing method mean Proc's return acts like return from the method containing it.'

Example: 
  p = Proc.new { |user| "Hello #{user}" }
  p.call("John") #=> Hello John

🔸A lambda is just a Proc with special rules for "return" and "arguments".
Lambda is strict for arguments — it will raise an error if you pass the wrong number of arguments.
In Lambda, return exits from the lambda itself , not the enclosing method.

Example:  
  my_lambda = ->(name) { puts "Hi #{name}!" }  #OR
  my_lambda = lambda { |name| puts "Hi #{name}!" }

  my_lambda.call("Alice") # Hi Alice!

🔸yield is used to transfer control from a method to the block passed to it, execute that block, and then return control back to the method. So yield is used inside a method to execute the block passed to it.

Example:
  def greet
    yield("Pankaj")
  end

  greet { |name| puts "Hello #{name}" }

If no block is passed, yield raises an error, so we usually check with block_given?

----------------------------------------------------------------------------------------------------
What is Hash and json?
Answer -> In Ruby, a Hash is a native data structure used to store key-value pairs, while JSON is a text-based data format used for data interchange, especially between systems like APIs.

A Hash is an in-memory Ruby object.
Keys and values can be of any Ruby type
Used internally in Rails for things like params, configs, etc.
  Example: user = { name: "Pankaj", age: 25 }

JSON (JavaScript Object Notation) is a string format used to send and receive data, mainly in APIs.
Keys are always strings.
Data is in string format.
Language-independent
  Example:
    { "name": "Pankaj", "age": 25 }


Conversion between Hash and JSON:
  require 'json'
  hash = { name: "Pankaj" }

  json = hash.to_json      # Hash → JSON string
  parsed = JSON.parse(json) # JSON string → Hash

  NOTE: JSON.parse returns a Hash with string keys, not symbols

----------------------------------------------------------------------------------------------------
What is class variable and instance variables in rails?
Answer: An instance variable belongs to a specific object. Each object has its own copy.
Example:
  class User
    def initialize(name)
      @name = name
    end

    def name
      @name
    end
  end

  u1 = User.new("Pankaj")
  u2 = User.new("Rahul")

  puts u1.name #=> Pankaj
  puts u2.name #=> Rahul

  u1 and u2 have different @name values
  Not shared between objects

A class variable is shared across the class and all its instances.
  Example:
    class User
      @@count = 0

      def initialize
        @@count += 1
      end

      def self.count
        @@count
      end
    end
    
  Shared across all instances
  If one object modifies it, all see the change

So instance variables are object-specific, class variables are shared globally within the class hierarchy.

--------------------------------------------------------------------------------------------------------------
What is the difference between select, map, collect and pluck?
Answer ->In Ruby, select, map, and collect are all enumerable methods.

🔸select is used to filter elements based on a condition.
  It return a new array of elements that satisfy the condition.
  The output size may be smaller than input.
  Example:
    [1, 2, 3, 4].select { |n| n.even? } # => [2, 4]

🔸map is used to transform each element in a collection.
  It returns a new array with transformed values.
  The output size is same as input.
  Example:
    [1, 2, 3].map { |n| n * 2 } # => [2, 4, 6]

🔸collect is just an alias of map — they behave exactly the same. There is no functional differecne.
  Example:
    [1, 2, 3].collect { |n| n * 2 } # => [2, 4, 6]

🔸pluck directly queries specific columns from the database.
  It works at DB level, fetches only required columns.
  It does not instantiate ActiveRecord objects.
  It is much more efficient for large datasets.

  Example:
    User.pluck(:name)
    This will generates SQL like: SELECT name FROM users;

  NOTE:
    User.where(active: true).map(&:email)   # loads full objects in memory and then loop over them to extract email.
    User.where(active: true).pluck(:email)  # only emails from DB.
  
--------------------------------------------------------------------------------------------------------------
What is the difference between form_for and form_with?
Answer -> Both form_for and form_with are used to create forms in Rails, but the main difference is that form_with is the newer and more flexible method, while form_for is older and now mostly considered legacy.

Earlier, we used form_for when working with models. It automatically binds the form to a model object, sets the correct URL, and handles things like create vs update based on whether the record is new or persisted.

Later, Rails introduced form_with to unify form helpers. With form_with, we can use it with a model just like form_for, or even without a model by just passing a URL. So it basically replaces both form_for and form_tag.

One important difference is that earlier versions of form_with submitted forms using AJAX by default, whereas form_for used normal HTTP submission. But in newer Rails versions, form_with defaults to normal submission unless we explicitly enable remote.

Also, form_for automatically generates element IDs and classes, while form_with is a bit more minimal and does not include them unless specified.

So overall, in modern Rails applications, we prefer form_with because it is more flexible and is the standard going forward.

Examples:
  <%= form_for @user do |f| %>
    <%= f.text_field :name %>
  <% end %>

  With model:
    <%= form_with model: @user do |f| %>
      <%= f.text_field :name %>
    <% end %>

  Without modal:
    <%= form_with url: "/users" do |f| %>
      <%= f.text_field :name %>
    <% end %>

----------------------------------------------------------------------------------------------
What is form tag?
Answer -> In Rails, form_tag is a helper used to create forms without binding them to a model. It is mainly used when we just need to send some data to a URL, like in search forms or custom actions.

With form_tag, we manually define the URL and the input fields, instead of relying on a model object.

Example:
  <%= form_tag("/search", method: :get) do %>
    <%= text_field_tag :query %>
    <%= submit_tag "Search" %>
  <% end %>

---------------------------------------------------------------------------------------------------
What is the differecne between render and redirect?
Answer: render is used to display a view within the same request. It does not make a new HTTP request. It simply takes a template and renders it directly. Also, the URL in the browser does not change.

On the other hand, redirect_to sends a new HTTP response, telling the browser to make a new request to a different URL. So it is a completely new request-response cycle, and the URL changes in the browser. We usually use flash if we want to pass messages.

For example, after creating a record successfully, we usually use redirect_to to avoid resubmission issues. But if validation fails, we use render to show the same form again with errors, because we want to keep the existing data and errors.

----------------------------------------------------------------------------------------------
In sidekiq, what is the differecne between quiet, stop and dead?
Answer: In Sidekiq, quiet, stop, and dead are related to job processing and lifecycle management.

Quiet is used when we want Sidekiq to stop taking new jobs, but continue processing the ones that are already running. It is mainly used during deployments or graceful shutdowns.

Stop is the next step after quiet. It tells Sidekiq to shut down the process. It waits for current jobs to finish for a limited time, and if they do not, those jobs are pushed back to Redis so they can be retried later. So jobs are not lost.

Dead refers to jobs that have failed multiple times and exhausted their retry limit. These jobs are moved to the Dead Job Queue, where they are no longer retried automatically.

To handle dead jobs, we usually inspect the error, fix the root cause, and then manually retry them from the Sidekiq dashboard or handle them programmatically if needed.

So quiet is for graceful pause, stop is for shutdown, and dead is for jobs that have permanently failed and need manual intervention.


----------------------------------------------------------------------------------------------
What are jQuery selectors?
Answer: In jQuery, selectors are used to find and target HTML elements in the DOM, similar to CSS selectors. Once selected, we can manipulate those elements — like changing text, styles, handling events, etc
We can select elements by ID, class, or tag.
Example:
  $('#id')        // select by id
  $('.class')     // select by class
  $('p')          // select all <p> tags

We can also combine selectors or target specific elements.
Example:
  $('div.active')        // div with class active
  $('ul li:first')       // first li inside ul
  $('input[type="text"]') // input with type text

So jQuery selectors provide a simple and flexible way to access and manipulate DOM elements using CSS-like syntax
----------------------------------------------------------------------------------------------
Replace each vowels by '*' in a given string.
Answer:
    solution 1:
      str = "Elephant"
      vowels = "aeiou"

      new_str = ""
      str.length.times do |i|
        if vowels.include?(str[i].downcase)
          new_str << "*"
        else
          new_str << str[i]
        end
      end

      puts new_str


    solution 2:
      str = "Elephant"
      vowels = "aeiou"
      result = str.chars.map do |char|
        vowels.include?(char.downcase) ? '*': char 
      end.join

      puts result
    
    solution 3: (Inplace)

      str = "Elephant"
      vowels = "aeiou"

      str.each_char.with_index do |ch, i|
        str[i] = '*' if vowels.include?(ch.downcase)
      end
      puts str

---------------------------------------------------------------------------------------------------
Print the frequency count of each words in the given sentence.
Answer:
    solution 1:
      str = "Hello, Ram is a good boy also ram is intelligent"
      puts str.downcase.split(" ").tally

    solution 2:
      str = "Hello, Ram is a good boy also ram is intelligent"
      hash = Hash.new(0)

      str.split(" ").each do |word|
          hash[word.downcase] += 1
      end

      puts hash

    solution 3:
      hash = Hash.new(0)

      str.scan(/\w+/).each do |word|
        hash[word.downcase] +=1  
      end

      puts hash


-------------------------------------------------------------------------------------
Given an array and a value k. Find kth largest element from the array.
arr = [12, 9,39, 23, 47, 19, 8]
k = 3

Solution 1:
  arr.sort[-(k)]

Solution 2:
  arr.sort.reverse[k-1]

Solution 3:

  def find_kth_largest(arr, k)
    top_k =[]

    arr.each do |num|
      if top_k.size < k
        top_k << num 
      else

        # find minimum in top_k
        min_index = 0
        (1...k).each do |i|
          min_index = i if top_k[i] < top_k[min_index]
        end

        # replace minimum if larger number found
        if num > top_k[min_index]
          top_k[min_index] = num
        end
        
      end
    end

    top_k.min
  end

  arr = [12, 9,39, 23, 47, 19, 8]
  k = 3
  puts find_kth_largest(arr, k)

------------------------------------------------------------------------------------
Given a string, find the length of the longest substring without repeating characters.
Answer: This is variable Sliding window pattern.

  def longest_substring(s)
    set = {}
    left = 0
    max_length = 0

    (0...s.length).each do |right|
      while set[s[right]]
        set.delete(s[left])
        left += 1
      end

      set[s[right]] = true
      max_length = [max_length, right - left + 1].max
    end

    max_length
  end

  puts longest_substring("abcabcbb")

-----------------------------------------------------------------------------------------
Max sum of subarray of size k
Answer -> This is fixed sliding window pattern.

def max_subarray_sum(arr, k)
  window_sum = 0

  # Step 1: first window
  (0...k).each do |i|
    window_sum += arr[i]
  end

  max_sum = window_sum

  # Step 2: slide window
  (k...arr.length).each do |i|
    window_sum += arr[i]       # add next element
    window_sum -= arr[i - k]   # remove left element

    max_sum = [max_sum, window_sum].max
  end

  max_sum
end

puts max_subarray_sum([2,1,5,1,3,2], 3)

---------------------------------------------------------------------------------
Given an array of integers nums and an integer k, return the total number of subarrays whose sum equals to k.
Array may contain negative numbers.
A subarray is a contiguous non-empty sequence of elements within an array.

def subarray_sum(nums, k)
  target = k
  count = 0
  sum = 0

  map = Hash.new(0)
  map[0] = 1   # very important

  nums.each do |num|
    sum += num

    count += map[sum - target]

    map[sum] += 1
  end
  count
end


puts subarray_sum([1,2,3], 3)  # 2

---------------------------------------------------------------------------------
Flights are given, find the path. Print the desired output.
flights = [["DEL", "KOL" ], ["KOL", "BOM"], ["HYD","DEL"] , ["BOM", "GOA"], ["HYD", "GOA"]]
Output: 
  ["DEL", "KOL" ]
  ["KOL", "BOM"]
  ["BOM", "GOA"]

Here, we have given the flight between the city. City represents node and edge represent path i.e flight.
We have to find the path from source "DEL" to destination "GOA".

def find_path(flights, source, destination)
  # First create the directed graph
  graph = Hash.new { |h, k| h[k] = [] }  # {"DEL"=>["KOL"], "KOL"=>["BOM"], "HYD"=>["DEL", "GOA"], "BOM"=>["GOA"]} 

  flights.each do |from, to|
    graph[from] << to
  end

  visited = {}

  # Recursive path finding
  dfs(source, destination, graph, visited, [])
end

def dfs(node, destination, graph, visited, path)
  return path if node == destination

  visited[node] = true

  graph[node].each do |neigh|
    next if visited[neigh]

    result = dfs(neigh, destination, graph, visited, path + [[node, neigh]])
    return result if result
  end

  nil
end

flights = [["DEL", "KOL" ], ["KOL", "BOM"], ["HYD","DEL"] , ["BOM", "GOA"], ["HYD", "GOA"]]
result = find_path(flights, "DEL", "GOA")
puts result.inspect


------------------------------------------------------------------
def shortest_path(flights, source, destination)
  graph = Hash.new { |h, k| h[k] = [] }

  flights.each do |from, to|
    graph[from] << to
  end

  visited = {}
  queue = [[source, []]]   # [current_node, path_so_far]

  while !queue.empty?
    node, path = queue.shift

    return path if node == destination

    next if visited[node]
    visited[node] = true

    graph[node].each do |neigh|
      next if visited[neigh]

      queue << [neigh, path + [[node, neigh]]]
    end
  end

  nil
end

flights = [["DEL", "KOL" ], ["KOL", "BOM"], ["HYD","DEL"] , ["BOM", "GOA"], ["HYD", "GOA"]]

puts shortest_path(flights, "DEL", "GOA").inspect