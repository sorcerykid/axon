minetest.count_nodes_in_area = function( pos_min, pos_max, names, is_group )
	local counts, node_counts
	local voxel_manip = minetest.get_voxel_manip( )

	voxel_manip:read_from_map( pos_min, pos_max )
	node_counts = select( 2, minetest.find_nodes_in_area( pos_min, pos_max, names ) )

	if is_group == false then
		return counts
	end

	counts = { }    -- use new table for transposing node counts into group counts
	for _, name in ipairs( names ) do
		local group_name = string.match( name, "group:(.+)" )
		if group_name then
			counts[ name ] = 0
			for node_name, node_count in pairs( node_counts ) do
				if minetest.registered_nodes[ node_name ].groups[ group_name ] then
					counts[ name ] = counts[ name ] + node_count
				end
			end
		else
			counts[ name ] = node_counts[ name ]
		end
	end
	return counts
end
