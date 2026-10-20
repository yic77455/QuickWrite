#include "win32_window.h"

#include <dwmapi.h>
#include <flutter_windows.h>

#include "resource.h"

#include <imm.h>
#pragma comment(lib, "imm32.lib")

#include <commctrl.h>
#pragma comment(lib, "comctl32.lib")

namespace {

/// Window attribute that enables dark mode window decorations.
///
/// Redefined in case the developer's machine has a Windows SDK older than
/// version 10.0.22000.0.
/// See: https://docs.microsoft.com/windows/win32/api/dwmapi/ne-dwmapi-dwmwindowattribute
#ifndef DWMWA_USE_IMMERSIVE_DARK_MODE
#define DWMWA_USE_IMMERSIVE_DARK_MODE 20
#endif

constexpr const wchar_t kWindowClassName[] = L"FLUTTER_RUNNER_WIN32_WINDOW";

/// Registry key for app theme preference.
///
/// A value of 0 indicates apps should use dark mode. A non-zero or missing
/// value indicates apps should use light mode.
constexpr const wchar_t kGetPreferredBrightnessRegKey[] =
  L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize";
constexpr const wchar_t kGetPreferredBrightnessRegValue[] = L"AppsUseLightTheme";

// The number of Win32Window objects that currently exist.
static int g_active_window_count = 0;

using EnableNonClientDpiScaling = BOOL __stdcall(HWND hwnd);

// Scale helper to convert logical scaler values to physical using passed in
// scale factor
int Scale(int source, double scale_factor) {
  return static_cast<int>(source * scale_factor);
}

// Dynamically loads the |EnableNonClientDpiScaling| from the User32 module.
// This API is only needed for PerMonitor V1 awareness mode.
void EnableFullDpiSupportIfAvailable(HWND hwnd) {
  HMODULE user32_module = LoadLibraryA("User32.dll");
  if (!user32_module) {
    return;
  }
  auto enable_non_client_dpi_scaling =
      reinterpret_cast<EnableNonClientDpiScaling*>(
          GetProcAddress(user32_module, "EnableNonClientDpiScaling"));
  if (enable_non_client_dpi_scaling != nullptr) {
    enable_non_client_dpi_scaling(hwnd);
  }
  FreeLibrary(user32_module);
}

}  // namespace

// Manages the Win32Window's window class registration.
class WindowClassRegistrar {
 public:
  ~WindowClassRegistrar() = default;

  // Returns the singleton registrar instance.
  static WindowClassRegistrar* GetInstance() {
    if (!instance_) {
      instance_ = new WindowClassRegistrar();
    }
    return instance_;
  }

  // Returns the name of the window class, registering the class if it hasn't
  // previously been registered.
  const wchar_t* GetWindowClass();

  // Unregisters the window class. Should only be called if there are no
  // instances of the window.
  void UnregisterWindowClass();

 private:
  WindowClassRegistrar() = default;

  static WindowClassRegistrar* instance_;

  bool class_registered_ = false;
};

WindowClassRegistrar* WindowClassRegistrar::instance_ = nullptr;

const wchar_t* WindowClassRegistrar::GetWindowClass() {
  if (!class_registered_) {
    WNDCLASS window_class{};
    window_class.hCursor = LoadCursor(nullptr, IDC_ARROW);
    window_class.lpszClassName = kWindowClassName;
    window_class.style = CS_HREDRAW | CS_VREDRAW;
    window_class.cbClsExtra = 0;
    window_class.cbWndExtra = 0;
    window_class.hInstance = GetModuleHandle(nullptr);
    window_class.hIcon =
        LoadIcon(window_class.hInstance, MAKEINTRESOURCE(IDI_APP_ICON));
    window_class.hbrBackground = 0;
    window_class.lpszMenuName = nullptr;
    window_class.lpfnWndProc = Win32Window::WndProc;
    RegisterClass(&window_class);
    class_registered_ = true;
  }
  return kWindowClassName;
}

void WindowClassRegistrar::UnregisterWindowClass() {
  UnregisterClass(kWindowClassName, nullptr);
  class_registered_ = false;
}

Win32Window::Win32Window() {
  ++g_active_window_count;
}

Win32Window::~Win32Window() {
  --g_active_window_count;
  Destroy();
}

bool Win32Window::Create(const std::wstring& title,
                         const Point& origin,
                         const Size& size) {
  Destroy();

  const wchar_t* window_class =
      WindowClassRegistrar::GetInstance()->GetWindowClass();

  const POINT target_point = {static_cast<LONG>(origin.x),
                              static_cast<LONG>(origin.y)};
  HMONITOR monitor = MonitorFromPoint(target_point, MONITOR_DEFAULTTONEAREST);
  UINT dpi = FlutterDesktopGetDpiForMonitor(monitor);
  double scale_factor = dpi / 96.0;

  HWND window = CreateWindow(
      window_class, title.c_str(), WS_OVERLAPPEDWINDOW,
      Scale(origin.x, scale_factor), Scale(origin.y, scale_factor),
      Scale(size.width, scale_factor), Scale(size.height, scale_factor),
      nullptr, nullptr, GetModuleHandle(nullptr), this);

  if (!window) {
    return false;
  }

  UpdateTheme(window);

  return OnCreate();
}

bool Win32Window::Show() {
  return ShowWindow(window_handle_, SW_SHOWNORMAL);
}

// static
LRESULT CALLBACK Win32Window::WndProc(HWND const window,
                                      UINT const message,
                                      WPARAM const wparam,
                                      LPARAM const lparam) noexcept {
  if (message == WM_NCCREATE) {
    auto window_struct = reinterpret_cast<CREATESTRUCT*>(lparam);
    SetWindowLongPtr(window, GWLP_USERDATA,
                     reinterpret_cast<LONG_PTR>(window_struct->lpCreateParams));

    auto that = static_cast<Win32Window*>(window_struct->lpCreateParams);
    EnableFullDpiSupportIfAvailable(window);
    that->window_handle_ = window;
  } else if (Win32Window* that = GetThisFromHandle(window)) {
    return that->MessageHandler(window, message, wparam, lparam);
  }

  return DefWindowProc(window, message, wparam, lparam);
}

LRESULT
Win32Window::MessageHandler(HWND hwnd,
                            UINT const message,
                            WPARAM const wparam,
                            LPARAM const lparam) noexcept {
  switch (message) {
     case WM_IME_STARTCOMPOSITION: {
      ApplyImeCursorToWindow(hwnd);
      return 0;
    }
    case WM_IME_COMPOSITION: {
      break;
    }
    case WM_IME_NOTIFY: {
      if (wparam == IMN_OPENCANDIDATE) {
        ApplyImeCursorToWindow(hwnd);
      }
      break;
    }
    case WM_DESTROY:
      window_handle_ = nullptr;
      Destroy();
      if (quit_on_close_) {
        PostQuitMessage(0);
      }
      return 0;

    case WM_DPICHANGED: {
      auto newRectSize = reinterpret_cast<RECT*>(lparam);
      LONG newWidth = newRectSize->right - newRectSize->left;
      LONG newHeight = newRectSize->bottom - newRectSize->top;

      SetWindowPos(hwnd, nullptr, newRectSize->left, newRectSize->top, newWidth,
                   newHeight, SWP_NOZORDER | SWP_NOACTIVATE);

      return 0;
    }
    case WM_SIZE: {
      RECT rect = GetClientArea();
      if (child_content_ != nullptr) {
        // Size and position the child window.
        MoveWindow(child_content_, rect.left, rect.top, rect.right - rect.left,
                   rect.bottom - rect.top, TRUE);
      }
      return 0;
    }

    case WM_ACTIVATE:
      if (child_content_ != nullptr) {
        SetFocus(child_content_);
      }
      return 0;

    case WM_DWMCOLORIZATIONCOLORCHANGED:
      UpdateTheme(hwnd);
      return 0;
  }

  return DefWindowProc(window_handle_, message, wparam, lparam);
}

namespace {

// Physical pixel rectangle of the IME tracking area in client coordinates.
struct ImePhysicalRect {
  LONG left = 0;
  LONG top = 0;
  LONG right = 0;
  LONG bottom = 16;
  LONG text_height = 16;
};

// Converts the logical tracking rect into physical client pixels.
// The conversion mirrors the Flutter engine: scale by the window DPI, then
// truncate. Sharing the same rule keeps the engine's placement and ours
// pixel-identical.
ImePhysicalRect ToPhysicalImeRect(HWND target_hwnd,
                                  const ImeCursorPosition& pos) {
  UINT dpi = 96;
  using GetDpiForWindowFn = UINT(WINAPI*)(HWND);
  static auto getDpiForWindow = reinterpret_cast<GetDpiForWindowFn>(
      GetProcAddress(GetModuleHandle(L"User32.dll"), "GetDpiForWindow"));
  if (getDpiForWindow) {
    dpi = getDpiForWindow(target_hwnd);
  }

  const double scale = static_cast<double>(dpi) / 96.0;
  ImePhysicalRect rect;
  rect.left = static_cast<LONG>(pos.x * scale);
  rect.top = static_cast<LONG>(pos.y * scale);
  rect.right = static_cast<LONG>((pos.x + pos.width) * scale);
  rect.bottom = static_cast<LONG>((pos.y + pos.height) * scale);
  if (rect.bottom <= rect.top) {
    rect.bottom = rect.top + 16;
  }
  rect.text_height = static_cast<LONG>(pos.text_height * scale);
  if (rect.text_height <= 0 || rect.text_height > rect.bottom - rect.top) {
    rect.text_height = rect.bottom - rect.top;
  }
  return rect;
}

}  // namespace

void ApplyImeCursor(HWND target_hwnd, const ImeCursorPosition& pos) {
  if (!pos.valid) {
    return;
  }

  HIMC hImc = ImmGetContext(target_hwnd);
  if (!hImc) {
    return;
  }
 
  const ImePhysicalRect rect = ToPhysicalImeRect(target_hwnd, pos);

  // Anchor the composition window at the bottom of the text glyphs. IMEs that
  // draw the composing string inside their candidate window derive the
  // candidate position from this anchor, so anchoring at the rect top would
  // make the candidate overlap the upper half of the text line.
  LONG composition_top = rect.bottom - rect.text_height;
  if (composition_top < rect.top) {
    composition_top = rect.top;
  }
  if (composition_top > rect.bottom - 1) {
    composition_top = rect.bottom - 1;
  }

  COMPOSITIONFORM cf = {};
  cf.dwStyle = CFS_POINT;
  cf.ptCurrentPos.x = rect.left;
  cf.ptCurrentPos.y = composition_top;
  ImmSetCompositionWindow(hImc, &cf);
 
  // Anchor the candidate window at the bottom-left corner and exclude the
  // whole rect so that it never covers the text being typed. This is identical
  // to the Flutter engine's own placement, so the two never fight each other.
  CANDIDATEFORM cdf = {};
  cdf.dwIndex = 0;
  cdf.dwStyle = CFS_EXCLUDE;
  cdf.ptCurrentPos.x = rect.left;
  cdf.ptCurrentPos.y = rect.bottom;
  cdf.rcArea.left = rect.left;
  cdf.rcArea.top = rect.top;
  cdf.rcArea.right = rect.right;
  cdf.rcArea.bottom = rect.bottom;
  ImmSetCandidateWindow(hImc, &cdf);
 
  ImmReleaseContext(target_hwnd, hImc);
}

void Win32Window::ApplyImeCursorToWindow(HWND hwnd) {
  if (applying_ime_cursor_) return;
  applying_ime_cursor_ = true;

  ApplyImeCursor(child_content_ ? child_content_ : hwnd, ime_cursor_pos_);
  applying_ime_cursor_ = false;
}
 
void Win32Window::UpdateImeCursorPosition(double x, double y, double width, double height,
                                          double text_height) {
  ime_cursor_pos_.x = x;
  ime_cursor_pos_.y = y;
  ime_cursor_pos_.width = (width > 0) ? width : 0;
  ime_cursor_pos_.height = (height > 0) ? height : 16;
  ime_cursor_pos_.text_height = (text_height > 0) ? text_height : 16;
  ime_cursor_pos_.valid = true;

  if (window_handle_) {
    ApplyImeCursorToWindow(window_handle_);
  }
}

void Win32Window::Destroy() {
  OnDestroy();

  if (window_handle_) {
    DestroyWindow(window_handle_);
    window_handle_ = nullptr;
  }
  if (g_active_window_count == 0) {
    WindowClassRegistrar::GetInstance()->UnregisterWindowClass();
  }
}

Win32Window* Win32Window::GetThisFromHandle(HWND const window) noexcept {
  return reinterpret_cast<Win32Window*>(
      GetWindowLongPtr(window, GWLP_USERDATA));
}

void Win32Window::SetChildContent(HWND content) {
  child_content_ = content;
  SetParent(content, window_handle_);
  RECT frame = GetClientArea();

  MoveWindow(content, frame.left, frame.top, frame.right - frame.left,
             frame.bottom - frame.top, true);

  // Subclass the child window to intercept IME messages safely
  SetWindowSubclass(child_content_, ChildSubclassProc, 1, reinterpret_cast<DWORD_PTR>(this));

  SetFocus(child_content_);
}

LRESULT CALLBACK Win32Window::ChildSubclassProc(HWND hWnd, UINT uMsg, WPARAM wParam,
                                                LPARAM lParam, UINT_PTR uIdSubclass,
                                                DWORD_PTR dwRefData) {
  Win32Window* that = reinterpret_cast<Win32Window*>(dwRefData);
  if (that) {
    switch (uMsg) {
      case WM_IME_STARTCOMPOSITION:
      case WM_IME_COMPOSITION: {
        // Call the original window proc first so Flutter does its thing
        LRESULT result = DefSubclassProc(hWnd, uMsg, wParam, lParam);
        // Then apply our correct coordinates
        that->ApplyImeCursorToWindow(hWnd);
        return result;
      }
      case WM_IME_NOTIFY: {
        LRESULT result = DefSubclassProc(hWnd, uMsg, wParam, lParam);
        if (wParam == IMN_OPENCANDIDATE || wParam == 0x0006 /* IMN_CHANGECANDIDATE */ || wParam == 0x000B /* IMN_SETCOMPOSITIONWINDOW */) {
          that->ApplyImeCursorToWindow(hWnd);
        }
        return result;
      }
      case WM_NCDESTROY:
        RemoveWindowSubclass(hWnd, ChildSubclassProc, uIdSubclass);
        break;
    }
  }
  return DefSubclassProc(hWnd, uMsg, wParam, lParam);
}

RECT Win32Window::GetClientArea() {
  RECT frame;
  GetClientRect(window_handle_, &frame);
  return frame;
}

HWND Win32Window::GetHandle() {
  return window_handle_;
}

void Win32Window::SetQuitOnClose(bool quit_on_close) {
  quit_on_close_ = quit_on_close;
}

bool Win32Window::OnCreate() {
  // No-op; provided for subclasses.
  return true;
}

void Win32Window::OnDestroy() {
  // No-op; provided for subclasses.
}

void Win32Window::UpdateTheme(HWND const window) {
  DWORD light_mode;
  DWORD light_mode_size = sizeof(light_mode);
  LSTATUS result = RegGetValue(HKEY_CURRENT_USER, kGetPreferredBrightnessRegKey,
                               kGetPreferredBrightnessRegValue,
                               RRF_RT_REG_DWORD, nullptr, &light_mode,
                               &light_mode_size);

  if (result == ERROR_SUCCESS) {
    BOOL enable_dark_mode = light_mode == 0;
    DwmSetWindowAttribute(window, DWMWA_USE_IMMERSIVE_DARK_MODE,
                          &enable_dark_mode, sizeof(enable_dark_mode));
  }
}
