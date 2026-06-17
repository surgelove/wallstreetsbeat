-- ── CONFIG & CSV DATA ──
csvFileData = {}
instrumentConfig = {}
featureUnlocks = {}
featureConfig = {}
featuresUnlocked = {}
groups = {}

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
        if cfg.group then
            if not groups[cfg.group] then groups[cfg.group] = {} end
            table.insert(groups[cfg.group], name)
        end
    end
    
    local ok3, fchunk = pcall(love.filesystem.load, "files.lua")
    if ok3 then
        local ok4, files = pcall(fchunk)
        if ok4 and type(files) == "table" then
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
