-- ── CONTROLS THEME (Balatro-inspired) ──
-- Single source of truth for all UI element styling

return {
    cornerRadius = 5,
    emboss = 3,        -- height of the 3D emboss/raised effect
    shadowOffset = 3,  -- drop shadow offset in px

    color = {
        -- Backgrounds
        bg          = {0.07, 0.08, 0.09},
        surface     = {0.18, 0.18, 0.23},
        surfaceAlt  = {0.14, 0.14, 0.18},
        shadow      = {0, 0, 0, 0.35},

        -- Text
        fg          = {1,   1,   1},
        fgDim       = {0.50, 0.50, 0.55},

        -- Accents
        accent      = {0.94, 0.71, 0.16},
        red         = {0.82, 0.18, 0.22},   -- Balatro primary red
        redDark     = {0.55, 0.10, 0.14},   -- darker for emboss bottom
        redLight    = {0.92, 0.35, 0.38},   -- lighter for emboss top
        green       = {0.10, 0.70, 0.38},
        greenDark   = {0.06, 0.50, 0.26},
        greenLight  = {0.25, 0.85, 0.50},
        blue        = {0.28, 0.48, 0.82},
        gold        = {0.94, 0.71, 0.16},
        goldDark    = {0.65, 0.48, 0.08},
        goldLight   = {1,   0.82, 0.35},
        purple      = {0.48, 0.41, 0.93},
        purpleDark  = {0.32, 0.26, 0.70},
        purpleLight = {0.62, 0.56, 1},
        grey        = {0.35, 0.35, 0.40},
        greyLight   = {0.50, 0.50, 0.55},
        white       = {1,   1,   1},
        black       = {0,   0,   0},
        label       = {0.50, 0.50, 0.55},
    },
}
