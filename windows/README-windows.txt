CherryTree for Windows
======================

This is CherryTree (https://github.com/giuspen/cherrytree, GPL-3.0) built
from source for Windows, with a few small patches, and bundled with:

  * GTK theme      Cherry-Dark (dark headerbar, round title buttons)
  * Icon theme     Flat-Remix-Blue-Dark
  * Fonts          Cantarell 11 / Fira Code Medium 10 (SIL OFL 1.1)
  * Text rendering fontconfig + FreeType, hintslight, RGB subpixel (as on Linux)
  * Editor colours Cherry-Dark GtkSourceView scheme, tree #23252e / selection #2777ff
  * No "Check Newer Version" menu item (the same patch Debian uses)

Double-click CherryTree.exe (portable folder) or use the Start menu (installer).
Everything it needs is inside this folder: nothing to install, no PATH to set.
Copy the whole folder (or the zip) to another PC and it runs there too.

Settings are stored in %APPDATA%\CherryTree\config.cfg, separate from a regular
CherryTree install. On the first run that file is created from the bundled
defaults; delete it to get them back.
To make it fully portable (settings kept in this folder), copy
ucrt64\usr\share\cherrytree\data\config-default.cfg next to this README and
rename the copy to config.cfg.

Set the environment variable CHERRYTREE_NATIVE_LOOK=1 to use the Windows font
renderer and native title bars instead.

Theme, icons, editor colours and default settings: from the kali-themes
package (GPL-3.0, Copyright Offensive Security), renamed.
Source, patches and build scripts: https://github.com/Bisaam/cherrytree
