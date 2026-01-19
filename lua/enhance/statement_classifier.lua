-- enhance.nvim - Statement Classifier
-- Classifies statements for execution strategy (batch vs de-batch)

local M = {}

---Statement types that should be de-batched (executed individually)
local DEBATCH_TYPES = {
  INSERT = true,
  UPDATE = true,
  DELETE = true,
  CREATE = true,
  DROP = true,
  ALTER = true,
  TRUNCATE = true,
  MERGE = true,
}

---Statement types that should stay batched (metadata/analysis queries)
local BATCH_TYPES = {
  SELECT = true,
  PRAGMA = true,
  SHOW = true,
  DESCRIBE = true,
  DESC = true,
  EXPLAIN = true,
  UNKNOWN = true,  -- Unknown statements stay batched for safety
}

---Check if a statement should be de-batched
---@param statement_type string Statement type
---@return boolean True if should be de-batched
local function should_debatch(statement_type)
  return DEBATCH_TYPES[statement_type] == true
end

---Check if a statement should stay batched
---@param statement_type string Statement type
---@return boolean True if should stay batched
local function should_batch(statement_type)
  return BATCH_TYPES[statement_type] == true
end

---Classify statements for execution strategy
---@param statements table[] Array of statement objects from statement_detector
---@return table Classification result
function M.classify_for_execution(statements)
  if not statements or #statements == 0 then
    return {
      execution_mode = "batch",
      reason = "no_statements",
      groups = {},
    }
  end
  
  -- Check for transaction block first
  local statement_detector = require("enhance.statement_detector")
  if statement_detector.contains_transaction_block(statements) then
    return {
      execution_mode = "batch",
      reason = "transaction_block",
      groups = {
        {
          type = "batch",
          statements = statements,
        }
      },
    }
  end
  
  -- Check if all statements should be batched (metadata queries)
  local all_batch = true
  for _, stmt in ipairs(statements) do
    if not should_batch(stmt.type) then
      all_batch = false
      break
    end
  end
  
  if all_batch then
    return {
      execution_mode = "batch",
      reason = "metadata_queries",
      groups = {
        {
          type = "batch",
          statements = statements,
        }
      },
    }
  end
  
  -- Check if any statements should be de-batched
  local has_debatch = false
  for _, stmt in ipairs(statements) do
    if should_debatch(stmt.type) then
      has_debatch = true
      break
    end
  end
  
  if not has_debatch then
    -- No de-batch statements, keep batched
    return {
      execution_mode = "batch",
      reason = "no_dml_ddl",
      groups = {
        {
          type = "batch",
          statements = statements,
        }
      },
    }
  end
  
  -- De-batch mode: create groups
  -- Group consecutive batch statements, separate de-batch statements
  local groups = {}
  local current_batch = nil
  
  for _, stmt in ipairs(statements) do
    if should_debatch(stmt.type) then
      -- Save current batch group if exists
      if current_batch and #current_batch > 0 then
        table.insert(groups, {
          type = "batch",
          statements = current_batch,
        })
        current_batch = nil
      end
      
      -- Add individual statement
      table.insert(groups, {
        type = "individual",
        statements = { stmt },
      })
    else
      -- Batch statement - add to current batch group
      if not current_batch then
        current_batch = {}
      end
      table.insert(current_batch, stmt)
    end
  end
  
  -- Save final batch group if exists
  if current_batch and #current_batch > 0 then
    table.insert(groups, {
      type = "batch",
      statements = current_batch,
    })
  end
  
  return {
    execution_mode = "debatch",
    reason = "individual_statements",
    groups = groups,
  }
end

-- Expose internal functions for testing
M._should_debatch = should_debatch
M._should_batch = should_batch

return M

