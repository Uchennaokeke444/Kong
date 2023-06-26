local kong_meta       = require "kong.meta"
local tracing_context = require "kong.tracing.tracing_context"

local table_insert        = table.insert
local ngx_req_get_headers = ngx.req.get_headers

local EXTRACTORS_PATH = "kong.plugins.tracing-headers-propagation.extractors."
local INJECTORS_PATH  = "kong.plugins.tracing-headers-propagation.injectors."


local TracingHeadersPropagationHandler = {
  VERSION = kong_meta.version,
  -- Run before all tracing plugins
  PRIORITY = 100001,
}


-- Extract tracing data from incoming tracing headers
-- @tparam table conf Plugin configuration
-- @treturn table|nil Tracing context
local function extract_tracing_context(conf)
  local tracing_data = {}
  local headers = ngx_req_get_headers()

  local extractors = conf.extract
  if not extractors then
    -- configuring no extractors is valid to disable
    -- context extraction from incoming tracing headers
    return tracing_data
  end

  for extractor_m in extractors do
    local extractor = require(EXTRACTORS_PATH .. extractor_m)
    local ctx = extractor:extract(headers)

    if ctx then
      tracing_data = ctx
      kong.ctx.plugin.extracted_from = extractor_m
      break
    end
  end

  return tracing_data
end


-- Sync tracing context with the current request tracing context
-- @tparam table tracing_data Tracing context
--   Example:
--    tracing_data = {
--      trace_id = "1234567890abcdef",
--      span_id = "1234",
--      parent_id = "1234567890abcdef",
--      should_sample = true,
--      baggage = {},
--    }
local function sync_tracing_context(incoming_tracing_data)
  if not incoming_tracing_data or next(incoming_tracing_data) == nil then
    return
  end



  -- INTERACT WITH CORE TRACING HERE (TMP):
  local root_span = ngx.ctx.KONG_SPANS and ngx.ctx.KONG_SPANS[1]
  -- get the global tracer when available, or instantiate a new one
  local tracer = kong.tracing.name == "noop" and kong.tracing.new("propagation")
                 or kong.tracing
  -- make propagation work with tracing disabled
  if not root_span then
    root_span = tracer.start_span("root")
    root_span:set_attribute("kong.propagation_only", true)
  end
  local injected_parent_span = tracing_context.get_unlinked_span("balancer") or root_span

  -- sync tracing_data with the current request tracing context
  -- e.g. call set_raw_trace_id etc
  if incoming_tracing_data.trace_id then
    injected_parent_span.trace_id = incoming_tracing_data.trace_id
    tracing_context.set_raw_trace_id(incoming_tracing_data.trace_id)
  end

  --...

  -- TODO: continue here maybe we can avoid some of this stuff if we 
  -- can keep it in otel


  -- TODO: add the rest of the information in the `extracted` table in the tracing context
  -- maybe use something like tr_context.add_extracted_info to call for each key except trace_id?
  -- use ctx_namespace to put them in the right place
  return tracing_context.get()
end


-- Inject tracing context into outgoing requests
-- @tparam table injectors The configured injectors
local function inject_tracing_context(injectors, tracing_ctx)
  if not injectors then
    -- configuring no injectors is valid to disable
    -- context injection in outgoing requests
    return true
  end

  local err = {}
  for injector_m in injectors do
    if injector_m == "preserve" then
      -- preserve the incoming tracing header type
      injector_m = kong.ctx.plugin.extracted_from
    end

    local injector = require(INJECTORS_PATH .. injector_m)

    -- inject tracing context information in outgoing headers
    -- and obtain the formatted trace_id
    local formatted_trace_id, injection_err = injector.inject(tracing_ctx)

    if not formatted_trace_id then
      table_insert(err, injection_err)
    else
      tracing_context.add_trace_id_formats(formatted_trace_id)
    end
  end

  if #err > 0 then
    return nil, table.concat(err, ", ")
  end

  kong.log.set_serialize_value("trace_id", tracing_context.trace_id.formatted)
  return true
end


function TracingHeadersPropagationHandler:accssess(conf)
  -- tracing context extraction
  local incoming_tracing_info, extraction_err = extract_tracing_context(conf)
  if not incoming_tracing_info then
    kong.log.err("failed to extract tracing context: ", extraction_err)
  end

  -- tracing context sync
  local synced_context = sync_tracing_context(incoming_tracing_info)

  -- tracing context injection
  local injectors = conf.inject
  local ok, injection_err = inject_tracing_context(injectors, synced_context)
  if not ok then
    kong.log.err("failed to inject tracing context: ", injection_err)
  end
end


return TracingHeadersPropagationHandler
