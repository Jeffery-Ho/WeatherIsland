# Weather Island

仓库当前聚焦一个方向：

- `WeatherIslandXcode/`：macOS 高拟真刘海天气组件原型

## 当前工程

当前推荐使用：

```bash
xcodebuild -project WeatherIslandXcode/WeatherIsland.xcodeproj -scheme WeatherIsland -configuration Debug -destination 'platform=macOS' build
```

构建成功。

补充说明：

- 根目录旧的 SwiftPM 原型不再是主构建入口。
- 如果你之前是从 `Sources/WeatherIsland/main.swift` 那条路径触发构建，容易遇到 `@main` 与 `main.swift` 的入口冲突。
- 当前请统一通过 `WeatherIslandXcode/WeatherIsland.xcodeproj` 或根目录的 `build-app.sh`、`package.sh` 构建，这条链路不需要你单独安装额外的 Metal 技术栈。
