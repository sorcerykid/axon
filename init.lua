--------------------------------------------------------
-- Minetest :: Axon Event Propagation Mod (axon)
--
-- See README.txt for licensing and release notes.
-- Copyright (c) 2019-2020, Leslie E. Krause
--
-- ./games/minetest_game/mods/axon/init.lua
--------------------------------------------------------

--local S1,S1_ = Stopwatch( "axon" )

axon = { }

local sources = { }
local stack_size = 0

--------------------

local random = math.random
local pow = math.pow
local ceil = math.ceil

local function check_limits( v, min_v, max_v )
	return v >= min_v and v <= max_v
end

local function clamp( val, min, max )
	return val < min and min or val > max and max or val
end

local function get_power_decrease( scale, power, ratio )
	return ratio <= 1 - scale and 1.0 or
		max( 1 - pow( ( scale + ratio - 1 ) / scale, 1 + power ), 0 )
end

local function get_power_increase( scale, power, ratio )
	return ratio >= scale and 1.0 or
		1 - pow( ( scale - ratio ) / scale, 1 + power )
end

local function get_signal_strength( max_value, cur_value, slope )
	return math.pow( cur_value / max_value, 1 - clamp( slope, 0, 1 ) )
end

local function punch_object( obj, groups, pos )
	stack_size = stack_size + 1
	assert( stack_size < 10, "punch_object( ): Aborting callback relay due to possible recursion" )

	obj:punch( obj, 1.0, {
		full_punch_interval = 1.0,
		damage_groups = groups
	}, pos and vector.direction( obj:get_pos( ), pos ) or nil )

	stack_size = stack_size - 1
end

--------------------

local function ContactStimulus( node_name, group, intensity, chance, period, power )
	local self = { }

	self.group = group
	self.class = "contact"
	self.period = period

	self.on_action = function ( source_pos, target_obj )
		if random( chance ) == 1 then
			local touch_counts = minetest.count_nodes_in_area(
				vector.add( source_pos, -0.5 ), vector.add( source_pos, 0.5 ), { node_name }, true )
			local count = touch_counts[ node_name ]

			if count > 0 then
				local damage = intensity * pow( count, power )
				target_obj:punch( target_obj, period, {
					full_punch_interval = period,
					damage_groups = { [group] = damage },
	     			}, nil )
			end
		end
	end

	return self
end

local function RadiationStimulus( node_name, group, intensity, chance, period, radius, scale, power, max_count )
	local self = { }

	self.group = group
	self.class = "radiation"
	self.period = period

	self.on_action = function ( source_pos, target_obj )
		if random( chance ) == 1 then
			local touch_counts = minetest.count_nodes_in_area(
				vector.add( source_pos, -radius ), vector.add( source_pos, radius ), { node_name }, true )
			local count = touch_counts[ node_name ]

			if count > 0 then
				local damage = intensity * get_power_increase( scale, power, count / max_count )
				target_obj:punch( target_obj, period, {
					full_punch_interval = period,
					damage_groups = { [group] = damage },
	     			}, nil )
			end
		end
	end

	return self
end

local function ImmersionStimulus( node_name, group, intensity, chance, period )
	local self = { }

	self.group = group
	self.class = "immersion"
	self.period = period

	self.on_action = function ( source_pos, target_obj )
		if random( chance ) == 1 then
			local node = minetest.get_node( vector.round( source_pos ) )
			local node_group = string.match( node_name, "^group:(.+)" )
				
			if node.name == node_name or node_group and minetest.get_item_group( node.name, node_group ) > 0 then
				target_obj:punch( target_obj, period, {
					full_punch_interval = period,
					damage_groups = { [group] = intensity },
	     			}, nil )
			end
		end
	end

	return self
end

local function AxonPropagator( obj )
	local event_defs = { }
	local clock = 0.0
	local delay = 0.0
	local self = { }

	self.start = function ( stimulus )
		table.insert( event_defs, {
			group = stimulus.group,
			period = stimulus.period,
			expiry = clock + stimulus.period,
			started = clock,
			on_action = stimulus.on_action
		} )
	end

	self.on_step = function ( dtime, pos )
		clock = clock + dtime

		for i, v in ipairs( event_defs ) do
			if clock >= v.expiry and clock > v.started then
				v.expiry = clock + v.period
				v.on_action( pos, obj )
			end
		end
	end

	return self
end

function AxonObject( self, armor_groups )
	local old_on_step = self.on_step
	local old_on_punch = self.on_punch
	local propagator = AxonPropagator( self.object )

	if not self.receptrons then
		self.receptrons = { }
	end

	-- initialize armor groups
	if not armor_groups then
		armor_groups = { }
	end
	for k, v in pairs( self.receptrons ) do
		armor_groups[ k ] = v.sensitivity or 100
	end
	self.object:set_armor_groups( armor_groups )

	-- start stimulus propagators
	for k, v in pairs( sources ) do
		for idx, stimulus in ipairs( v ) do
			-- ignore stimulii without a receptron
			if self.receptrons[ stimulus.group ] then
				propagator.start( stimulus )
			end
		end
	end

	self.on_step = function ( self, dtime, pos, ... )
		--S1()
		propagator.on_step( dtime, pos )
		--S1_()
		old_on_step( self, dtime, pos, ... )
	end

	self.generate_direct_stimulus = function ( self, obj, groups )
		if obj ~= self.object then
			punch_object( obj, groups )
		end
	end

	self.generate_radial_stimulus = function ( self, radius, speed, slope, chance, groups, classes )
		local pos = self.object:get_pos( )

		for obj in mobs.iterate_registry( pos, radius, radius, classes ) do
			local length = vector.distance( pos, obj:get_pos( ) )

			if obj ~= self.object and length <= radius and random( chance ) == 1 then
				local damage_groups = { }

				for k, v in pairs( groups ) do
					damage_groups[ k ] = v * get_signal_strength( radius, radius - length, slope )
				end

				if speed > 0 then
					minetest.after( length / speed, function ( )
						punch_object( obj, damage_groups )
					end )
				else
					punch_object( obj, damage_groups )
				end
			end
		end
	end

	self.on_punch = function ( self, puncher, time_from_last_punch, tool_capabilities, direction, damage )
		if puncher == self.object then
			-- filter and relay the incoming stimulus
			for k, v in pairs( tool_capabilities.damage_groups ) do
				local receptron = self.receptrons[ k ]
				if receptron and check_limits( v, receptron.min_intensity or 1, receptron.max_intensity or 65536 ) then
					-- if receptron returns false, then stimulus was handled
					if not receptron.on_reaction( self, v, direction ) then return true end
				end
			end
		end

		-- if stimulus wasn't handled by a receptron, fallback to on_punch method
		return old_on_punch( self, puncher, time_from_last_punch, tool_capabilities, direction, damage )
	end
end

--------------------

axon.register_source = function ( node_name, stimulus_list )
	if not sources[ node_name ] then
		sources[ node_name ] = { }
	end
	for i, v in pairs( stimulus_list ) do
		local stimulus
		if v.class == "contact" then
			stimulus = ContactStimulus( node_name, v.group, v.intensity, v.chance, v.period, v.power )
		elseif v.class == "radiation" then
			stimulus = RadiationStimulus( node_name, v.group, v.intensity, v.chance, v.period, v.radius, v.scale, v.power, v.max_count )
		elseif v.class == "immersion" then
			stimulus = ImmersionStimulus( node_name, v.group, v.intensity, v.chance, v.period )
		end
		table.insert( sources[ node_name ], stimulus )
	end
end

axon.register_source_group = function ( node_group, node_names )
	for i, v in ipairs( node_names ) do
		local groups = minetest.registered_nodes[ v ].groups

		groups[ node_group ] = 1
		minetest.override_item( v, { groups = groups } )
	end
end

axon.generate_direct_stimulus = function ( obj, groups )
	punch_object( obj, groups )
end

axon.generate_radial_stimulus = function ( pos, radius, speed, slope, chance, groups, classes )
	for obj in mobs.iterate_registry( pos, radius, radius, classes ) do
		local length = vector.distance( pos, obj:get_pos( ) )

		if length <= radius and random( chance ) == 1 then
			local damage_groups = { }

			for k, v in pairs( groups ) do
				damage_groups[ k ] = ceil( v * get_signal_strength( radius, radius - length, slope ) )
			end

			if speed > 0 then
				minetest.after( length / speed, function ( )
					punch_object( obj, damage_groups, pos )
				end )
			else
				punch_object( obj, damage_groups, pos )
			end
		end
	end
end

--------------------

dofile( minetest.get_modpath( "axon" ) .. "/sources.lua" )
