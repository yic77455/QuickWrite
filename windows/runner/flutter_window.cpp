#include "flutter_window.h"

#include <optional>

#include "flutter/generated_plugin_registrant.h"
#include "desktop_multi_window/desktop_multi_window_plugin.h"

#include "flutter/method_channel.h"
#include "flutter/standard_method_codec.h"
#include <commctrl.h>
#pragma comment(lib, "comctl32.lib")

struct ImeWindowContext {
  ImeCursorPosition pos;
  bool applying = false;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel;

  void Apply(HWND target_hwnd) {
    if (applying) return;
    applying = true;

    HIMC hImc = ImmGetContext(target_hwnd);
    if (!hImc) {
      applying = false;
      return;
    }
   
    UINT dpi = 96;
    using GetDpiForWindowFn = UINT(WINAPI*)(HWND);
    static auto getDpiForWindow = reinterpret_cast<GetDpiForWindowFn>(
        GetProcAddress(GetModuleHandle(L"User32.dll"), "GetDpiForWindow"));
    if (getDpiForWindow) {
      dpi = getDpiForWindow(target_hwnd);
    }
   
    auto toPhysical = [&](int32_t logical) -> LONG {
      return static_cast<LONG>(logical * static_cast<double>(dpi) / 96.0 + 0.5);
    };
   
    LONG physX = toPhysical(pos.x);
    LONG physY = toPhysical(pos.y);
    LONG physH = toPhysical(pos.height);
   
    POINT clientPt = {physX, physY};

    COMPOSITIONFORM cf = {};
    cf.dwStyle = CFS_POINT;
    cf.ptCurrentPos.x = clientPt.x;
    cf.ptCurrentPos.y = clientPt.y - physH; 
    ImmSetCompositionWindow(hImc, &cf);
   
    CANDIDATEFORM cdf = {};
    cdf.dwIndex = 0;
    cdf.dwStyle = CFS_EXCLUDE;
    cdf.ptCurrentPos.x = clientPt.x;
    cdf.ptCurrentPos.y = clientPt.y;
    cdf.rcArea.left   = clientPt.x;
    cdf.rcArea.top    = clientPt.y - physH;
    cdf.rcArea.right  = clientPt.x + toPhysical(2); 
    cdf.rcArea.bottom = clientPt.y;
    ImmSetCandidateWindow(hImc, &cdf);
   
    ImmReleaseContext(target_hwnd, hImc);
    applying = false;
  }
};

static LRESULT CALLBACK MultiWindowSubclassProc(HWND hWnd, UINT uMsg, WPARAM wParam,
                                                LPARAM lParam, UINT_PTR uIdSubclass,
                                                DWORD_PTR dwRefData) {
  ImeWindowContext* ctx = reinterpret_cast<ImeWindowContext*>(dwRefData);
  if (ctx) {
    switch (uMsg) {
      case WM_IME_STARTCOMPOSITION:
      case WM_IME_COMPOSITION: {
        LRESULT result = DefSubclassProc(hWnd, uMsg, wParam, lParam);
        ctx->Apply(hWnd);
        return result;
      }
      case WM_IME_NOTIFY: {
        LRESULT result = DefSubclassProc(hWnd, uMsg, wParam, lParam);
        if (wParam == IMN_OPENCANDIDATE || wParam == 0x0006 || wParam == 0x000B) {
          ctx->Apply(hWnd);
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
            int32_t x = 0, y = 0, height = 16;
            auto xi = args->find(flutter::EncodableValue("x"));
            if (xi != args->end()) x = std::get<int32_t>(xi->second);
            auto yi = args->find(flutter::EncodableValue("y"));
            if (yi != args->end()) y = std::get<int32_t>(yi->second);
            auto hi = args->find(flutter::EncodableValue("height"));
            if (hi != args->end()) height = std::get<int32_t>(hi->second);
            
            ctx->pos.x = x;
            ctx->pos.y = y;
            ctx->pos.height = (height > 0) ? height : 16;
            ctx->Apply(hwnd);
            
            result->Success();
          } else {
            result->Error("INVALID_ARGS", "Expected map with x, y, height");
          }
        } else {
          result->NotImplemented();
        }
      });

  ctx->channel = std::move(channel);
  SetWindowSubclass(hwnd, MultiWindowSubclassProc, 1, reinterpret_cast<DWORD_PTR>(ctx));
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
              int32_t x = 0, y = 0, height = 16;
              auto xi = args->find(flutter::EncodableValue("x"));
              if (xi != args->end())
                x = std::get<int32_t>(xi->second);
              auto yi = args->find(flutter::EncodableValue("y"));
              if (yi != args->end())
                y = std::get<int32_t>(yi->second);
              auto hi = args->find(flutter::EncodableValue("height"));
              if (hi != args->end())
                height = std::get<int32_t>(hi->second);
              UpdateImeCursorPosition(x, y, height);
              result->Success();
            } else {
              result->Error("INVALID_ARGS", "Expected map with x, y, height");
            }
          } else {
            result->NotImplemented();
          }
        });

    ime_channel_ = std::move(channel);
  DesktopMultiWindowSetWindowCreatedCallback([](void *controller) {
    auto *flutter_view_controller =
        reinterpret_cast<flutter::FlutterViewController *>(controller);
    auto *registry = flutter_view_controller->engine();
    RegisterPlugins(registry);
    AttachImeFixerToMultiWindow(flutter_view_controller);
  });
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

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
