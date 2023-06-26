local function validate_inject(header_formats)
  if header_formats == nil then
    return true
  end

  for _, v in ipairs(header_formats) do
    if v == "preserve" then
      if #header_formats > 1 then
        return nil, "if \"preserve\" is specified, it must be the only value in the list"
      end


    end
  end
  return true
end

local header_types = {
  "w3c",
  "b3",
  "b3-single",
  "jaeger",
  "ot",
  "aws",
  "gcp",
  "datadog"
}


return {
  name = "tracing-headers-propagation",
  fields = { {
    config = {
      type = "record",
      fields = {
        {
          extract = {
            description = "Header formats used to extract tracing context from incoming requests. If multiple values are specified, the first one found will be used for extraction. If left empty, Kong will not extract any tracing context information from incoming requests and generate a trace with no parent and a new trace ID.",
            type = "array",
            elements = {
              type = "string",
              one_of = header_types
            },
          }
        },
        {
          inject = {
            description = "Header formats used to inject tracing context. The value `preserve` will use the same header format as the incoming request. If multiple values are specified, all of them will be used during injection. If left empty, Kong will not inject any tracing context information in outgoing requests.",
            type = "array",
            elements = {
              type = "string",
              one_of = { "preserve", table.unpack(header_types) }
            },
            custom_validator = validate_inject,
          }
        },
      },
      custom_validator = function(config)
        -- check that when inject contains `preserve`, the `extract` field is not empty
        if config.inject and type(config.inject) == "table" and config.inject[1] == "preserve" and
            (not config.extract or type(config.extract) ~= "table" or #config.extract == 0) then
          return nil, "cannot use `preserve` injection strategy when `extract` is empty"
        end
        return true
      end,
    },
  }, },
}
