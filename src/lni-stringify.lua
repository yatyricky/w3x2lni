local function stringify_object(name, input, output)
    local hash = {}
    local children = {}
    for key, value in pairs(input) do
        if type(key) == 'string' then
            if type(value) == 'string' then
                table.insert(hash, {key, ("%s = %q"):format(key, value)})
            elseif type(value) == 'number' then
                if math.type(value) == 'integer' then
                    table.insert(hash, {key, ("%s = %d"):format(key, value)})
                else
                    table.insert(hash, {key, ("%s = %f"):format(key, value)})
                end
            elseif type(value) == 'table' then
                table.insert(children, {key, value})
            else
                error('error value type in "' ..  key .. '": ' .. type(value))
            end
        elseif type(key) == 'number' then
            if type(value) ~= 'table' then
                error('error value type in "' ..  key .. '": ' .. type(value))
            end
        else
            error('error key type : ' .. type(key))
        end
    end
    table.sort(hash, function(a, b) return a[1] < b[1] end)
    table.sort(children, function(a, b) return a[1] < b[1] end)
    if next(hash) ~= nil then
        if name:sub(-2) == '[]' then
            table.insert(output, ("[[%s]]"):format(name:sub(1, -3)))
        else
            table.insert(output, ("[%s]"):format(name))
        end
    end
    for _, t in ipairs(hash) do
        table.insert(output, t[2])
    end
    for _, t in ipairs(children) do
        if name == 'root' then
            stringify_object(t[1], t[2], output)
        else
            stringify_object(name .. '.' .. t[1], t[2], output)
        end
    end
    local i = 1
    while input[i] do
        stringify_object(name .. '[]', input[i], output)
        i = i + 1
    end
end
local function stringify_root(input, output)
    for key, value in pairs(input) do
        if type(key) == 'string' then
            if type(value) == 'table' then
                stringify_object(key, value, output)
            else
                error('error value type in "' ..  key .. '": ' .. type(value))
            end
        else
            error('error key type : ' .. type(key))
        end
    end
end

return function(input)
    local output = {}
    stringify_object('root', input, output)
    return table.concat(output, '\r\n')
end
