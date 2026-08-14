Max sum of subarray of size k
Answer -> This is fixed sliding window pattern.


def max_subarray_sum(arr, k)
  first_window = arr[0...k]
  sum = first_window.sum
  max_sum = sum

  (k...arr.size).each do |i|
    sum += arr[i]
    sum -= arr[i-k]
    max_sum = sum if sum > max_sum
  end

  max_sum
end


puts max_subarray_sum([2,1,5,1,3,2], 3)