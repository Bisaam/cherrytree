// CherryTree.app/Contents/MacOS/CherryTree-launcher (the bundle's CFBundleExecutable): points GTK,
// GLib, fontconfig and gdk-pixbuf at the files inside the bundle, then runs CherryTree
// (Contents/MacOS/CherryTree) in this same process.
#include <CoreFoundation/CoreFoundation.h>
#include <limits.h>
#include <mach-o/dyld.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

static char res[PATH_MAX];  // CherryTree.app/Contents/Resources

static void set_res_env(const char* name, const char* suffix)
{
    char value[PATH_MAX * 2];
    snprintf(value, sizeof value, "%s%s", res, suffix);
    setenv(name, value, 1);
}

static void mkdir_p(const char* path)
{
    char buf[PATH_MAX];
    snprintf(buf, sizeof buf, "%s", path);
    for (char* p = buf + 1; *p; ++p) {
        if (*p == '/') { *p = 0; mkdir(buf, 0755); *p = '/'; }
    }
    mkdir(buf, 0755);
}

// module caches need absolute paths: copy the template replacing @RES@ with the bundle location
static int write_cache(const char* tmpl, const char* out)
{
    FILE* in = fopen(tmpl, "rb");
    if (!in) return -1;
    fseek(in, 0, SEEK_END);
    long n = ftell(in);
    fseek(in, 0, SEEK_SET);
    char* buf = malloc((size_t)n + 1);
    if (!buf || fread(buf, 1, (size_t)n, in) != (size_t)n) { fclose(in); free(buf); return -1; }
    buf[n] = 0;
    fclose(in);
    char tmp[PATH_MAX];
    snprintf(tmp, sizeof tmp, "%s.%d", out, (int)getpid());
    FILE* o = fopen(tmp, "wb");
    if (!o) { free(buf); return -1; }
    const char* key = "@RES@";
    for (char* p = buf; *p;) {
        char* q = strstr(p, key);
        if (!q) { fputs(p, o); break; }
        fwrite(p, 1, (size_t)(q - p), o);
        fputs(res, o);
        p = q + strlen(key);
    }
    fclose(o);
    free(buf);
    return rename(tmp, out);
}

int main(int argc, char* argv[])
{
    char exe[PATH_MAX], real[PATH_MAX];
    uint32_t size = sizeof exe;
    if (_NSGetExecutablePath(exe, &size) != 0 || !realpath(exe, real)) {
        fprintf(stderr, "CherryTree: can't find its own location\n");
        return 1;
    }
    // real = .../CherryTree.app/Contents/MacOS/CherryTree-launcher
    char contents[PATH_MAX];
    snprintf(contents, sizeof contents, "%s", real);
    *strrchr(contents, '/') = 0;  // .../Contents/MacOS
    *strrchr(contents, '/') = 0;  // .../Contents
    snprintf(res, sizeof res, "%s/Resources", contents);

    set_res_env("XDG_DATA_DIRS", "/share");             // themes, icons, gtksourceview, schemas
    set_res_env("XDG_CONFIG_DIRS", "/etc");             // gtk-3.0/settings.ini
    set_res_env("GTK_DATA_PREFIX", "");
    set_res_env("GTK_EXE_PREFIX", "");
    set_res_env("GTK_PATH", "/lib/gtk-3.0");            // input methods, print backends
    set_res_env("GSETTINGS_SCHEMA_DIR", "/share/glib-2.0/schemas");
    set_res_env("FONTCONFIG_PATH", "/etc/fonts");
    set_res_env("FONTCONFIG_FILE", "/etc/fonts/fonts.conf");

    const char* home = getenv("HOME");
    char cache[PATH_MAX], tmpl[PATH_MAX], out[PATH_MAX];
    snprintf(cache, sizeof cache, "%s/Library/Caches/io.github.bisaam.cherrytree", home ? home : "/tmp");
    mkdir_p(cache);
    snprintf(tmpl, sizeof tmpl, "%s/lib/gdk-pixbuf-2.0/2.10.0/loaders.cache.in", res);
    snprintf(out, sizeof out, "%s/loaders.cache", cache);
    if (write_cache(tmpl, out) == 0) setenv("GDK_PIXBUF_MODULE_FILE", out, 1);
    snprintf(tmpl, sizeof tmpl, "%s/lib/gtk-3.0/3.0.0/immodules.cache.in", res);
    snprintf(out, sizeof out, "%s/immodules.cache", cache);
    if (write_cache(tmpl, out) == 0) setenv("GTK_IM_MODULE_FILE", out, 1);

    // apps started from Finder get no LANG: take it from the macOS language settings
    const char* lang = getenv("LANG");
    if (!lang || !*lang) {
        char id[64] = "en_US";
        CFLocaleRef locale = CFLocaleCopyCurrent();
        if (locale) {
            CFStringGetCString(CFLocaleGetIdentifier(locale), id, sizeof id, kCFStringEncodingUTF8);
            CFRelease(locale);
        }
        char* at = strchr(id, '@');  // e.g. en_GB@rg=pkzzzz
        if (at) *at = 0;
        char value[80];
        snprintf(value, sizeof value, "%s.UTF-8", id);
        setenv("LANG", value, 1);
    }

    char bin[PATH_MAX];
    snprintf(bin, sizeof bin, "%s/MacOS/CherryTree", contents);
    char** args = calloc((size_t)argc + 1, sizeof(char*));
    int n = 0;
    args[n++] = bin;  // CherryTree finds its data from its own path (Contents/Resources/share/cherrytree)
    for (int i = 1; i < argc; ++i) {
        if (strncmp(argv[i], "-psn_", 5) != 0) args[n++] = argv[i];  // old Finder process serial number
    }
    args[n] = NULL;
    execv(bin, args);
    perror("CherryTree: can't start Contents/MacOS/CherryTree");
    return 127;
}
