#include "my_application.h"

int main(int argc, char** argv) {
  // window_manager 0.4.x uses X11 APIs. Hyprland runs this native GTK program
  // through XWayland; selecting Wayland here would crash those plugin calls.
  g_setenv("GDK_BACKEND", "x11", TRUE);
  g_autoptr(MyApplication) app = my_application_new();
  return g_application_run(G_APPLICATION(app), argc, argv);
}
