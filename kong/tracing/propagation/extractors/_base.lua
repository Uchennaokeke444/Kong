local clear_header = kong.service.request.clear_header

local _EXTRACTOR = {}
_EXTRACTOR.__index = _EXTRACTOR


function _EXTRACTOR:new(e)
  e = e or {}
  e.headers = e.headers or {}
  return setmetatable(e, _EXTRACTOR)
end


function _EXTRACTOR:extract(headers)
  local ext_tracing_ctx, err = self:get_context(headers)
  -- after tracing ctx extraction, clear this extractor's headers from the
  -- current request
  self:clear_headers()

  if err then
    return nil, err
  end
  return ext_tracing_ctx
end


-- Extractor subclasses MUST implement this
-- TODO: doc
function _EXTRACTOR:get_context()
  return nil, "get_context() not implemented in base class"
end


function _EXTRACTOR:clear_headers()
  for _, header in ipairs(self.headers) do
    clear_header(header)
  end
end


return _EXTRACTOR
