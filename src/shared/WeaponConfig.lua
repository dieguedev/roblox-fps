local WeaponConfig = {
    AK47 = {
        Slot = "Primary",
        Type = "Ranged",
        FireRate = 0.10,
        BulletSpeed = 3000,
        BulletRange = 500,
        Damage = 17,
        HeadshotMultiplier = 2,
        TracerColor = Color3.fromRGB(255, 220, 80),
        TracerThickness = 0.15,
        TracerLifetime = 0.08,
        Auto = true,
        MagazineSize = 30,
        ReserveAmmo = 90,
        ReloadTime = 2.5, -- seconds; real AK mag-change is ~2.5-3.5s, this is on the fast end for pacing

        -- Third-person hold pose, relative to HumanoidRootPart (tuned visually
        -- against WeaponTestDummy in Studio; the gun mesh isn't hand-rigged,
        -- so this is a fixed offset rather than a real grip/IK attachment).
        HeldOffset = CFrame.new(0.8, -0.3, -1.0) * CFrame.Angles(0, math.rad(90), 0),
    },
    P2000 = {
        Slot = "Secondary",
        Type = "Ranged",
        FireRate = 0.20,
        BulletSpeed = 2500,
        BulletRange = 350,
        Damage = 20,
        HeadshotMultiplier = 1.75,
        TracerColor = Color3.fromRGB(200, 220, 255),
        TracerThickness = 0.1,
        TracerLifetime = 0.06,
        Auto = false,
        MagazineSize = 15,
        ReserveAmmo = 60,
        ReloadTime = 1.6,

        -- Third-person hold pose, relative to HumanoidRootPart (tuned visually
        -- against WeaponTestDummy in Studio, same technique as AK47.HeldOffset).
        HeldOffset = CFrame.new(0.6, -0.3, -0.4) * CFrame.Angles(0, math.rad(90), 0),

        -- First-person viewmodel nudge (see ViewmodelOffset in WeaponController):
        -- the raw P2000 template has the gun sitting further back from the fake
        -- arms than AK47's does, so pull it forward to match.
        ViewmodelOffset = CFrame.new(0, 0, -0.5),
    },
    Knife = {
        -- Melee slot, no attack implemented yet (equip-only placeholder).
        Slot = "Knife",
        Type = "Melee",
    },
    -- Add other weapons here
}
return WeaponConfig
