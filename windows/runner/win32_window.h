#ifndef RUNNER_WIN32_WINDOW_H_
#define RUNNER_WIN32_WINDOW_H_

#include <windows.h>
#include <imm.h>
#include <functional>
#include <memory>
#include <string>

// IME tracking rect; coordinates and size are in logical pixels relative to
// the Flutter view client area. Sub-pixel values are preserved so that the
// physical pixel conversion matches the Flutter engine exactly.
struct ImeCursorPosition {  
  double x = 0;           // Left edge of the rect
  double y = 0;           // Top edge of the rect
  double height = 16;     // Rect height, i.e. the full text line height
  double text_height = 16; // Glyph height of the text, used to anchor the
                           // composition window at the bottom of the line
  bool valid = false;     // Whether a position has been reported by Dart yet
};  

// Places the composition window of the target window at the bottom of the text
// glyphs. IMEs which draw the composing string inside their candidate window
// derive the candidate position from this anchor, so anchoring at the top of
// the line would make the candidate overlap the upper half of the text line.
// The candidate window itself is left to the Flutter engine, which positions it
// from the caret rect fed by the framework: keeping a single placement authority
// avoids the candidate being moved twice within one keystroke.
void ApplyImeCompositionWindow(HWND target_hwnd, const ImeCursorPosition& pos);

// A class abstraction for a high DPI-aware Win32 Window. Intended to be
// inherited from by classes that wish to specialize with custom
// rendering and input handling
class Win32Window {
 public:
  struct Point {
    unsigned int x;
    unsigned int y;
    Point(unsigned int x, unsigned int y) : x(x), y(y) {}
  };

  struct Size {
    unsigned int width;
    unsigned int height;
    Size(unsigned int width, unsigned int height)
        : width(width), height(height) {}
  };
  void UpdateImeCursorPosition(double x, double y, double height,
                               double text_height); 

  Win32Window();
  virtual ~Win32Window();

  // Creates a win32 window with |title| that is positioned and sized using
  // |origin| and |size|. New windows are created on the default monitor. Window
  // sizes are specified to the OS in physical pixels, hence to ensure a
  // consistent size this function will scale the inputted width and height as
  // as appropriate for the default monitor. The window is invisible until
  // |Show| is called. Returns true if the window was created successfully.
  bool Create(const std::wstring& title, const Point& origin, const Size& size);

  // Show the current window. Returns true if the window was successfully shown.
  bool Show();

  // Release OS resources associated with window.
  void Destroy();

  // Inserts |content| into the window tree.
  void SetChildContent(HWND content);

  // Returns the backing Window handle to enable clients to set icon and other
  // window properties. Returns nullptr if the window has been destroyed.
  HWND GetHandle();

  // If true, closing this window will quit the application.
  void SetQuitOnClose(bool quit_on_close);

  // Return a RECT representing the bounds of the current client area.
  RECT GetClientArea();

 protected:
  void ApplyImeCompositionAnchorToView(HWND hwnd);

  // Processes and route salient window messages for mouse handling,
  // size change and DPI. Delegates handling of these to member overloads that
  // inheriting classes can handle.
  virtual LRESULT MessageHandler(HWND window,
                                 UINT const message,
                                 WPARAM const wparam,
                                 LPARAM const lparam) noexcept;

  // Called when CreateAndShow is called, allowing subclass window-related
  // setup. Subclasses should return false if setup fails.
  virtual bool OnCreate();

  // Called when Destroy is called.
  virtual void OnDestroy();

 private:
  friend class WindowClassRegistrar;
  
  ImeCursorPosition ime_cursor_pos_;

  // OS callback called by message pump. Handles the WM_NCCREATE message which
  // is passed when the non-client area is being created and enables automatic
  // non-client DPI scaling so that the non-client area automatically
  // responds to changes in DPI. All other messages are handled by
  // MessageHandler.
  static LRESULT CALLBACK WndProc(HWND const window,
                                  UINT const message,
                                  WPARAM const wparam,
                                  LPARAM const lparam) noexcept;

  // Retrieves a class instance pointer for |window|
  static Win32Window* GetThisFromHandle(HWND const window) noexcept;

  // Update the window frame's theme to match the system theme.
  static void UpdateTheme(HWND const window);

  bool quit_on_close_ = false;
  bool applying_ime_cursor_ = false;

  // window handle for top level window.
  HWND window_handle_ = nullptr;

  // window handle for hosted content.
  HWND child_content_ = nullptr;
  static LRESULT CALLBACK ChildSubclassProc(HWND hWnd, UINT uMsg, WPARAM wParam,
                                            LPARAM lParam, UINT_PTR uIdSubclass,
                                            DWORD_PTR dwRefData);
};

#endif  // RUNNER_WIN32_WINDOW_H_
