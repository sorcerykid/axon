-- This is a sample source definition file. You will want to modify this for your particular game.

axon.register_source( "group:lava_source", {
	{ group = "heat_stim", class = "radiation", intensity = 30, chance = 1, period = 1.5, radius = 5.0, scale = 1.0, power = 0.0, max_count = 6 },
	{ group = "lava_stim", class = "immersion", intensity = 10, chance = 1, period = 0.5 },
} )

axon.register_source( "group:water_source", {
	{ group = "water_stim", class = "immersion", intensity = 5, chance = 1, period = 0.5 },
} )

axon.register_source( "group:heat_source", {
	{ group = "heat_stim", class = "contact", intensity = 3, chance = 2, period = 1.0, power = 0.8 },
} )

axon.register_source_group( "lava_source", { "default:lava_source", "default:lava_flowing" } )

axon.register_source_group( "heat_source", { "default:torch", "default:furnace_active", "fire:permanent_flame" } )

axon.register_source_group( "water_source", { "default:water_source", "default:water_flowing" } )
