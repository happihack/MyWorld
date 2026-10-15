# Splash screen and main menu pictures

- **splash.png** (optional): put a PNG here named `splash.png` and the splash screen
  shows it, fitted to the screen and centred on the background colour, instead of the
  built-in title card (the game's icon, name and tagline). Any size works; a portrait
  picture about 1080 × 1920 suits phones best. Godot imports it the next time the
  editor opens or the game is exported.
- **title_background.jpg**: the picture behind the main menu (a capture of the
  whole box from the game). Replace it with any picture of the same name.

The scenes are `scenes/main/splash.tscn` (scripts/ui/splash_screen.gd) and
`scenes/main/title.tscn` (scripts/ui/title_screen.gd).
- **launch@2x.png / launch@3x.png**: the iOS launch screen (what iOS shows before the engine
  starts). They are fully transparent on purpose, so the launch screen is only the background
  colour and the first thing seen is the lid animation; without them Godot's own logo appears.
  The iOS preset points at them (`storyboard/custom_image@2x`, `@3x`) with the background colour.
