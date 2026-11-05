CherryTree for macOS
====================

Drag CherryTree to the Applications folder, then open it.

The app is not notarized by Apple, so the first time macOS says it can't
check CherryTree for malware. To open it anyway:
  1. Try to open CherryTree once and close the message, then
  2. open System Settings > Privacy & Security, scroll down and click
     "Open Anyway" next to CherryTree.
Or run this once in Terminal:
  xattr -dr com.apple.quarantine /Applications/CherryTree.app

Needs a Mac with Apple silicon (M1 or newer) and macOS 15 Sequoia or newer.

This is CherryTree (https://github.com/giuspen/cherrytree, GPL-3.0) built from
source, with a few small patches, and bundled with the Cherry-Dark theme,
Flat-Remix-Blue-Dark icons, Cantarell / Fira Code fonts and Linux-style font
rendering.

Settings are stored in ~/Library/Application Support/CherryTree, separate from
a Homebrew CherryTree. On the first run they start from the bundled defaults.
Set the environment variable CHERRYTREE_NATIVE_LOOK=1 to use the macOS font
renderer instead.

Theme, icons, editor colours and default settings: from the kali-themes
package (GPL-3.0, Copyright Offensive Security), renamed. App icon: Flat Remix
icon theme (GPL-3.0).
Source, patches and build scripts: https://github.com/Bisaam/cherrytree
