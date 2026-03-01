Class
=====
  ➤ A class is a blueprint for creating objects (instances). It defines the properties/state (via instance variables) and behavior (via methods) of its instances.

  ➤ Key Features of a Class
    - Can be instantiated using .new
    - Methods inside a class are by default instance methods.

Polymorphism
============
  - Polymorphism means having multiple forms
  - Polymorphism allows objects of different classes to respond to the same method name in their own way.
    class Animal
      def speak
        "Some sound"
      end
    end

    class Dog < Animal
      def speak
        "Bark"
      end
    end

    class Cat < Animal
      def speak
        "Meow"
      end
    end

    animals = [Dog.new, Cat.new]
    animals.each { |a| puts a.speak }

    # Output:
    # Bark
    # Meow
    - All classes respond to .speak, but behavior changes depending on the actual class.
    - This is runtime polymorphism.

Super
======
  ➤ The super keyword is used inside a method to call the same method from the superclass (parent class).
  ➤ It is useful when you want to add or modify behavior without fully replacing it.

  class A
    def greet(name)
      "Hello, #{name}"
    end
  end

  class B < A
    def greet(name)
      super(name) + " from B"
    end
  end

  puts B.new.greet("Alice")
  # => "Hello, Alice from B"

  - If the method in the child does not specify arguments, just calling super automatically passes all arguments from the current method to the parent method.

➤ Ruby encourages simple inheritance and modules for shared behavior (instead of multiple inheritance). 
  So you wll often combine inheritance (for hierarchy) and mixins (for shared utility methods) in idiomatic Ruby.
