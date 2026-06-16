-- ── CONFIG & CSV DATA ──
csvFileData = {}
instrumentConfig = {}
featureUnlocks = {}
featureConfig = {}
featuresUnlocked = {}
groups = {}

RANDOM_BASE = 32.40
RW_TOTAL = 391 * 12

function initData()
    local ok, chunk = pcall(love.filesystem.load, "config.lua")
    if ok then
        local ok2, config = pcall(chunk)
        if ok2 and type(config) == "table" then
            instrumentConfig = config
        end
    end
    if not instrumentConfig then instrumentConfig = { features = {} } end
    
    for k, v in pairs(instrumentConfig.features or {}) do
        if type(v) == "boolean" then
            featureUnlocks[k] = v and 0 or math.huge
        elseif type(v) == "number" then
            featureUnlocks[k] = v
        end
        featureConfig[k] = false
        featuresUnlocked[k] = false
    end
    
    local insts = instrumentConfig.instruments or {}
    for name, cfg in pairs(insts) do
        local g = cfg.group or "OTHER"
        if not groups[g] then groups[g] = {} end
        table.insert(groups[g], name)
    end
    
    local f2 = love.filesystem.read("files.json")
    if f2 then
        local files = {}
        for line in f2:gmatch('"([^"]+%.csv)"') do
            table.insert(files, line)
        end
        for _, filename in ipairs(files) do
            local content = love.filesystem.read(filename)
            if content then
                local dayName = filename:gsub("%.csv$", "")
                csvFileData[dayName] = {}
                for line in content:gmatch("[^\r\n]+") do
                    local fields = {}
                    for val in line:gmatch("([^,]+)") do
                        table.insert(fields, val)
                    end
                    if #fields >= 4 and fields[2] ~= "instrument" then
                        local inst = fields[2]
                        if not csvFileData[dayName][inst] then
                            csvFileData[dayName][inst] = {}
                        end
                        local time = ""
                        if fields[1]:match("%s+") then
                            time = fields[1]:match("%s+(%S+)")
                            if time then time = time:sub(1, 5) end
                        end
                        table.insert(csvFileData[dayName][inst], {
                            bid = tonumber(fields[3]),
                            ask = tonumber(fields[4]),
                            time = time,
                            date = fields[1]:match("^(%S+)") or ""
                        })
                    end
                end
            end
        end
    end
end

function interpolate5s(minuteData)
    local result = {}
    for i = 1, #minuteData do
        local curr = minuteData[i]
        local nxt = minuteData[math.min(i + 1, #minuteData)]
        for j = 0, 11 do
            local t = j / 12
            local noise = 0
            if math.random() > 0.4 then
                noise = (math.random() - 0.5) * (0.005 + math.random() * 0.015) * 2
            end
            table.insert(result, {
                bid = math.floor((curr.bid + (nxt.bid - curr.bid) * t + noise) * 1000 + 0.5) / 1000,
                ask = math.floor((curr.ask + (nxt.ask - curr.ask) * t + noise) * 1000 + 0.5) / 1000,
                time = curr.time,
                date = curr.date
            })
        end
    end
    return result
end

function getGroupMembers(group)
    return groups[group] or {}
end

function applyConfig(key)
    local insts = instrumentConfig.instruments or instrumentConfig
    local cfg = insts[key] or { increment = 100, maxShares = 1000 }
    shareInc = cfg.increment
    shareMax = cfg.maxShares
end
