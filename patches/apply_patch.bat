@echo off
echo 正在为 Flutter SDK 应用文本选中补丁...

:: 获取 Flutter 根目录
for /f "tokens=*" %%i in ('where flutter') do set FLUTTER_BIN=%%i
set FLUTTER_ROOT=%FLUTTER_BIN:\bin\flutter.bat=%
echo Flutter SDK 路径: %FLUTTER_ROOT%

cd /d "%FLUTTER_ROOT%"

:: 【防呆机制】：先强制把目标文件还原成官方初始状态，防止重复打补丁报错
git checkout packages/flutter/lib/src/rendering/editable.dart

:: 应用补丁（忽略由 Windows/Mac 换行符 CRLF/LF 引起的空白警告）
git apply --whitespace=nowarn "%~dp0\fix_textfield.patch"

if %ERRORLEVEL% EQU 0 (
    echo [成功] 补丁应用完成！
    :: 清理缓存以强制重新编译框架
    del /f /q "%FLUTTER_ROOT%\bin\cache\flutter_tools.stamp"
) else (
    echo [错误] 补丁应用失败，请检查 Flutter 版本是否跨度过大。
)

pause