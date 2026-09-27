// 1.Given an array of integers nums and an integer target, return the indices of the
// two numbers that add up to target. Exactly one solution exists; do not reuse an element.
// Input:  nums = [2, 7, 11, 15], target = 9
// Output: [0, 1]

// class Solution {
// public:
//     vector<int> twoSum(vector<int>& nums, int target) {
//         unordered_map<int, int> seen;
//         int complement;

//         for(int i= 0; i<nums.size(); i++){
//             complement = target - nums[i];

//             if (seen.count(complement)){
//                 return {seen[complement], i};
//             }
            
//             seen[nums[i]] = i;
//         }

//         return {};
//     }
// };




#include<bits/stdc++.h>
using namespace std;

class Solution {
public:
    vector<vector<string>> groupAnagrams(vector<string>& strs) {
        unordered_map<string, vector<string>> hash;

        for (string str : strs) {
            string key = str;
            sort(key.begin(), key.end());

            hash[key].push_back(str);
        }

        vector<vector<string>> ans;

        for (auto& [key, group] : hash) {
            ans.push_back(group);
        }

        return ans;
    }
};

int main() {
    vector<string> strs = {"eat","tea","tan","ate","nat","bat"};

    Solution obj;
    vector<vector<string>> ans = obj.groupAnagrams(strs);

    for (const auto& group : ans) {
        cout << "[ ";
        for (const auto& str : group) {
            cout << str << " ";
        }
        cout << "]" << endl;
    }
    return 0;
}
