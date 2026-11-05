#!/usr/bin/env python3
"""Assemble CherryTree.app from a CMake install tree and Homebrew.

Copies the binary, the bundled look (look/), the GTK data it needs and every Homebrew library it
loads into the bundle, rewrites the library references to @loader_path-relative ones, signs it ad
hoc and fails if anything still points outside the bundle (other than macOS itself).

  CherryTree.app/Contents/MacOS/CherryTree-launcher   launcher (macos/launcher.c): environment, then exec
  CherryTree.app/Contents/MacOS/CherryTree            CherryTree
  (the two names must differ by more than case: macOS file systems are usually case-insensitive)
  CherryTree.app/Contents/Resources/lib/       libraries + gdk-pixbuf loaders + GTK modules
  CherryTree.app/Contents/Resources/share/     cherrytree data, locale, themes, icons, schemas, fonts
  CherryTree.app/Contents/Resources/etc/       gtk-3.0/settings.ini, fonts/ (fontconfig)
"""
import argparse
import os
import plistlib
import re
import shutil
import subprocess
import sys
from pathlib import Path

BUNDLE_ID = "io.github.bisaam.cherrytree"
SYSTEM_PREFIXES = ("/usr/lib/", "/System/")
TRANSLATION_DOMAINS = ("gtk30", "gtk30-properties", "gtksourceview-4", "gspell-1", "glib20")


def run(*cmd, **kw):
    return subprocess.run([str(c) for c in cmd], check=True, text=True, capture_output=True, **kw).stdout


def brew_prefix(brew, formula):
    return Path(run(brew / "bin" / "brew", "--prefix", formula).strip())


def is_macho(path):
    try:
        with open(path, "rb") as f:
            magic = f.read(4)
    except OSError:
        return False
    return magic in (b"\xcf\xfa\xed\xfe", b"\xce\xfa\xed\xfe", b"\xca\xfe\xba\xbe", b"\xbe\xba\xfe\xca")


def copyfile(src, dst):
    """Copy one file (following symlinks: Homebrew links into kegs) with plain writable permissions
    (Homebrew's are read-only)."""
    dst = Path(dst)
    dst.parent.mkdir(parents=True, exist_ok=True)
    if dst.exists():
        dst.chmod(0o644)
    shutil.copyfile(os.path.realpath(src), dst)
    dst.chmod(0o755 if is_macho(dst) else 0o644)
    return dst


def copytree(src, dst):
    """Copy a directory, following symlinks, merging into dst."""
    shutil.copytree(src, dst, symlinks=False, dirs_exist_ok=True, copy_function=copyfile)


def deps_of(path):
    """Install names a Mach-O file links against (without its own id)."""
    lines = run("otool", "-L", path).splitlines()[1:]
    deps = [ln.strip().split(" (compatibility")[0] for ln in lines if ln.strip()]
    own_id = run("otool", "-D", path).splitlines()[1:]
    if own_id and deps and deps[0] == own_id[0].strip():
        deps = deps[1:]
    return deps


def rpaths_of(path):
    out, rpaths = run("otool", "-l", path).splitlines(), []
    for i, ln in enumerate(out):
        if ln.strip() == "cmd LC_RPATH":
            m = re.search(r"path (.*) \(offset", out[i + 2])
            if m:
                rpaths.append(m.group(1))
    return rpaths


def resolve(dep, origin):
    """Real file behind an install name, as seen from the original (Homebrew) file `origin`."""
    origin_dir = Path(origin).parent
    candidates = []
    if dep.startswith("@loader_path/") or dep.startswith("@executable_path/"):
        candidates.append(origin_dir / dep.split("/", 1)[1])
    elif dep.startswith("@rpath/"):
        for rp in rpaths_of(origin):
            rp = rp.replace("@loader_path", str(origin_dir)).replace("@executable_path", str(origin_dir))
            candidates.append(Path(rp) / dep[len("@rpath/"):])
    else:
        candidates.append(Path(dep))
    for c in candidates:
        if c.exists():
            return Path(os.path.realpath(c))
    return None


class Bundler:
    def __init__(self, res):
        self.res = res
        self.lib = res / "lib"
        self.origin = {}  # bundled file -> original file (for resolving its relative references)

    def add_macho(self, bundled, original):
        self.origin[bundled] = Path(os.path.realpath(original))

    def relocate_all(self):
        queue = list(self.origin)
        done = set()
        while queue:
            f = queue.pop()
            if f in done:
                continue
            done.add(f)
            changes = []
            for dep in deps_of(f):
                if dep.startswith(SYSTEM_PREFIXES):
                    continue
                real = resolve(dep, self.origin[f])
                if real is None:
                    sys.exit(f"error: {f.name} needs {dep}, which can't be found")
                target = self.lib / real.name
                if target not in self.origin:
                    copyfile(real, target)
                    self.add_macho(target, real)
                    queue.append(target)
                changes += ["-change", dep, "@loader_path/" + os.path.relpath(target, f.parent)]
            args = list(changes)
            if f.parent == self.lib:
                args += ["-id", "@rpath/" + f.name]
            if args:
                run("install_name_tool", *args, f)
            for rp in rpaths_of(f):
                subprocess.run(["install_name_tool", "-delete_rpath", rp, str(f)], capture_output=True)
        return sorted(done)


def check_bundle(app):
    """Every Mach-O in the bundle may only load macOS itself or files inside the bundle."""
    bad = []
    for f in sorted(p for p in app.rglob("*") if p.is_file() and not p.is_symlink() and is_macho(p)):
        for dep in deps_of(f):
            if dep.startswith(SYSTEM_PREFIXES):
                continue
            if not dep.startswith("@loader_path/") or not (f.parent / dep.split("/", 1)[1]).exists():
                bad.append(f"  {f.relative_to(app)} -> {dep}")
    if bad:
        sys.exit("error: the bundle is not self-contained:\n" + "\n".join(bad))


def min_macos(files):
    best = (0, 0)
    for f in files:
        for m in re.finditer(r"minos (\d+)\.(\d+)", run("otool", "-l", f)):
            best = max(best, (int(m.group(1)), int(m.group(2))))
    return f"{best[0]}.{best[1]}" if best != (0, 0) else "15.0"


def rewrite_module_cache(src_cache, bundled_dir, res, brew):
    """Homebrew's loaders.cache / immodules.cache with paths pointing into the bundle as @RES@/..."""
    out = []
    keep = True
    for line in Path(src_cache).read_text().replace(f"{brew}/share/locale", "@RES@/share/locale").splitlines():
        m = re.match(r'^"(/[^"]+\.so)"\s*$', line)
        if m:
            name = Path(m.group(1)).name
            keep = (bundled_dir / name).exists()
            if keep:
                line = '"@RES@/' + str((bundled_dir / name).relative_to(res)) + '"'
        elif not line.strip():
            keep = True
        if keep:
            out.append(line)
    return "\n".join(out) + "\n"


def make_icns(svg, icns, rsvg, work):
    iconset = work / "cherrytree.iconset"
    shutil.rmtree(iconset, ignore_errors=True)
    iconset.mkdir(parents=True)
    for size in (16, 32, 128, 256, 512):
        for scale in (1, 2):
            px = size * scale
            inner = round(px * 0.82)  # macOS icon grid: artwork inside a margin
            off = (px - inner) // 2
            name = f"icon_{size}x{size}{'@2x' if scale == 2 else ''}.png"
            run(rsvg, "-w", inner, "-h", inner, "--page-width", px, "--page-height", px,
                "--left", off, "--top", off, "-o", iconset / name, svg)
    run("iconutil", "-c", "icns", iconset, "-o", icns)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--version", required=True)
    ap.add_argument("--install", type=Path, required=True, help="cmake --install prefix")
    ap.add_argument("--root", type=Path, required=True, help="this project")
    ap.add_argument("--brew", type=Path, required=True, help="brew --prefix")
    ap.add_argument("--app", type=Path, required=True)
    a = ap.parse_args()
    root, brew, app = a.root.resolve(), a.brew, a.app
    look, mac = root / "look", root / "macos"
    work = app.parent

    shutil.rmtree(app, ignore_errors=True)
    contents = app / "Contents"
    macos_dir, res = contents / "MacOS", contents / "Resources"
    share, etc = res / "share", res / "etc"
    for d in (macos_dir, res, share, etc):
        d.mkdir(parents=True, exist_ok=True)
    b = Bundler(res)

    print("binary + launcher")
    binary, launcher = macos_dir / "CherryTree", macos_dir / "CherryTree-launcher"
    copyfile(a.install / "bin" / "cherrytree", binary)
    b.add_macho(binary, a.install / "bin" / "cherrytree")
    run("clang", "-O2", "-Wall", "-mmacosx-version-min=11.0", "-framework", "CoreFoundation",
        "-o", launcher, mac / "launcher.c")
    if os.path.samefile(binary, launcher) or binary.stat().st_size == launcher.stat().st_size:
        sys.exit("error: the launcher overwrote the CherryTree binary")

    print("cherrytree data, translations")
    copytree(a.install / "share" / "cherrytree", share / "cherrytree")
    if (a.install / "share" / "locale").is_dir():
        copytree(a.install / "share" / "locale", share / "locale")
    for mo in (brew / "share" / "locale").glob("*/LC_MESSAGES/*.mo"):
        if mo.stem in TRANSLATION_DOMAINS:
            copyfile(mo, share / "locale" / mo.parent.parent.name / "LC_MESSAGES" / mo.name)

    print("look: theme, icons, editor schemes, default settings, fonts")
    copytree(look / "themes" / "Cherry-Dark", share / "themes" / "Cherry-Dark")
    copytree(look / "icons" / "Flat-Remix-Blue-Dark", share / "icons" / "Flat-Remix-Blue-Dark")
    for theme in ("Adwaita", "hicolor"):
        copytree(brew / "share" / "icons" / theme, share / "icons" / theme)
    for xml in (look / "styles").glob("*.xml"):
        copyfile(xml, share / "cherrytree" / "styles" / xml.name)
    copyfile(look / "config" / "config.cfg", share / "cherrytree" / "data" / "config-default.cfg")
    copyfile(look / "gtk-3.0" / "settings.ini", etc / "gtk-3.0" / "settings.ini")
    fonts = share / "fonts" / "cherrytree"
    for f in list(look.glob("fonts/*.otf")) + list(look.glob("fonts/*.ttf")) + list(look.glob("fonts/LICENSE-*.txt")):
        copyfile(f, fonts / f.name)
    copyfile(look / "COPYRIGHT-themes.txt", share / "themes" / "Cherry-Dark" / "COPYRIGHT.txt")

    print("fontconfig")
    copyfile(brew / "etc" / "fonts" / "fonts.conf", etc / "fonts" / "fonts.conf")
    for conf in sorted((brew / "etc" / "fonts" / "conf.d").glob("*.conf")):
        copyfile(conf, etc / "fonts" / "conf.d" / conf.name)
    copyfile(look / "fonts" / "99-cherrytree-fonts.conf", etc / "fonts" / "conf.d" / "99-cherrytree-fonts.conf")
    copyfile(mac / "99-cherrytree-macos-fonts.conf", etc / "fonts" / "conf.d" / "99-cherrytree-macos-fonts.conf")

    print("GtkSourceView, GSettings schemas")
    copytree(brew_prefix(brew, "gtksourceview4") / "share" / "gtksourceview-4", share / "gtksourceview-4")
    schemas = share / "glib-2.0" / "schemas"
    for x in (brew / "share" / "glib-2.0" / "schemas").glob("*.xml"):
        copyfile(x, schemas / x.name)
    run(brew / "bin" / "glib-compile-schemas", schemas)

    print("modules: gdk-pixbuf loaders, GTK input methods + print backends, enchant providers")
    pixbuf_src = brew / "lib" / "gdk-pixbuf-2.0" / "2.10.0"
    pixbuf_dst = res / "lib" / "gdk-pixbuf-2.0" / "2.10.0"
    for so in (pixbuf_src / "loaders").glob("*.so"):
        copyfile(so, pixbuf_dst / "loaders" / so.name)
        b.add_macho(pixbuf_dst / "loaders" / so.name, so)
    gtk_src = brew_prefix(brew, "gtk+3") / "lib" / "gtk-3.0" / "3.0.0"
    gtk_dst = res / "lib" / "gtk-3.0" / "3.0.0"
    for kind in ("immodules", "printbackends"):
        for so in (gtk_src / kind).glob("*.so"):
            copyfile(so, gtk_dst / kind / so.name)
            b.add_macho(gtk_dst / kind / so.name, so)
    enchant_src = brew_prefix(brew, "enchant") / "lib" / "enchant-2"
    for so in enchant_src.glob("*.so"):
        copyfile(so, res / "lib" / "enchant-2" / so.name)
        b.add_macho(res / "lib" / "enchant-2" / so.name, so)

    print("libraries")
    machos = b.relocate_all()
    print(f"  {len(machos)} Mach-O files")

    print("module caches (absolute paths filled in by the launcher at start)")
    loaders_cache = pixbuf_src / "loaders.cache"
    if not loaders_cache.exists():  # not generated by Homebrew's post-install: make one
        loaders_cache = work / "loaders.cache"
        loaders_cache.write_text(run(brew / "bin" / "gdk-pixbuf-query-loaders", *sorted((pixbuf_src / "loaders").glob("*.so"))))
    (pixbuf_dst / "loaders.cache.in").write_text(rewrite_module_cache(loaders_cache, pixbuf_dst / "loaders", res, brew))
    immodules_cache = brew / "lib" / "gtk-3.0" / "3.0.0" / "immodules.cache"
    if immodules_cache.exists():
        (gtk_dst / "immodules.cache.in").write_text(rewrite_module_cache(immodules_cache, gtk_dst / "immodules", res, brew))
    update_icon_cache = brew / "bin" / "gtk3-update-icon-cache"
    for theme in (share / "icons").iterdir():
        if (theme / "index.theme").exists():
            run(update_icon_cache, "-q", "-f", "-t", theme)

    print("icon, Info.plist")
    make_icns(mac / "cherrytree.svg", res / "cherrytree.icns", brew / "bin" / "rsvg-convert", work)
    doc_types = [
        ("ctb", "CherryTree SQLite Document"), ("ctx", "CherryTree SQLite Document, Protected"),
        ("ctd", "CherryTree XML Document"), ("ctz", "CherryTree XML Document, Protected"),
    ]
    info = {
        "CFBundleDevelopmentRegion": "en",
        "CFBundleExecutable": "CherryTree-launcher",
        "CFBundleIdentifier": BUNDLE_ID,
        "CFBundleName": "CherryTree",
        "CFBundleDisplayName": "CherryTree",
        "CFBundleIconFile": "cherrytree",
        "CFBundleInfoDictionaryVersion": "6.0",
        "CFBundlePackageType": "APPL",
        "CFBundleShortVersionString": a.version,
        "CFBundleVersion": a.version,
        "LSMinimumSystemVersion": min_macos(machos),
        "LSApplicationCategoryType": "public.app-category.productivity",
        "NSHighResolutionCapable": True,
        "NSHumanReadableCopyright": "CherryTree by Giuseppe Penone, GPL-3.0. macOS build: github.com/Bisaam/cherrytree",
        "CFBundleDocumentTypes": [
            {"CFBundleTypeName": name, "CFBundleTypeRole": "Editor", "LSHandlerRank": "Default",
             "CFBundleTypeIconFile": "cherrytree", "LSItemContentTypes": [f"{BUNDLE_ID}.{ext}"]}
            for ext, name in doc_types
        ],
        "UTExportedTypeDeclarations": [
            {"UTTypeIdentifier": f"{BUNDLE_ID}.{ext}", "UTTypeDescription": name,
             "UTTypeConformsTo": ["public.data"], "UTTypeIconFile": "cherrytree",
             "UTTypeTagSpecification": {"public.filename-extension": [ext]}}
            for ext, name in doc_types
        ],
    }
    with open(contents / "Info.plist", "wb") as f:
        plistlib.dump(info, f)
    print(f"  LSMinimumSystemVersion {info['LSMinimumSystemVersion']}")

    print("checks + ad-hoc signature")
    check_bundle(app)
    for f in machos:
        run("codesign", "--force", "--sign", "-", "--timestamp=none", f)
    run("codesign", "--force", "--sign", "-", "--timestamp=none", app)
    run("codesign", "--verify", "--strict", app)
    size = sum(p.stat().st_size for p in app.rglob("*") if p.is_file())
    print(f"ok: {app} ({size / 1e6:.0f} MB, {len(machos)} Mach-O files, all inside the bundle)")


if __name__ == "__main__":
    main()
