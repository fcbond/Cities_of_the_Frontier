--[[
Cities of the Frontier — Lua utilities

Provides three custom WML actions needed because the standard Wesnoth engine
tags lack equivalent functionality:

  [save_map]   variable=VAR
      Serialises the entire map (including borders) into a WML variable as a
      map-data string.  Used by STORE_MAP_AND_UNITS to persist the map between
      scenarios without writing a save file.

  [load_map]   variable=VAR
      Deserialises a previously stored map string and calls replace_map, which
      also handles shrinking/expanding the playable area.  Used by
      RESTORE_MAP_AND_UNITS at the start of each new scenario.

  [store_shroud]  side=N  variable=VAR
  [set_shroud]    side=N  shroud_data=VAR
      Store and restore a side's shroud bitmap so that explored fog-of-war
      state carries over correctly across scenario boundaries.

These code snippets are modified versions of code by silene and melinath on the
Wesnoth forums.  I do not know Lua, so several features of this campaign would
not have been possible without the helpful posts of these fine individuals!

http://forums.wesnoth.org/viewtopic.php?f=21&t=27450
http://forums.wesnoth.org/viewtopic.php?t=28306&p=414894
--]]

-- Save and load the map using a WML variable
local function required_attribute(cfg, name, tag)
  return cfg[name] or wml.error(("[%s] missing required %s= attribute."):format(tag, name))
end

local function save_map(cfg)
  local map = wesnoth.current.map
  local b = tonumber(cfg.border_size) or map.border_size
  local w, h = map.playable_width, map.playable_height
  local t = {}
  for y = 1 - b, h + b do
    local r = {}
    for x = 1 - b, w + b do
      r[x + b] = map[{x, y}]
    end
    t[y + b] = table.concat(r, ',')
  end
  local s = table.concat(t, '\n')
  local v = required_attribute(cfg, "variable", "save_map")
  wml.variables[v] = string.format("border_size=%d\nusage=map\n\n%s", b, s)
end
wesnoth.wml_actions["save_map"] = save_map


local function load_map(cfg)
  local v = required_attribute(cfg, "variable", "load_map")
  wml.fire.replace_map {
    map = wml.variables[v],
    expand = true,
    shrink = true
  }
end
wesnoth.wml_actions["load_map"] = load_map



-- Save and load the shroud using a WML variable
local function store_shroud(cfg)
  local side_num = tonumber(required_attribute(cfg, "side", "store_shroud"))
  local storage = required_attribute(cfg, "variable", "store_shroud")
  local side = wesnoth.sides[side_num]
  if not side then
    wml.error(("[store_shroud] invalid side=%s."):format(cfg.side))
  end
  wml.variables[storage] = side.shroud_data
end
wesnoth.wml_actions["store_shroud"] = store_shroud


local function set_shroud(cfg)
  local side_num = tonumber(required_attribute(cfg, "side", "set_shroud"))
  local shroud = required_attribute(cfg, "shroud_data", "set_shroud")
  local side = wesnoth.sides[side_num]
  if not side then
    wml.error(("[set_shroud] invalid side=%s."):format(cfg.side))
  end
  if shroud:sub(1, 1) ~= "|" then
    wml.error("[set_shroud] was passed an invalid shroud string.")
  end
  side.shroud_data = shroud
end
wesnoth.wml_actions["set_shroud"] = set_shroud
