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

- `TextSize` on labels not using `TextScaled` — legibility floor.
- Icon/decorative element sizes, *if* paired with `UIAspectRatioConstraint`
  or `SizeConstraint = Enum.SizeConstraint.RelativeYY`/`RelativeXX` so they
  stay square/proportional instead of stretching when the parent resizes.
- A reticle/crosshair or similarly tiny, always-same-size marker (see
  `HideCursorAndShowCrosshair.client.lua`) — it's deliberately not meant to
  grow with the screen.

`UIStroke.Thickness` is **not** one of these, despite looking like a border
that "needs a fixed pixel width" — `VitalsGUI`'s bars proved the opposite in
practice. Set `UIStroke.StrokeSizingMode = Enum.StrokeSizingMode.ScaledSize`
and give `Thickness` a small **Scale** value (VitalsGUI ships `0.11`–`0.22`)
instead of the default `FixedSize` + Offset pixels. With `FixedSize`, a
border tuned to look right on desktop (e.g. `3.5`) is a much thicker
relative line on a small phone bar than on a wide desktop one — the opposite
of what "responsive" means. `ScaledSize` ties the border to the element's
own rendered size, so it reads the same on any screen.

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

## The nested UIAspectRatioConstraint trap

`UIAspectRatioConstraint` **overrides whatever `Size` you set — Scale or
Offset — even overriding a `UIListLayout`**, to force a fixed width:height
ratio. That's fine, even necessary, on a single element that must stay
square/proportional (an icon, a `ViewportFrame`, or the outermost shape of a
compound HUD block). It breaks the moment you stack it on more than one
level of the same bar:

- `VitalsGUI`'s health/stamina fill bars (`Healthbar.Healthbar`,
  `Staminabar.Fill`) each had their own `UIAspectRatioConstraint` *and* were
  being resized every frame by `HealthBarClient`/`StaminaBarClient`
  (`TweenSize`/`Size` on the width, to animate HP/stamina draining). Every
  width change forced the constraint to recompute height to match, so the
  fill visibly squashed vertically as it drained instead of just shrinking
  left-to-right. **Fix: never put `UIAspectRatioConstraint` on an element a
  script resizes dynamically.**
- Separately, `HudStack` → `Healthbar`/`Staminabar` (outer containers) each
  additionally had their *own* `UIAspectRatioConstraint`, nested inside
  `HudStack`'s. Because the ratio each one locks to is computed against the
  parent's actual on-screen pixel box, and phones commonly have a more
  elongated width:height screen ratio than a desktop monitor, the extra
  nested lock compounded and made the whole bar noticeably thinner on mobile
  than on desktop even though every `Size` was already correct Scale. **Fix:
  keep at most one `UIAspectRatioConstraint` per compound HUD block** (the
  outermost shape container, e.g. `HudStack`) — don't also put one on the
  bars nested inside it. If a specific bar genuinely needs its own fixed
  ratio, that's a sign the parent's layout math (Sizes + `UIListLayout`
  padding) should be doing that job instead.

Before adding `UIAspectRatioConstraint` to anything, check whether it's
already nested inside another element carrying one, and whether anything
downstream is going to `Size`/`TweenSize` it at runtime — either one is a
reason not to add it there.

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

## TextScaled + UITextSizeConstraint: the cap silently wins

`TextScaled = true` grows/shrinks text with its label's own `Size` (Scale),
which is exactly what you want — until a `UITextSizeConstraint` child caps
it. `MaxTextSize` isn't a "just in case" safety net: once the scaled text
reaches that pixel size, it **stops growing**, full stop, no matter how much
bigger the screen or the label gets from there. `VitalsGUI`'s HP label had
`MaxTextSize = 26`, which is small enough that a normal desktop monitor
already hits the ceiling — so the text looked fine on a phone (never got
close to 26) but visibly refused to grow on a bigger screen, which reads as
"TextScaled isn't working" when it's actually working exactly as capped.
If you add `UITextSizeConstraint`, set `MaxTextSize` generously — high enough
that it only ever kicks in on genuinely huge/4K displays, not on an ordinary
1080p monitor — or leave it out and let `TextScaled` do the full job.

Also prefer **Scale** for `UIPadding` around a `TextScaled` label (fractions
like `0.02`/`0.03`), not `Offset` pixels. A few fixed pixels of left/right
padding is a bigger bite out of a small mobile label's box than a desktop
one, which visibly pushes/decenters the text differently per device even
though the label's own `Position`/`Size`/`AnchorPoint` are all correct Scale.

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

1. **Built by hand in Studio, wired up by script** (`VitalsGUI`, `AmmoHud`,
   `RoundHud` with `HealthBarClient`/`StaminaBarClient`/`AmmoUI`/`RoundUI`
   `.client.lua`): the actual `Frame`/`UIStroke`/`UICorner` instances live in
   `StarterGui`, visible in Studio's Explorer without hitting Play. The
   `LocalScript` only reads existing instances and animates them (tweening a
   fill bar's `Size`, listening to attribute changes) — it constructs
   nothing. This is the convention for every current HUD element in the
   project, ammo and round counter included — don't assume a HUD script
   builds its own instances just because it has style constants at the top.
2. **Built entirely by code** (`HideCursorAndShowCrosshair.client.lua`): a
   block of `Instance.new(...)` calls that build the whole UI at runtime.
   Nothing is visible in Studio until you hit Play. Currently used only for
   the crosshair — a tiny, fixed-size reticle where Offset sizing is the
   *correct* choice (see the Offset exceptions above), not a HUD panel.

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
2. Is this a border? → `UIStroke` with `StrokeSizingMode = ScaledSize` and a
   small Scale `Thickness`, not `FixedSize` + Offset pixels.
3. Is this a font size, or an icon/reticle that needs a fixed size floor? →
   Offset is fine, ideally paired with an aspect-ratio safeguard for icons.
4. Adding `UIAspectRatioConstraint`? → Check nothing resizes this element by
   script at runtime, and that no ancestor in the same HUD block already has
   one — at most one per compound block.
5. Adding `UITextSizeConstraint` next to `TextScaled`? → Set `MaxTextSize`
   generously so it doesn't cap growth on an ordinary desktop monitor, and
   prefer Scale over Offset for any `UIPadding` around the label.
6. Is this element nested in an `AutomaticSize` parent? → Make sure the
   sizing isn't circular (see above).
7. Does this sit in a bottom corner or need to be tapped on mobile? → Check
   joystick/jump-button overlap and the ~44x44 touch-target floor.
8. Building something new? → Ask which of the two construction patterns
   above the user wants before writing anything.
