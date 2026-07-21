修改了源码文件：flutter/packages/flutter/lib/src/rendering/editable.dart。
在这个文件中搜索 void _paintSelection 或者搜索 canvas.drawRect（与 selection 相关的绘制逻辑）。
应用了补丁后，删除 flutter/bin/cache/flutter_tools.stamp 文件，然后重新运行项目。

---------------------------
# 查看刚才改了哪些文件
在 Flutter SDK 根目录下，打开终端，运行：
git status 

----------------------------
# 还原 Flutter SDK
将 Flutter SDK 恢复到未修改状态：
终端运行：
git checkout .
----------------------------
