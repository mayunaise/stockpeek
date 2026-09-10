# 应用图标

使用与应用侧边栏相同的 SF Symbol `waveform.path`（light 字重）和冰蓝色（0.65, 0.79, 0.98），搭配深色圆角底座。

- AppIcon.png：1024px 透明背景母图。
- AppIcon.icns：macOS 16–1024px 图标包，已在应用 Info.plist 中注册。
- AppIcon-preview.png：256px 预览。
- 修改或重建：bash scripts/build-icon.sh。AppKit 渲染代码为 scripts/render-icon.swift。
