local function server_error(message)
  return { status = 500, message = message }
end

local function unauthorized(message, www_auth_content)
  return { status = 401, message = message, headers = { ["WWW-Authenticate"] = www_auth_content } }
end

return {
  server_error = server_error,
  unauthorized = unauthorized
}
