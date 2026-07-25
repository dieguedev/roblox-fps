local ZombieConfig = {
    Normal = {
        MaxHealth = 150,
        WalkSpeed = 18, -- faster than the player's walk (16) but slower than sprint (26)
        AttackRange = 4.5,
        AttackDamage = 20,
        AttackCooldown = 1.5,
    },
    Corredor = {
        MaxHealth = 100, -- ~66.7% of Normal, ratio kept when round health scaling lands in Paso 4
        WalkSpeed = 28, -- faster than the player's sprint (26), so outrunning it isn't an option
        AttackRange = 4.5,
        AttackDamage = 20,
        AttackCooldown = 0.9, -- shorter than Normal's, hits more often
    },
    -- Add other zombie types here
}
return ZombieConfig
