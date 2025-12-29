-- enhance.nvim - JSON Column Detection
-- Detect which columns in result sets contain JSON data

local M = {}
local json_utils = require("enhance.json_utils")

---Detect which columns contain JSON data by sampling rows
---@param headers string[] Column headers
---@param rows string[][] Data rows
---@param sample_size? number Number of rows to sample (default: 5)
---@return table<number, boolean> Map of column_index -> is_json_column
function M.detect_json_columns(headers, rows, sample_size)
  sample_size = sample_size or 5
  
  -- Initialize result map (all columns default to false)
  local json_columns = {}
  for i = 1, #headers do
    json_columns[i] = false
  end
  
  -- Handle empty result set
  if #rows == 0 then
    return json_columns
  end
  
  -- Determine how many rows to sample
  local rows_to_check = math.min(sample_size, #rows)
  
  -- For each column, check if it contains JSON
  for col_idx = 1, #headers do
    local has_json = false
    local has_non_null = false
    local all_sampled_are_json = true
    
    -- Sample first N rows for this column
    for row_idx = 1, rows_to_check do
      local cell = rows[row_idx][col_idx]
      
      -- Skip NULL/empty cells (they don't disqualify a column from being JSON)
      if cell and cell ~= "" then
        has_non_null = true
        
        -- Check if this cell contains valid JSON
        if json_utils.is_json(cell) then
          has_json = true
        else
          -- Found a non-JSON, non-NULL value - this column is NOT a JSON column
          all_sampled_are_json = false
          break
        end
      end
    end
    
    -- Column is JSON if:
    -- 1. We found at least one JSON value
    -- 2. All non-NULL sampled values were valid JSON
    if has_json and has_non_null and all_sampled_are_json then
      json_columns[col_idx] = true
    end
  end
  
  return json_columns
end

-- Expose internal functions for testing
M._detect_json_columns = M.detect_json_columns

return M

