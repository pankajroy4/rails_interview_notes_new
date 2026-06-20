======================================================================================================
                      DSA Most Important Patterns
======================================================================================================
╰➤Arrays & Hashing
   🔸Two Sum
   🔸Group Anagrams
   🔸Product Except Self
   🔸Top K Frequent

╰➤Two Pointers
   🔸3Sum / 4Sum/ kSum
   🔸Container With Most Water
   🔸Remove Duplicates

╰➤Sliding Window
   🔸Longest Substring Without Repeating
   🔸Minimum Window Substring
   🔸Permutation in String

╰➤Stack
   🔸Valid Parentheses
   🔸Min Stack
   🔸Daily Temperatures

╰➤Binary Search
   🔸Search Rotated Array
   🔸First/Last Position
   🔸Koko Eating Bananas

╰➤Linked List
   🔸Reverse Linked List
   🔸Merge K Lists
   🔸LRU Cache

╰➤Trees
   🔸Level Order
   🔸Diameter
   🔸Lowest Common Ancestor
   🔸Validate BST

╰➤Heap
   🔸Kth Largest
   🔸Merge K Sorted Lists
   🔸Top K Frequent

╰➤Intervals
   🔸Merge Intervals
   🔸Meeting Rooms

╰➤Graphs
   🔸BFS and DFS
   🔸Number of Islands
   🔸Clone Graph

╰➤Dynamic Programming
   🔸Climbing Stairs
   🔸House Robber
   🔸Coin Change
   🔸Longest Increasing Subsequence



Re-solve same problem after: 1 day, 3 days, 7 days. This is where actual retention happens.

==========================================================================================================
                                    Pattern Recogonisation
==========================================================================================================

                +-------------------------------------------------------+
                | Problem Signal         | Likely Pattern               |
                |------------------------|------------------------------|
                | contiguous subarray    | sliding window               |
                | sorted array           | binary search / two pointers |
                | top k                  | heap                         |
                | repeated recalculation | DP                           |
                | parent-child traversal | tree DFS/BFS                 |
                +-------------------------------------------------------+


--------------------------------------------------------------------------------------------------------------
Q1. Given an array of integers nums and an integer target, return the indices of the two numbers such that they add up to target.
  You may assume that:
    Each input has exactly one solution
    You may not use the same element twice
    You can return the answer in any order

  Input:
    nums = [7,2,11,15]
    target = 9

  Output:
    [0,1]

  Explanation:
    nums[0] + nums[1] = 7+ 2 = 9

  Note: You have to return the indices, so sorting the array will not help you.

Solution:
  def find_two_sum(arr, target)
    hash = {}

    arr.each_with_index do |num, i|
      remainder = target - num

      if hash.key?(remainder) # check , is there any seen number same as remainer present in hash.
        return [hash[remainder], i]
      end

      hash[num] = i  # store seen number in hash with index
    end
  end

  arr = [2,7,11,15]
  target = 9
  puts find_two_sum(arr, target).inspect

-----------------------------------------------------------------------------------------------------------
Q2. Given an array of strings strs, group the anagrams together.
You can return the answer in any order.
An anagram is a word or phrase formed by rearranging the letters of another word using exactly the same letters and same frequency.

Input:
  strs = ["eat","tea","tan","ate","nat","bat"]

Output:
  [
    ["bat"],
    ["nat","tan"],
    ["ate","eat","tea"]
  ]


-----------------------------------------------------------------------------------------------------------

def first_occurrence(arr, k)
  left = 0
  right = arr.size - 1
  ans = -1

  while left <= right
    mid = left + (right - left) / 2

    if arr[mid] == k
      ans = mid
      right = mid - 1
    elsif arr[mid] < k
      left = mid + 1
    else
      right = mid - 1
    end
  end

  ans
end

def last_occurrence(arr, k)
  left = 0
  right = arr.size - 1
  ans = -1

  while left <= right
    mid = left + (right - left) / 2

    if arr[mid] == k
      ans = mid
      left = mid + 1
    elsif arr[mid] < k
      left = mid + 1
    else
      right = mid - 1
    end
  end

  ans
end

def find_frequency(arr, k)
  first = first_occurrence(arr, k)

  return 0 if first == -1

  last = last_occurrence(arr, k)

  last - first + 1
end

arr = [12, 19, 21, 21, 21, 21, 56, 78]

puts find_frequency(arr, 21)