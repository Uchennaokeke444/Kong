local char = string.char
local gsub = string.gsub

local function hex_to_char(c)
  return char(tonumber(c, 16))
end

local function from_hex(str)
  if str ~= nil then
    str = gsub(str, "%x%x", hex_to_char)
  end
  return str
end

-- adds `count` number of zeros to the left of str
local function left_pad_zero(str, count)
  return ('0'):rep(count-#str) .. str
end

return {
  from_hex = from_hex,
  left_pad_zero = left_pad_zero,
}
