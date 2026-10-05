package server

// `json`, as the script sees it: json.encode(value) and json.decode(text) between Lua and
// JSON; a table with keys 1..n is an array, any other an object; json.null stands for a
// null, as nil cannot be held in a table; json.array(t) marks a table (an empty one) as
// an array, and a decoded array comes so marked. It is Lua, run as the script's state is
// made, so what the script gets back is exactly what Lua makes of it.

JSON_PRELUDE :: `
json = {}
json.null = setmetatable({}, {__tostring = function() return 'null' end})
local escapes = {['"'] = '\\"', ['\\'] = '\\\\', ['\b'] = '\\b', ['\f'] = '\\f',
  ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t'}
local function is_array(t)
  local n = 0
  for k in pairs(t) do
    if type(k) ~= 'number' or k ~= math.floor(k) or k < 1 then return false end
    n = n + 1
  end
  return n == #t
end
local function encode(v, out)
  local t = type(v)
  if v == json.null or v == nil then out[#out + 1] = 'null'
  elseif t == 'boolean' then out[#out + 1] = tostring(v)
  elseif t == 'number' then
    if v ~= v or v == math.huge or v == -math.huge then error('json: a number must be finite') end
    if v == math.floor(v) and math.abs(v) < 2^53 then out[#out + 1] = string.format('%d', v)
    else out[#out + 1] = string.format('%.14g', v) end
  elseif t == 'string' then
    out[#out + 1] = '"' .. v:gsub('[%c"\\]', function(c)
      return escapes[c] or string.format('\\u%04x', c:byte()) end) .. '"'
  elseif t == 'table' then
    if #v > 0 or (next(v) == nil and getmetatable(v) == json.array_mt) then
      if not is_array(v) then error('json: a table with both numbered and named keys') end
      out[#out + 1] = '['
      for i = 1, #v do
        if i > 1 then out[#out + 1] = ',' end
        encode(v[i], out)
      end
      out[#out + 1] = ']'
    else
      out[#out + 1] = '{'
      local first = true
      for k, val in pairs(v) do
        if type(k) ~= 'string' then error('json: an object key must be a string') end
        if not first then out[#out + 1] = ',' end
        first = false
        encode(k, out)
        out[#out + 1] = ':'
        encode(val, out)
      end
      out[#out + 1] = '}'
    end
  else error('json: cannot encode a ' .. t) end
end
json.array_mt = {}
function json.array(t) return setmetatable(t or {}, json.array_mt) end
function json.encode(v) local out = {}; encode(v, out); return table.concat(out) end
local decode_value
local function skip(s, i) return s:find('%S', i) or #s + 1 end
local function decode_string(s, i)
  local out, j = {}, i + 1
  while true do
    local c = s:sub(j, j)
    if c == '' then error('json: an unterminated string') end
    if c == '"' then return table.concat(out), j + 1 end
    if c == '\\' then
      local e = s:sub(j + 1, j + 1)
      local map = {b = '\b', f = '\f', n = '\n', r = '\r', t = '\t', ['"'] = '"', ['\\'] = '\\', ['/'] = '/'}
      if e == 'u' then
        local code = tonumber(s:sub(j + 2, j + 5), 16)
        if not code then error('json: a bad \\u escape') end
        out[#out + 1] = utf8.char(code)
        j = j + 6
      elseif map[e] then out[#out + 1] = map[e]; j = j + 2
      else error('json: a bad escape \\' .. e) end
    else out[#out + 1] = c; j = j + 1 end
  end
end
function decode_value(s, i)
  i = skip(s, i)
  local c = s:sub(i, i)
  if c == '{' then
    local obj = {}
    i = skip(s, i + 1)
    if s:sub(i, i) == '}' then return obj, i + 1 end
    while true do
      i = skip(s, i)
      if s:sub(i, i) ~= '"' then error('json: an object key must be a string, at ' .. i) end
      local key; key, i = decode_string(s, i)
      i = skip(s, i)
      if s:sub(i, i) ~= ':' then error('json: expected a colon at ' .. i) end
      obj[key], i = decode_value(s, i + 1)
      i = skip(s, i)
      local d = s:sub(i, i)
      if d == '}' then return obj, i + 1 end
      if d ~= ',' then error('json: expected a comma at ' .. i) end
      i = i + 1
    end
  elseif c == '[' then
    local arr = json.array()
    i = skip(s, i + 1)
    if s:sub(i, i) == ']' then return arr, i + 1 end
    while true do
      arr[#arr + 1], i = decode_value(s, i)
      i = skip(s, i)
      local d = s:sub(i, i)
      if d == ']' then return arr, i + 1 end
      if d ~= ',' then error('json: expected a comma at ' .. i) end
      i = i + 1
    end
  elseif c == '"' then return decode_string(s, i)
  elseif s:sub(i, i + 3) == 'true' then return true, i + 4
  elseif s:sub(i, i + 4) == 'false' then return false, i + 5
  elseif s:sub(i, i + 3) == 'null' then return json.null, i + 4
  else
    local num = s:match('^-?%d+%.?%d*[eE]?[-+]?%d*', i)
    if not num or num == '' then error('json: unexpected text at ' .. i) end
    return tonumber(num), i + #num
  end
end
function json.decode(s)
  local v, i = decode_value(s, 1)
  if skip(s, i) <= #s then error('json: text after the value at ' .. i) end
  return v
end
`
