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
