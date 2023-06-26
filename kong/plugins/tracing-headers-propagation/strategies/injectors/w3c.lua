local propagation_utils = require "kong.plugins.tracing-headers-propagation.utils"

local set_header = kong.service.request.set_header
local to_hex     = propagation_utils.to_hex
local W3C_TRACEID_LEN = 16


local W3C_INJECTOR = {}


local function to_w3c_trace_id(trace_id)
  if #trace_id < W3C_TRACEID_LEN then
    return ('\0'):rep(W3C_TRACEID_LEN - #trace_id) .. trace_id
  elseif #trace_id > W3C_TRACEID_LEN then
    return trace_id:sub(-W3C_TRACEID_LEN)
  end

  return trace_id
end

function W3C_INJECTOR:inject(out_tracing_ctx)
  local trace_id  = to_hex(to_w3c_trace_id(out_tracing_ctx.trace_id))
  local parent_id = to_hex(out_tracing_ctx.parent_id)
  local sampled   = out_tracing_ctx.should_sample and "01" or "00"

  set_header("traceparent", string.format("00-%s-%s-%s",
      trace_id, parent_id, sampled))

  return { w3c = trace_id }
end

return W3C_INJECTOR
