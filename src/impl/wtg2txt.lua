local mt = {}

function mt:read_accept(...)
	self.pos = select(-1, ...)
	return ...
end

function mt:read(fmt)
	return self:read_accept(fmt:unpack(self.buf, self.pos))
end

--文件头
function mt:parseHeader(wtg)
	wtg.file_id, wtg.file_ver = self:read('c4l')
end

--触发器类别(文件夹)
function mt:parseCategories(wtg)
	wtg.categories = {}
	local category_count = self:read('l')
	for i = 1, category_count do
		self:parseCategory(wtg.categories)
	end
end

function mt:parseCategory(categories)
	local category = {}
	category.id, category.name, category.comment = self:read('lzl')
	table.insert(categories, category)
end

--全局变量
function mt:parseGlobals(wtg)
	local _, global_count = self:read('ll')
	wtg.globals = {}
	for i = 1, global_count do
		self:parseGlobal(wtg.globals)
	end
end

function mt:parseGlobal(globals)
	local global = {}
	global.name,       --变量名
	global.type,       --变量类型
	global.int_unknow_1,   --(永远是1,忽略)
	global.is_array,   --是否是数组(0不是, 1是)
	global.array_size, --数组大小(非数组是1)
	global.is_default, --是否是默认值(0是, 1不是)
	global.value       --初始数值
	= self:read('zzllllz')
	table.insert(globals, global)
	globals[global.name]  = global
end

--触发器
function mt:parseTriggers(wtg)
	wtg.triggers  = {}
	local trigger_count = self:read('l')
	for i = 1, trigger_count do
		self:parseTrigger(wtg.triggers)
	end
end

function mt:parseTrigger(triggers)
	local trigger = {}
	trigger.name,       --触发器名字
	trigger.des,        --触发器描述
	trigger.type,       --类型(0普通, 1注释)
	trigger.enable,     --是否允许(0禁用, 1允许)
	trigger.wct,        --是否是自定义代码(0不是, 1是)
	trigger.init,       --是否初始化(0是, 1不是)
	trigger.run_init,   --地图初始化时运行
	trigger.category    --在哪个文件夹下
	= self:read('zzllllll')
	local eca_count = self:read('l')
	table.insert(triggers, trigger)
	--初始化
	trigger.ecas = {}
	for i = 1, eca_count do
		self:parseEca(trigger.ecas)
	end
end

function mt:parseEca(ecas, is_child)
	local eca = {}
	table.insert(ecas, eca)
	--类型(0事件, 1条件, 2动作, 3函数调用)
	eca.type = self:read('l')
	--是否是复合结构
	if is_child then
		eca.child_id = self:read('l')
	end
	eca.name, eca.enable = self:read('zl')
	
	--参数
	eca.args    = {}
	if not self.function_state[eca.type][eca.name] then
		error(('没有找到%q的UI定义'):format(eca.name))
	end
	local state_args = self.function_state[eca.type][eca.name].args
	local arg_count = #state_args
	for i = 1, arg_count do
		self:parseArg(eca.args)
	end
	
	--if,loop等复合结构
	local eca_count = self:read('l')
	if eca_count > 0 then
		eca.ecas = {}
		for i = 1, eca_count do
			self:parseEca(eca.ecas, true)
		end
	end
end

function mt:parseArg(args)
	local arg = {}
	table.insert(args, arg)
	local has_eca
	arg.type, arg.value, has_eca = self:read('lzl')
	if has_eca == 1 then
		arg.ecas = {}
		self:parseEca(arg.ecas)
		self:read('l')
		return
	end
	local has_arg = self:read('l')
	if has_arg == 1 then
		self:parseArg(args)
	end
end

function mt:parse(wtg, buf, function_state)
	self.pos = 1
	self.buf = buf
	self.function_state = function_state
	self:parseHeader(wtg)
	self:parseCategories(wtg)
	self:parseGlobals(wtg)
	self:parseTriggers(wtg)
end

local stringify = require 'lni-stringify'

local function wtg2txt(self, file_name_in, file_name_out)
	local content = io.load(file_name_in)
	if not content then
		print('文件无效:' .. file_name_in:string())
		return
	end

	local wtg = {}
	mt:parse(wtg, content, self.function_state)

	io.save(file_name_out, stringify(wtg))
	do return end
	--开始转化文本
	local lines = string.create_lines(1)
	
	do
		--版本
		lines '[\'%s\']=%d,' ('VERSION', wtg.file_ver)
		lines '[\'%s\']=%d,' ('未知1', wtg.int_unknow_1)

		--全局变量
		local function f()
			local lines = string.create_lines(2)
			for i, global in ipairs(wtg.globals) do
				if global.is_array == 1 then
					if global.value ~= '' then
						lines '{%q, %q, %d, %q}' (global.type, global.name, global.array_size, global.value)
					else
						lines '{%q, %q, %d}' (global.type, global.name, global.array_size)
					end
				else
					if global.value ~= '' then
						lines '{%q, %q, %d, %q}' (global.type, global.name, 0, global.value)
					else
						lines '{%q, %q}' (global.type, global.name)
					end
				end
			end
			return table.concat(lines, ',\r\n')
		end
		
		lines '[\'%s\']={\r\n%s' ('全局变量', f())
		lines '},'

		--触发器类别(文件夹)
		local function f()
			local lines = string.create_lines(2)

			for _, category in ipairs(wtg.categories) do
				lines '{%q, %d, %d}' (
					category.name,
					category.id,
					category.comment
				)
			end

			return table.concat(lines, ',\r\n')
		end
		
		lines '[\'%s\']={\r\n%s' ('触发器类别', f())
		lines '},'
		

		--ECA结构
		

		--触发器
		local function f()
			local lines = string.create_lines(2)

			for _, trigger in ipairs(wtg.triggers) do
				local function f()
					local lines = string.create_lines(3)
					
					lines '[\'%s\']=%q' ('名称', trigger.name)
					lines '[\'%s\']=%q' ('描述', trigger.des)
					lines '[\'%s\']=%d' ('类型', trigger.type)
					lines '[\'%s\']=%d' ('允许', trigger.enable)
					lines '[\'%s\']=%d' ('自定义代码', trigger.wct)
					lines '[\'%s\']=%d' ('初始打开', trigger.init)
					lines '[\'%s\']=%d' ('初始化运行', trigger.run_init)
					lines '[\'%s\']=%d' ('类别', trigger.category)

					--触发器ECA
					local max       = #trigger.ecas
					if max > 0 then
						
						local function f()
							local lines = string.create_lines(4)
							local lines_event = string.create_lines(5)
							local lines_condition = string.create_lines(5)
							local lines_action = string.create_lines(5)
						
							local tab   = 1
							local ecas, index = trigger.ecas, 1

							local function push_eca(eca, lines_arg)
								if not eca then
									eca = ecas[index]
									index   = index + 1
									if not eca then
										return false
									end
								end
								
								local lines
								if lines_arg then
									lines = lines_arg
								else
									if eca.type == 0 then
										lines = lines_event
									elseif eca.type == 1 then
										lines = lines_condition
									elseif eca.type == 2 then
										lines = lines_action
									else
										print('eca类型错误', eca.type)
									end
								end

								local function f(tab)
									local lines = string.create_lines()

									lines '%q' (eca.name)
									if eca.enable == 0 then
										lines 'false'
									end
									return table.concat(lines, ', ')
								end

								if #eca.args == 0 then
									lines '{%s}' (f(lines.tab))
								else
									--参数
									local function f2(tab)
										local lines = string.create_lines()
										
										local function f(tab)
											local lines = string.create_lines(tab + 1)
											local index = 1

											local function push_arg(arg, lines_arg)
												if not arg then
													arg = eca.args[index]
													index = index + 1
													if not arg then
														return
													end
												end

												local lines = lines_arg or lines
												
												if arg.insert_call == 1 then
													push_eca(arg.eca, lines)
												else
													--索引
													if arg.insert_index == 1 then
														local function f2(tab)
															local lines = string.create_lines()
															
															local function f(tab)
																local lines = string.create_lines(tab + 1)
																push_arg(nil, lines)
																return table.concat(lines, ',\r\n')
															end
															lines '[\'%s\']={\r\n%s' ('索引', f(tab))
															return table.concat(lines, '\r\n')
														end
														
														lines '{%q, %d, %s' (arg.value, arg.type, f2(lines.tab))
														lines '}}'
													else
														lines '{%q, %d}' (arg.value, arg.type)
													end
												end
												return arg
											end

											while push_arg() do
											end

											return table.concat(lines, ',\r\n')
										end

										lines '[\'%s\']={\r\n%s' ('参数', f(tab))
										return table.concat(lines, '\r\n')
									end

									lines '{%s, %s' (f(lines.tab), f2(lines.tab))
									lines '}}'
								end
								return true
							end
							--ECA结构
							while push_eca() do
							end

							lines '[\'%s\']={\r\n%s' ('事件', table.concat(lines_event, ',\r\n'))
							lines '},'

							lines '[\'%s\']={\r\n%s' ('条件', table.concat(lines_condition, ',\r\n'))
							lines '},'

							lines '[\'%s\']={\r\n%s' ('动作', table.concat(lines_action, ',\r\n'))
							lines '},'

							return table.concat(lines, '\r\n')
						end
						
						lines '[\'%s\']={\r\n%s' ('触发', f())
						lines '}'
						
					end
					return table.concat(lines, ',\r\n')
				end
				lines '{\r\n%s' (f(trigger))
				lines '},'
				
			end

			return table.concat(lines, '\r\n')
		end
		
		lines '[\'%s\']={\r\n%s' ('触发器', f())
		lines '},'
		
		
	end

	io.save(file_name_out, table.concat(lines, '\r\n'))--:convert_wts(true))
end

return wtg2txt
