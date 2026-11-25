# 1.3.2

### 新增

- 重构大纲编辑器的字体、字底颜色选单，新增字体、字底、关键词自定义颜色功能；

### 优化

- 优化桌面端全屏切换逻辑，现在在最大化下切换全屏模式时不用先恢复成小窗口再进入全屏了；
- 重构 TextField 组件，进行了多项选区细节上的优化；
- 大纲编辑器引入节点ID替代层级路径作为节点唯一标识，避免了层级变化可能导致的一些潜在问题；
- 重构桌面端右键菜单内边距与样式；
- 优化移动端快捷操作栏按钮尺寸与样式；
- 为大纲编辑器的备注编辑接入撤销、恢复功能；

### 修复

- 修复大纲编辑器及部分输入框的一个选区BUG；（你们嘴是真硬啊，大纲编辑器的选区都被字底色给压住了也不反馈，我今天才注意到有这个问题）
- 修复大纲编辑器在查找替换栏开启和关闭时内容闪烁的问题；
- 修复编辑器宽度变化时视口位置偏移过大的问题；
- 修复多分卷合并导出章节错位问题；
- 修复开启实时同步后，分卷/分组的展开状态不会被保存的问题

## 下载

| 设备/平台 | 默认地址 | 备用地址 |
|-------|-------|-------|
| Windows | [下载](https://github.com/yic77455/QuickWrite/releases/download/v{{VERSION}}/quick-write-{{VERSION}}-windows-x64.exe) | [下载](https://gitee.com/yic77455/quick-write/releases/download/v{{VERSION}}/quick-write-{{VERSION}}-windows-x64.exe) |
| macOS | [下载](https://github.com/yic77455/QuickWrite/releases/download/v{{VERSION}}/quick-write-{{VERSION}}-macos-universal.dmg) | [下载](https://gitee.com/yic77455/quick-write/releases/download/v{{VERSION}}/quick-write-{{VERSION}}-macos-universal.dmg) |
| Linux | [下载](https://github.com/yic77455/QuickWrite/releases/download/v{{VERSION}}/quick-write-{{VERSION}}-linux-amd64.deb) | [下载](https://gitee.com/yic77455/quick-write/releases/download/v{{VERSION}}/quick-write-{{VERSION}}-linux-amd64.deb) |
| Android | [下载](https://github.com/yic77455/QuickWrite/releases/download/v{{VERSION}}/quick-write-{{VERSION}}-android.apk) | [下载](https://gitee.com/yic77455/quick-write/releases/download/v{{VERSION}}/quick-write-{{VERSION}}-android.apk) |

> Linux 和 macOS 平台版本尚处于测试阶段，如果在使用过程中遇到问题，请及时反馈。
