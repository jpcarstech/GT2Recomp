/* gt2_stub.c — "Gran Turismo 2 Recompiled.exe", the install's front door.
 *
 * A multi-disc install keeps one recompiled build per disc under
 * titles\<name>\ (arcade, simulation, combined ...). This tiny Windows
 * program is what the player double-clicks: it reads which disc they used
 * last ([launcher] active_title in settings.toml, written by the runtime's
 * Disc rows) and starts that title's exe, working directory set to the
 * title folder. No window, no console — the game IS the window.
 *
 * Fallbacks, in order: the remembered title if its folder still has an exe;
 * otherwise the alphabetically first titles\* folder that has one; if the
 * titles\ tree is missing entirely, a same-folder game exe (the pre-0.2
 * single-build layout) so an old install keeps working under the new stub.
 *
 * Built by local_build.sh with the same MinGW gcc that builds the game:
 *   gcc -O2 -mwindows -o "Gran Turismo 2 Recompiled.exe" gt2_stub.c
 * Plain C, no dependencies beyond kernel32/user32.
 */
#include <windows.h>
#include <stdio.h>
#include <string.h>

static void dir_of_self(char *out, size_t cap) {
    DWORD n = GetModuleFileNameA(NULL, out, (DWORD)cap);
    if (n == 0 || n >= cap) { out[0] = '\0'; return; }
    char *slash = strrchr(out, '\\');
    if (slash) *slash = '\0';
}

/* settings.toml line-scan for   active_title = "<name>"   inside [launcher].
 * Deliberately not a TOML parser: the runtime writes this file, the format
 * is stable, and the stub must stay dependency-free. */
static int read_active_title(const char *dir, char *out, size_t cap) {
    char path[MAX_PATH];
    FILE *f;
    char line[512];
    int in_launcher = 0;
    _snprintf(path, sizeof(path), "%s\\settings.toml", dir);
    f = fopen(path, "r");
    if (!f) return 0;
    out[0] = '\0';
    while (fgets(line, sizeof(line), f)) {
        char *p = line;
        while (*p == ' ' || *p == '\t') p++;
        if (*p == '#') continue;
        if (*p == '[') {
            in_launcher = (strncmp(p, "[launcher]", 10) == 0);
            continue;
        }
        if (!in_launcher) continue;
        if (strncmp(p, "active_title", 12) != 0) continue;
        {
            char *q1 = strchr(p + 12, '"');
            char *q2 = q1 ? strchr(q1 + 1, '"') : NULL;
            if (q1 && q2 && (size_t)(q2 - q1 - 1) < cap) {
                memcpy(out, q1 + 1, (size_t)(q2 - q1 - 1));
                out[q2 - q1 - 1] = '\0';
            }
        }
    }
    fclose(f);
    return out[0] != '\0';
}

/* Alphabetically first *.exe directly inside `dir`, full path into out.
 * (Each title folder ships exactly one exe; alphabetical makes it
 * deterministic if someone drops extras in.) */
static int find_exe_in(const char *dir, char *out, size_t cap) {
    char pattern[MAX_PATH];
    WIN32_FIND_DATAA fd;
    HANDLE h;
    char best[MAX_PATH] = "";
    _snprintf(pattern, sizeof(pattern), "%s\\*.exe", dir);
    h = FindFirstFileA(pattern, &fd);
    if (h == INVALID_HANDLE_VALUE) return 0;
    do {
        if (fd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) continue;
        if (best[0] == '\0' || _stricmp(fd.cFileName, best) < 0)
            _snprintf(best, sizeof(best), "%s", fd.cFileName);
    } while (FindNextFileA(h, &fd));
    FindClose(h);
    if (best[0] == '\0') return 0;
    _snprintf(out, cap, "%s\\%s", dir, best);
    return 1;
}

/* First titles\* subfolder (alphabetical) that contains an exe. */
static int find_any_title_exe(const char *titles, char *out, size_t cap) {
    char pattern[MAX_PATH];
    WIN32_FIND_DATAA fd;
    HANDLE h;
    char best[MAX_PATH] = "";
    _snprintf(pattern, sizeof(pattern), "%s\\*", titles);
    h = FindFirstFileA(pattern, &fd);
    if (h == INVALID_HANDLE_VALUE) return 0;
    do {
        char candidate[MAX_PATH];
        char exe[MAX_PATH];
        if (!(fd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY)) continue;
        if (fd.cFileName[0] == '.') continue;
        _snprintf(candidate, sizeof(candidate), "%s\\%s", titles, fd.cFileName);
        if (!find_exe_in(candidate, exe, sizeof(exe))) continue;
        if (best[0] == '\0' || _stricmp(fd.cFileName, best + strlen(titles) + 1) < 0)
            _snprintf(best, sizeof(best), "%s", candidate);
    } while (FindNextFileA(h, &fd));
    FindClose(h);
    if (best[0] == '\0') return 0;
    return find_exe_in(best, out, cap);
}

int WINAPI WinMain(HINSTANCE hi, HINSTANCE hp, LPSTR cmdline, int show) {
    char root[MAX_PATH], titles[MAX_PATH], exe[MAX_PATH] = "";
    char title_name[128];
    (void)hi; (void)hp; (void)show;

    dir_of_self(root, sizeof(root));
    if (!root[0]) return 1;
    _snprintf(titles, sizeof(titles), "%s\\titles", root);

    /* 1) The disc the player used last. */
    if (read_active_title(root, title_name, sizeof(title_name))) {
        char tdir[MAX_PATH];
        _snprintf(tdir, sizeof(tdir), "%s\\%s", titles, title_name);
        (void)find_exe_in(tdir, exe, sizeof(exe));
    }
    /* 2) Any installed title. */
    if (!exe[0]) (void)find_any_title_exe(titles, exe, sizeof(exe));
    /* 3) Pre-0.2 single-build layout: the game exe sits next to this stub.
     *    Take the alphabetically first OTHER exe in our own folder. */
    if (!exe[0]) {
        char self[MAX_PATH];
        char pattern[MAX_PATH];
        WIN32_FIND_DATAA fd;
        HANDLE h;
        char best[MAX_PATH] = "";
        GetModuleFileNameA(NULL, self, sizeof(self));
        {
            const char *self_name = strrchr(self, '\\');
            self_name = self_name ? self_name + 1 : self;
            _snprintf(pattern, sizeof(pattern), "%s\\*.exe", root);
            h = FindFirstFileA(pattern, &fd);
            if (h != INVALID_HANDLE_VALUE) {
                do {
                    if (fd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY)
                        continue;
                    if (_stricmp(fd.cFileName, self_name) == 0) continue;
                    if (best[0] == '\0' || _stricmp(fd.cFileName, best) < 0)
                        _snprintf(best, sizeof(best), "%s", fd.cFileName);
                } while (FindNextFileA(h, &fd));
                FindClose(h);
            }
        }
        if (best[0])
            _snprintf(exe, sizeof(exe), "%s\\%s", root, best);
    }

    if (!exe[0]) {
        MessageBoxA(NULL,
                    "No game build found.\n\n"
                    "Run \"Setup GT2.cmd\" first - it builds the game from "
                    "your disc images into the titles folder.",
                    "Gran Turismo 2 Recompiled", MB_ICONERROR);
        return 1;
    }

    {
        STARTUPINFOA si;
        PROCESS_INFORMATION pi;
        char cmd[2 * MAX_PATH + 8];
        char wd[MAX_PATH];
        char *slash;
        memset(&si, 0, sizeof(si));
        memset(&pi, 0, sizeof(pi));
        si.cb = sizeof(si);
        _snprintf(wd, sizeof(wd), "%s", exe);
        slash = strrchr(wd, '\\');
        if (slash) *slash = '\0';
        if (cmdline && cmdline[0])
            _snprintf(cmd, sizeof(cmd), "\"%s\" %s", exe, cmdline);
        else
            _snprintf(cmd, sizeof(cmd), "\"%s\"", exe);
        if (!CreateProcessA(NULL, cmd, NULL, NULL, FALSE, 0, NULL, wd,
                            &si, &pi)) {
            MessageBoxA(NULL, "Could not start the game.",
                        "Gran Turismo 2 Recompiled", MB_ICONERROR);
            return 1;
        }
        CloseHandle(pi.hThread);
        CloseHandle(pi.hProcess);
    }
    return 0;
}
