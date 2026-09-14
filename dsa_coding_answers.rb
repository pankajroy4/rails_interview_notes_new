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

    return nums.slice(0,i).length
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