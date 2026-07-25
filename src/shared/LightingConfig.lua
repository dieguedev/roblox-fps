local LightingConfig = {
    -- Base Lighting service properties: overcast midday (not dusk/night, so
    -- visibility stays fine) with a desaturated, grayish ambient tone.
    Lighting = {
        Brightness = 2.5,
        Ambient = Color3.fromRGB(110, 110, 115),
        OutdoorAmbient = Color3.fromRGB(140, 140, 145),
        ColorShift_Bottom = Color3.fromRGB(90, 90, 95),
        ColorShift_Top = Color3.fromRGB(160, 160, 165),
        ExposureCompensation = 0,
        ClockTime = 12, -- midday sun so there's plenty of light to work with
        FogColor = Color3.fromRGB(180, 180, 180),
        FogStart = 15,
        FogEnd = 120,
        ShadowSoftness = 1,
    },

    -- ColorCorrectionEffect: pulls saturation down and tints slightly gray
    -- for the "washed out / half-dead landscape" look, without darkening.
    ColorCorrection = {
        Saturation = -0.6,
        Contrast = 0.05,
        Brightness = 0.05,
        TintColor = Color3.fromRGB(215, 218, 215),
    },

    -- Atmosphere: thick mist for a "short-sighted" feel — visibility drops
    -- noticeably past mid range, forcing players to rely on close-range awareness.
    Atmosphere = {
        Density = 0.8,
        Offset = 0.3,
        Color = Color3.fromRGB(180, 180, 180),
        Decay = Color3.fromRGB(140, 140, 140),
        Glare = 0,
        Haze = 4.5,
    },
}
return LightingConfig
