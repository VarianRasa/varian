//
//  Generated file. Do not edit.
//

// clang-format off

#include "generated_plugin_registrant.h"

#include <audio_decoder/audio_decoder_plugin.h>
#include <desktop_drop/desktop_drop_plugin.h>
#include <file_selector_linux/file_selector_plugin.h>
#include <flutter_angle/flutter_angle_plugin.h>
#include <flutter_secure_storage_linux/flutter_secure_storage_linux_plugin.h>
#include <flutter_webrtc/flutter_web_r_t_c_plugin.h>
#include <gtk/gtk_plugin.h>
#include <livekit_client/live_kit_plugin.h>
#include <media_kit_video/media_kit_video_plugin.h>
#include <merman/merman_flutter_plugin.h>
#include <open_file_linux/open_file_linux_plugin.h>
#include <screen_retriever_linux/screen_retriever_linux_plugin.h>
#include <url_launcher_linux/url_launcher_plugin.h>
#include <window_manager/window_manager_plugin.h>

void fl_register_plugins(FlPluginRegistry* registry) {
  g_autoptr(FlPluginRegistrar) audio_decoder_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "AudioDecoderPlugin");
  audio_decoder_plugin_register_with_registrar(audio_decoder_registrar);
  g_autoptr(FlPluginRegistrar) desktop_drop_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "DesktopDropPlugin");
  desktop_drop_plugin_register_with_registrar(desktop_drop_registrar);
  g_autoptr(FlPluginRegistrar) file_selector_linux_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "FileSelectorPlugin");
  file_selector_plugin_register_with_registrar(file_selector_linux_registrar);
  g_autoptr(FlPluginRegistrar) flutter_angle_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "FlutterAnglePlugin");
  flutter_angle_plugin_register_with_registrar(flutter_angle_registrar);
  g_autoptr(FlPluginRegistrar) flutter_secure_storage_linux_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "FlutterSecureStorageLinuxPlugin");
  flutter_secure_storage_linux_plugin_register_with_registrar(flutter_secure_storage_linux_registrar);
  g_autoptr(FlPluginRegistrar) flutter_webrtc_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "FlutterWebRTCPlugin");
  flutter_web_r_t_c_plugin_register_with_registrar(flutter_webrtc_registrar);
  g_autoptr(FlPluginRegistrar) gtk_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "GtkPlugin");
  gtk_plugin_register_with_registrar(gtk_registrar);
  g_autoptr(FlPluginRegistrar) livekit_client_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "LiveKitPlugin");
  live_kit_plugin_register_with_registrar(livekit_client_registrar);
  g_autoptr(FlPluginRegistrar) media_kit_video_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "MediaKitVideoPlugin");
  media_kit_video_plugin_register_with_registrar(media_kit_video_registrar);
  g_autoptr(FlPluginRegistrar) merman_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "MermanFlutterPlugin");
  merman_flutter_plugin_register_with_registrar(merman_registrar);
  g_autoptr(FlPluginRegistrar) open_file_linux_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "OpenFileLinuxPlugin");
  open_file_linux_plugin_register_with_registrar(open_file_linux_registrar);
  g_autoptr(FlPluginRegistrar) screen_retriever_linux_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "ScreenRetrieverLinuxPlugin");
  screen_retriever_linux_plugin_register_with_registrar(screen_retriever_linux_registrar);
  g_autoptr(FlPluginRegistrar) url_launcher_linux_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "UrlLauncherPlugin");
  url_launcher_plugin_register_with_registrar(url_launcher_linux_registrar);
  g_autoptr(FlPluginRegistrar) window_manager_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "WindowManagerPlugin");
  window_manager_plugin_register_with_registrar(window_manager_registrar);
}
