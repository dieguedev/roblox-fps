---
name: responsive-roblox-ui
description: How to size and position Roblox UI (ScreenGui, Frame-based HUDs, health/stamina/ammo bars, menus, panels, buttons) so it actually stays proportional across devices instead of looking right only in Studio's default viewport. Use this whenever creating or editing any UI in this project — adding a new HUD element, a menu, a bar/meter, a button, or touching any UDim2/Position/Size/AnchorPoint value on an existing GuiObject — even if the user doesn't mention "responsive," "mobile," or "scaling" explicitly. Also trigger if the user reports a UI element looking wrong at a different resolution, overlapping another element, being too big/small, or "not matching" a bar/panel it's supposed to sit next to.
---

# Building responsive Roblox UI

This project shipped a HUD (health bar, stamina bar, ammo panel) built with
`UDim2` values that mixed Scale and Offset without thinking about why each one
was chosen — margins in fixed pixels, bar heights in fixed pixels, a panel
sized as a literal `240x90` box. It looked fine in Studio's default viewport
and was subtly wrong everywhere else: over 60% of Roblox's players are on
mobile, and a fixed-pixel margin or bar height is a much bigger fraction of a
small phone screen than of a desktop monitor. Nothing crashed — it just
quietly wasn't what "responsive" actually means. Don't repeat that: reason
about Scale vs. Offset up front, for every new UI element, not just the ones
that look obviously broken.

## The rule: Scale for position and size, Offset only where you can justify it

`UDim2`/`UDim` values are always two components, and they mean very different
things:

- **Scale** — a fraction of the parent's size. Proportional by construction:
  `0.3` is 30% of the parent on any device, any resolution.
- **Offset** — literal pixels. `20` is 20 pixels whether the screen is 400px
  or 4000px wide. Fine for a desktop-only prototype; wrong for anything meant
  to look right on both a phone and a monitor.

Default to Scale for anything that determines **where a panel sits or how
big it is relative to the screen or its parent**: `Position`, the `Size` of
top-level panels/containers, margins from screen edges, gaps between stacked
elements.

Offset is a legitimate, deliberate choice only for things that need a
**fixed minimum pixel footprint regardless of resolution**, not for "it was
easier to type a pixel number":

- `UIStroke.Thickness` — a border scaled by resolution can vanish on a phone
  or look absurdly thick on 4K.
- `TextSize` on labels not using `TextScaled` — legibility floor.
- Icon/decorative element sizes, *if* paired with `UIAspectRatioConstraint`
  or `SizeConstraint = Enum.SizeConstraint.RelativeYY`/`RelativeXX` so they
  stay square/proportional instead of stretching when the parent resizes.

`UICorner.CornerRadius` deserves its own callout: a fixed offset radius
under-rounds a thin bar (an 8px radius on an 18px-tall bar looks like clipped
corners, not a pill). Use `UDim.new(0.5, 0)` (pure Scale) when you want a true
capsule/pill shape regardless of the element's exact pixel height — the 0.5
scale always resolves to half of whichever dimension is smaller, so it stays
a full pill at any size.

If you're about to type a raw pixel number into a `Position` or a panel's
`Size`, stop and ask: does this actually need a fixed pixel footprint (icon,
border, font), or am I just describing "where does this sit relative to the
screen" (which should be Scale)?

## The AutomaticSize + Scale trap

A parent Frame with `AutomaticSize = Enum.AutomaticSize.Y` derives its height
*from* its children. If a child's own `Size` is a Scale fraction *of that same
parent*, you've built a circular dependency — the child's height depends on
the parent's height, which depends on the child's height. This doesn't error,
it just quietly resolves to something smaller than you intended (we hit this
exact bug shipping the stamina bar above the health bar).

Two ways out, pick one per container:
- Give the parent a **fixed, non-automatic** Scale-based `Size`, and give
  every child a Scale fraction *of that fixed size* — including the
  `UIListLayout.Padding` between them as its own Scale fraction, so
  everything sums to `1.0` (children fractions + padding fractions = 1).
- Or don't mix `AutomaticSize` with Scale-based children at all — use it only
  when children are Offset-sized (e.g. a frame that hugs a fixed-size icon).

## Mobile-specific things worth checking

- **Touch targets**: anything tappable wants roughly 44x44 points minimum.
  If a button's Scale size would resolve smaller than that on a typical phone
  viewport, consider detecting `UserInputService.TouchEnabled` and applying a
  size bump (~1.3–1.5x) on touch devices.
- **Safe area**: set `ScreenGui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets`
  rather than defaulting to ignoring insets, so elements don't sit under
  notches/rounded corners/system bars. Only set `IgnoreGuiInset = true`
  deliberately (e.g. a full-bleed background), not as a default habit.
- **Corner real estate**: the bottom-left corner is where Roblox's mobile
  virtual joystick lives, and the bottom-right is where the jump button
  lives. This project's `VitalsGUI` (bottom-left) and `AmmoUI` (bottom-right)
  currently sit in exactly those corners — that's a real thing to verify
  on an actual mobile viewport (or Studio's device emulator, which the user
  runs, not the agent — see the project's testing rule), not just a
  hypothetical. Flag it rather than silently assuming it's fine.

## Two valid ways to build UI in this project — ask which one

This codebase has two established, equally valid patterns for HUD elements,
and they're not interchangeable in how you'd implement one vs. the other:

1. **Built by hand in Studio, wired up by script** (`VitalsGUI`,
   `HealthBarClient.client.lua`/`StaminaBarClient.client.lua`): the actual
   `Frame`/`UIStroke`/`UICorner` instances live in `StarterGui`, visible in
   Studio's Explorer without hitting Play. The `LocalScript` only reads
   existing instances and animates them (tweening a fill bar's `Size`,
   listening to attribute changes) — it constructs nothing.
2. **Built entirely by code** (`AmmoUI.client.lua`): a `CONFIG` table of style
   constants at the top of the script, then a block of `Instance.new(...)`
   calls that build the whole UI at runtime. Nothing is visible in Studio
   until you hit Play.

Neither is "more correct" — they're a real tradeoff (visible-in-editor and
easy for a non-coder to nudge by hand, vs. fully version-controlled and
guaranteed reproducible). When adding a new UI element, **ask the user which
pattern they want** for that specific element before building it, rather than
defaulting to one silently. Whichever they pick, the Scale-first rules above
still apply — the building pattern and the sizing rules are independent
decisions.

## Quick checklist before writing/editing any UDim2 value

1. Is this a panel/container's `Position` or `Size`? → Scale, unless you have
   a specific, statable reason it needs fixed pixels.
2. Is this a border thickness, font size, or icon that needs a size floor? →
   Offset is fine, ideally paired with an aspect-ratio safeguard for icons.
3. Is this element nested in an `AutomaticSize` parent? → Make sure the
   sizing isn't circular (see above).
4. Does this sit in a bottom corner or need to be tapped on mobile? → Check
   joystick/jump-button overlap and the ~44x44 touch-target floor.
5. Building something new? → Ask which of the two construction patterns
   above the user wants before writing anything.
