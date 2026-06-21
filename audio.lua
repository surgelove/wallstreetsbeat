-- ── AUDIO ──
rewindSources = {}
rewindDuration = 0
rewindOverlapTimer = 0
musicSource = nil
musicBPM = 125
musicTrackFile = nil
musicLoopDetected = false
lastMusicSample = 0

function initAudio()
end

function startMusic()
    if musicSource then return end
    local cfg = instrumentConfig and instrumentConfig.music
    if cfg then
        musicTrackFile = cfg.track or "music/EDM.mp3"
        musicBPM = cfg.bpm or 125
    else 
        musicTrackFile = "music/EDM.mp3"
        musicBPM = 125
    end
    local ok, src = pcall(love.audio.newSource, musicTrackFile, "stream")
    if ok then
        musicSource = src
        musicSource:setLooping(true)
        musicSource:setVolume(0.4)
        musicSource:play()
        lastMusicSample = 0
    end
end

function startRewindSound()
    if #rewindSources == 0 then
        local src = love.audio.newSource("sounds/rewind.wav", "static")
        src:setVolume(0.25)
        src:play()
        rewindDuration = src:getDuration()
        rewindOverlapTimer = rewindDuration * 0.6
        table.insert(rewindSources, src)
    end
end

function updateRewindSound(dt)
    if #rewindSources == 0 then return end
    rewindOverlapTimer = rewindOverlapTimer - dt
    if rewindOverlapTimer <= 0 then
        local src = love.audio.newSource("sounds/rewind.wav", "static")
        src:setVolume(0.25)
        src:play()
        rewindOverlapTimer = rewindDuration * 0.6
        table.insert(rewindSources, src)
    end
    -- Clean up finished sources
    for i = #rewindSources, 1, -1 do
        if not rewindSources[i]:isPlaying() then
            table.remove(rewindSources, i)
        end
    end
end

function stopRewindSound()
    for _, src in ipairs(rewindSources) do
        src:stop()
    end
    rewindSources = {}
    rewindOverlapTimer = 0
end

function playBuy()
    local src = love.audio.newSource("sounds/buy.wav", "static")
    src:setVolume(0.3)
    src:play()
end

function playSell()
    local src = love.audio.newSource("sounds/sell.wav", "static")
    src:setVolume(0.3)
    src:play()
end

function playStar()
    local src = love.audio.newSource("sounds/star.wav", "static")
    src:setVolume(0.3)
    src:play()
end

function playX()
    local src = love.audio.newSource("sounds/x.wav", "static")
    src:setVolume(0.3)
    src:play()
end
