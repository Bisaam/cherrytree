/*
 * CherryTree.exe - launcher at the top of the portable folder / install dir.
 * Starts ucrt64\bin\cherrytree.exe (which sits next to all its DLLs) with the same arguments,
 * so nothing ever has to be added to PATH.
 */
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <wchar.h>
#include <stdlib.h>

/* skip argv[0] in a raw command line, following the CommandLineToArgvW quoting rules for it */
static const wchar_t* skip_program_name(const wchar_t* p)
{
    if (*p == L'"') {
        ++p;
        while (*p && *p != L'"') ++p;
        if (*p == L'"') ++p;
    }
    else {
        while (*p && *p != L' ' && *p != L'\t') ++p;
    }
    while (*p == L' ' || *p == L'\t') ++p;
    return p;
}

int WINAPI wWinMain(HINSTANCE hInst, HINSTANCE hPrev, PWSTR pCmdLine, int nShow)
{
    (void)hInst; (void)hPrev; (void)pCmdLine; (void)nShow;

    wchar_t dir[4096];
    DWORD n = GetModuleFileNameW(NULL, dir, (DWORD)(sizeof(dir) / sizeof(dir[0])));
    if (n == 0 || n >= sizeof(dir) / sizeof(dir[0])) return 1;
    wchar_t* slash = wcsrchr(dir, L'\\');
    if (slash) slash[1] = L'\0';

    wchar_t exe[4200];
    swprintf(exe, sizeof(exe) / sizeof(exe[0]), L"%lsucrt64\\bin\\cherrytree.exe", dir);

    const wchar_t* args = skip_program_name(GetCommandLineW());
    size_t len = wcslen(exe) + wcslen(args) + 4;
    wchar_t* cmd = (wchar_t*)malloc(len * sizeof(wchar_t));
    if (!cmd) return 1;
    swprintf(cmd, len, L"\"%ls\" %ls", exe, args);

    STARTUPINFOW si;
    PROCESS_INFORMATION pi;
    ZeroMemory(&si, sizeof(si));
    si.cb = sizeof(si);
    ZeroMemory(&pi, sizeof(pi));
    if (!CreateProcessW(exe, cmd, NULL, NULL, FALSE, 0, NULL, NULL, &si, &pi)) {
        wchar_t msg[4400];
        swprintf(msg, sizeof(msg) / sizeof(msg[0]),
                 L"Could not start\n%ls\n\nKeep the 'ucrt64' folder next to CherryTree.exe.", exe);
        MessageBoxW(NULL, msg, L"CherryTree", MB_OK | MB_ICONERROR);
        free(cmd);
        return 1;
    }
    CloseHandle(pi.hThread);
    CloseHandle(pi.hProcess);
    free(cmd);
    return 0;
}
