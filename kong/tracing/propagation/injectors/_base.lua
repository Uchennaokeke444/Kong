local set_header = kong.service.request.set_header

local _INJECTOR = {}
_INJECTOR.__index = _INJECTOR


function _INJECTOR:new(e)
  e = e or {}
  return setmetatable(e, _INJECTOR)
end


function _INJECTOR:inject(inj_tracing_ctx)
  if not inj_tracing_ctx then
    return nil, "tracing ctx to inject was not provided"
  end

  local headers, h_err = self:get_headers(inj_tracing_ctx)
  if not headers then
    return nil, h_err
  end

  for _, header in ipairs(headers) do
    set_header(header.name, header.value)
  end

  local formatted_trace_id, t_err = self:get_formatted_trace_id(inj_tracing_ctx)
  if not formatted_trace_id then
    return nil, t_err
  end
  return formatted_trace_id
end


-- Injector subclasses MUST implement this
-- TODO: doc
function _INJECTOR:get_headers()
  return nil, "headers() not implemented in base class"
end


-- Injector subclasses MUST implement this
-- TODO: doc
function _INJECTOR:get_formatted_trace_id()
  return nil, "trace_id() not implemented in base class"
end


return _INJECTOR
