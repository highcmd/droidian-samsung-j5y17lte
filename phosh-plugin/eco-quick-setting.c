/*
 * Eco mode quick setting for Phosh (Samsung J5 2017 / Droidian)
 *
 * Shows whether eco mode (lower CPU/GPU clocks, lazier CPU governor) is on
 * and toggles it on tap through `sudo -n /usr/local/sbin/j5-eco toggle`.
 * The state is read from /run/j5-eco.state, written by j5-eco, and watched
 * for changes. Same structure as pihole-quick-setting.c.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#include "quick-setting.h"
#include "status-icon.h"

#include <gio/gio.h>
#include <gtk/gtk.h>

#define STATE_FILE "/run/j5-eco.state"
#define TOGGLE_CMD "/usr/local/sbin/j5-eco"
#define EXTENSION_POINT "phosh-quick-setting-widget"

#define PHOSH_TYPE_ECO_QUICK_SETTING (phosh_eco_quick_setting_get_type ())
G_DECLARE_FINAL_TYPE (PhoshEcoQuickSetting, phosh_eco_quick_setting,
                      PHOSH, ECO_QUICK_SETTING, PhoshQuickSetting)

struct _PhoshEcoQuickSetting {
  PhoshQuickSetting  parent;
  PhoshStatusIcon   *info;
  GFileMonitor      *monitor;
  gboolean           busy;
};

G_DEFINE_TYPE (PhoshEcoQuickSetting, phosh_eco_quick_setting,
               PHOSH_TYPE_QUICK_SETTING)


static void
show_state (PhoshEcoQuickSetting *self, const char *state)
{
  gboolean on = g_strcmp0 (state, "on") == 0;
  gboolean known = on || g_strcmp0 (state, "off") == 0;

  phosh_quick_setting_set_active (PHOSH_QUICK_SETTING (self), on);
  phosh_status_icon_set_icon_name (self->info,
                                   on ? "power-profile-power-saver-symbolic" : "power-profile-balanced-symbolic");
  phosh_status_icon_set_info (self->info,
                              self->busy ? "Eco…" :
                              on ? "Eco" : known ? "Eco off" : "Eco ?");
}


static void
read_state (PhoshEcoQuickSetting *self)
{
  g_autofree char *contents = NULL;

  if (g_file_get_contents (STATE_FILE, &contents, NULL, NULL))
    g_strstrip (contents);
  show_state (self, contents);
}


static void
on_cmd_done (GObject *source, GAsyncResult *res, gpointer user_data)
{
  g_autoptr (PhoshEcoQuickSetting) self = user_data;
  g_autoptr (GError) err = NULL;

  if (!g_subprocess_wait_check_finish (G_SUBPROCESS (source), res, &err))
    g_warning ("j5-eco failed: %s", err->message);
  self->busy = FALSE;
  read_state (self);
}


static void
run_toggle (PhoshEcoQuickSetting *self, const char *action)
{
  g_autoptr (GError) err = NULL;
  g_autoptr (GSubprocess) proc = NULL;

  if (self->busy)
    return;

  proc = g_subprocess_new (G_SUBPROCESS_FLAGS_STDOUT_SILENCE | G_SUBPROCESS_FLAGS_STDERR_SILENCE,
                           &err, "sudo", "-n", TOGGLE_CMD, action, NULL);
  if (!proc) {
    g_warning ("Cannot run %s: %s", TOGGLE_CMD, err->message);
    return;
  }
  self->busy = TRUE;
  read_state (self);
  g_subprocess_wait_check_async (proc, NULL, on_cmd_done, g_object_ref (self));
}


static void
on_clicked (PhoshEcoQuickSetting *self)
{
  run_toggle (self, "toggle");
}


static void
on_state_changed (PhoshEcoQuickSetting *self)
{
  read_state (self);
}


static void
phosh_eco_quick_setting_dispose (GObject *object)
{
  PhoshEcoQuickSetting *self = PHOSH_ECO_QUICK_SETTING (object);

  g_clear_object (&self->monitor);
  G_OBJECT_CLASS (phosh_eco_quick_setting_parent_class)->dispose (object);
}


static void
phosh_eco_quick_setting_class_init (PhoshEcoQuickSettingClass *klass)
{
  G_OBJECT_CLASS (klass)->dispose = phosh_eco_quick_setting_dispose;
}


static void
phosh_eco_quick_setting_init (PhoshEcoQuickSetting *self)
{
  g_autoptr (GFile) file = g_file_new_for_path (STATE_FILE);

  self->info = PHOSH_STATUS_ICON (phosh_status_icon_new ());
  phosh_status_icon_set_pixel_size (self->info, 16);
  gtk_widget_set_visible (GTK_WIDGET (self->info), TRUE);
  g_object_set (self, "status-icon", self->info, NULL);

  g_signal_connect (self, "clicked", G_CALLBACK (on_clicked), NULL);

  self->monitor = g_file_monitor_file (file, G_FILE_MONITOR_NONE, NULL, NULL);
  if (self->monitor)
    g_signal_connect_swapped (self->monitor, "changed", G_CALLBACK (on_state_changed), self);

  if (g_file_test (STATE_FILE, G_FILE_TEST_EXISTS))
    read_state (self);
  else
    run_toggle (self, "status");   /* creates the state file */
}


void
g_io_module_load (GIOModule *module)
{
  g_type_module_use (G_TYPE_MODULE (module));
  g_io_extension_point_implement (EXTENSION_POINT,
                                  PHOSH_TYPE_ECO_QUICK_SETTING,
                                  "eco-quick-setting",
                                  10);
}


void
g_io_module_unload (GIOModule *module)
{
}


char **g_io_phosh_plugin_eco_quick_setting_query (void);

char **
g_io_phosh_plugin_eco_quick_setting_query (void)
{
  char *extension_points[] = { EXTENSION_POINT, NULL };

  return g_strdupv (extension_points);
}
