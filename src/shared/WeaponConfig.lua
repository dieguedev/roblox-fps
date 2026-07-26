local WeaponConfig = {
    AK47 = {
        Slot = "Primary",
        Type = "Ranged",
        FireRate = 0.10,
        BulletSpeed = 3000,
        BulletRange = 500,
        -- Rebalanced against real CoD Zombies AR damage (BO2's M27/MTAR deal
        -- ~30-40 per bullet at close range) now that zombie HP follows the
        -- real CoD curve (150 round 1 -> ~950 round 9 -> exponential after):
        -- the old value of 17 meant ~9 body shots just to drop a round-1
        -- Normal, which is why early rounds dragged.
        Damage = 35,
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

        -- Weapon slots HUD icon (2D image, not the old 3D viewport render) --
        -- fill in with the real rbxassetid:// once it's uploaded.
        Icon = "rbxassetid://88370215937040",
    },
    P2000 = {
        Slot = "Secondary",
        Type = "Ranged",
        FireRate = 0.20,
        BulletSpeed = 2500,
        BulletRange = 350,
        -- Secondary stays weaker than the primary (real CoD pistols like the
        -- M1911 are a rounds-1-3 stopgap, not a mainline weapon), but still
        -- bumped up from 20 for the same reason as AK47.Damage above.
        Damage = 24,
        HeadshotMultiplier = 2,
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

        -- Weapon slots HUD icon -- fill in with the real rbxassetid:// once uploaded.
        Icon = "rbxassetid://106018095444497",
    },
    Knife = {
        -- Melee slot, no attack implemented yet (equip-only placeholder).
        Slot = "Knife",
        Type = "Melee",

        -- Weapon slots HUD icon -- fill in with the real rbxassetid:// once uploaded.
        Icon = "rbxassetid://0",
    },
    -- Add other weapons here
}
return WeaponConfig
