1.Given an array of integers nums and an integer target, return the indices of the
two numbers that add up to target. Exactly one solution exists; do not reuse an element.
Input:  nums = [2, 7, 11, 15], target = 9
Output: [0, 1]

def find_indices(arr, target)
    seen = Hash.new(0)
    arr.each_with_index do |num, i|
        remain = target - num
        if seen.has_key?(remain)
            return [seen[remain], i]
        end
        seen[num] = i
    end
end

arr = [2, 7, 11, 15]
target = 9
puts find_indices(arr, target).inspect

-----------------------------------------------------------------------------------------------------------------------------------
2.Given an array prices where prices[i] is the stock price on day i, return the maximum profit from one buy followed by one sell. Return 0 if no profit is possible.
Input:  prices = [7, 1, 5, 3, 6, 4]
Output: 5

def max_profit(prices)
    max_profit = 0
    buy = Float::INFINITY

    prices.each do |price|
        buy = price if price < buy

        profit = price-buy
        max_profit = profit if profit > max_profit
    end
    return max_profit
end

prices = [7, 1, 5, 3, 6, 4]
puts max_profit(prices)

-----------------------------------------------------------------------------------------------------------------------------------
3.Given an integer array nums, find the contiguous subarray with the largest sum and return its sum.
Input:  nums = [-2, 1, -3, 4, -1, 2, 1, -5, 4]
Output: 6

def max_subarray(nums)
    max_sum = 0
    current_sum = 0

    nums.each do |num|
        current_sum = [num, current_sum+num].max
        max_sum = [max_sum, current_sum].max
    end
    return max_sum
end

nums = [-2, 1, -3, 4, -1, 2, 1, -5, 4]
puts max_subarray(nums)

Note: The above solution will fail when the array contains only negative elements.
example: nums = [-1]
         expected_outout =  -1
         output of above code = 0

    To fix this, initialize both max_sum and current_sum with the first element of the array, and then iterate over the remaining elements.

    def max_subarray(nums)
        max_sum = nums[0]
        current_sum = nums[0]

        nums.drop(1).each do |num|
            current_sum = [current_sum + num, num].max
            max_sum = [max_sum, current_sum].max
        end

        max_sum
    end
-----------------------------------------------------------------------------------------------------------------------------------
4.Problem: Given an array nums, move all 0s to the end while maintaining the relative order of the non-zero elements, in-place.
Input:  nums = [0, 1, 0, 3, 12]
Output: [1, 3, 12, 0, 0]


def move_zero(nums)
    j = 0
    i = 0

    (0...nums.length).each do |k|
        if nums[j] != 0
            nums[i], nums[j] = nums[j], nums[i]
            i+=1
        end 
        j+=1
    end

    return nums
end

nums = [0, 1, 0, 3, 12]
puts move_zero(nums).inspect

-----------------------------------------------------------------------------------------------------------------------------------
5.Problem: Given a sorted array nums, remove duplicates in-place so each element appears once, and return the new length.
Input:  nums = [1, 1, 2, 2, 3]
Output: 3  (nums becomes [1, 2, 3])

def remove_duplicates(nums)
    i = 0
    j = 1
    (0...nums.length).each do |k|
        if nums[j] != nums[i]
            i+=1
            nums[i] = nums[j]
        end

        j+=1  
    end

    return nums.slice(0,i).length # or simply return i+1
end

nums = [1, 1, 2, 2, 3]
puts remove_duplicates(nums).inspect

-----------------------------------------------------------------------------------------------------------------------------------
6.Given two sorted arrays nums1 (with extra trailing space) and nums2, merge nums2 into nums1 in-place as one sorted array.
Input:  nums1 = [1,2,3,0,0,0], m = 3, nums2 = [2,5,6], n = 3
Output: [1,2,2,3,5,6]

def merge(nums1, nums2,m,n)
    ans = []
    i=0
    j=0

    while ( i < m && j < n) do 
        if nums1[i] < nums2[j]
            ans << nums1[i]
            i+=1
        else 
            ans << nums2[j]
            j+=1
        end
    end

    while (i< m) do 
        ans << nums1[i]
        i+=1
    end

    while (j< n) do 
        ans << nums2[j]
        j+=1
    end

    return ans
end

nums1 = [1,2,3,0,0,0]
m = 3
nums2 = [2,5,6]
n = 3

puts merge(nums1, nums2,m,n).inspect

# ----------- Inplace solution(Start filling from back side, 3 pointers) -------------------

def merge(nums1, nums2, m, n)
    i=m-1
    j=n-1
    k=(m+n)-1

    while ( i >= 0 && j >=0) do 
        if nums2[j] > nums1[i]
            nums1[k] = nums2[j]
            j-=1
            k-=1
        else
            nums1[k] = nums1[i]
            k-=1
            i-=1
        end
    end

    while j >= 0
        nums1[k] = nums2[j]
        k-=1
        j-=1
    end

    return nums1
end

nums1 = [1,2,3,0,0,0]
m = 3
nums2 = [2,5,6]
n = 3

puts merge(nums1, nums2,m,n).inspect

-----------------------------------------------------------------------------------------------------------------------------------
7.Given an integer array nums, return all UNIQUE triplets [nums[i], nums[j], nums[k]]
such that i != j != k and they sum to 0.
Input:  nums = [-1, 0, 1, 2, -1, -4]
Output: [[-1, -1, 2], [-1, 0, 1]]
Explanation: Both triplets sum to zero; duplicates triplets are excluded.

def unique_triplet(nums)
    nums = nums.sort   #Sort the array
    answer = []

    (0...nums.length).each do |i|
        left = i+1
        right = nums.length-1

        next if i > 0 && nums[i] == nums[i-1] # skip duplicates fixed num

        while left < right

            sum = nums[i]+nums[left]+nums[right]
            if sum < 0
                left+=1
            elsif sum > 0
                right-=1
            else
                answer << [nums[i], nums[left], nums[right]]
                left +=1
                right -= 1

                # Skip duplicate left values
                while left < right && nums[left] == nums[left - 1]
                    left += 1
                end

                # Skip duplicate right values
                while left < right && nums[right] == nums[right + 1]
                    right -= 1
                end
            end
        end
    end
    return answer
end

nums = [-1, 0, 1, 2, -1, -4]
puts unique_triplet(nums).inspect

-----------------------------------------------------------------------------------------------------------------------------------
8.Given an array with only 0s, 1s, and 2s, sort it in-place in one pass without using a library sort.
Input:  nums = [2, 0, 2, 1, 1, 0]
Output: [0, 0, 1, 1, 2, 2]

def sort_color(nums)
    low = 0
    mid = 0
    high = nums.length-1 

    while mid <= high
        if nums[mid] == 0
            nums[low], nums[mid] = nums[mid], nums[low]
            low +=1
            mid +=1
        elsif nums[mid] == 1
            mid +=1
        else
            nums[mid], nums[high] = nums[high], nums[mid]
            high -= 1
        end
    end

    return nums
end

nums = [2, 0, 2, 1, 1, 0]
puts sort_color(nums).inspect

-----------------------------------------------------------------------------------------------------------------------------------
9.Given an array nums, return an array where each element is the product of all other elements, without using division.
Input:  nums = [1, 2, 3, 4]
Output: [24, 12, 8, 6]

def product_of_array(nums)
    n = nums.length
    ans = Array.new(n, 1)

    # prefix_pass
    prefix  = 1
    nums.each_with_index do |num, i|
        ans[i] = prefix
        prefix = prefix*num
    end 

    # suffix_pass
    suffix = 1
    (n-1).downto(0).each do |i|
        ans[i] = suffix * ans[i]  # store after multiplying with already claculated prefix answers
        suffix = suffix * nums[i] 
    end

    return ans
end

nums = [1, 2, 3, 4]
puts product_of_array(nums).inspect

-----------------------------------------------------------------------------------------------------------------------------------
10.Given heights array, find two lines that together with the x-axis form a
container holding the most water. Return the max area.
Input:  height = [1, 8, 6, 2, 5, 4, 8, 3, 7]
Output: 49
Explanation: Lines at index 1 (height 8) and index 8 (height 7): area = 7 * min(8,7) = 49
Constraints: 2 <= height.length <= 10^5, 0 <= height[i] <= 10^4
Approach: two pointers from both ends, move the shorter side inward — O(n) time, O(1) space

def most_water(height)
    max_area = 0
    current_area = 0
    left = 0 
    right = height.length-1

    while left < right
        current_area  = (right-left) * [height[left], height[right]].min
        max_area = [max_area, current_area].max

        if height[left] < height[right]
            left +=1     
        else
            right -=1
        end 
    end
    max_area
end

height = [1, 8, 6, 2, 5, 4, 8, 3, 7]
puts most_water(height)

-----------------------------------------------------------------------------------------------------------------------------------
11.Given an array of intervals, merge all overlapping intervals and return the non-overlapping intervals covering all input ranges.
Input:  intervals = [[1,3],[2,6],[8,10],[15,18]]
Output: [[1,6],[8,10],[15,18]]

def merge_overlap(intervals)
    intervals = intervals.sort_by { |interval| interval[0] }

    ans = [intervals[0]]

    intervals[1..].each do |current|
        previous = ans[-1] # last element (an arry) of ans. NOTE: This is reference, so any change in previous array, will be reflected in ans array

        if current[0] <= previous[1]
            previous[1] = [previous[1], current[1]].max
        else
            ans << current
        end
    end
    ans
end

intervals = [[1,3],[2,6],[8,10],[15,18]] 

puts merge_overlap(intervals).inspect

-----------------------------------------------------------------------------------------------------------------------------------
12. Given a sorted, non-overlapping list of intervals and a new interval, insert it and merge if necessary. Return the resulting list.

Input:  intervals = [[1,3],[6,9]], newInterval = [2,5]
Output: [[1,5],[6,9]]
Explanation: [2,5] overlaps [1,3], merges into [1,5]; [6,9] stays separate.
Constraints: 0 <= intervals.length <= 10^4

def insert_interval(intervals, newInterval)
  ans = []

  intervals.each do |interval|
    # Current interval is completely before newInterval
    if interval[1] < newInterval[0]
      ans << interval

    # Current interval is completely after newInterval
    elsif interval[0] > newInterval[1]
      ans << newInterval
      newInterval = interval   #"Hum newInterval ko continuously update karte hain

    # Overlapping intervals → merge
    else
      newInterval[0] = [newInterval[0], interval[0]].min
      newInterval[1] = [newInterval[1], interval[1]].max
    end
  end

   #"Hum newInterval ko continuously update karte hain, aur appropriate time par ans mein insert kar dete hain; end mein jo last newInterval bachta hai usko bhi insert kar dete hain."
  ans << newInterval
  ans
end

intervals = [[1, 3], [6, 9]]
newInterval = [2, 5]

puts insert_interval(intervals, newInterval).inspect

-----------------------------------------------------------------------------------------------------------------------------------
13.Given an array nums, rotate it to the right by k steps, in-place.
Input:  nums = [1,2,3,4,5,6,7], k = 3
Output: [5,6,7,1,2,3,4]

def rotate_array(nums, k)
    n = nums.length
    k = k%n

    nums.reverse!  #1. Reverse the full array!
    nums[0...k] = nums[0...k].reverse #2. Reverse the first k element
    nums[k...n] = nums[k...n].reverse #3. Rverse the rest remaining element

    nums
end

nums = [1,2,3,4,5,6,7]
k = 3
puts rotate_array(nums, k).inspect

-----------------------------------------------------------------------------------------------------------------------------------
14.Rearrange numbers into the lexicographically next greater permutation. If none exists, rearrange to the lowest possible order (sorted ascending).
Input:  nums = [1, 2, 3]
Output: [1, 3, 2]


def fun(nums)
    pivot_index = -1
    n = nums.length-2

    n.downto(0).each do |i|
        if nums[i]< nums[i+1]
            pivot_index = i
            break
        end
    end

    return nums.reverse! if pivot_index == -1

    swap_index = -1

    (nums.length-1).downto(pivot_index+1).each do |i|
        if nums[i]> nums[pivot_index]
            swap_index = i
            break
        end
    end

    nums[pivot_index], nums[swap_index] = nums[swap_index], nums[pivot_index]

    nums[pivot_index+1..] = nums[pivot_index+1..].reverse

    return nums

end

nums = [1, 2, 3]
puts fun(nums).inspect

-----------------------------------------------------------------------------------------------------------------------------------
14.Find All Duplicates in an Array — (Pattern: Index Marking / Negative Marking)
Problem:Given an integer array nums of length n where all the integers of nums are in the range [1, n] and each integer appears at most twice, return an array of all the integers that appears twice.
You must write an algorithm that runs in O(n) time and uses only constant auxiliary space, excluding the space needed to store the output
Input: nums = [4,3,2,7,8,2,3,1]
Output: [2,3]

def find_duplicate(nums)
    ans = []

    nums.each do |num|
        num = num.abs
        if nums[num-1] < 0
            ans << num
        else
            nums[num-1] = -nums[num-1]
        end
    end
    ans
end

nums = [4,3,2,7,8,2,3,1]
puts find_duplicate(nums).inspect

-----------------------------------------------------------------------------------------------------------------------------------
19.Reverse a character array in-place without using extra space or built-ins.
Input:  s = ['h','e','l','l','o']
Output: ['o','l','l','e','h']

def reverse_string(s)
    i = 0
    j = s.length-1

    while i<j
        s[i], s[j] = s[j], s[i]
        i+=1
        j-=1
    end
    s
end

s = ['h','e','l','l','o']
puts reverse_string(s).inspect


-----------------------------------------------------------------------------------------------------------------------------------
20.Given two strings s and t, return true if t is an anagram of s.
Input:  s = "anagram", t = "nagaram"
Output: true

def is_anagram?(s, t)
  return false if s.length != t.length

  count = Hash.new(0)

  s.each_char do |char|
    count[char] += 1
  end

  t.each_char do |char|
    count[char] -= 1
  end

  count.values.all?(&:zero?)
end

s = "anagram" 
t = "nagaram"
puts is_anagram?(s,t)

-----------------------------------------------------------------------------------------------------------------------------------
21.Given a string s, check if it is a palindrome after converting to lowercase and removing non-alphanumeric characters.
Input:  s = "A man, a plan, a canal: Panama"
Output: true
Explanation: Cleaned string "amanaplanacanalpanama" reads the same forwards and backwards.

# This will fail if string is alphanumeric
def is_palindrome?(str)
    return true if str.length == 0

    i=0
    j=str.length-1

    while i<j
        while i<j && ( str[i].downcase.ord < 97 || str[i].downcase.ord > 122)
            i+=1
        end

        while i< j && ( str[j].downcase.ord < 97 || str[j].downcase.ord > 122 )
            j-=1
        end

        return false if str[i].downcase != str[j].downcase
        i+=1
        j-=1
    end

    true
end

str = "A man, a plan, a canal: Panama"
puts is_palindrome?(str)

# ----------- More clean solution -------------------

def is_palindrome?(str)
    i = 0
    j = str.length - 1

    while i < j
        while i < j && !alphanumeric?(str[i])
            i += 1
        end

        while i < j && !alphanumeric?(str[j])
            j -= 1
        end

        return false if str[i].downcase != str[j].downcase
        i += 1
        j -= 1
    end
    true
end

def alphanumeric?(char)
    ascii = char.downcase.ord
    (ascii >= 97 && ascii <= 122) || (ascii >= 48 && ascii <= 57)
end

str = "A man, a plan, a canal: Panama"
puts is_palindrome?(str)

-----------------------------------------------------------------------------------------------------------------------------------
22.Given haystack and needle strings, return the index of the first occurrence of
needle in haystack, or -1 if not found.
Input:  haystack = "sadbutsad", needle = "sad"
Output: 0

# Brute-force implementation 1:

def implement_str(haystack, needle)
    n = needle.length

    left = 0
    right = n-1

    while right < haystack.length
        if haystack[left..right] == needle
            return left
        else
            left+=1
            right+=1
        end
    end

    return -1
end


haystack = "sadbutsad"
needle = "pad"
puts implement_str(haystack, needle)

# Brute-force implementation 2:

def implement_str(haystack, needle)
    i=0
    # atleast needle ki length jitna string availabe ho haystack me, whi tak loop krenge. Matlab jis index ke baad niddle fit hi nahi hoga uske aage loop krne ka koi matlab nahi hai.
    while i <= haystack.length - needle.length
        j = i
        k = 0

        while k < needle.length
            if haystack[j] != needle[k]
                break
            end
            j+=1
            k+=1
        end

        return i if k == needle.length
        i+=1
    end
    -1
end

haystack = "sadbutsad"
needle = "but"
puts implement_str(haystack, needle)

# Brute-force implementation 3:

def implement_str(haystack, needle)
    i=0
    while i <= haystack.length - needle.length
        j = 0

        while j < needle.length
            if haystack[i+j] != needle[j]
                break
            end
            j+=1
        end

        return i if j == needle.length
        i+=1
    end
    -1
end

haystack = "sadbutsad"
needle = "but"
puts implement_str(haystack, needle)

# Optimised Implementation using LPS and KMP algo:

def generate_lps_array(str)
    lps = []
    lps[0] = 0

    i=0
    j=1

    while j<str.length
        if str[i] == str[j]
            lps[j] = i+1
            i+=1
            j+=1
        else
            if i == 0
                lps[j] = 0
                j+=1
            else
                i = lps[i-1]
            end
        end
    end

    return lps
end


def implement_str(haystack, needle)
    lps = generate_lps_array(needle)
 
    i= 0
    j = 0

    while i < haystack.length
        
        if haystack[i] == needle[j]
            i+=1
            j+=1
        else
            if  j == 0 
                i+=1
            else
                j = lps[j-1]
            end
        end

        return i-j if j == needle.length
    end

    -1
end

puts implement_str("sadbutsad", "but") # => 3
puts implement_str("hello", "ll") # => 2
puts implement_str("aaaaa", "aaa") # => 0
puts implement_str("abc", "xyz") # => -1
puts implement_str("abc", "abcd") # => -1

-----------------------------------------------------------------------------------------------------------------------------------
23.Given an array of strings, group the anagrams together.
Input:  strs = ["eat","tea","tan","ate","nat","bat"]
Output: [["eat","tea","ate"],["tan","nat"],["bat"]]

def group_anagrams(strs)
    hash = {}

    strs.each do |str|
        # key = str.chars.sort_by(&:downcase).join
        key = str.chars.sort.join # if guaranteed that strings will contain only lowecase alphabet

        if hash.key?(key)
            hash[key] << str
        else
            hash[key] = [str]
        end
    end

    hash.values
end

strs = ["eat","tea","tan","ate","nat","bat"]
puts group_anagrams(strs).inspect

-----------------------------------------------------------------------------------------------------------------------------------
24.Longest Substring Without Repeating Characters — (Pattern: Sliding Window)
Problem: Given a string s, find the length of the longest substring without repeating
characters.
Input:  s = "abcabcbb"
Output: 3
Explanation: The answer "abc" or "cab" both valid, with length 3.

# Approach 1: Hash + Shrinking Window # Duplicate milne par left se characters ko one-by-one delete karte hain # jab tak duplicate key remove nahi ho jata. Correct O(n) solution hai, but extra deletion/shrinking karna padta hai.
def longest_substring(s)
    hash = {}
    left = 0
    right = 0
    max_length = 0

    while right < s.length
        c = s[right]
        while hash[c]
            hash.delete(s[left])
            left+=1
        end

        hash[c] = true
        max_length = [max_length, right-left+1].max
        right+=1
    end

    return max_length
end

s = "abcdbcbb"
puts longest_substring(s)

# Approach 2: Last Seen Index — Better Approach # Har character ki last position store karte hain. # Duplicate milne par left ko directly previous seen position + 1 par jump kar dete hain. Isliye delete ya inner while loop ki need nahi hai. O(n) time and cleaner approach.

def longest_substring(s)
    hash = {}
    left = 0
    right = 0
    max_length = 0

    while right<s.length
        c = s[right]
        if hash.key?(c) && left <= hash[c]  # left pointer never goes back
            left = hash[c]+1
        end

        max_length = [max_length,right-left+1].max
        hash[c] = right
        right+=1
    end
    max_length
end

s = "abcdbcbb"
puts longest_substring(s)

----------------------------------------------------------------------------------------------------------------------------------- 
25.Longest Palindromic Substring — (Pattern: Expand Around Center / DP)
Problem: Given a string s, return the longest palindromic substring.
Input:  s = "babad"
Output: "bab"  (or "aba", both valid)
Explanation: "bab" and "aba" are both palindromes of length 3; either is accepted.

def longest_palindrome(s)
    longest_p = "" 
    max_length = 0

    (0...s.length).each do |i|
        # Considering odd length
        left =  i
        right = i

        while left>=0 && right<s.length && s[left] == s[right]
            current_length = right - left + 1

            if current_length > max_length
                max_length = current_length
                longest_p = s[left..right]
            end

            left -=1
            right +=1
        end

        # Considering even length
        left =  i
        right = i+1
      
        while left>=0 && right<s.length && s[left] == s[right]
            current_length = right - left + 1

            if current_length > max_length
                max_length = current_length
                longest_p = s[left..right]
            end

            left -=1
            right +=1
        end
    end
    longest_p
end

s = "bdaa"
puts longest_palindrome(s)

        #----------------------- Cleaner version ------------------------------------

def longest_palindrome(s)
  result = ""

  (0...s.length).each do |i|
    odd_palindrome = expand(s, i, i)
    even_palindrome = expand(s, i, i + 1)

    result = odd_palindrome if odd_palindrome.length > result.length
    result = even_palindrome if even_palindrome.length > result.length
  end

  result
end

def expand(s, left, right)
  while left >= 0 && right < s.length && s[left] == s[right]
    left -= 1
    right += 1
  end

  s[(left + 1)..(right - 1)]
end

s = "bdaa"
puts longest_palindrome(s)

-----------------------------------------------------------------------------------------------------------------------------------
26.String Compression — (Pattern: Two Pointers)

Problem: Compress a character array in-place using counts of consecutive repeated characters, and return the new length.

Input: chars = ['a','a','b','b','c','c','c']
Output: 6
Modified chars: ['a','2','b','2','c','3']
Explanation: 'a' repeats twice → a2, 'b' twice → b2, 'c' three times → c3. If a character appears only once, do not write 1. If a character count has multiple digits, write each digit separately — e.g. a count of 12 should be written as '1','2'.

Input: chars = ["a","b","b","b","b","b","b","b","b","b","b","b","b"]
Output: 4
Explanation: The groups are "a" and "bbbbbbbbbbbb". This compresses to "ab12".
After modifying the input array in-place, the first 4 characters of chars should be ["a","b","1","2"].

Constraints:1 <= chars.length <= 200
            chars[i] is a lowercase English letter, uppercase English letter, digit, or symbol.

def compress(chars)
    read = 0
    write = 0

    while read < chars.length
        current_char = chars[read]
        count = 0

        while read < chars.length && chars[read] == current_char
            read += 1
            count += 1
        end

        chars[write] = current_char
        write += 1

        if count > 1
            count.to_s.each_char do |digit|
                chars[write] = digit
                write += 1
            end
        end
    end

    write
end

-----------------------------------------------------------------------------------------------------------------------------------
27. Implement atoi: convert a string to a 32-bit signed integer, handling
leading whitespace, optional sign, digits, and overflow clamping.
Input:  s = "   -42"
Output: -42
Explanation: Leading spaces are skipped, sign is captured, digits parsed until non-digit.
Constraints: 0 <= s.length <= 200, result clamped to [-2^31, 2^31 - 1]

#include <bits/stdc++.h>
using namespace std;

class Solution {
public:
    int myAtoi(string s) {

        int i = 0;
        int num = 0;
        int sign = 1;

        while (i < s.size() && s[i] == ' ') {
            i++;
        }

        if (i < s.size() && (s[i] == '+' || s[i] == '-')) {
            sign = (s[i] == '-') ? -1 : 1;
            i++;
        }

        while (i < s.size() && isdigit(s[i])) {
            int digit = s[i] - '0';

            //-2147483648, 2147483647
            if (num > INT_MAX / 10 || (num == INT_MAX / 10 && digit > 7)) {
                return sign == 1 ? INT_MAX : INT_MIN;
            }

            num = num * 10 + digit;
            i++;
        }

        return num * sign;
    }
};

int main(){
    Solution obj;

    int ans1  = obj.myAtoi("    -12b34"); // => -12
    int ans2  = obj.myAtoi("0-4"); // => 0
    int ans3  = obj.myAtoi("42"); // => 42
    int ans4  = obj.myAtoi("    -042"); // => -42
    int ans5  = obj.myAtoi("1337c0d3"); // => 1337
    cout << "Answers are :"<< ans1 <<", "<< ans2<<", "<< ans3 <<", "<< ans4<<", "<< ans5<< endl;
    return 0;
}


-----------------------------------------------------------------------------------------------------------------------------------
28.Given strings s1 and s2, check if s2 is a rotation of s1.
Input:  s1 = "waterbottle", s2 = "erbottlewat"
Output: true
Explanation: s2 is rotation of s1.

Input:  s1 = "abc", s2 = "ab"
Output: false
Explanation: s2 can never be rotation of s1 as their length are different.
Constraints: 0 <= s1.length == s2.length <= 10^4


#Brute froce searching of substring after concatenation.
def rotate_string(s, goal)
    return false if s.length != goal.length

    s = s+s
    i=0

    while i < s.length
        k = i
        j = 0

        while j < goal.length &&  s[k] == goal[j]
            j+=1
            k+=1
        end

        if j == goal.length
            return true
        end

        i+=1;
    end
    false;
end

s1 = "waterbottle"
s2 = "erbottlewat"
puts rotate_string(s1,s2)

#Efficient searching of substring after concatenation.
def generate_lps(str)
    lps = []
    lps[0] = 0
    i=0
    j=1

    while j< str.length
        if str[i] == str[j]
            lps[j] = i+1
            j+=1
            i+=1         
        else
            if i==0
               lps[j] = 0
               j+=1 
            else
                i = lps[i-1]
            end
        end
    end

    lps
end

def rotate_string(s, goal)
    str = s+s
    lps = generate_lps(goal)

    i = 0
    j = 0

    while i < str.length
        if str[i] == goal[j]
            i+=1
            j+=1
        else
            j = lps[j-1]
        end
        return true if j == goal.length
    end
    false
end

s1 = "waterbottle"
s2 = "erbottlewat"
puts rotate_string(s1,s2)

-----------------------------------------------------------------------------------------------------------------------------------
31.Contains Duplicate — (Pattern: Hashing)
Problem: Given an array nums, return true if any value appears at least twice.
Input:  nums = [1, 2, 3, 1]
Output: true
Explanation: 1 appears twice.
Constraints: 1 <= nums.length <= 10^5
Approach: hash set, return true on first repeat — O(n) time, O(n) space


def contains_duplicate?(nums)
    hash = {}

    nums.each do |num|
        return true if hash.key?(num)
        hash[num] = true
    end

    false
end

nums = [1, 2, 3, 1]
puts contains_duplicate?(nums)

-----------------------------------------------------------------------------------------------------------------------------------
32.First Non-Repeating (unique) Character in a String — (Pattern: Frequency Map)
Problem: Given a string s, return the index of the first character that does not
repeat; return -1 if none exists.
Input:  s = "leetcode"
Output: 0
Explanation: 'l' is the first character that appears only once.
Constraints: 1 <= s.length <= 10^5, lowercase English letters
Approach: frequency count pass, then scan for first count == 1 — O(n) time, O(1) space (fixed alphabet)

def unique_char(str)
    hash = Hash.new(0)

    str.each_char do |c|
        hash[c] +=1
    end

    str.each_char.with_index do |c, i|
      return i if hash[c] == 1
    end
    return -1
end

s = "leetlcode"
puts unique_char(s)

#Highly optimsed one. Use almost zero memory.
def unique_char(str)
    arr = Array.new(26,0)

    # Count frequencies using ASCII math ('a' becomes index 0)
    str.each_char do |c|
        arr[c.ord - 'a'.ord] +=1
    end

    str.each_char.with_index do |c, i|
      return i if arr[c.ord - 'a'.ord] == 1
    end

    return -1
end

s = "leetlcode"
puts unique_char(s)

-----------------------------------------------------------------------------------------------------------------------------------
33.Isomorphic Strings — (Pattern: Hashing)
Problem: Given strings s and t, return true if the characters in s can be replaced to
get t, with a consistent one-to-one mapping.
Input:  s = "egg", t = "add"
Output: true
Explanation: 'e'->'a', 'g'->'d' is a consistent bijective mapping.

def isomorphic_string(s,t)
    return false if s.length != t.length
    h1 = {}
    h2 = {}
    i=0

    while i < s.length
        c1 = s[i]
        c2 = t[i]
        # Har source character ki ek fixed destination honi chahiye, aur har destination ko sirf ek source character own kar sakta hai.
        if h1.key?(c1) || h2.key?(c2)
            return false if ( h1[c1] != c2  || h2[c2] != c1 )
        end

        h1[c1] = c2
        h2[c2] = c1
        i+=1
    end
    return true
end

s = "foo"
t = "bar"
puts isomorphic_string(s,t)

-----------------------------------------------------------------------------------------------------------------------------------
38.Problem: Given a string containing only '(', ')', '{', '}', '[', ']', determine if
brackets are balanced and correctly nested.
Input:  s = "()[]{}"
Output: true
Constraints: 1 <= s.length <= 10^4

def valid_parentheses(s)
    stack = []
    hash = {")" => "(" , "}" => "{", "]" => "["}

    s.each_char do |c|
        if hash.key?(c)
            return false if stack.empty?
            return false if hash[c] != stack.pop
        else
            satck << c
        end 
    end

    stack.empty?
end

s = "()[]{}"
puts valid_parentheses(s)

-----------------------------------------------------------------------------------------------------------------------------------
72.Given a sorted array nums and a target, return its index, or -1 if not found.
Input:  nums = [-1,0,3,5,9,12], target = 9
Output: 4
Explanation: nums[4] == 9

# Recursion based implementation
def binary_search(nums, target)
    i = 0
    j = nums.length-1
    search(nums, i, j, target)
end

def search(nums, i, j, target)
    return -1 if i>j

    mid = (i+j)/2

    if nums[mid] == target
        return mid
    elsif nums[mid]>target
        return search(nums, i, mid-1, target) 
    else    
        return search(nums, mid+1, j, target) 
    end
end

nums = [-1,0,3,5,9,12]
target = 18
puts binary_search(nums, target)

# Non recursion based solution
def binary_search(nums, target)
    i = 0
    j = nums.length-1
    
    while (i <=j)
        mid = (i+j)/2

        if nums[mid] == target
            return mid
        elsif nums[mid]>target
            j = mid -1
        else    
            i = mid+1
        end
    end
    return -1
end


nums = [-1,0,3,5,9,12]
target = 9
puts binary_search(nums, target)

-----------------------------------------------------------------------------------------------------------------------------------
34.A number is "happy" if repeatedly replacing it with the sum of squares of its
digits eventually reaches 1. Determine if n is happy.
Input:  n = 19
Output: true
Explanation: 19 -> 82 -> 68 -> 100 -> 1
Constraints: 1 <= n <= 2^31 - 1

def is_happy(n)
    hash = {}

    while n > 1
        return false if hash.key?(n)
        hash[n] = true

        sum = 0

        # calculate digit square sum
        while n > 0
            digit = n % 10
            sum += digit * digit
            n /= 10
        end

        n = sum # again pass the current sum as n
    end
  true
end

n = 19
puts happy_nums(n)

Time complexity explanantion:
    Inner loop: n is divided by 10 each time → O(log₁₀ n)
    Outer loop: n predictably decrease nahi ho rha, n har baar change hoga due to sum, so directly O(log n) nahi bol sakte.

    Given complexity:  n ≤ 2³¹ - 1, so n will have at max 10 digits. Maximum possible number of 10 digits: 9999999999
    Maximum digit-square sum: 10 * 9² = 810

    So first transformation ke baad n ≤ 810. Therefore outer loop has only constant number of possible states (1 - 810) → O(1).
    Hash (seen) previously visited values ko store karta hai. Agar koi value repeat hoti hai, cycle detect karke loop terminate ho jata hai.

    Therefore, outer loop can be considered O(1) for the given constraints.
    so we can assume outer loop as constant.
    Overall: O(1) * O(log n) = O(log n).

-----------------------------------------------------------------------------------------------------------------------------------
35.Given an array nums and integer k, return true if there are two distinct
indices i, j such that nums[i] == nums[j] and |i - j| <= k.
Input:  nums = [1,1,2,3,1], k = 3
Output: true
Explanation: nums[0] == nums[3] and |0-3| = 3 <= k.

# Implementation 1 - O(n) space
def duplicate(nums, k)
    seen = {}

    nums.each_with_index do |num, i| 
        if seen.key?(num)
            return true if (seen[num] - i).abs <= k
        end
        seen[num] = i
    end
    false
end

nums = [1,2,3,1]
k = 3
puts duplicate(nums, k)

# Impelmentation 2 - O(min(n, k)) space
def duplicate(nums, k)
    window = {}

    nums.each_with_index do |num, i| 
        return true if window.key?(num)
        window[num] = i
        window.delete(nums[i-k]) if window.length > k
    end
    false
end

nums = [1,2,3,1]
k = 3
puts duplicate(nums, k)

-----------------------------------------------------------------------------------------------------------------------------------
85.Problem: Given an array where every element appears twice except one, find that
single element in linear time and O(1) space.
Input:  nums = [4, 1, 2, 1, 2]
Output: 4

def single_number(nums)
    result = 0
    nums.each do |num|
        result = result ^ num
    end
    return result
end

nums = [4, 1, 2, 1, 2]
puts single_number(nums)

-----------------------------------------------------------------------------------------------------------------------------------
36.Given an array nums and integer k, return the k most frequent elements.
Input:  nums = [1,1,1,2,2,3], k = 2
Output: [1, 2]

def top_k_frequent(nums, k)
    freq = nums.tally
    buckets = Array.new(nums.length + 1) { [] }

    freq.each do |num, freq|
        buckets[freq] = buckets[freq] << num # or simply:  buckets[freq] << num  
    end

    # Instead of using (buckets.length - 1), we use (nums.length) because (buckets.length - 1) provides no additional benefit here. We can safely use nums.length because the maximum possible frequency cannot exceed (nums.length), and this avoids unnecessary iterations when the maximum actual frequency is lower than (nums.length).
    result = []
    (nums.length).downto(1) do |count|
        buckets[count].each do |num|
            result << num
            return result if result.length == k
        end
    end
    result
end

nums = [1,2,1,2,1,2,3,1,3,2]
k = 2
puts top_k_frequent(nums,k).inspect

-----------------------------------------------------------------------------------------------------------------------------------
37.Problem: Given an unsorted array nums, return the length of the longest run of
consecutive integers, in O(n) time.
Input:  nums = [100, 4, 200, 1, 3, 2]
Output: 4
Explanation: The consecutive sequence [1, 2, 3, 4] has length 4.

def longest_consecutive_sequence(nums)
    hash = nums.tally
    ans = 0

    hash.each do |num, count|
        unless hash.key?(num-1)
            current_ans = 0
            while hash.key?(num)
                current_ans +=1
                num +=1
            end
            ans = current_ans if current_ans > ans
        end
    end
    ans
end

nums = [100, 4, 200, 1, 3, 2]
puts longest_consecutive_sequence(nums)

#   --------------- We can also use set --------------------

def longest_consecutive_sequence(nums)
    num_set = nums.to_set
    ans = 0

    num_set.each do |num|
        unless num_set.include?(num-1)
            current_ans = 0
            while num_set.include?(num)
                current_ans +=1
                num +=1
            end
            ans = current_ans if current_ans > ans
        end
    end
    ans
end

nums = [100, 4, 200, 1, 3, 2]
puts longest_consecutive_sequence(nums)

-----------------------------------------------------------------------------------------------------------------------------------
39.Design a stack supporting push, pop, top, and getMin(), all in O(1) time.
Input:  push(-2), push(0), push(-3), getMin(), pop(), top(), getMin()
Output: -3, 0, -2
Explanation: getMin() reflects the current minimum after each operation.
Constraints: up to 3*10^4 calls total

class MinStack
    def initialize()
        @stack = []
        @min_stack = []
    end

    def push(value)
        if @min_stack.empty? || value <= @min_stack[-1]
            @min_stack << value
        end

        @stack << value
        nil
    end

    def pop()  
        val = @stack.pop
        @min_stack.pop  if val == @min_stack[-1]
        val
    end

    def top()
        @stack[-1]      
    end

    def get_min()
        @min_stack[-1]
    end
end

minStack = MinStack.new;
minStack.push(-2);
minStack.push(0);
minStack.push(-3);
puts minStack.get_min(); # return -3
minStack.pop();
puts minStack.top();    # return 0
puts minStack.get_min(); # return -2

-----------------------------------------------------------------------------------------------------------------------------------
40.Problem: Given an array nums, for each element find the next greater element to its right; use -1 if none exists.
Input:  nums = [2, 1, 2, 4, 3]
Output: [4, 2, 4, -1, -1]
Explanation: For 2 (index 0), next greater is 4; for 1, next greater is 2; etc.
Constraints: 1 <= nums.length <= 10^4

def next_greater_element(nums)
    ans = Array.new(nums.length, -1)
    stack = []

    nums.each_with_index do |num, i|
        while stack.length > 0 && num > nums[stack[-1]]
            ans[stack[-1]] = num
            stack.pop
        end
        stack << i
    end
    #for remaining element in stack, ans array already holds -1 , so we are not working for remaining elements of stack
    ans
end
 
nums = [2, 1, 2, 4, 3]
puts next_greater_element(nums).inspect

-----------------------------------------------------------------------------------------------------------------------------------
40.The next greater element of some element x in an array is the first greater element that is to the right of x in the same array.
You are given two distinct 0-indexed integer arrays nums1 and nums2, where nums1 is a subset of nums2.
For each 0 <= i < nums1.length, find the index j such that nums1[i] == nums2[j] and determine the next greater element of nums2[j] in nums2. If there is no next greater element, then the answer for this query is -1.

Return an array ans of length nums1.length such that ans[i] is the next greater element as described above.
Example:
Input: nums1 = [4,1,2], nums2 = [1,3,4,2]
Output: [-1,3,-1]
Explanation:The next greater element for each value of nums1 is as follows:
            4 is underlined in nums2 = [1,3,4,2]. There is no next greater element, so the answer is -1.
            1 is underlined in nums2 = [1,3,4,2]. The next greater element is 3.
            2 is underlined in nums2 = [1,3,4,2]. There is no next greater element, so the answer is -1.
Constraints:
1 <= nums1.length <= nums2.length <= 1000
0 <= nums1[i], nums2[i] <= 104
All integers in nums1 and nums2 are unique.
All the integers of nums1 also appear in nums2.

# as values in nums2 are uniuqe so we can create the stack of values too instead of index
def next_greater_element(nums1, nums2)
    hash = Hash.new(-1)
    stack = []

    nums2.each_with_index do |num|
        while stack.length > 0 && num > stack[-1]
            hash[stack[-1]] = num
            stack.pop
        end
        stack << num
    end

    ans = []
    # We are not working for remaining elements in stack. As hash initialized with -1, so for any other key it will return -1
    nums1.each do |num|
        ans << hash[num]
    end
    ans
end

nums1 = [4,1,2]
nums2 = [1,3,4,2]
puts next_greater_element(nums1, nums2).inspect
