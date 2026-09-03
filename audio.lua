-- ── AUDIO ──
rewindSources = {}
rewindDuration = 0
rewindOverlapTimer = 0
musicSource = nil
musicBPM = 125
musicTrackFile = nil
musicLoopDetected = false
lastMusicSample = 0
musicTargetVolume = 0.4
musicFadeSpeed = 0  -- >0 fading in, <0 fading out, 0 idle

-- User volume levels on a 0-10 scale. 10 keeps the original loudness.
musicLevel  = 10   -- config value, 0-10
soundLevel  = 10   -- config value, 0-10
MUSIC_VOL   = 0.4  -- base music volume at level 10
SFX_VOL     = 0.3  -- base SFX volume at level 10

local function musicGain()  return math.max(0, math.min(1, (musicLevel or 10) / 10)) end
local function soundGain()  return math.max(0, math.min(1, (soundLevel or 10) / 10)) end
local function musicVol()   return MUSIC_VOL * musicGain() end
local function sfxVol(base) return (base or SFX_VOL) * soundGain() end

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
        musicSource:setVolume(musicVol())
        musicSource:play()
        lastMusicSample = 0
        musicTargetVolume = musicVol()
        musicFadeSpeed = 0
    end
end

-- Re-apply the current music level to a live music source (after the user
-- changes the music setting mid-song).
function applyMusicVolume()
    if not musicSource then return end
    musicTargetVolume = musicVol()
    musicSource:setVolume(musicVol())
end

function updateMusic(dt, paused)
    if not musicSource then return end
    if paused and musicFadeSpeed >= 0 then
        -- Start fading out over 1 second
        musicFadeSpeed = -1 / 1.0
        musicTargetVolume = 0
    elseif not paused and musicFadeSpeed <= 0 and musicSource:getVolume() < musicVol() then
        -- Start fading in over 1 second
        musicFadeSpeed = 1 / 1.0
        musicTargetVolume = musicVol()
    end
    if musicFadeSpeed ~= 0 then
        local vol = musicSource:getVolume() + musicFadeSpeed * dt
        if musicFadeSpeed < 0 then
            -- Fading out
            if vol <= 0 then
                vol = 0
                musicFadeSpeed = 0
                musicSource:pause()
            end
        else
            -- Fading in
            if vol >= musicTargetVolume then
                vol = musicTargetVolume
                musicFadeSpeed = 0
            end
            if not musicSource:isPlaying() then
                musicSource:play()
            end
        end
        musicSource:setVolume(vol)
    end
end

function startRewindSound()
    if #rewindSources == 0 then
        local src = love.audio.newSource("sounds/rewind.wav", "static")
        src:setVolume(sfxVol(0.25))
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
        src:setVolume(sfxVol(0.25))
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
    src:setVolume(sfxVol())
    src:play()
end

function playSell()
    local src = love.audio.newSource("sounds/sell.wav", "static")
    src:setVolume(sfxVol())
    src:play()
end

function playStar()
    local src = love.audio.newSource("sounds/star.wav", "static")
    src:setVolume(sfxVol())
    src:play()
end

function playX()
    local src = love.audio.newSource("sounds/x.wav", "static")
    src:setVolume(sfxVol())
    src:play()
end
