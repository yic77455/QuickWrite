#include "flutter_window.h"

#include <optional>
#include <unordered_map>

#include "flutter/generated_plugin_registrant.h"
#include "desktop_multi_window/desktop_multi_window_plugin.h"

#include "flutter/method_channel.h"
#include "flutter/standard_method_codec.h"
#include <commctrl.h>
#pragma comment(lib, "comctl32.lib")

// Reads the IME tracking rect from a channel argument map.
// Both integer and double values are accepted so the payload stays compatible
// with either encoding.
static bool ReadImeCursorPosition(const flutter::EncodableMap& args,
                                  ImeCursorPosition* pos) {
  auto read = [&args](const char* key, double fallback) -> double {
    auto it = args.find(flutter::EncodableValue(key));
    if (it == args.end()) {
      return fallback;
    }
    if (const auto* value = std::get_if<double>(&it->second)) {
      return *value;
    }
    if (const auto* value = std::get_if<int32_t>(&it->second)) {
      return static_cast<double>(*value);
    }
    return fallback;
  };

  pos->x = read("x", 0);
  pos->y = read("y", 0);
  pos->height = read("height", 16);
  pos->text_height = read("textHeight", 16);
  if (pos->height <= 0) {
    pos->height = 16;
  }
  if (pos->text_height <= 0) {
    pos->text_height = 16;
  }
  pos->valid = true;
  return true;
}

struct ImeWindowContext {
  ImeCursorPosition pos;
  bool applying = false;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      fullscreen_channel;

  void Apply(HWND target_hwnd, bool composition_start = false) {
    if (applying) return;
    applying = true;

    if (composition_start) {
      ApplyImeCompositionStartAnchor(target_hwnd, pos);
    } else {
      ApplyImeCompositionWindow(target_hwnd, pos);
    }

    applying = false;
  }
};

// Window state saved before entering fullscreen, restored on exit.
struct FullScreenState {
  WINDOWPLACEMENT placement{};
  LONG style = 0;
};

// One entry per window handle so multi-window mode keeps its own state.
static std::unordered_map<HWND, FullScreenState> g_fullscreen_states;

// Resolves the top-level window of a Flutter view. The runner reparents the
// view after the channel is created, so this has to be resolved lazily;
// resolving it while the channel is created yields the view itself.
static HWND GetTopLevelWindow(HWND view) {
  HWND root = ::GetAncestor(view, GA_ROOT);
  return root != nullptr ? root : view;
}

// Returns true when the client area covers |monitor|.
static bool ClientCoversMonitor(HWND hwnd, const RECT& monitor) {
  RECT client_rect{};
  POINT origin{0, 0};
  ::GetClientRect(hwnd, &client_rect);
  ::ClientToScreen(hwnd, &origin);
  return origin.x <= monitor.left && origin.y <= monitor.top &&
         origin.x + client_rect.right >= monitor.right &&
         origin.y + client_rect.bottom >= monitor.bottom;
}

// Makes the client area cover |monitor|.
// window_manager insets the client area in WM_NCCALCSIZE, so land on the
// monitor rect first and compensate the window rect by the measured inset.
static void FitClientToMonitor(HWND hwnd, const RECT& monitor) {
  for (int attempt = 0; attempt < 2; ++attempt) {
    ::SetWindowPos(hwnd, nullptr, monitor.left, monitor.top,
                   monitor.right - monitor.left,
                   monitor.bottom - monitor.top,
                   SWP_NOZORDER | SWP_NOACTIVATE | SWP_FRAMECHANGED);

    RECT window_rect{};
    RECT client_rect{};
    POINT origin{0, 0};
    ::GetWindowRect(hwnd, &window_rect);
    ::GetClientRect(hwnd, &client_rect);
    ::ClientToScreen(hwnd, &origin);

    const int dx = monitor.left - origin.x;
    const int dy = monitor.top - origin.y;
    const int dw = monitor.right - (origin.x + client_rect.right);
    const int dh = monitor.bottom - (origin.y + client_rect.bottom);
    if (dx != 0 || dy != 0 || dw != 0 || dh != 0) {
      ::SetWindowPos(hwnd, nullptr, window_rect.left + dx, window_rect.top + dy,
                     (window_rect.right - window_rect.left) + dw,
                     (window_rect.bottom - window_rect.top) + dh,
                     SWP_NOZORDER | SWP_NOACTIVATE | SWP_FRAMECHANGED);
    }
    if (ClientCoversMonitor(hwnd, monitor)) {
      return;
    }
    // The size request was clamped, which means the window is still maximized.
    ::ShowWindow(hwnd, SW_RESTORE);
  }
}

// Enters fullscreen: leave the maximized state, drop the resizable frame and
// cover the monitor, all inside one call. Splitting it into several calls lets
// the intermediate state be composited as a frame, which leaves a text ghost.
static bool EnterFullScreen(HWND hwnd) {
  if (g_fullscreen_states.find(hwnd) != g_fullscreen_states.end()) {
    return true;
  }

  HMONITOR monitor = ::MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST);
  MONITORINFO monitor_info{};
  monitor_info.cbSize = sizeof(MONITORINFO);

  FullScreenState state;
  state.placement.length = sizeof(WINDOWPLACEMENT);
  if (monitor == nullptr || !::GetMonitorInfo(monitor, &monitor_info) ||
      !::GetWindowPlacement(hwnd, &state.placement)) {
    return false;
  }
  state.style = static_cast<LONG>(::GetWindowLongPtr(hwnd, GWL_STYLE));

  const RECT target = monitor_info.rcMonitor;
  if (::IsZoomed(hwnd)) {
    // A maximized window keeps its size clamped to the work area, so leave that
    // state synchronously first (SetWindowPlacement does not animate).
    WINDOWPLACEMENT placement = state.placement;
    placement.showCmd = SW_SHOWNORMAL;
    placement.rcNormalPosition = target;
    ::SetWindowPlacement(hwnd, &placement);
  }
  ::SetWindowLongPtr(hwnd, GWL_STYLE,
                     static_cast<LONG>(state.style &
                                       ~(WS_THICKFRAME | WS_MAXIMIZEBOX)));
  FitClientToMonitor(hwnd, target);
  if (!ClientCoversMonitor(hwnd, target)) {
    // Give up and let the caller fall back to window_manager's fullscreen.
    ::SetWindowLongPtr(hwnd, GWL_STYLE, state.style);
    return false;
  }

  // Topmost, so the taskbar cannot cover the fullscreen content.
  ::SetWindowPos(hwnd, HWND_TOPMOST, 0, 0, 0, 0,
                 SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);

  g_fullscreen_states[hwnd] = state;
  return true;
}

// Leaves fullscreen: restores the style and placement saved on entry
// (including the maximized state) in one call.
static bool ExitFullScreen(HWND hwnd) {
  auto saved = g_fullscreen_states.find(hwnd);
  if (saved == g_fullscreen_states.end()) {
    return false;
  }
  const FullScreenState state = saved->second;
  g_fullscreen_states.erase(saved);

  ::SetWindowLongPtr(hwnd, GWL_STYLE, state.style);
  ::SetWindowPlacement(hwnd, &state.placement);
  ::SetWindowPos(hwnd, nullptr, 0, 0, 0, 0,
                 SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE |
                     SWP_FRAMECHANGED);
  if (state.placement.showCmd == SW_SHOWMAXIMIZED && !::IsZoomed(hwnd)) {
    ::ShowWindow(hwnd, SW_MAXIMIZE);
  }
  return true;
}

static std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
CreateFullScreenChannel(flutter::FlutterViewController* controller) {
  auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          controller->engine()->messenger(), "window_fullscreen_channel",
          &flutter::StandardMethodCodec::GetInstance());
  HWND view = controller->view()->GetNativeWindow();
  channel->SetMethodCallHandler(
      [view](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        const HWND hwnd = GetTopLevelWindow(view);
        if (call.method_name() == "enterFullScreen") {
          result->Success(flutter::EncodableValue(EnterFullScreen(hwnd)));
        } else if (call.method_name() == "exitFullScreen") {
          result->Success(flutter::EncodableValue(ExitFullScreen(hwnd)));
        } else {
          result->NotImplemented();
        }
      });
  return channel;
}

static LRESULT CALLBACK MultiWindowSubclassProc(HWND hWnd, UINT uMsg, WPARAM wParam,
                                                LPARAM lParam, UINT_PTR uIdSubclass,
                                                DWORD_PTR dwRefData) {
  ImeWindowContext* ctx = reinterpret_cast<ImeWindowContext*>(dwRefData);
  if (ctx) {
    switch (uMsg) {
      case WM_IME_STARTCOMPOSITION: {
        LRESULT result = DefSubclassProc(hWnd, uMsg, wParam, lParam);
        // Re-anchor every IME window from the rect reported by the focused
        // input, because the embedder may still position the first candidate
        // from the caret rect cached before the focus or the window size
        // changed.
        ctx->Apply(hWnd, /*composition_start=*/true);
        return result;
      }
      case WM_IME_COMPOSITION: {
        LRESULT result = DefSubclassProc(hWnd, uMsg, wParam, lParam);
        ctx->Apply(hWnd, /*composition_start=*/false);
        return result;
      }
      case WM_IME_NOTIFY: {
        LRESULT result = DefSubclassProc(hWnd, uMsg, wParam, lParam);
        // Some IMEs move the composition window themselves; re-anchor it after
        // they do so the candidate stays below the text line
        if (wParam == 0x000B /* IMN_SETCOMPOSITIONWINDOW */) {
          ctx->Apply(hWnd, /*composition_start=*/false);
        }
        return result;
      }
      case WM_NCDESTROY:
        RemoveWindowSubclass(hWnd, MultiWindowSubclassProc, uIdSubclass);
        delete ctx;
        break;
    }
  }
  return DefSubclassProc(hWnd, uMsg, wParam, lParam);
}

// Subclass procedure that suppresses the Windows Alt+key menu-activation beep.
// It is attached to the Flutter view (child window), which receives keyboard
// messages while it has focus. Flutter coalesces WM_SYSKEYDOWN and WM_SYSCHAR
// to produce Alt+key key events, so WM_SYSCHAR must NOT be blocked. The beep
// comes from DefWindowProc handling WM_SYSCHAR: it synthesizes and sends
// WM_SYSCOMMAND(SC_KEYMENU) to this child window, and a window without a menu
// falls back to the default MessageBeep on that message. Intercepting
// SC_KEYMENU here removes the beep while WM_SYSCHAR keeps flowing to Flutter.
// Alt+Space is passed through to preserve the window system menu.
static LRESULT CALLBACK AltBeepSuppressProc(HWND hWnd, UINT uMsg,
                                            WPARAM wParam, LPARAM lParam,
                                            UINT_PTR uIdSubclass,
                                            DWORD_PTR dwRefData) {
  switch (uMsg) {
    case WM_SYSCOMMAND:
      if ((wParam & 0xFFF0) == SC_KEYMENU && lParam != VK_SPACE) {
        return 0;
      }
      break;
    case WM_NCDESTROY:
      RemoveWindowSubclass(hWnd, AltBeepSuppressProc, uIdSubclass);
      break;
  }
  return DefSubclassProc(hWnd, uMsg, wParam, lParam);
}

void AttachImeFixerToMultiWindow(flutter::FlutterViewController* controller) {
  auto ctx = new ImeWindowContext();
  
  auto channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      controller->engine()->messenger(),
      "ime_cursor_channel",
      &flutter::StandardMethodCodec::GetInstance());

  HWND hwnd = controller->view()->GetNativeWindow();

  channel->SetMethodCallHandler(
      [ctx, hwnd](const flutter::MethodCall<flutter::EncodableValue>& call,
                  std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        if (call.method_name() == "updateCursorPosition") {
          const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
          if (args) {
            ReadImeCursorPosition(*args, &ctx->pos);
            ctx->Apply(hwnd);
            
            result->Success();
          } else {
            result->Error("INVALID_ARGS", "Expected map with x, y, height, textHeight");
          }
        } else {
          result->NotImplemented();
        }
      });

  ctx->channel = std::move(channel);
  ctx->fullscreen_channel = CreateFullScreenChannel(controller);
  SetWindowSubclass(hwnd, MultiWindowSubclassProc, 1, reinterpret_cast<DWORD_PTR>(ctx));
  // Also attach the Alt+key beep suppressor to multi-window Flutter views
  SetWindowSubclass(hwnd, AltBeepSuppressProc, 2, 0);
}

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  auto channel =
        std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
            flutter_controller_->engine()->messenger(),
            "ime_cursor_channel",
            &flutter::StandardMethodCodec::GetInstance());

    channel->SetMethodCallHandler(
        [this](
            const flutter::MethodCall<flutter::EncodableValue>& call,
            std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
          if (call.method_name() == "updateCursorPosition") {
            const auto* args =
                std::get_if<flutter::EncodableMap>(call.arguments());
            if (args) {
              ImeCursorPosition pos;
              ReadImeCursorPosition(*args, &pos);
              UpdateImeCursorPosition(pos.x, pos.y, pos.height,
                                      pos.text_height);
              result->Success();
            } else {
              result->Error("INVALID_ARGS", "Expected map with x, y, height, textHeight");
            }
          } else {
            result->NotImplemented();
          }
        });
    ime_channel_ = std::move(channel);
  fullscreen_channel_ = CreateFullScreenChannel(flutter_controller_.get());
  DesktopMultiWindowSetWindowCreatedCallback([](void *controller) {
    auto *flutter_view_controller =
        reinterpret_cast<flutter::FlutterViewController *>(controller);
    auto *registry = flutter_view_controller->engine();
    RegisterPlugins(registry);
    AttachImeFixerToMultiWindow(flutter_view_controller);
  });
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  // Attach the Alt+key beep suppressor to the Flutter view child window,
  // which receives WM_SYSCHAR when it has keyboard focus
  SetWindowSubclass(flutter_controller_->view()->GetNativeWindow(),
                    AltBeepSuppressProc, 2, 0);

  // flutter_controller_->engine()->SetNextFrameCallback([&]() {
  //   this->Show();
  // });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  std::optional<LRESULT> result;
  if (flutter_controller_) {
    result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
  }

  if (result) {
    return *result;
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
