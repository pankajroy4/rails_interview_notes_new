Question 1: What is elasticSearch?

Ansewer -> Elasticsearch is a distributed, REST-based search and analytics engine built on Apache Lucene.
It is designed for:
  Full-text search
  Extremely fast querying
  Horizontal scalability
  Real-time indexing
  Complex filtering + aggregations

Think of it as: A highly optimized search engine that indexes your data separately from your main database.
It is not a replacement for PostgreSQL/MySQL. It complements them.

Elasticsearch is: Eventually consistent with your database.
Meaning:
  You update DB
  Then ES updates index
  Small delay may exist

Interview Answer -> Elasticsearch is a distributed search and analytics engine that we use in Rails applications when we need advanced search capabilities beyond what a relational database can efficiently provide.

In a typical Rails app, PostgreSQL or MySQL is used as the primary database, but they are not optimized for full-text search, typo tolerance, relevance ranking, or complex filtering. That is where Elasticsearch comes in.

For example, in an e-commerce application, if users search for products with partial words, spelling mistakes, or multiple filters like price range, category, and rating, Elasticsearch can handle that very efficiently.

In Rails, we usually integrate it using gems like elasticsearch-model or by using a service object to index data. The database remains the source of truth, and Elasticsearch stores a searchable index of that data. Whenever a record is created or updated, we sync it to Elasticsearch, often using background jobs.

So in short, we use Elasticsearch in Rails when we need fast, scalable, relevance-based search with features like autocomplete, fuzzy search, and aggregations.

-----------------------------------------------------------------------------------------------
Question 2: Why Use Elasticsearch in a Rails Application?

Relational databases are good at:
  Exact matching
  Simple filters
  Structured queries

They are not optimized for:
  Fuzzy search
  Autocomplete
  Ranking by relevance
  Multi-field text search
  Large-scale analytics

That is where Elasticsearch fits.

-----------------------------------------------------------------------------------------------
Question 3: How To Use Elasticsearch in Rails
Answer - > 
Step 1: Install Elasticsearch Server
  Install locally or use cloud service.

Step 2: Add Gem
  Most common:
    gem 'elasticsearch-model'
    gem 'elasticsearch-rails'

Step 3: Include in Model
  class Product < ApplicationRecord
    include Elasticsearch::Model
    include Elasticsearch::Model::Callbacks
  end

  Callbacks automatically sync DB changes to Elasticsearch.

Step 4: Create Index
  Product.__elasticsearch__.create_index!
  Product.import

  Now all products are indexed.

Step 5: Searching
    Product.search("iphone")

  Or advanced query:

    Product.search(
      query: {
        multi_match: {
          query: "iphone 15",
          fields: ["name", "description"]
        }
      }
    )

-----------------------------------------------------------------------------------------------
Question 4: Why not just use PostgreSQL full-text search?”

Answer: -> PostgreSQL is fine for moderate datasets.
Elasticsearch is designed for distributed search.
Better scoring, analyzers, tokenizers.
Better scalability.
Better aggregation engine.

PostgreSQL full-text search is good for moderate datasets and simple use cases. But Elasticsearch is designed specifically for distributed search. It provides better relevance scoring, typo tolerance, customizable analyzers, autocomplete support, and powerful aggregations.

Also, Elasticsearch scales horizontally much better. So for large datasets or search-heavy applications like e-commerce or job portals, Elasticsearch is usually a better choice.

-----------------------------------------------------------------------------------------------
Question 5: How do you keep Elasticsearch in sync with Rails database?

Answer ->  The database remains the source of truth. Whenever a record is created, updated, or deleted, we sync those changes to Elasticsearch.

In Rails, this is often done using model callbacks or, preferably, background jobs with Sidekiq. That way indexing happens asynchronously and doesn’t slow down the main request cycle.

This makes the system eventually consistent.

-----------------------------------------------------------------------------------------------
Question 6: What do you mean by "Elasticsearch is eventually consistent"?

Answer ->  It means that when we update data in the database, Elasticsearch might not reflect that change immediately.
There is usually a small delay because indexing may happen asynchronously. But eventually, both systems become consistent.
This tradeoff improves performance and scalability.

-----------------------------------------------------------------------------------------------
Question 7: What is an index in Elasticsearch?

Answer -> An index in Elasticsearch is similar to a table in a relational database.
It stores documents, which are JSON objects. Each document represents a record — for example, a product or a user.
The index is optimized for search, not for relational queries.

-----------------------------------------------------------------------------------------------
Question 8: What is a document in Elasticsearch?

Answer -> A document is a JSON object stored inside an index.
For example, a product document may contain fields like name, description, price, and category.
Unlike relational databases, Elasticsearch is schema-flexible and stores data in JSON format.

-----------------------------------------------------------------------------------------------
Question 9: What are analyzers in Elasticsearch?

Answer -> An analyzer is responsible for processing text before it is indexed or searched.
It breaks text into tokens, removes stop words, applies lowercase conversion, and may perform stemming.
For example, the word “Running” might be stored as “run” depending on the analyzer.
This improves search accuracy.

-----------------------------------------------------------------------------------------------
Question 10: How does Elasticsearch handle typo tolerance?

Answer -> Elasticsearch supports fuzzy queries.
It uses edit distance algorithms to match similar words.
So if a user types “iphnoe” instead of “iphone,” Elasticsearch can still return relevant results.

-----------------------------------------------------------------------------------------------
Question 11: What are aggregations in Elasticsearch?

Answer -> Aggregations are used for analytics.
For example, counting products by category, calculating average price, or grouping results.
They are very powerful and optimized for fast analytical queries.

-----------------------------------------------------------------------------------------------
Question 12: When should you NOT use Elasticsearch?

Answer -> If the dataset is small and search requirements are simple, PostgreSQL full-text search is sufficient.
Elasticsearch adds operational complexity — cluster management, memory tuning, and monitoring.
So it is better to use it only when advanced search or scalability is truly needed.

-----------------------------------------------------------------------------------------------
Question 13: What are the downsides of Elasticsearch?

Answer ->  It increases infrastructure complexity.
You need to manage clusters, memory usage, index mappings, and reindexing strategies.
Also, since it is eventually consistent, it may not be suitable for highly critical real-time financial systems where absolute consistency is required.

-----------------------------------------------------------------------------------------------
Question 13: Suppose you have to implement a search feature something like user search products on flipkart. In this search data my came from multiple model. There is no association in between the model. How will you implemt that?

Answer -> If we need a search feature like Flipkart and data comes from multiple models with no direct association, I would not rely purely on SQL with UNION.

Instead, I would use Elasticsearch.

I would create a unified search index where documents from different models — for example Product, Brand, Category — are indexed in a common searchable structure.

The database would remain the source of truth, and whenever records change, we would update Elasticsearch asynchronously using background jobs.

This allows relevance-based ranking, typo tolerance, autocomplete, filtering, and better scalability compared to raw SQL queries.

==========================================================================================
Example app code where elastic search is implement and search feature uses multiple model.
Implementation: 

Architecture:
-------------
  Models:
    Product
    Brand
    Category

  We will:
    Index all of them into ONE index called global_search
    Store a record_type field to differentiate models
    Search across everything

Step 1: Add Gems
  gem 'elasticsearch-model'
  gem 'elasticsearch-rails'

  Then:
    bundle install

Step 2: Create a Searchable Concern:
  Instead of duplicating logic in every model, create:

  # app/models/concerns/searchable.rb
  module Searchable
    extend ActiveSupport::Concern

    included do
      include Elasticsearch::Model
      include Elasticsearch::Model::Callbacks

      index_name "global_search"

      settings do
        mappings dynamic: false do
          indexes :name, type: :text
          indexes :description, type: :text
          indexes :record_type, type: :keyword
        end
      end

      def as_indexed_json(options = {})
        {
          name: respond_to?(:name) ? name : title,
          description: try(:description),
          record_type: self.class.name,
          record_id: id
        }
      end
    end
  end

  This ensures:
    All models use same index
    Same structure
    Searchable across models  

Step 3: Include in Multiple Models
  Product Model:
    class Product < ApplicationRecord
      include Searchable
    end

  Brand Model:
    class Brand < ApplicationRecord
      include Searchable
    end

  Category Model:

    class Category < ApplicationRecord
      include Searchable
    end

Step 4: Create Index and Import Data
  Run in Rails console:

    Product.__elasticsearch__.create_index!(force: true)
    Product.import
    Brand.import
    Category.import

  Now all records are in one Elasticsearch index.

  NOTE: 

Step 5: Create Search Service
  Instead of searching from model directly, use a service.

  # app/services/global_search_service.rb
  class GlobalSearchService
    def self.search(query)
      response = Elasticsearch::Model.client.search(
        index: "global_search",
        body: {
          query: {
            multi_match: {
              query: query,
              fields: ["name", "description"]
            }
          }
        }
      )

      response["hits"]["hits"].map do |hit|
        hit["_source"]
      end
    end
  end

Step 6: Controller
  class SearchController < ApplicationController
    def index
      @results = GlobalSearchService.search(params[:q])
    end
  end

Step 7: Example Search

  If user searches: ?q=iphone

  It may return:
    [
      { "name": "iPhone 15", "record_type": "Product" },
      { "name": "Apple", "record_type": "Brand" },
      { "name": "Smartphones", "record_type": "Category" }
    ]

  All from different tables.
==========================================================================================
