local schema_def = require "kong.plugins.tracing-headers-propagation.schema"
local validate_plugin_config_schema = require "spec.helpers".validate_plugin_config_schema

describe("Plugin: tracing-headers-propagation (schema)", function()
  it("rejects invalid inject configuration", function()
    local ok, err = validate_plugin_config_schema({
      extract = {
        "w3c",
      },
      inject = {
        "preserve",
        "w3c",
      },
    }, schema_def)

    assert.is_falsy(ok)
    assert.same({ config = {
        inject = "if \"preserve\" is specified, it must be the only value in the list",
    } }, err)
  end)

  it("rejects incompatible inject/extract configurations", function()
    local ok, err = validate_plugin_config_schema({
      inject = {
        "preserve"
      },
    }, schema_def)

    assert.is_falsy(ok)
    assert.same({ config =  "cannot use `preserve` injection strategy when `extract` is empty" }, err)
  end)

  it("accepts valid inject configuration", function()
    local ok = validate_plugin_config_schema({
      extract = {
        "w3c",
      },
      inject = {
        "preserve",
      }
    }, schema_def)

    assert.is_truthy(ok)
  end)
end)
