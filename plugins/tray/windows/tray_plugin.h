#ifndef FLUTTER_PLUGIN_TRAY_PLUGIN_INTERNAL_H_
#define FLUTTER_PLUGIN_TRAY_PLUGIN_INTERNAL_H_

#include <windows.h>

#include <shellapi.h>

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <memory>
#include <optional>
#include <string>

namespace tray {

class TrayPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar);

  TrayPlugin(
      flutter::PluginRegistrarWindows* registrar,
      std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel);

  ~TrayPlugin() override;

  TrayPlugin(const TrayPlugin&) = delete;
  TrayPlugin& operator=(const TrayPlugin&) = delete;

 private:
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  bool Show(const flutter::EncodableMap& arguments);
  void Hide();
  bool OpenMenu();
  bool ApplyIcon(bool add);
  void RebuildMenu(HMENU menu, const flutter::EncodableList& items);
  void SendEvent(const char* name, const flutter::EncodableValue& arguments);

  std::optional<LRESULT> HandleWindowProc(HWND window,
                                          UINT message,
                                          WPARAM wparam,
                                          LPARAM lparam);
  HWND MainWindow();

  flutter::PluginRegistrarWindows* registrar_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;

  NOTIFYICONDATAW icon_data_{};
  HMENU menu_ = nullptr;
  std::wstring tool_tip_;
  bool visible_ = false;

  UINT taskbar_created_message_ = 0;
  int window_proc_id_ = -1;
  // 顶层窗口：由窗口过程首次收到消息时缓存。
  // 不再反复调 registrar_->GetView()，那条路会穿进引擎，view 生命周期一变就崩在
  // flutter_windows.dll（实测崩溃日志最后一行就是 MethodCall show）。
  HWND window_ = nullptr;
  // 菜单项 id：先记下，PostMessage 后再回调 Dart（TrackPopupMenu 的嵌套消息循环里
  // 不能直接进引擎）。
  UINT_PTR pending_menu_command_ = 0;
};

}  // namespace tray

#endif  // FLUTTER_PLUGIN_TRAY_PLUGIN_INTERNAL_H_
