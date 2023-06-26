local tracing_context     = require "kong.tracing.tracing_context"
local table_new           = require "table.new"

local table_insert        = table.insert
local ngx_req_get_headers = ngx.req.get_headers
local null                = ngx.null


local EXTRACTORS_PATH = "kong.tracing.propagation.extractors."
local INJECTORS_PATH  = "kong.tracing.propagation.injectors."


-- This function retrieves the queue parameters from a plugin configuration,
-- converting legacy parameters to their new locations.
local function get_plugin_params(config)
  local propagation_config = config.propagation or table_new(0, 3)

  for _, v in pairs(propagation_config) do
    if (v or null) ~= null then
      -- if the new configuration is set, return it as is
      return propagation_config
    end
  end

  if (config.default_header_type or null) ~= null then
    propagation_config.default_format = config.default_header_type

    kong.log.warn(
      "the default_header_type parameter is deprecated, please update your "
      .. "configuration to use propagation.default_format instead")
  end

  if (config.header_type or null) ~= null then
    if config.header_type == "preserve" then
      propagation_config.extract = {
        "b3",
        "b3-single",
        "w3c",
        "jaeger",
        "ot",
        "aws",
        "gcp",
      }
      propagation_config.inject = { "preserve" }
    elseif config.header_type == "ignore" then
      propagation_config.inject = propagation_config.default_format or { "b3" }
    else
      propagation_config.extract = { config.header_type }
      propagation_config.inject = { config.header_type }
    end

    kong.log.warn(
      "the header_type parameter is deprecated, please update your "
      .. "configuration to use propagation.extract and propagation.inject instead")
  end

  return propagation_config
end


-- Extract tracing data from incoming tracing headers
-- @param table conf Plugin configuration
-- @return table|nil Tracing context
local function extract_tracing_context(conf)
  local tracing_data = {}
  local headers = ngx_req_get_headers()

  local extractors = conf.extract
  if not extractors then
    -- configuring no extractors is valid to disable
    -- context extraction from incoming tracing headers
    return tracing_data
  end

  local extracted_ctx
  for _, extractor_m in ipairs(extractors) do
    local extractor = require(EXTRACTORS_PATH .. extractor_m)

    if not extracted_ctx then
      -- extract tracing context only from the first successful extractor
      extracted_ctx = extractor:extract(headers)
      tracing_data = extracted_ctx
      kong.ctx.plugin.extracted_from = extractor_m
    end
  end

  return tracing_data
end


-- Inject tracing context into outgoing requests
-- @param table injectors The configured injectors
local function inject_tracing_context(propagation_conf, inject_ctx)
  local injectors = propagation_conf.inject
  if not injectors then
    -- configuring no injectors is valid to disable
    -- context injection in outgoing requests
    return
  end

  local err = {}
  local trace_id_formats
  for _, injector_m in ipairs(injectors) do
    if injector_m == "preserve" then
      -- preserve the incoming tracing header type
      injector_m = kong.ctx.plugin.extracted_from or propagation_conf.default_format or "w3c"
    end

    local injector = require(INJECTORS_PATH .. injector_m)

    -- inject tracing context information in outgoing headers
    -- and obtain the formatted trace_id
    local formatted_trace_id, injection_err = injector:inject(inject_ctx)
    if formatted_trace_id then
      trace_id_formats = tracing_context.add_trace_id_formats(formatted_trace_id)
    else
      table_insert(err, injection_err)
    end
  end

  if #err > 0 then
    return nil, table.concat(err, ", ")
  end
  return trace_id_formats
end


local function propagate(propagation_conf, get_inject_ctx_cb)
  -- Tracing context extraction
  local extract_ctx, extract_err = extract_tracing_context(propagation_conf)
  if not extract_ctx then
    kong.log.err("failed to extract tracing context: ", extract_err)
  end

  -- Obtain the inject ctx (data for outgoing tracing headers). The logic to
  -- obtain this is plugin-specific, defined in the callback parameter.
  local inject_ctx = extract_ctx
  if get_inject_ctx_cb then
    inject_ctx = get_inject_ctx_cb(extract_ctx)
  end

  -- Tracing context injection and formatted trace_ids logging
  local trace_id_formats, injection_err =
      inject_tracing_context(propagation_conf, inject_ctx)
  if trace_id_formats then
    kong.log.set_serialize_value("trace_id", trace_id_formats)
  elseif injection_err then
    kong.log.err("failed to inject tracing context: ", injection_err)
  end
end


return {
  propagate = propagate,
  get_plugin_params = get_plugin_params,
}
