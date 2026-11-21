# 1.3.0

### 新增

- 移动端新增快捷输入栏符号列表的自定义功能，用户可在「其他设置 - 快捷输入」下的「符号列表」中进行修改。支持成对符号配置，修改后即时生效于编辑器自动补全、快捷输入栏及回车跳出成对符号逻辑；
- 移动端字数浮窗新增可选的精简和极简模式，极简模式下仅显示字数信息，不显示图标与标签；
- 移动端新增快捷短语功能，用户可在「其他设置 - 快捷输入」下的「右侧图标」中进行配置使用；
- 新增自动替换功能，桌面端入口在「其他设置 - 输入习惯」下，移动端入口在「其他设置 - 快捷输入」中，点击后弹出替换规则配置窗口；

### 优化

- 优化查找替换功能，现在会优先从当前光标位置寻找下一个，而不是从文档开头；
- 优化了正文编辑器的底部安全机制逻辑，当滚动条和页面没有触底的情况下，编辑最后一行时，除非换行了，否则不再触发底部安全机制使视口移动；
- 现在在桌面端的纸张模式下，纸张会始终居中，不再受两个侧边栏的宽度影响了；
- 优化随机取名的生成数量选择，将生成数量的下拉框改成输入框，用户可以直接输入生成数量；
- 将移动端工作台的码字统计面板对齐桌面端，以右边栏的形式显示，用户现在可通过从屏幕右边缘向左滑动的方式直接打开码字统计面板；

### 修复

- 修复移动端正文编辑器的滚动条无法拖动的问题；
- 修复移动端右边栏在打开状态下直接杀后台结束应用进程后，下次进入工作台无法正常打开右边栏的问题；
- 修复移动端目录列表拖拽排序时拖拽项会变成模糊一团的问题；
- 修复移动端部分场景的非活跃弹窗会在变成活跃的那一瞬间为正在收起的输入法让位，在视觉上往上顶一下再落回来的问题；


## 下载

| 设备/平台 | 默认地址 | 备用地址 |
|-------|-------|-------|
| Windows | [下载](https://github.com/yic77455/QuickWrite/releases/download/v{{VERSION}}/quick-write-{{VERSION}}-x64-setup.exe) | [下载](https://gitee.com/yic77455/quick-write/releases/download/v{{VERSION}}/quick-write-{{VERSION}}-x64-setup.exe) |
| macOS | [下载](https://github.com/yic77455/QuickWrite/releases/download/v{{VERSION}}/quick-write-{{VERSION}}-macos-universal.dmg) | [下载](https://gitee.com/yic77455/quick-write/releases/download/v{{VERSION}}/quick-write-{{VERSION}}-macos-universal.dmg) |
| Linux | [下载](https://github.com/yic77455/QuickWrite/releases/download/v{{VERSION}}/quickwrite_{{VERSION}}_amd64.deb) | [下载](https://gitee.com/yic77455/quick-write/releases/download/v{{VERSION}}/quickwrite_{{VERSION}}_amd64.deb) |
| Android | [下载](https://github.com/yic77455/QuickWrite/releases/download/v{{VERSION}}/quick-write-{{VERSION}}-android.apk) | [下载](https://gitee.com/yic77455/quick-write/releases/download/v{{VERSION}}/quick-write-{{VERSION}}-android.apk) |

> Linux 和 macOS 平台版本尚处于测试阶段，如果在使用过程中遇到问题，请及时反馈。
> Linux 端卸载：终端执行 `sudo apt remove quickwrite` 即可，书稿与设置不会被删除；如需连同配置一起彻底清除，执行 `sudo apt purge quickwrite`。
