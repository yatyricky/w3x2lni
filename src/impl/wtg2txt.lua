local mt = {}

local self
local index	= 1
local content
--local len	= #content
local chunk	= {}
local categories, category, vars, var, triggers, trigger, ecas, eca, args, arg

function mt:read_accept(...)
	index = select(-1, ...)
	return ...
end

function mt:read(fmt)
	return self:read_accept(fmt:unpack(content, index))
end

--文件头
function mt:readHead()
	chunk.file_id,			--文件ID
	chunk.file_ver			--文件版本
	= self:read('c4l')
end
--触发器类别(文件夹)
function mt:readCategories()
	--触发器类别数量
	chunk.category_count = self:read('l')
	--初始化
	categories	= {}
	chunk.categories	= categories
	for i = 1, chunk.category_count do
		self:readCategory()
	end
end
function mt:readCategory()
	category	= {}
	category.id, category.name, category.comment = self:read('lzl')
	table.insert(categories, category)
end
--全局变量
function mt:readVars()
	--全局变量数量
	chunk.int_unknow_1, chunk.var_count = self:read('ll')
	
	--初始化
	vars	= {}
	chunk.vars	= vars
	for i = 1, chunk.var_count do
		self:readVar()
	end
end
function mt:readVar()
	var	= {}
	var.name,		--变量名
	var.type,		--变量类型
	var.int_unknow_1,	--(永远是1,忽略)
	var.is_array,	--是否是数组(0不是, 1是)
	var.array_size,	--数组大小(非数组是1)
	var.is_default,	--是否是默认值(0是, 1不是)
	var.value		--初始数值
	= self:read('zzllllz')
	table.insert(vars, var)
	vars[var.name]	= var
end
--触发器
function mt:readTriggers()
	--触发器数量
	chunk.trigger_count	= self:read('l')
	--初始化
	triggers	= {}
	chunk.triggers	= triggers
	for i = 1, chunk.trigger_count do
		self:readTrigger()
	end
end
function mt:readTrigger()
	trigger	= {}
	trigger.name,		--触发器名字
	trigger.des,		--触发器描述
	trigger.type,		--类型(0普通, 1注释)
	trigger.enable,		--是否允许(0禁用, 1允许)
	trigger.wct,		--是否是自定义代码(0不是, 1是)
	trigger.init,		--是否初始化(0是, 1不是)
	trigger.run_init,	--地图初始化时运行
	trigger.category	--在哪个文件夹下
	= self:read('zzllllll')
	table.insert(triggers, trigger)
	--print('trigger:' .. trigger.name)
	--读取子结构
	self:readEcas()
end
--子结构
function mt:readEcas()
	--子结构数量
	trigger.eca_count = self:read('l')
	--初始化
	ecas	= {}
	trigger.ecas	= ecas
	for i = 1, trigger.eca_count do
		self:readEca()
	end
end
function mt:readEca(is_child, is_arg)
	eca	= {}
	local eca	= eca
	
	eca.type	--类型(0事件, 1条件, 2动作, 3函数调用)
	= self:read('l')
	--是否是复合结构
	if is_child then
		eca.child_id = self:read('l')
	end
	--是否是参数中的子函数
	if is_arg then
		is_arg.eca	= eca
	else
		table.insert(ecas, eca)
	end
	
	eca.name,	--名字
	eca.enable	--是否允许(0不允许, 1允许)
	= self:read('zl')
	--print('eca:' .. eca.name)
	--读取参数
	self:readArgs(eca)
	--if,loop等复合结构
	eca.child_eca_count = self:read('l')
	for i = 1, eca.child_eca_count do
		self:readEca(true)
	end
end
--参数
function mt:readArgs(eca)
	--初始化
	args	= {}
	local args	= args
	eca.args	= args
	--print(eca.type, eca.name)
	if not self.function_state[eca.type][eca.name] then
		error(('没有找到%q的UI定义'):format(eca.name))
	end
	local state_args	= self.function_state[eca.type][eca.name].args
	local arg_count	= #state_args
	--print('args:' .. arg_count)
	for i = 1, arg_count do
		self:readArg(args)
	end
end
function mt:readArg(args)
	arg	= {}
	arg.type, 			--类型(0预设, 1变量, 2函数, 3代码)
	arg.value,			--值
	arg.insert_call	--是否需要插入调用
	= self:read('lzl')
	--print('var:' .. arg.value)
	--是否是索引
	table.insert(args, arg)
	--插入调用
	if arg.insert_call == 1 then
		self:readEca(false, arg)
		arg.int_unknow_1 = self:read('l') --永远是0
		--print(arg.int_unknow_1)
		return
	end
	arg.insert_index	--是否需要插入数组索引
	= self:read('l')
	--插入数组索引
	if arg.insert_index == 1 then
		self:readArg(args)
	end
end


local function wtg2txt(_self, file_name_in, file_name_out)
	mt.function_state = _self.function_state
	content	= io.load(file_name_in)
	if not content then
		print('文件无效:' .. file_name_in:string())
		return
	end

	--开始解析
	mt:readHead()
	mt:readCategories()
	mt:readVars()
	mt:readTriggers()

	--开始转化文本
	local lines	= string.create_lines(1)
	
	do
		--版本
		lines '[\'%s\']=%d,' ('VERSION', chunk.file_ver)
		lines '[\'%s\']=%d,' ('未知1', chunk.int_unknow_1)

		--全局变量
		local function f()
			local lines = string.create_lines(2)
			for i, var in ipairs(chunk.vars) do
				if var.is_array == 1 then
					if var.value ~= '' then
						lines '{%q, %q, %d, %q}' (var.type, var.name, var.array_size, var.value)
					else
						lines '{%q, %q, %d}' (var.type, var.name, var.array_size)
					end
				else
					if var.value ~= '' then
						lines '{%q, %q, %d, %q}' (var.type, var.name, 0, var.value)
					else
						lines '{%q, %q}' (var.type, var.name)
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

			for _, category in ipairs(chunk.categories) do
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

			for _, trigger in ipairs(chunk.triggers) do
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
					local max		= #trigger.ecas
					if max > 0 then
						
						local function f()
							local lines = string.create_lines(4)
							local lines_event = string.create_lines(5)
							local lines_condition = string.create_lines(5)
							local lines_action = string.create_lines(5)
						
							local tab	= 1
							local ecas, index = trigger.ecas, 1

							local function push_eca(eca, lines_arg)
								if not eca then
									eca	= ecas[index]
									index	= index + 1
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
