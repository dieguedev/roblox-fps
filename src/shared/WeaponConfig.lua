local WeaponConfig = {
    AK47 = {
        Slot = "Primary",
        Type = "Ranged",
        FireRate = 0.12,
        BulletSpeed = 3000,
        BulletRange = 500,
        Damage = 12,
        TracerColor = Color3.fromRGB(255, 220, 80),
        TracerThickness = 0.15,
        TracerLifetime = 0.08,
        Auto = true,
    },
    Pistol = {
        Slot = "Secondary",
        Type = "Ranged",
        FireRate = 0.3,
        BulletSpeed = 2500,
        BulletRange = 350,
        Damage = 18,
        TracerColor = Color3.fromRGB(200, 220, 255),
        TracerThickness = 0.1,
        TracerLifetime = 0.06,
        Auto = false,
    },
    Knife = {
        -- Melee slot, no attack implemented yet (equip-only placeholder).
        Slot = "Knife",
        Type = "Melee",
    },
    -- Add other weapons here
}
return WeaponConfig
