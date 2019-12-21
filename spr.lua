---------------------------------------------------------------------
-- spr: Spring-driven animation library
--
-- Copyright (c) 2019 Parker Stebbins. All rights reserved.
-- Released under the MIT license.
--
-- License & docs can be found at https://github.com/Fraktality/spr
--
-- API Summary:
--
--  spr.target(
--     Instance obj,
--     number dampingRatio,
--     number undampedFrequency,
--     dict<string, variant> targetProperties)
--
--     Animates the given properties towardes the desired values on
--     a spring with a given damping ratio and undamped frequency.
--
--
--  spr.stop(
--     Instance obj,
--     string property)
--
--     Stops the specified property from animating on an object.
--
---------------------------------------------------------------------

local SLEEP_OFFSET_SQ_LIMIT = 1e-4^2
local SLEEP_VELOCITY_SQ_LIMIT = 1e-2^2

local RunService = game:GetService("RunService")

local pi = math.pi
local abs = math.abs
local exp = math.exp
local sin = math.sin
local cos = math.cos
local min = math.min
local sqrt = math.sqrt

local function magnitudeSq(v)
	local out = 0
	for i = 1, #v do
		out = out + v[i]*v[i]
	end
	return out
end

local function distanceSq(v0, v1)
	local out = 0
	for idx = 1, #v0 do
		local d = v1[idx] - v0[idx]
		out = out + d*d
	end
	return out
end

-- an array of values defining basic arithmetic ops
local LinearValue = {} do
	LinearValue.__index = LinearValue

	function LinearValue:__add(rhs)
		local out = setmetatable({unpack(self)}, LinearValue)
		for i = 1, #out do
			out[i] = out[i] + rhs[i]
		end
		return out
	end

	function LinearValue:__sub(rhs)
		local out = setmetatable({unpack(self)}, LinearValue)
		for i = 1, #out do
			out[i] = out[i] - rhs[i] 
		end
		return out
	end

	function LinearValue:__mul(rhs)
		local out = setmetatable({unpack(self)}, LinearValue)
		for i = 1, #out do
			out[i] = out[i]*rhs
		end
		return out
	end

	function LinearValue:__div(rhs)
		local out = setmetatable({unpack(self)}, LinearValue)
		for i = 1, #out do
			out[i] = out[i]/rhs
		end
		return out
	end
end

local LinearSpring = {} do
	LinearSpring.__index = LinearSpring
	
	function LinearSpring.new(dampingRatio, frequency, pos, typedat, rawTarget)
		local linearPos = typedat.toIntermediate(pos)
		return setmetatable(
			{
				d = dampingRatio,
				f = frequency,
				g = linearPos,
				p = linearPos,
				v = table.create(#linearPos, 0),
				typedat = typedat,
				rawTarget = rawTarget,
			},
			LinearSpring
		)
	end

	function LinearSpring:setGoal(goal)
		self.rawTarget = goal
		self.g = self.typedat.toIntermediate(goal)
	end

	function LinearSpring:canSleep()
		if magnitudeSq(self.v) > SLEEP_VELOCITY_SQ_LIMIT then
			return false
		end
		if distanceSq(self.p, self.g) > SLEEP_OFFSET_SQ_LIMIT then
			return false
		end
		return true
	end

	function LinearSpring:step(dt)
		local d = self.d
		local f = self.f*2*pi
		local g = self.g
		local p = self.p
		local v = self.v

		if d == 1 then -- critically damped
			local q = exp(-f*dt)
			local w = dt*q

			local c0 = q + w*f
			local c2 = q - w*f
			local c3 = w*f*f

			for idx = 1, #p do
				local o = p[idx] - g[idx]
				p[idx] = o*c0 + v[idx]*w + g[idx]
				v[idx] = v[idx]*c2 - o*c3
			end

		elseif d < 1 then -- underdamped
			local o = p - g
			local q = exp(-d*f*dt)
			local c = sqrt(1 - d*d)

			local i = cos(dt*f*c)
			local j = sin(dt*f*c)

			local y = j/(f*c)
			local z = j/c

			for idx = 1, #p do
				local o = p[idx] - g[idx]
				p[idx] = (o*(i + z*d) + v[idx]*y)*q + g[idx]
				v[idx] = (v[idx]*(i - z*d) - o*(z*f))*q
			end

		else -- overdamped
			local o = p - g
			local c = sqrt(d*d - 1)

			local r1 = -f*(d - c)
			local r2 = -f*(d + c)
			
			local co2 = (v - o*r1)/(2*f*c)
			local co1 = o - co2

			local e1 = co1*exp(r1*dt)
			local e2 = co2*exp(r2*dt)

			self.p = e1 + e2 + g
			self.v = e1*r1 + e2*r2
		end

		return self.typedat.fromIntermediate(self.p)
	end
end

-- transforms Roblox types into intermediate types, converting 
-- between spaces as necessary to preserve perceptual linearity
local typeMetadata = setmetatable(
	{
		number = {
			springType = LinearSpring.new,

			toIntermediate = function(value)
				return setmetatable({value}, LinearValue)
			end,

			fromIntermediate = function(value)
				return value[1]
			end,
		},

		NumberRange = {
			springType = LinearSpring.new,

			toIntermediate = function(value)
				return setmetatable({value.Min, value.Max}, LinearValue)
			end,

			fromIntermediate = function(value)
				return NumberRange.new(value[1], value[2])
			end,
		},

		UDim = {
			springType = LinearSpring.new,

			toIntermediate = function(value)
				return setmetatable({value.Scale, value.Offset}, LinearValue)
			end,

			fromIntermediate = function(value)
				return UDim.new(value[1], value[2])
			end,
		},

		UDim2 = {
			springType = LinearSpring.new,

			toIntermediate = function(value)
				local x = value.X
				local y = value.Y
				return setmetatable({x.Scale, x.Offset, y.Scale, y.Offset}, LinearValue)
			end,

			fromIntermediate = function(value)
				return UDim2.new(value[1], value[2], value[3], value[4])
			end,
		},

		Vector2 = {
			springType = LinearSpring.new,

			toIntermediate = function(value)
				return setmetatable({value.X, value.Y}, LinearValue)
			end,

			fromIntermediate = function(value)
				return Vector2.new(value[1], value[2])
			end,
		},

		Vector3 = {
			springType = LinearSpring.new,

			toIntermediate = function(value)
				return setmetatable({value.X, value.Y, value.Z}, LinearValue)
			end,

			fromIntermediate = function(value)
				return Vector3.new(value[1], value[2], value[3])
			end,
		},

		Color3 = {
			springType = LinearSpring.new,

			toIntermediate = function(value)
				-- convert to a variant of CIELUV space with modified L component

				local r, g, b = value.r, value.g, value.b

				r = r < 0.0404482362771076 and r/12.92 or 0.87941546140213*(r + 0.055)^2.4
				g = g < 0.0404482362771076 and g/12.92 or 0.87941546140213*(g + 0.055)^2.4
				b = b < 0.0404482362771076 and b/12.92 or 0.87941546140213*(b + 0.055)^2.4

				local x = 0.9257063972951867*r - 0.8333736323779866*g - 0.09209820666085898*b
				local y = 0.2125862307855956*r + 0.71517030370341085*g + 0.0722004986433362*b
				local z = 3.6590806972265883*r + 11.4426895800574232*g + 4.1149915024264843*b

				local l = y > 0.008856451679035631 and 116*y^(1/3) - 16 or 903.296296296296*y
				local u, v
				if z > 1e-14 then
					u = l*x/z
					v = l*(9*y/z - 0.46832)
				else
					u = -0.19783*l
					v = -0.46832*l
				end

				return setmetatable({l, u, v}, LinearValue)
			end,

			fromIntermediate = function(value)
				-- convert to RGB space

				local l = value[1]
				if l < 0.0197955 then
					return Color3.new(0, 0, 0)
				end
				local u = value[2]/l + 0.19783
				local v = value[3]/l + 0.46832

				local y = (l + 16)/116
				y = y > 0.206896551724137931 and y*y*y or 0.12841854934601665*y - 0.01771290335807126
				local x = y*u/v
				local z = y*((3 - 0.75*u)/v - 5)

				local r =  7.2914074*x - 1.5372080*y - 0.4986286*z
				local g = -2.1800940*x + 1.8757561*y + 0.0415175*z
				local b =  0.1253477*x - 0.2040211*y + 1.0569959*z

				if r < 0 and r < g and r < b then
					r, g, b = 0, g - r, b - r
				elseif g < 0 and g < b then
					r, g, b = r - g, 0, b - g
				elseif b < 0 then
					r, g, b = r - b, g - b, 0
				end

				return Color3.new(
					min(r < 3.1306684425e-3 and 12.92*r or 1.055*r^(1/2.4) - 0.055, 1),
					min(g < 3.1306684425e-3 and 12.92*g or 1.055*g^(1/2.4) - 0.055, 1),
					min(b < 3.1306684425e-3 and 12.92*b or 1.055*b^(1/2.4) - 0.055, 1)
				)
			end,
		},
	},
	{
		__index = function(_, t)
			error("unsupported type " .. t, 3)
		end,
	}
)

local springStates = {} -- {[instance] = {[property] = spring}

RunService.Stepped:Connect(function(_, dt)
	for instance, state in pairs(springStates) do
		for propName, spring in pairs(state) do
			if spring:canSleep() then
				state[propName] = nil
				instance[propName] = spring.rawTarget
			else
				instance[propName] = spring:step(dt)
			end
		end

		if not next(state) then
			springStates[instance] = nil
		end
	end
end)

local spr = {}

function spr.target(instance, dampingRatio, frequency, properties)
	local state = springStates[instance]

	if not state then
		state = {}
		springStates[instance] = state
	end

	for propName, propTarget in pairs(properties) do
		local propValue = instance[propName]

		if typeof(propTarget) ~= typeof(propValue) then
			error(
				("type mismatch: %s %s = %s"):format(
					typeof(propValue),
					propName,
					typeof(propTarget)
				), 2
			)
		end

		local spring = state[propName]
		if not spring then
			local md = typeMetadata[typeof(propTarget)]
			spring = md.springType(dampingRatio, frequency, propValue, md, propTarget)
			state[propName] = spring
		end

		spring.d = dampingRatio
		spring.f = frequency
		spring:setGoal(propTarget)
	end
end

function spr.stop(instance, property)
	if property then
		local state = springStates[instance]
		if state then
			state[property] = nil
		end
	else
		springStates[instance] = nil
	end
end

return spr
