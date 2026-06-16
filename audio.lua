-- ── AUDIO ──
function initAudio()
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
