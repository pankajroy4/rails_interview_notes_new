# Simple Ruby prohrams.
# ========================================

def prime?(num)
  return false if num <=1
  limit = Math.sqrt(num).to_i

  (2..limit).each do |i|
    return false if num%i==0;
  end
  true
end

puts "Enter a Number to check prime:"
num = gets.to_i
if prime?(num)
  puts "Given Number #{num} is prime"
else 
  puts "Given Number #{num} is not prime"
end

# ========================================

def prime?(num)
  return false if num <=1
  i = 2
  while i*i <= num 
    return false if num%i == 0
    i+=1
  end
  true
end

puts "Enter a Number to check prime:"
num = gets.to_i
if prime?(num)
  puts "Given Number #{num} is prime"
else 
  puts "Given Number #{num} is not prime"
end

# ================================================

$first_name = "pankaj" #Global variable
$last_name = "Kumar"

def print_name
  puts "#{$first_name} #{$last_name}"
end

print_name  # Call the function