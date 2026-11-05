# dmgbuild-Einstellungen für „Music Library.dmg“
import os

application = defines.get("app", "build/Music Library.app")  # noqa: F821 (von dmgbuild bereitgestellt)
appname = os.path.basename(application)
here = os.path.dirname(os.path.abspath(__file__))

format = "UDZO"
filesystem = "HFS+"
compression_level = 9
size = None

files = [application]
# Verknüpfung zum Programme-Ordner (Finder zeigt /Applications auf Deutsch als „Programme“)
symlinks = {"Programme": "/Applications"}

icon = os.path.join(here, "..", "Resources", "AppIcon.icns")
badge_icon = None

# Retina-Hintergrund: make_dmg.sh erzeugt mit tiffutil eine TIFF-Datei aus 1×- und 2×-PNG
background = defines.get("background", os.path.join(here, "..", "Resources", "DMG", "background.png"))  # noqa: F821
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
sidebar_width = 180

window_rect = ((200, 160), (660, 420))
default_view = "icon-view"
show_icon_preview = False

arrange_by = None
grid_offset = (0, 0)
grid_spacing = 100
scroll_position = (0, 0)
label_pos = "bottom"
text_size = 13
icon_size = 128

icon_locations = {
    appname: (170, 205),
    "Programme": (490, 205),
}
