local _INJECTOR = require "kong.tracing.propagation.injectors._base"
local to_hex    = require "resty.string".to_hex

local W3C_TRACEID_LEN = 16

local W3C_INJECTOR = _INJECTOR:new()


local function to_w3c_trace_id(trace_id)
  if #trace_id < W3C_TRACEID_LEN then
    return ('\0'):rep(W3C_TRACEID_LEN - #trace_id) .. trace_id
  elseif #trace_id > W3C_TRACEID_LEN then
    return trace_id:sub(-W3C_TRACEID_LEN)
  end

  return trace_id
end


function W3C_INJECTOR:get_headers(out_tracing_ctx)
  local trace_id  = to_hex(to_w3c_trace_id(out_tracing_ctx.trace_id))
  local parent_id = to_hex(out_tracing_ctx.parent_id)
  local sampled   = out_tracing_ctx.should_sample and "01" or "00"

  return {{
    name = "traceparent",
    value = string.format("00-%s-%s-%s", trace_id, parent_id, sampled)
  }}
end


function W3C_INJECTOR:get_formatted_trace_id(out_tracing_ctx)
  local trace_id  = to_hex(to_w3c_trace_id(out_tracing_ctx.trace_id))
  return { w3c = trace_id }
end


return W3C_INJECTOR
