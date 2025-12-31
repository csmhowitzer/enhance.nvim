-- enhance.nvim - Statement Matcher
-- Matches detected SQL statements to parsed output

local M = {}

---Generate message for DML statement (INSERT/UPDATE/DELETE)
---@param statement_type string Statement type
---@param row_count number Number of rows affected
---@return string Message
local function generate_dml_message(statement_type, row_count)
  local action_map = {
    INSERT = "inserted",
    UPDATE = "updated",
    DELETE = "deleted",
  }
  local action = action_map[statement_type] or (statement_type:lower() .. "ed")
  local plural = row_count == 1 and "row" or "rows"
  return string.format("✓ %d %s %s", row_count, plural, action)
end

---Generate message for DDL statement (CREATE/DROP/ALTER)
---@param query_type string? Query type from metadata
---@return string Message
local function generate_ddl_message(query_type)
  if query_type == "CREATE_TABLE" then
    return "✓ Table created successfully"
  elseif query_type == "DROP_TABLE" then
    return "✓ Table dropped successfully"
  elseif query_type == "ALTER_TABLE" then
    return "✓ Table altered successfully"
  else
    return "✓ Statement executed successfully"
  end
end

---Match detected statements to parsed output
---@param statements table[] Array of detected statements from statement_detector
---@param parsed_output table Parsed output from parser
---@param metadata table Execution metadata (execution_time, row_count, etc.)
---@return table[] Array of Statement Result Objects
function M.match_statements(statements, parsed_output, metadata)
  local results = {}
  
  -- Handle single result set (no multiple_results flag)
  -- This can happen with:
  -- 1. Single statement (e.g., just SELECT)
  -- 2. Multiple statements where only one produces output (e.g., INSERT + SELECT)
  if not parsed_output.multiple_results then
    if #statements == 0 then
      return results
    end

    -- If we have multiple statements but only one result set,
    -- we need to match the result to the correct statement
    local result_consumed = false

    for _, stmt in ipairs(statements) do
      local result = {
        type = stmt.type,
        query_text = stmt.text,
        rows = 0,
        elapsed = metadata.execution_time or 0,
        db_type = metadata.db_type,
        db_name = metadata.connection_name,
        executed_on = metadata.timestamp,
      }

      -- SELECT gets result_table (if not already consumed)
      if stmt.type == "SELECT" and not result_consumed then
        result.result_table = {
          headers = parsed_output.headers,
          rows = parsed_output.rows,
        }
        result.rows = #parsed_output.rows
        result.message = nil
        result_consumed = true
      -- INSERT/UPDATE/DELETE get message (no result set)
      elseif stmt.type == "INSERT" or stmt.type == "UPDATE" or stmt.type == "DELETE" then
        result.result_table = nil
        result.rows = metadata.row_count or 0
        result.message = generate_dml_message(stmt.type, result.rows)
      -- CREATE/DROP/ALTER get DDL message (no result set)
      elseif stmt.type == "CREATE" or stmt.type == "DROP" or stmt.type == "ALTER" then
        result.result_table = nil
        result.message = generate_ddl_message(metadata.query_type)
      end

      table.insert(results, result)
    end

    return results
  end
  
  -- Handle multiple statements
  local result_set_index = 1
  for _, stmt in ipairs(statements) do
    local result = {
      type = stmt.type,
      query_text = stmt.text,
      rows = 0,
      elapsed = metadata.execution_time or 0,
      db_type = metadata.db_type,
      db_name = metadata.connection_name,
      executed_on = metadata.timestamp,
    }
    
    -- SELECT gets next result set
    if stmt.type == "SELECT" then
      if result_set_index <= #parsed_output.result_sets then
        local result_set = parsed_output.result_sets[result_set_index]
        result.result_table = {
          headers = result_set.headers,
          rows = result_set.rows,
        }
        result.rows = #result_set.rows
        result_set_index = result_set_index + 1
      else
        result.result_table = { headers = {}, rows = {} }
      end
      result.message = nil
    -- INSERT/UPDATE/DELETE get message (no result set consumed)
    elseif stmt.type == "INSERT" or stmt.type == "UPDATE" or stmt.type == "DELETE" then
      result.result_table = nil
      result.rows = metadata.row_count or 0
      result.message = generate_dml_message(stmt.type, result.rows)
      -- Skip empty result set if present
      if result_set_index <= #parsed_output.result_sets then
        local result_set = parsed_output.result_sets[result_set_index]
        if #result_set.headers == 0 and #result_set.rows == 0 then
          result_set_index = result_set_index + 1
        end
      end
    -- CREATE/DROP/ALTER get DDL message (no result set consumed)
    elseif stmt.type == "CREATE" or stmt.type == "DROP" or stmt.type == "ALTER" then
      result.result_table = nil
      result.message = generate_ddl_message(metadata.query_type)
      -- Skip empty result set if present
      if result_set_index <= #parsed_output.result_sets then
        local result_set = parsed_output.result_sets[result_set_index]
        if #result_set.headers == 0 and #result_set.rows == 0 then
          result_set_index = result_set_index + 1
        end
      end
    end
    
    table.insert(results, result)
  end
  
  return results
end

-- Expose internal functions for testing
M._generate_dml_message = generate_dml_message
M._generate_ddl_message = generate_ddl_message

return M

