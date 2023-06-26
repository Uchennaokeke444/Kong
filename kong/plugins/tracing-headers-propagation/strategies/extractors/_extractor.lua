Extractor = {}

Extractor.__index = Extractor

function Extractor:new(e)
  e = e or {} -- TODO: remove if not needed
  return setmetatable(e, Extractor)
end

function Extractor:extract(headers)
  return nil, "not implemented in base class"
end

return Extractor
