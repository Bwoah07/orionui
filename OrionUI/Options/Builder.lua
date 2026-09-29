-- Turns a module's settings schema into widget specs, so a new module gets an options
-- page for free (CLAUDE.md §9.1). Schema nodes carry label/desc/order/hidden; a
-- module can append hand-written widgets with spec.options(M) -> { {type=, ...} }.
local _, ns = ...

local Builder = {}
ns.OptionsBuilder = Builder

local KIND_TO_WIDGET = { bool = "Toggle", number = "Slider", enum = "Dropdown", color = "Color", string = "Input" }

local function SortedFields(fields)
    local names = {}
    for name, node in pairs(fields) do
        if not node.hidden then names[#names + 1] = name end
    end
    table.sort(names, function(a, b)
        local oa, ob = fields[a].order or 100, fields[b].order or 100
        if oa ~= ob then return oa < ob end
        return a < b
    end)
    return names
end

-- "boneShield.warnAt" -> "Warn At" when no label is given.
local function Humanize(key)
    key = key:gsub("(%l)(%u)", "%1 %2")
    return (key:gsub("^%l", string.upper))
end

-- Called after any change so the module shows it immediately.
local function Changed(M)
    if M.enabled then ns.SafeCall(M.name, M.Refresh, M) end
end

local function Collect(M, node, prefix, out)
    for _, name in ipairs(SortedFields(node.fields)) do
        local field = node.fields[name]
        local path = prefix and (prefix .. "." .. name) or name
        local label = field.label or Humanize(name)
        if field.kind == "table" then
            out[#out + 1] = { type = "Header", label = label }
            Collect(M, field, path, out)
        elseif KIND_TO_WIDGET[field.kind] then
            local spec = {
                type = KIND_TO_WIDGET[field.kind],
                label = label, desc = field.desc,
                min = field.min, max = field.max, step = field.step, fmt = field.fmt,
                hasAlpha = field.hasAlpha,
                values = field.valueLabels and function()
                    local list = {}
                    for _, v in ipairs(field.values) do list[#list + 1] = { value = v, text = field.valueLabels[v] or tostring(v) } end
                    return list
                end or field.values,
                get = function() return ns.Util.GetPath(M.db, path) end,
                path = path,
            }
            if path == "enabled" then
                spec.set = function(v) M:SetEnabled(v) end
            else
                spec.set = function(v)
                    ns.Util.SetPath(M.db, path, v)
                    Changed(M)
                end
                spec.disabled = function() return M.db.enabled == false end
            end
            out[#out + 1] = spec
        end
        -- list/map settings need a hand-written editor (spec.options).
    end
end

-- -> array of widget specs for the module's page.
function Builder:Specs(M)
    local out = {}
    if M.schema then Collect(M, M.schema, nil, out) end
    if M.options then
        local ok, extra = ns.SafeCall(M.name, M.options, M)
        if ok and type(extra) == "table" then
            for _, spec in ipairs(extra) do out[#out + 1] = spec end
        end
    end
    return out
end
