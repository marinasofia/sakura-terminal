// tiny Lua 5.4 runner using Hammerspoon's bundled LuaSkin: runlua file.lua [args]
#include <dlfcn.h>
#include <stdio.h>
typedef void* L;
int main(int argc, char **argv) {
  void *h = dlopen("/Applications/Hammerspoon.app/Contents/Frameworks/LuaSkin.framework/LuaSkin", RTLD_NOW);
  if (!h) { fprintf(stderr, "%s\n", dlerror()); return 2; }
  L (*newstate)(void) = dlsym(h, "luaL_newstate");
  void (*openlibs)(L) = dlsym(h, "luaL_openlibs");
  int (*loadfilex)(L, const char*, const char*) = dlsym(h, "luaL_loadfilex");
  int (*pcallk)(L, int, int, int, long, void*) = dlsym(h, "lua_pcallk");
  const char *(*tolstring)(L, int, size_t*) = dlsym(h, "lua_tolstring");
  L s = newstate(); openlibs(s);
  if (argc < 2) { fprintf(stderr, "usage: runlua file.lua\n"); return 2; }
  if (loadfilex(s, argv[1], NULL) || pcallk(s, 0, 0, 0, 0, NULL)) { fprintf(stderr, "lua error: %s\n", tolstring(s, -1, NULL)); return 1; }
  return 0;
}
