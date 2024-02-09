local cjson = require "cjson.safe"
local raw_log = require "ngx.errlog".raw_log

local _, ngx_pipe = pcall(require, "ngx.pipe")
local worker_id = ngx.worker.id
local native_timer_at = _G.native_timer_at or ngx.timer.at


local kong = kong
local ngx_INFO = ngx.INFO
local cjson_decode = cjson.decode
local SIGTERM = 15


local proc_mgmt = {}


--[[

Plugin info requests

Disclaimer:  The best way to do it is to have "ListPlugins()" and "GetInfo(plugin)"
RPC methods; but Kong would like to have all the plugin schemas at initialization time,
before full cosocket is available.  At one time, we used blocking I/O to do RPC at
non-yielding phases, but was considered dangerous.  The alternative is to use
`io.popen(cmd)` to ask fot that info.

The pluginserver_XXX_query_cmd contains a string to be executed as a command line.
The output should be a JSON string that decodes as an array of objects, each
defining the name, priority, version,  schema and phases of one plugin.

    [{
      "name": ... ,
      "priority": ... ,
      "version": ... ,
      "schema": ... ,
      "phases": [ phase_names ... ],
    },
    {
      ...
    },
    ...
    ]

This array should describe all plugins currently available through this server,
no matter if actually enabled in Kong's configuration or not.

--]]
local _plugin_infos

local function query_external_plugin_info(server_def)
  if not server_def.query_command then
    return nil, "no info query for " .. server_def.name
  end

  local fd, err = io.popen(server_def.query_command)
  if not fd then
    return nil, string.format("error loading plugins info from [%s]: %s", server_def.name, err)
  end

  local infos_dump = fd:read("*a")
  fd:close()
  local dump, err = cjson_decode(infos_dump)
  if err then
    return nil, "failed decoding plugin info: " .. err
  end

  if type(dump) ~= "table" then
    return nil, string.format("not a plugin info table: \n%s\n%s", server_def.query_command, infos_dump)
  end

  server_def.protocol = dump.Protocol or "MsgPack:1"
  local infos = dump.Plugins or dump

  -- once upon a time, a plugin server could serve more than one plugin
  -- nowadays, external plugins use an "embedded pluginserver" model, where
  -- each plugin acts as a pluginserver
  for _, plugin_info in ipairs(infos) do
    _plugin_infos[plugin_info.Name] = {
      server_def = server_def,
      --rpc = server_def.rpc,
      name = plugin_info.Name,
      PRIORITY = plugin_info.Priority,
      VERSION = plugin_info.Version,
      schema = plugin_info.Schema,
      phases = plugin_info.Phases,
    }
  end

  return true
end


local function load_external_plugins_info(kong_conf)
  if not _plugin_infos then
    _plugin_infos = {}
    for _, server_def in ipairs(kong_conf.pluginservers) do
      local plugin_info, err = query_external_plugin_info(server_def)
      if not plugin_info then
        return nil, err
      end
    end
  end

  return true
end

function proc_mgmt.get_plugin_info(plugin_name, kong_conf)
  local ok, err = load_external_plugins_info(kong_conf)
  if not ok then
    return nil, err
  end
  return _plugin_infos[plugin_name]
end


--[[

Process management

Pluginservers with a corresponding `pluginserver_XXX_start_cmd` field are managed
by Kong.  Stdout and stderr are joined and logged, if it dies, Kong logs the
event and respawns the server.

If the `_start_cmd` is unset (and the default doesn't exist in the filesystem)
it's assumed the process is managed externally.

--]]

local function grab_logs(proc, name)
  local prefix = string.format("[%s:%d] ", name, proc:pid())

  while true do
    local data, err, partial = proc:stdout_read_line()
    local line = data or partial
    if line and line ~= "" then
      raw_log(ngx_INFO, prefix .. line)
    end

    if not data and (err == "closed" or ngx.worker.exiting()) then
      return
    end
  end
end


local function pluginserver_timer(premature, server_def)
  if premature then
    return
  end

  if ngx.config.subsystem ~= "http" then
    return
  end

  local next_spawn = 0

  while not ngx.worker.exiting() do
    if ngx.now() < next_spawn then
      ngx.sleep(next_spawn - ngx.now())
    end

    kong.log.notice("Starting " .. server_def.name or "")
    server_def.proc = assert(ngx_pipe.spawn("exec " .. server_def.start_command, {
      merge_stderr = true,
    }))
    next_spawn = ngx.now() + 1
    server_def.proc:set_timeouts(nil, nil, nil, 0)     -- block until something actually happens

    while true do
      grab_logs(server_def.proc, server_def.name)
      local ok, reason, status = server_def.proc:wait()
      if ok == false and reason == "exit" and status == 127 then
        kong.log.err(string.format(
                "external pluginserver %q start command %q exited with \"command not found\"",
                server_def.name, server_def.start_command))
        break
      elseif ok ~= nil or reason == "exited" or ngx.worker.exiting() then
        kong.log.notice("external pluginserver '", server_def.name, "' terminated: ", tostring(reason), " ", tostring(status))
        break
      end
    end
  end
  kong.log.notice("Exiting: pluginserver '", server_def.name, "' not respawned.")
end


function proc_mgmt.start_pluginservers()
  local kong_config = kong.configuration

  -- only worker 0 manages plugin server processes
  if worker_id() == 0 then -- TODO move to privileged worker?
    local pluginserver_timer = pluginserver_timer

    for _, server_def in ipairs(kong_config.pluginservers) do
      if server_def.start_command then
        native_timer_at(0, pluginserver_timer, server_def)
      end
    end
  end

  return true
end

function proc_mgmt.stop_pluginservers()
  local kong_config = kong.configuration

  -- only worker 0 manages plugin server processes
  if worker_id() == 0 then -- TODO move to privileged worker?
    for _, server_def in ipairs(kong_config.pluginservers) do
      if server_def.proc then
        server_def.proc:kill(SIGTERM)
      end
    end
  end

  return true
end

return proc_mgmt
