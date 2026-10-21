# NONO UI design system

Single source of truth: `assets/ui/nono_theme.tres`, applied project-wide via
`gui/theme/custom` in `project.godot`. Any Control that does not set a
`theme_override_*` inherits from it. Prefer `theme_type_variation` over
per-node overrides.

## Type scale (exactly 6 steps - no other font sizes anywhere)

| token   | px | used for |
|---------|----|----------|
| display | 48 | game title / GAME OVER / wave banner |
| title   | 32 | section headings, upgrade title, achievement name |
| readout | 28 | live HUD numbers: score, combo, floating popups |
| heading | 24 | buttons, upgrade card names |
| body    | 18 | settings rows, descriptions, wave label |
| label   | 16 | secondary/muted text, chips, boss title, hints |

## Spacing scale
4 / 8 / 12 / 16 / 24 / 32 - every content margin and separation comes from it.

## Shape
One corner radius: 6. One border width: 1 (2 for emphasis: hover/pressed/focus).

## Colour tokens
deep panel navy 0.06,0.13,0.22 | panel mid 0.14,0.27,0.40 |
panel light 0.16,0.30,0.46 | primary cyan 0.35,0.85,1.00 |
cyan bright 0.55,0.95,1.00 | cyan soft 0.45,0.95,1.00 |
text bright 0.85,0.97,1.00 | text alt 0.85,0.92,1.00 |
text muted 0.62,0.70,0.85 | gold 0.95,0.85,0.40 |
gold bright 1.00,0.80,0.30 | danger 0.90,0.20,0.15 |
danger soft 1.00,0.70,0.70 | boss orange 1.00,0.50,0.20.

## Type variations
- Label: Display, Title, TitleHud, Heading, Body, BodyMuted, Small, Readout,
  ReadoutHud, BodyHud, SmallHud, BossTitle, Gold, Section, ChipStack, ChipOnce,
  ChipRepeat, AchName, AchDesc, AchState, AchIcon, ToastTitle, ToastName,
  ToastDesc, FloatPopup, PopupSmall, DebugInfo. The *Hud variants add a single
  outline so text over the starfield stays legible; panel variants have neither
  outline nor shadow.
- Panel/PanelContainer: MenuPanel, OverlaysPanel, FloatPanel, HUDPanel,
  HUDReadoutPanel, DebugPanel.
- Button: Primary, Ghost, Danger, Hud, Touch, Card.

## Text treatment rule
Text over the gameplay backdrop: outline only. Text on a solid panel: no
outline. Never outline AND shadow on the same text - there are zero
shadow_offset_* overrides in the project.

## Font
Chakra Petch (Google Fonts, SIL Open Font License 1.1) - see assets/fonts/OFL.txt.
Files: ChakraPetch-Regular.ttf, ChakraPetch-SemiBold.ttf, ChakraPetch-Bold.ttf.
To swap the family later, replace those three files (or repoint the three
ext_resource fonts in assets/ui/nono_theme.tres) - no other edit needed.

## Icons
toggle_on.png (cyan pill + check), toggle_off.png (navy pill + knob),
slider_grabber.png (cyan disc) and slider_grabber_highlight.png (brighter disc)
are committed static assets referenced by the CheckButton and HSlider entries in
nono_theme.tres. To restyle, replace the PNGs in place at the same sizes - the
theme keeps pointing at the same paths, so no other edit is needed.

Editing the theme: `nono_theme.tres` is the committed source of truth. Open it in
Godot's theme editor (or edit the resource directly, one entry per
`<Variation>/<data_type>/<name>` key), then re-run the game to verify.
