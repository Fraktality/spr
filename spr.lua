---------------------------------------------------------------------
-- spr - Spring-driven motion library
--
-- Copyright (c) 2020 Parker Stebbins. All rights reserved.
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
--     dict<string, Variant> targetProperties)
--
--     Animates the given properties towardes the target values,
--     given damping ratio and undamped frequency.
--
--
--  spr.stop(
--     Instance obj[,
--     string property])
--
--     Stops the specified property from animating on an Instance.
--     If no property is specified, all properties under the Instance
--     will stop animating.
---------------------------------------------------------------------

local STRICT_TYPES = true -- assert on parameter and property type mismatch
local STRICT_API_ACCESS = false -- lock down the API table to prevent writes & empty reads
local SLEEP_OFFSET_SQ_LIMIT = (1/3840)^2 -- square of the offset sleep limit
local SLEEP_VELOCITY_SQ_LIMIT = 1e-2^2 -- square of the velocity sleep limit
local EPS = 1e-5 -- epsilon for stability checks around pathological frequency/damping values

local RunService = game:GetService("RunService")

local pi = math.pi
local exp = math.exp
local sin = math.sin
local cos = math.cos
local min = math.min
local sqrt = math.sqrt

local function magnitudeSq(vec)
	local out = 0

	for _, v in ipairs(vec) do
		out += v^2
	end

	return out
end

local function distanceSq(vec0, vec1)
	local out = 0

	for i0, v0 in ipairs(vec0) do
		out += (vec1[i0] - v0)^2
	end

	return out
end

-- create a proxy object for a table that prevents reading
-- empty keys, writing keys, and inspecting the metatable
local tableLock do
	local function invalidRead(_, k)
		error(("reading nonexistent element %q from locked table"):format(tostring(k)), 2)
	end

	local function invalidWrite(_, k)
		error(("writing key %q to locked table"):format(tostring(k)), 2)
	end

	local RW_LOCK = {
		__index = invalidRead,
		__newindex = invalidWrite,
	}

	function tableLock(tbl)
		setmetatable(tbl, RW_LOCK)

		return setmetatable(
			{},
			{
				__index = tbl,
				__newindex = invalidWrite,
				__metatable = "The metatable is locked",
			}
		)
	end
end

-- spring for an array of linear values
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
		-- Advance the spring simulation by dt seconds.
		-- Take the damped harmonic oscillator ODE:
		--    f^2*(X[t] - g) + 2*d*f*X'[t] + X''[t] = 0
		-- Where X[t] is position at time t, g is target position,
		-- f is undamped angular frequency, and d is damping ratio.
		-- Apply constant initial conditions:
		--    X[0] = p0
		--    X'[0] = v0
		-- Solve the IVP to get analytic expressions for X[t] and X'[t].
		-- The solution takes one of three forms for 0<=d<1, d=1, and d>1

		local d = self.d
		local f = self.f*2*pi -- Hz -> Rad/s
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
			local q = exp(-d*f*dt)
			local c = sqrt(1 - d*d)

			local i = cos(dt*f*c)
			local j = sin(dt*f*c)

			-- Damping ratios approaching 1 can cause division by very small numbers.
			-- To mitigate that, group terms around z=j/c and find an approximation for z.
			-- Start with the definition of z:
			--    z = sin(dt*f*c)/c
			-- Substitute a=dt*f:
			--    z = sin(a*c)/c
			-- Take the Maclaurin expansion of z with respect to c:
			--    z = a - (a^3*c^2)/6 + (a^5*c^4)/120 + O(c^6)
			--    z ≈ a - (a^3*c^2)/6 + (a^5*c^4)/120
			-- Rewrite in Horner form:
			--    z ≈ a + ((a*a)*(c*c)*(c*c)/20 - c*c)*(a*a*a)/6

			local z
			if c > EPS then
				z = j/c
			else
				local a = dt*f
				z = a + ((a*a)*(c*c)*(c*c)/20 - c*c)*(a*a*a)/6
			end

			-- Frequencies approaching 0 present a similar problem.
			-- We want an approximation for y as f approaches 0, where:
			--    y = sin(dt*f*c)/(f*c)
			-- Substitute b=dt*c:
			--    y = sin(b*c)/b
			-- Now reapply the process from z.

			local y
			if f*c > EPS then
				y = j/(f*c)
			else
				local b = f*c
				y = dt + ((dt*dt)*(b*b)*(b*b)/20 - b*b)*(dt*dt*dt)/6
			end

			for idx = 1, #p do
				local o = p[idx] - g[idx]
				p[idx] = (o*(i + z*d) + v[idx]*y)*q + g[idx]
				v[idx] = (v[idx]*(i - z*d) - o*(z*f))*q
			end

		else -- overdamped
			local c = sqrt(d*d - 1)

			local r1 = -f*(d - c)
			local r2 = -f*(d + c)

			local ec1 = exp(r1*dt)
			local ec2 = exp(r2*dt)

			for idx = 1, #p do
				local o = p[idx] - g[idx]
				local co2 = (v[idx] - o*r1)/(2*f*c)
				local co1 = ec1*(o - co2)

				p[idx] = co1 + co2*ec2 + g[idx]
				v[idx] = co1*r1 + co2*ec2*r2
			end
		end

		return self.typedat.fromIntermediate(self.p)
	end
end

-- transforms Roblox types into intermediate types, converting
-- between spaces as necessary to preserve perceptual linearity
local typeMetadata = {
	number = {
		springType = LinearSpring.new,

		toIntermediate = function(value)
			return {value}
		end,

		fromIntermediate = function(value)
			return value[1]
		end,
	},

	NumberRange = {
		springType = LinearSpring.new,

		toIntermediate = function(value)
			return {value.Min, value.Max}
		end,

		fromIntermediate = function(value)
			return NumberRange.new(value[1], value[2])
		end,
	},

	UDim = {
		springType = LinearSpring.new,

		toIntermediate = function(value)
			return {value.Scale, value.Offset}
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
			return {x.Scale, x.Offset, y.Scale, y.Offset}
		end,

		fromIntermediate = function(value)
			return UDim2.new(value[1], value[2], value[3], value[4])
		end,
	},

	Vector2 = {
		springType = LinearSpring.new,

		toIntermediate = function(value)
			return {value.X, value.Y}
		end,

		fromIntermediate = function(value)
			return Vector2.new(value[1], value[2])
		end,
	},

	Vector3 = {
		springType = LinearSpring.new,

		toIntermediate = function(value)
			return {value.X, value.Y, value.Z}
		end,

		fromIntermediate = function(value)
			return Vector3.new(value[1], value[2], value[3])
		end,
	},

	Color3 = {
		springType = LinearSpring.new,

		toIntermediate = function(value)
			-- convert RGB to a variant of cieluv space
			local r, g, b = value.R, value.G, value.B

			-- D65 sRGB inverse gamma correction
			r = r < 0.0404482362771076 and r/12.92 or 0.87941546140213*(r + 0.055)^2.4
			g = g < 0.0404482362771076 and g/12.92 or 0.87941546140213*(g + 0.055)^2.4
			b = b < 0.0404482362771076 and b/12.92 or 0.87941546140213*(b + 0.055)^2.4

			-- sRGB -> xyz
			local x = 0.9257063972951867*r - 0.8333736323779866*g - 0.09209820666085898*b
			local y = 0.2125862307855956*r + 0.71517030370341085*g + 0.0722004986433362*b
			local z = 3.6590806972265883*r + 11.4426895800574232*g + 4.1149915024264843*b

			-- xyz -> modified cieluv
			local l = y > 0.008856451679035631 and 116*y^(1/3) - 16 or 903.296296296296*y

			local u, v
			if z > 1e-14 then
				u = l*x/z
				v = l*(9*y/z - 0.46832)
			else
				u = -0.19783*l
				v = -0.46832*l
			end

			return {l, u, v}
		end,

		fromIntermediate = function(value)
			-- convert back from modified cieluv to rgb space

			local l = value[1]
			if l < 0.0197955 then
				return Color3.new(0, 0, 0)
			end
			local u = value[2]/l + 0.19783
			local v = value[3]/l + 0.46832

			-- cieluv -> xyz
			local y = (l + 16)/116
			y = y > 0.206896551724137931 and y*y*y or 0.12841854934601665*y - 0.01771290335807126
			local x = y*u/v
			local z = y*((3 - 0.75*u)/v - 5)

			-- xyz -> D65 sRGB
			local r =  7.2914074*x - 1.5372080*y - 0.4986286*z
			local g = -2.1800940*x + 1.8757561*y + 0.0415175*z
			local b =  0.1253477*x - 0.2040211*y + 1.0569959*z

			-- clamp minimum sRGB component
			if r < 0 and r < g and r < b then
				r, g, b = 0, g - r, b - r
			elseif g < 0 and g < b then
				r, g, b = r - g, 0, b - g
			elseif b < 0 then
				r, g, b = r - b, g - b, 0
			end

			-- gamma correction from D65
			-- clamp to avoid undesirable overflow wrapping behavior on certain properties (e.g. BasePart.Color)
			return Color3.new(
				min(r < 3.1306684425e-3 and 12.92*r or 1.055*r^(1/2.4) - 0.055, 1),
				min(g < 3.1306684425e-3 and 12.92*g or 1.055*g^(1/2.4) - 0.055, 1),
				min(b < 3.1306684425e-3 and 12.92*b or 1.055*b^(1/2.4) - 0.055, 1)
			)
		end,
	},
}

local springStates = {} -- {[instance] = {[property] = spring}

RunService.Heartbeat:Connect(function(dt)
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

local function assertType(argNum, fnName, expectedType, value)
	if not STRICT_TYPES then
		return
	end

	if not expectedType:find(typeof(value)) then
		error(
			("bad argument #%d to %s (%s expected, got %s)"):format(
				argNum,
				fnName,
				expectedType,
				typeof(value)
			),
			3
		)
	end
end

local spr = {}

function spr.target(instance, dampingRatio, frequency, properties)
	assertType(1, "spr.target", "Instance", instance)
	assertType(2, "spr.target", "number", dampingRatio)
	assertType(3, "spr.target", "number", frequency)
	assertType(4, "spr.target", "table", properties)

	if dampingRatio ~= dampingRatio or dampingRatio < 0 then
		error(("expected damping ratio >= 0; got %.2f"):format(dampingRatio), 2)
	end

	if frequency ~= frequency or frequency < 0 then
		error(("expected undamped frequency >= 0; got %.2f"):format(frequency), 2)
	end

	local state = springStates[instance]

	if not state then
		state = {}
		springStates[instance] = state
	end

	for propName, propTarget in pairs(properties) do
		local propValue = instance[propName]

		if STRICT_TYPES and typeof(propTarget) ~= typeof(propValue) then
			error(
				("bad property %s to spr.target (%s expected, got %s)"):format(
					propName,
					typeof(propValue),
					typeof(propTarget)
				),
				2
			)
		end

		local spring = state[propName]
		if not spring then
			local md = typeMetadata[typeof(propTarget)]

			if not md then
				error("unsupported type: " .. typeof(propTarget), 2)
			end

			spring = md.springType(dampingRatio, frequency, propValue, md, propTarget)
			state[propName] = spring
		end

		spring.d = dampingRatio
		spring.f = frequency
		spring:setGoal(propTarget)
	end
end

function spr.stop(instance, property)
	assertType(1, "spr.stop", "Instance", instance)
	assertType(2, "spr.stop", "string|nil", property)

	if property then
		local state = springStates[instance]
		if state then
			state[property] = nil
		end
	else
		springStates[instance] = nil
	end
end

if STRICT_API_ACCESS then
	return tableLock(spr)
else
	return spr
end
