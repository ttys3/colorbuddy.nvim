-- {{{1 Imports
local log = require('colorbuddy.log')

local modifiers = require('colorbuddy.modifiers').modifiers
local util = require('colorbuddy.util')
-- util gives us some new globals:
-- luacheck: globals table.extend
-- luacheck: globals table.slice

local color_hash = {} -- {{{1

local add_color = function(c) -- {{{1
    color_hash[string.lower(c.name)] = c
end

local is_existing_color = function(raw_key) -- {{{1
    return color_hash[string.lower(raw_key)] ~= nil
end

local find_color = function(_, raw_key) -- {{{1
    local key = string.lower(raw_key)

    if is_existing_color(key) then
        return color_hash[key]
    else
        return {}
    end
end

local colors = {} -- {{{1
local __colors_mt = {
    __metatable = {},
    __index = find_color,
}
setmetatable(colors, __colors_mt)

local Color = {} -- {{{1
local IndexColor = function(_, key) -- {{{2
    if Color[key] ~= nil then
        return Color[key]
    end

    -- Return what the modifiers would be if we ran it based on the table's values
    if modifiers[key] then
        return function(s_table, ...) return modifiers[key](s_table.H, s_table.S, s_table.L, ...) end
    end

    return nil
end
local color_object_to_string = function(self) -- {{{2
    return string.format('[%s: (%s, %s, %s)]', self.name, self.H, self.S, self.L)
end

local color_object_add = function(left, right) -- {{{2
    print('left', unpack(modifiers.add(left.H, left.S, left.L, right, 1)))
    return Color.__private_create(nil, unpack(modifiers.add(left.H, left.S, left.L, right, 1)))
end

local __local_mt = { -- {{{2
    __type__ = 'color',
    __metatable = {},
    __index = IndexColor,
    __tostring = color_object_to_string,

    -- FIXME: Determine what the basic arithmetic operators should do for colors...
    __add = color_object_add,
}

Color.__private_create = function(name, H, S, L, mods) -- {{{2
    return setmetatable({
        __type__ = 'color',
        name = name,
        H = H,
        S = S,
        L = L,
        modifiers = mods,

        -- Color objects that depend on what this color is
        --  When "self" is changed, we update the attributes of these colors.
        --  See: |apply_modifier|
        children = {},

        -- Group objects that depend on what this color is
        --  When "self" is changed, we notify these groups that we have changed.
        --  Those groups are in charge of updating their configuration and Neovim.
        --  See: |apply_modifier| and |new|
        consumers = {},

    }, __local_mt)
end

Color.new = function(name, H, S, L, mods) -- {{{2
    -- Color:
    --  name
    --  H, S, L
    --  children: A table of all the colors that depend on this color
    assert(__local_mt)

    if type(H) == "string" and H:sub(1, 1) == "#" and H:len() == 7 then
        H, S, L = util.rgb_string_to_hsl(H)
    end

    -- Get an existing color if possible, so that we can update any references to this color
    -- when you use something like 'Color.new('red', ...)' twice
    local object
    if is_existing_color(name) then
        object = find_color(nil, name)
        object.H = H
        object.S = S
        object.L = L

        -- FIXME: Alert any colors that depend on this object that we have a new definition
        -- and then apply the modifiers correctly

        for consumer, _ in pairs(object.consumers) do
            log.info('Updating consumer:', consumer)
            consumer:update()
        end
    else
        object = Color.__private_create(name, H, S, L, mods)
        add_color(object)
    end

    return object
end

Color.to_rgb = function(self, H, S, L) -- {{{2
    if H == nil then H = self.H end
    if S == nil then S = self.S end
    if L == nil then L = self.L end

    local rgb = {util.hsl_to_rgb(H, S, L)}
    local buffer = "#"

    for _, v in ipairs(rgb) do
        buffer = buffer .. string.format("%02x", math.floor(v * 256 + 0.1))
    end

    return buffer
end

Color.apply_modifier = function(self, modifier_key, ...) -- {{{2
    log.debug('Applying Modifier for:', self.name, ' / ', modifier_key)
    if modifiers[modifier_key] == nil then
        error(string.format('Invalid key: "%s". Please use a valid key', modifier_key))
    end

    local new_hsl = modifiers[modifier_key](self.H, self.S, self.L, ...)
    self.H, self.S, self.L = unpack(new_hsl)

    -- Update all of the children.
    for _, child in pairs(self.children) do
        child:apply_modifier(modifier_key, ...)
    end
    -- FIXME: Check for loops within the children.
    -- FIXME: Call an event to update any color groups
end

Color._add_child = function(self, child) -- {{{2
    self.children[string.lower(child.name)] = child
end

Color.new_child = function(self, name, ...) -- {{{2
    if self.children[string.lower(name)] ~= nil then
        print('ERROR: must not use same name')
        return nil
    end

    log.debug('New Child: ', self, name, ...)
    local hsl_table = {self.H, self.S, self.L}

    for i, v in ipairs({...}) do
        log.debug('(i, v)', i, v)
        if type(v) == 'string' then
            if modifiers[v] ~= nil then
                log.debug('Applying string: ', i, v)
                hsl_table = modifiers[v](unpack(hsl_table))
            end
        elseif type(v) == 'table' then
            if modifiers[v[1]] ~= nil then
                local new_arg_table = table.extend(hsl_table, table.slice(v, 2))
                hsl_table = modifiers[v[1]](unpack(new_arg_table))
            end
        end
    end

    local kid_args = {unpack(hsl_table)}
    kid_args[4] = {}
    for index, passed_arg in ipairs({...}) do
        kid_args[4][index] = passed_arg
    end

    local kid = Color.new(name, unpack(kid_args))

    self:_add_child(kid)

    return kid
end

local is_color_object = function(c) -- {{{2
    if c == nil then
        return false
    end

    return c.__type__ == 'color'
end

local _clear_colors = function() color_hash = {} end -- {{{2


return { -- {{{1
    colors = colors,
    Color = Color,
    is_color_object = is_color_object,
    _clear_colors = _clear_colors,
}
