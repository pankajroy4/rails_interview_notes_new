# While Loop
i = 0
while i < arr.length
  puts arr[i]
  i += 1
end

# Range
(0...10).to_a => [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]
(0..10).to_a => [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
10.downto(1) => [10, 9, 8, 7, 6, 5, 4, 3, 2, 1] # Reverse Range
(1..5).reverse_each.to_a => [5, 4, 3, 2, 1]

# For Loop
for num in arr # num is a temporary variable that takes the value of each element in arr
  puts num
end

for i in 0...arr.length # This will loop from 0 to arr.length - 1
  puts arr[i]
end

# Two Pointer Pattern Example
left = 0
right = arr.length - 1

while left < right
  sum = arr[left] + arr[right]

  if sum == target
    return true
  elsif sum < target
    left += 1
  else
    right -= 1
  end
end

# Sliding Window Pattern Example
window_sum = 0
left = 0
(0...arr.length).each do |right|

  window_sum += arr[right]

  while window_sum > target
    window_sum -= arr[left]
    left += 1
  end
end

# Frequency Counter Pattern Example
count = {}

str.each_char do |ch|
  count[ch] = (count[ch] || 0) + 1
end

# Nested Loop
(0...arr.length).each do |i|
  (i+1...arr.length).each do |j|
    puts arr[i], arr[j]
  end
end

# Recursion
def factorial(n)
  return 1 if n <= 1
  n * factorial(n - 1)
end

# Reverse Array (No Built in Method)
arr = [1,2,3,4]
result = []

i = arr.length - 1
while i >= 0
  result << arr[i]
  i -= 1
end

# Find Max
max = arr[0]

i = 1
while i < arr.length
  if arr[i] > max
    max = arr[i]
  end
  i += 1
end

# ===================================== Practice ===========================================
# 1. Reverse a Array
arr = [1,2,3,4]
def reverse_array(arr)
  result = []
  i = arr.length - 1
  while i >= 0 do
    result.push(arr[i])
    i-=1
  end
end

def reverse_array(arr)
  result = []
  for i in (arr.length-1).downto(0) do
    result.push(arr[i])
  end
  result
end

# 2. Find Maximum Element
arr = [9,6,8,5,11,3,5]
def find_max(arr)
  max = arr[0]
  arr.each do |i|
    max = i if i > max
  end
  max
end

# 3. Check Palindrome
str = "madam"
def check_palindrome(str)
  start = 0
  endp = str.length-1
  while start < endp
    return false if str[start] != str[endp]
    start +=1
    endp -=1
  end
  true
end

# Length of longest substring without repeating characters
def length_of_longest_substring(s)
    hash = Hash.new(0)
    left = 0
    right = 0
    max = 0

    while right < s.length
        if hash.include?(s[right])
            max = [max, hash.count].max
            left +=1
            right = left
            hash.clear
        else
            hash[s[right]] += 1
            right+=1
        end
    end
    [max, hash.count].max
end



arr = ["a", 1, 5, "b", "a", 1, 2, "2"]

# hash =  Hash.new(0)
# result = []

# arr.each do | ele|
#   hash[ele] +=1
#   if hash[ele] > 1
#     result << ele
#   end
# end

# puts result.inspect


result = []
arr = ["a", 1, 5, "b", "a", 1, 2]

(0...arr.length-1).each do |i|
  (i+1...arr.length).each do |j|
    if arr[i] == arr[j] && !result.include?(arr[i])
      result << arr[i]
    end
  end
end

puts result.inspect