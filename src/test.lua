(function()
	local exepath = package.cpath:sub(1, package.cpath:find(';')-6)
	package.path = package.path .. ';' .. exepath .. '..\\?.lua'
end)()

require 'filesystem'
require 'utility'

local read_triggerdata = require 'impl.read_triggerdata'
local wtg2txt = require 'impl.wtg2txt'


function string.create_lines(tab)
    local tabstr = ''
    for i = 1, tab or 0 do
        tabstr = tabstr .. '\t'
    end
    local mt = {}
    function mt:__call(fmt)
        self[#self+1] = tabstr .. fmt
        return function(...)
            self[#self] = tabstr .. fmt:format(...)
        end
    end
    return setmetatable({tab = tab}, mt)
end

local self = {}

local wtg = fs.path([[E:\GitHub\w3x2txt\物品属性\war3map.wtg]])
local txt = fs.path([[E:\GitHub\w3x2txt\物品属性\war3map.wtg.ini]])
read_triggerdata(self, fs.path([[E:\GitHub\YDWE\Build\publish\YDWE1.30.4测试版\share\mpq\ydwe\ui\TriggerData.txt]]))
read_triggerdata(self, fs.path([[E:\GitHub\YDWE\Build\publish\YDWE1.30.4测试版\share\mpq\ydtrigger\ui\TriggerData.txt]]))
read_triggerdata(self, fs.path([[E:\GitHub\YDWE\Build\publish\YDWE1.30.4测试版\share\mpq\japi\ui\TriggerData.txt]]))
wtg2txt(self, wtg, txt)
