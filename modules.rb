Modules:
=======
  ➤ A module is a collection of methods, constants, and classes. 
    It cannot be instantiated (इन्स-टैन-शिएटेड) like a class but can be included or extended in other classes to share functionality.

  ➤ Key Features of a Module:
    - Used to group related methods.
    - Cannot be instantiated (इन्स-टैन-शिएटेड).
    - Can be included or extended to add functionality to classes.
    - Supports namespacing to organize code and avoid naming conflicts.
    - We cannot use instance methods of a module without including or extending (or prepending) it in some other class.

  module MyModule
    PI = 3.14
    class InnerClass
      def say_hello
        puts "Hello from InnerClass!"
      end
    end

    #Instance method (Directly defined method in the modules)
    def greet
      puts "Value of pi is #{PI}"
      puts "Hello from MyModule!"
    end

    # module methods (aka singleton methods)
    def self.area_of_circle(radius)
      PI * radius**2
    end
  end

  puts MyModule::PI   #=> 3.14
  puts MyModule::area_of_circle(7)   #=> 153.86 
  puts MyModule.greet  #=> Error (Can not use instance method direclty)
  puts MyModule::greet  #=> Error (Can not use instance method direclty)
  puts MyModule::InnerClass.new.say_hello  #=> Hello from InnerClass

  ➤ Mixins (Using include or extend)
      A mixin is a way to add module methods to a class. Since Ruby does not support multiple inheritance, mixins are used to share code across classes.
        include → Adds module methods(direclty defined methods of module) as instance methods in the target class
        extend → Adds module methods(direclty defined methods of module) as class methods in the target class.
      
      In Mixins, The visibility (public, protected, private) is preserved and comes with them. It means : private instance methods from module will remain private instance methods in target class and public instance methods will remian public instance method in target class.

  ➤ When a class extend, include or prepend a module then:
      - Only the instance methods (public or private) will get mixins to the target class.
      - Constants, classes and module methods will not get mixins to the target class.

  
Difference betwwen require, include, extend and prepend
========================================================
  ╰┈➤ require:
        - Used to load external files or libraries.
        - It is part of Ruby load path system, which finds the file and loads it once.
        - Typically used for loading Ruby gems, libraries, or custom Ruby files.
        - Loads the file once during runtime.
        - Does not include methods directly into a class or module.
        - Commonly used at the top of Ruby files to load dependencies.

        Syntax: require 'my_module'

  ╰┈➤ include:
        - Used to mix in a module's methods into a class. 
        - The module's instance methods(direclty defined methods of module) become Instance methods of the class where it is included.
        - Adds methods as instance methods.
        - Does not load files — the file must be required first if it os not already loaded.

  ╰┈➤ extend:
        - Used to mix in a module's methods into a class. 
        - The module's instance methods(direclty defined methods of module) become Class methods of the class where it is included.
        - Adds methods as Class methods.
        - Does not load files — the file must be required first if it os not already loaded.

  ╰┈➤ prepend:
        - Used to mix in a module's methods into a class. 
        - The module's instance methods(direclty defined methods of module) become instance methods of the class (just like include do) where it is included, But with higer prioprity.
        - Higher proiority means, If the target class already have method with same name then also module method will win which was injected by prepend
        - Adds methods as instance methods.
        - Does not load files — the file must be required first if it os not already loaded.

        module Greeting
          def greet
            puts "Hello from module!"
          end
        end

        class User
          prepend Greeting   # Adds `greet` as an instance method 

          def greet 
            puts "Hello from User instance method!"
          end
        end

        User.new.greet  #=> "Hello from module!"

  Think of it like:
    include - adds behavior
    extend - adds class behavior
    prepend - overrides behavior

➤ Mixins in Ruby act as an alternative to multiple inheritance, similar to how multiple inheritance works in C++.
    - Ruby follows a single inheritance model, meaning a class can inherit from only one parent class.
    - To achieve code reusability across multiple classes, Ruby provides mixins using modules.

    module A
      def greet
        puts "Hello from A!"
      end
    end

    module B
      def greet
        puts "Hello from B!"
      end
    end

    class C
      include A
      include B
    end

    obj = C.new
    obj.greet  # Output: "Hello from B!" (Last included module wins)

  - Ruby follows the Method Lookup Path (MRO).
  - In the above example, since B was included after A, its greet method takes priority.
  - This avoids the diamond problem common in C++ multiple inheritance.

  Even though module B takes priority (since it was included last), you can still explicitly call module A greet method using super.

    module A
      def greet
        puts "Hello from A!"
      end
    end

    module B
      def greet
        puts "Hello from B!"
        super   # Calls `greet` from the previous module in the lookup path (here, `module A`)
      end
    end

    class C
      include A
      include B
    end

    obj = C.new
    obj.greet

    # Output:
    # Hello from B!
    # Hello from A!

    - The super keyword calls the next method in the method lookup path (MRO).
    - Since module B was included last, its method runs first.
    - super then moves up the chain and calls module A method.

Singleton Methods:
=============================================================
  ➤In Ruby, every object (including classes, since classes are objects too) can have methods only defined on that object — these are called singleton methods.
  ➤Note that : Classes are objects too.

   🔸A singleton class (sometimes called a metaclass or eigenclass) is an anonymous class attached to a specific object.
   🔸Methods defined on an object’s singleton class only exist for that object — they aren’t shared with other instances of its class.

      str = "hello"
      def str.shout
        puts self.upcase
      end

      str.shout  # => "HELLO"

      other_str = "world"
      other_str.shout  # => NoMethodError!
      Here, shout is a singleton method of str. Only str can call it — not any other string.

   🔸Classes are objects too! So if you do:
      class MyClass
      end

      def MyClass.hello
        puts "Hello!"
      end

      MyClass.hello  # works
      Then hello is a singleton method of the MyClass object. It’s not an instance method, it’s a method on the class itself.
  
  ➤Are singleton methods and class methods the same?
    In practice: Yes — when you talk about class methods, you’re really talking about singleton methods of the class object.
    In Ruby, classes are objects.

    When you write:
      class MyClass
        def self.foo
          puts "class method"
        end
      end

      ...what you’re really doing is adding a singleton method foo to the object MyClass.

      So:
        MyClass.foo → calls foo on the MyClass object.
        Technically: foo is a singleton method of MyClass.
        In common usage: foo is called a class method.
      
    Class methods are just singleton methods of the class object.


The visibility (public, protected, private) is preserved upon mixins:
======================================================================
 ➤When you mixins a module:
  🔸The modules instance methods(public/private) get mixed into the target class.
  🔸The visibility (public, protected, private) of instance methods comes with them.

    When we do "include":
      The public instance methods of module gets mixin as public instance methods of the target class. Calling it directly on the instance of target class will work fine.
      The private instance methods of module gets mixin as priavte instance methods of the target class. Calling it directly on the instance of target class will fail. Private methods can be called with no explicit receiver. It can be called with implicit receiver.

      module MyModule
        def myfun
          puts "This is myfun"
        end

        private

        def yourfun
          puts "This is yourfun"
        end
      end

      class MyClass
        include MyModule

        def call_yourfun
          yourfun   # This works! Because private methods can be called with no explicit receiver.
        end
      end

      obj = MyClass.new
      obj.myfun      # Works: public instance method
      obj.yourfun    # Fails: private method
      obj.call_yourfun   # This works fine.

    When we do "extend":
      The public instance methods of module gets mixin as public class methods of the target class. Calling it directly with target class will work fine.
      The private instance methods of module gets mixin as priavte class methods of the target class. Calling it directly with target class will fail. Private methods can be called with no explicit receiver.

      module MyModule
        def myfun
          puts "myfun"
        end

        private

        def yourfun
          puts "yourfun"
        end
      end

      class MyClass
        extend MyModule

        def self.call_yourfun
          yourfun  # OK! Private methods can be called with implicit receiver.
        end
      end

      MyClass now has myfun as a public class method.
      yourfun is a private method on the singleton class of MyClass object.

      MyClass.myfun    # Works (public class method)
      MyClass.yourfun  # Raises NoMethodError: private method `yourfun` called
      MyClass.call_yourfun  # Works

    ➤NOTE: extend basically does:

        class << MyClass
          include MyModule
        end

      So the module’s instance methods become singleton methods of the class.
      The method’s visibility (public/private) is preserved, just like with include.


Nested module with extend & include
==================================
  👇With extend:
  module Greeting
    def greet
      puts "Hello!"
    end

    module ClassMethods
      def say_hello
        puts "say hello"
      end
    end
  end

  class User
    include Greeting
    extend Greeting::ClassMethods
  end

  User.say_hello   #=> say hello
  - This is how Rails does it internally too (ActiveSupport::Concern helps automate this).

  👇With include:
  module Greeting
    def greet
      puts "Hello!"
    end

    module ClassMethods
      def say_hello
        puts "say hello"
      end
    end
  end

  class User
    include Greeting
    include Greeting::ClassMethods
  end

  User.new.say_hello   #=> say hello

Method resolution precedence
============================
 ➤ Method resolution precedence when the same method name exists in module and in target class:
    ╰┈➤ When we use extend then:(Adds module methods as class method )
      - class method of the target class with same name will get precedence and method from module will not take into effect.
      - Adds module methods as class methods.
      - If the target class already defines a class method with the same name, it takes precedence.

        module Greet
          def hello
            "Hello from module!"
          end
        end

        class Person
          extend Greet

          def self.hello
            "Hello from person class method"
          end
        end

        Person.hello #=> Hello from person class method  #(Due to chain lookup, First ruby will seacrh for method in same class)

      - Instance method of same name in the target class will not have any problem , they will be used as before.
      - Instance methods in the target class with same name are unaffected.

        module Greet
          def hello
            "Hello from module!"
          end
        end

        class Person
          extend Greet
        
          def hello
            "Hello from person instance method"
          end
        end

        Person.hello  #=> Hello from module!
        Person.new.hello #=> Hello from person instance method

      - Person class defines an instance method hello, not a class method. 
      - So it does not override the hello method from the module, which was extended as a class method.

    ╰┈➤ When we use include then:(Adds module methods as instance method )
      - class method of the target class with same name will not got affected. They will be used as before.

        module Greet
          def hello
            "Hello from module method!"
          end
        end

        class Person
          include Greet

          def self.hello
            "Hello from person class method"
          end
        end

        Person.hello #=> Hello from person class method
        person.new.hello #=> Hello from module method!


      - Instance method of same name in the target class will get precedence and method from module will not take into effect.
        module Greet
          def hello
            "Hello from module!"
          end
        end

        class Person
        include Greet
        
          def hello
            "Hello from person instance method"
          end
        end

        Person.new.hello #=> Hello from person instance method

        - Even though the module defined hello, the class has its own hello, which takes precedence.

    ╰┈➤ When we use prepend then:(It is just like include but with higher method priority. Adds module methods as instance method in target class. )

        module Greet
          def hello
            "Hello from module!"
          end
        end

        class Person
          prepend Greet
        
          def hello
            "Hello from person instance method"
          end
        end

        Person.new.hello #=> Hello from module.

        - prepend is just like include, adds module methods as instance methods, but with higher priority.
        - Even if the target class defines the method with same name, module method wins.


The "module_function" Keyword:
=====================================
As we know :
  ➤ When a class extend, include or prepend a module then:
        - Only the instance methods will get mixins to the target class.
        - Constants, classes and module methods will not get mixins to the target class.

  But when we use the keyword: module_function:
    What module_function does:
      When you use the module_function keyword in a module:
        It creates two copies of each method defined below it:
         🔸A public module-level method (so you can call it like MyModule.my_method).
         🔸A private instance method (so it is available when the module is mixed in). => This method always be mixed in as private instance method or private singleton method (not public) when the module is included or extended.

        So when a class includes, extends, or prepends a module that uses module_function, the methods defined below the keyword module_function are mixed in as private (as private instance method when included , as private singleton method when extends) in the target class, while still remaining accessible on the module itself.

    Example:
      module MyModule
        def regular_instance_method
          "I am an instance method only"
        end

        module_function  # Methods defined below get two copies

        def my_module_function
          "I am both a module method and a private instance method"
        end
      end

      class MyClass
        include MyModule

        def call_methods
          [
            regular_instance_method,  # Works: mixed in as instance method
            my_module_function        # Works: mixed in privately by module_function
          ]
        end
      end

      obj = MyClass.new
      obj.call_methods # => ["I am an instance method", "I am both a module method and a private instance method"]
      obj.regular_instance_method  # => I am an instance method
      obj.my_module_function  # => NoMethodError (private method `my_module_function' called for #<MyClass:0x00005603998d3bf8>) . Error because module_function methods will be added as private instance method in target class.
      MyModule.my_module_function # => "I am both a module method and a private instance method"
      MyModule.regular_instance_method # => undefined method `regular_instance_method' for MyModule:Module (NoMethodError)
    
  module_function is for turning a module into a namespace of module-level utility methods while still allowing the instance methods to be used as private helpers in mixins.
  It makes a copy as a public module method and makes the instance method private.
  include or extend only mix in instance methods → so they get the private one.