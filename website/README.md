# My World in a Box — website

A static, single-page promotional site: `index.html`, `css/style.css`, `js/main.js`,
and the images in `assets/`. No build step and no frameworks. Open `index.html` in a
browser, or upload the folder as-is to any static host (GitHub Pages, Netlify,
Cloudflare Pages, an ordinary web server).

Godot ignores this folder (`.gdignore`), so none of it is imported into or exported
with the game.

## The screenshots

Every image is a real capture from the game. To make fresh ones:

```sh
G=path/to/Godot_v4.7.2-stable_mono_win64_console.exe

# 1. Grow a world for a few decades, in a save folder of its own (never your real saves).
$G --headless -s res://tests/tools/grow_world.gd -- --seed=4242 --years=35 --dir=C:/tmp/wiab_shots

# 2. Open it in a window and capture: the landscape scenes, then the phone screens.
$G -s res://tests/tools/capture_shots.gd -- --dir=C:/tmp/wiab_shots --out=C:/tmp/wiab_shots/img --size=1920x1080 --set=scenes
$G -s res://tests/tools/capture_shots.gd -- --dir=C:/tmp/wiab_shots --out=C:/tmp/wiab_shots/img --size=1080x2340 --set=phone

# 3. Make the web-sized images (needs Python with Pillow).
python website/tools/make_images.py C:/tmp/wiab_shots/img
```

`make_images.py` writes each scene at 1600 px and 800 px wide (`name.jpg`, `name-sm.jpg`)
and each phone screen at 720 px and 360 px.

## Before it goes live

- **Store link:** the "Google Play — coming soon" button (section `#notify`) is a
  placeholder. Replace it with the store badge and link once the listing exists.
- **Sign-up:** there is no mailing list form yet. If you want one, add a form from your
  mailing service in the `#notify` section.
- **Social image:** `og:image` points to `assets/img/box.jpg`. Some sites need an absolute
  URL there (`https://your-domain/assets/img/box.jpg`) once the site has a domain.
- **Fonts:** Fraunces and Inter are loaded from Google Fonts. The page falls back to
  system fonts when offline.
