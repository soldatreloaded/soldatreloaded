package ui

import rl "vendor:raylib"

// The look, the C client's main menu's: night and steel for the ground, white for what
// is read, and one accent, ember, kept for what acts or is chosen: the main button, the
// page in the rail, what is picked, where the keys are, what is being set. Nothing else
// is coloured. Sizes are in units.

ACCENT :: rl.Color{232, 80, 30, 255} // #E8501E
ACCENT_HOT :: rl.Color{242, 112, 66, 255}
ACCENT_SOFT :: rl.Color{232, 80, 30, 38}
TEXT :: rl.Color{236, 239, 244, 255}
MUTED :: rl.Color{146, 155, 172, 255}
FAINT :: rl.Color{94, 102, 120, 255}
SURFACE :: rl.Color{14, 17, 25, 222} // the one ground the rail and the page share
DIVIDER :: rl.Color{255, 255, 255, 24}
CONTROL :: rl.Color{28, 34, 47, 255}
CONTROL_HOT :: rl.Color{38, 46, 63, 255}
TYPING :: rl.Color{12, 15, 22, 255}
TRACK :: rl.Color{48, 56, 74, 255}
BORDER :: rl.Color{255, 255, 255, 22} // the hairline round a control
BORDER_HOT :: rl.Color{255, 255, 255, 48}
LINE :: rl.Color{255, 255, 255, 14}
HOVER :: rl.Color{255, 255, 255, 10}
WELL :: rl.Color{0, 0, 0, 70}
GOOD :: rl.Color{111, 208, 140, 255}
WARN :: rl.Color{236, 192, 84, 255}
BAD :: rl.Color{232, 85, 74, 255}
DISABLED :: rl.Color{24, 28, 38, 200} // a button that can't be pressed
DISABLED_EDGE :: rl.Color{255, 255, 255, 12}
POPUP :: rl.Color{22, 26, 37, 253}
POPUP_EDGE :: rl.Color{255, 255, 255, 34}
SHADE :: rl.Color{0, 0, 0, 120} // a popup's shadow

ROW_H :: 26
SECTION_H :: 30
CTRL_H :: 22 // a field, a list's box, a chip, a small button
RADIUS :: 4  // every control's corners
POPUP_ROW :: 20
TAB_H :: 34 // a row of tabs

// The type: Play at 9 points, Russo One and Black Ops One at 12, each scaled; the
// capitals tracked out, as small capitals are.
UI_POINTS :: 9 * POINT
DISPLAY_POINTS :: 12 * POINT

TINY :: Style{.Regular, UI_POINTS * 0.82, 0}
BODY :: Style{.Regular, UI_POINTS * 0.95, 0}
BOLD :: Style{.Bold, UI_POINTS * 0.95, 0}
LABEL :: Style{.Regular, UI_POINTS, 0}
NAV :: Style{.Regular, UI_POINTS, 0}
BUTTON :: Style{.Bold, UI_POINTS * 0.95, 0.02}
BIG :: Style{.Bold, UI_POINTS, 0.12}
SECTION :: Style{.Bold, UI_POINTS * 0.8, 0.16}
TAB :: Style{.Bold, UI_POINTS, 0.02}
GROUP :: Style{.Bold, UI_POINTS * 0.7, 0.24} // the rail's group labels: smaller and fainter than its items
SUBTITLE :: Style{.Regular, UI_POINTS * 0.95, 0}
TITLE :: Style{.Display, DISPLAY_POINTS * 1.25, 0.01}
LOGO :: Style{.Logo, DISPLAY_POINTS * 1.9, 0.03}
LOGO_SUB :: Style{.Bold, UI_POINTS * 0.78, 0} // its tracking is worked out to fit under the name

with_alpha :: proc(color: rl.Color, alpha: u8) -> rl.Color {
	return {color.r, color.g, color.b, alpha}
}
