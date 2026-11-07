# dmgbuild-Einstellungen für AETHER-macOS-Universal.dmg
import os

application = defines.get("app", "build/AETHER.app")  # noqa: F821 (von dmgbuild bereitgestellt)
appname = os.path.basename(application)
here = os.path.join(os.getcwd(), "scripts")

format = "UDZO"
filesystem = "HFS+"
compression_level = 9
size = None

files = [application]
# Finder zeigt /Applications auf Deutsch als „Programme“
symlinks = {"Programme": "/Applications"}

icon = defines.get("icon", os.path.join(here, "..", "Resources", "AppIcon.icns"))  # noqa: F821
badge_icon = None
background = defines.get("background", os.path.join(here, "..", "Resources", "DMG", "background.png"))  # noqa: F821

show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
window_rect = ((200, 160), (660, 420))
default_view = "icon-view"
show_icon_preview = False
arrange_by = None
label_pos = "bottom"
text_size = 13
icon_size = 112
icon_locations = {
    appname: (170, 205),
    "Programme": (490, 205),
}
