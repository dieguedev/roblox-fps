---
name: add-weapon-ammo-ui
description: How to make a new weapon show up correctly in the ammo HUD (src/client/AmmoUI.client.lua) — the ViewportFrame that renders a live 3D icon of the equipped gun next to its name/ammo count. Use this whenever the user asks to add a new weapon, gun, or firearm to the game, wants a weapon's icon/model to appear in the ammo UI, mentions ViewportFrame weapon icons, WeaponConfig entries, IconRotation, or reports that a weapon's HUD icon is missing/wrong/clipped/misaligned/rotated wrong. Also trigger if the user is adding entries to src/shared/WeaponConfig.lua or ReplicatedStorage.Weapons, even if they don't mention the UI explicitly — the icon is driven automatically off that config and will silently stay blank or look wrong if a step here is skipped.
---

# Adding a weapon to the ammo UI

The ammo HUD (`src/client/AmmoUI.client.lua`) never needs code changes for a new
weapon. It reads everything — name, icon, magazine size, low-ammo threshold —
off `src/shared/WeaponConfig.lua` and off `ReplicatedStorage.Weapons`, driven by
attributes the server (`WeaponService.server.lua`) sets on the player
(`EquippedWeapon`, `AmmoInMag`, `AmmoReserve`, `Reloading`). So "adding a weapon
to the UI" is really two content steps, not a scripting task. Do these in
order — the second step depends on the first existing, and a broken order is
the most common way a weapon silently shows no icon.

## Step 1 — Add the weapon to `WeaponConfig.lua`

Add an entry keyed by the weapon's exact name (this name is used as a lookup
key everywhere: `ReplicatedStorage.Weapons[name]`, `WeaponConfig[name]`, the
`EquippedWeapon` attribute — keep it identical in all three places). For the
ammo UI specifically, only two fields matter:

- `Type = "Ranged"` — the HUD frame is hidden entirely for anything else
  (that's how the `Knife` melee placeholder stays invisible; see
  `AmmoUI.client.lua` `refresh()`). If the weapon should show ammo, it must be
  `"Ranged"`.
- `MagazineSize` and `ReserveAmmo` — used both by the server to seed ammo and
  by the HUD to decide when the ammo count turns red (`LowAmmoThreshold`,
  default 25% of magazine).

Optionally tune `IconRotation` (a `CFrame.Angles(...)`) — see Step 3. If you
skip it, the icon falls back to `CONFIG.DefaultIconRotation` in
`AmmoUI.client.lua`, which is a reasonable side-view guess but rarely exactly
right for a new mesh.

If this weapon should actually be equippable (not just theoretically
configured), it also needs a `Slot` matching one of `WeaponService.server.lua`'s
`SLOTS` (`"Primary"`, `"Secondary"`, `"Knife"`) and a way into a player's
loadout (`DEFAULT_LOADOUT`, or wherever a future shop assigns loadouts) — the
ammo UI will simply never show a weapon that's never equipped, so if the icon
"doesn't show up" the first thing to check is whether the weapon is reachable
at all, before suspecting the icon code.

## Step 2 — Add the model to `ReplicatedStorage.Weapons`

This is the part most likely to trip someone up: `ReplicatedStorage.Weapons`
is **not** in `default.project.json` and isn't synced by Rojo — it's built
directly in Studio. If you're working from source files only, the model
won't exist and the icon (and the third-person held weapon) will just be
blank, with no error.

Under `ReplicatedStorage.Weapons`, create a folder/model named exactly like
the `WeaponConfig` key (e.g. `Weapons.AK47`). Inside it, put a `Model`
instance containing only the gun's parts — no fake first-person arms, no
camera rig. Both `AmmoUI.client.lua` (`getIconModelSource`) and
`WeaponAttachment.lua` (`getHeldModelSource`) grab the *first Model child*
of `Weapons[name]` and use it as the gun-only mesh, specifically so a
viewmodel template with bundled fake arms can sit alongside it without
polluting the icon or the third-person weld. If `Weapons[name]` has no Model
child (or no children at all), the icon silently renders nothing — there's no
error thrown, so check this first if an icon is blank for a weapon whose
`WeaponConfig` entry looks correct.

## Step 3 — Tune `IconRotation` if the icon looks wrong

The HUD's `ViewportFrame` (in `AmmoUI.client.lua`) is a live render, not a
static image: it clones the Model from Step 2, rotates it, fits a camera to
its bounding box, and re-renders it every time the equipped weapon changes.
Because every gun mesh can have a different "forward" axis depending on how
it was modeled, one fixed rotation doesn't suit every weapon — that's what
`WeaponConfig[name].IconRotation` is for.

```lua
-- in WeaponConfig.lua, alongside the weapon's other fields:
IconRotation = CFrame.Angles(0, math.rad(90), 0), -- tune per weapon, mesh-dependent
```

There's no formula for the right value — tune it visually in Studio the same
way `HeldOffset` is tuned: equip the weapon, look at the HUD icon in the
bottom-right corner, and adjust the angles until the gun reads as a
recognizable side profile. A few things that are handled for you and don't
need tuning:

- **Framing/zoom** — the camera auto-fits to whatever size the model's
  bounding box turns out to be (`computeWorldAABB` + the FOV math in
  `updateIcon`), so a shotgun and a pistol both fill the icon the same way
  without per-weapon size tweaks.
- **Screen tilt** — `CONFIG.IconScreenTilt` in `AmmoUI.client.lua` applies a
  fixed on-screen roll on top of every weapon's `IconRotation`, so all icons
  get the same "muzzle up-left" tilt for free. Only touch this if you want to
  change that tilt for every weapon at once, not for a single weapon.
- **Lighting/background** — shared across all weapons via `CONFIG.IconAmbient`
  / `IconLightColor` / `IconLightDirection`; a new weapon needs no per-weapon
  lighting setup.

If the gun looks clipped at the edges of the icon regardless of rotation,
that's not an `IconRotation` problem — check that the Model in Step 2 really
contains only the gun (stray extra parts inflate the bounding box and make
the camera back off further than it should, making the actual gun look
smaller than its neighbors).

## Quick checklist

1. `WeaponConfig.lua`: new entry, `Type = "Ranged"`, `MagazineSize`,
   `ReserveAmmo`, matching `Slot` if it needs to be equippable.
2. `ReplicatedStorage.Weapons.<Name>` exists in Studio with a `Model` child
   containing only the gun's parts.
3. (Optional) `IconRotation` tuned visually until the HUD icon looks right.
4. Nothing to change in `AmmoUI.client.lua` itself — if the icon is still
   blank/wrong after 1–3, that script is the last place to look, not the
   first.
