1.Given an array of integers nums and an integer target, return the indices of the
two numbers that add up to target. Exactly one solution exists; do not reuse an element.
Input:  nums = [2, 7, 11, 15], target = 9
Output: [0, 1]

class Solution {
public:
    vector<int> twoSum(vector<int>& nums, int target) {
        unordered_map<int, int> seen;
        int complement;

        for(int i= 0; i<nums.size(); i++){
            complement = target - nums[i];

            if (seen.count(complement)){
                return {seen[complement], i};
            }
            
            seen[nums[i]] = i;
        }

        return {};
    }
};

