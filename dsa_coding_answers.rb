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
7.Given an integer array nums, return all unique triplets [nums[i], nums[j], nums[k]]
such that i != j != k and they sum to 0.
Input:  nums = [-1, 0, 1, 2, -1, -4]
Output: [[-1, -1, 2], [-1, 0, 1]]
Explanation: Both triplets sum to zero; duplicates are excluded.

def unique_triplet(nums)
    nums = nums.sort
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