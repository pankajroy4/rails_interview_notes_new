// You are given an array containing a mix of even and odd integers.
// Rearrange the elements of the array in-place such that:
//     All even numbers appear on the left side of the array.
//     All odd numbers appear on the right side of the array.

// Constraints
//   The solution must be in-place (no extra array should be used).
//   Sorting is not allowed.
//   The relative order of even and odd numbers does not matter as there are 36 possbile answer.

// Example
//   Input:
//     [12, 3, 5, 8, 9, 26]
//   Valid Outputs (any one):
//     [12, 8, 26, 3, 5, 9]
//     OR
//     [8, 12, 26, 5, 3, 9]
// Any output is acceptable as long as all even numbers are positioned before all odd numbers.
 

#include <stdio.h>
int main(){
  int arr[] = {12,3,5,8,9,26};
  int n = sizeof(arr)/sizeof(arr[0]);
  
  //Printing original array
  for(int i= 0;i<6;i++){
    printf("%d, ", arr[i]);
  }

  // Inplace arrangement logic
  for(int i = 0, j = 0; j < n; j++){
    if(arr[j] %2 == 0){
      int temp = arr[j];
      arr[j] = arr[i];
      arr[i]= temp;
      i++;
    }
  }

  // Printing solution
  printf("\nSolution:\n");

  for(int i = 0; i < 6; i++){
    printf("%d, ", arr[i]);
  }
  printf("\n");
  return 0;
}


// ==============================================================================================================

// Given an array of integers nums and an integer k, return the total number of subarrays whose sum equals to k.
// A subarray is a contiguous non-empty sequence of elements within an array.
// Constraints:
//    1 <= nums.length <= 2 * 104
//   -1000 <= nums[i] <= 1000
//   -107 <= k <= 107

class Solution {
public:
    int subarraySum(vector<int>& nums, int k) {
        unordered_map<int, int> hash;
        hash[0] = 1; // hash.insert({0,1});

        int prefix_sum = 0;
        int count = 0;

        for(int i=0;i<nums.size(); i++){
            prefix_sum += nums[i];

            if(hash.find(prefix_sum-k) != hash.end()){
               count += hash[prefix_sum - k];
            }
            hash[prefix_sum]++;
        }
        
        return count;
    }
};