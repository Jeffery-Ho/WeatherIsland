# WeatherIsland 打包说明

这个文档记录当前仓库的 macOS 打包流程，目标是让你可以自己从源码生成：

- `WeatherIsland.app`
- `WeatherIsland-macOS.dmg`

当前仓库已经提供自动化脚本：

```bash
bash /Users/hexianji/Downloads/WeatherIsland/package.sh
```

如果你的环境里执行权限正常，也可以直接运行：

```bash
/Users/hexianji/Downloads/WeatherIsland/package.sh
```

以下步骤默认在仓库根目录执行：

```bash
cd /Users/hexianji/Downloads/WeatherIsland
```

## 1. 环境要求

- macOS
- 已安装 Xcode Command Line Tools
- 已安装完整 Xcode

可以先确认：

```bash
xcodebuild -version
```

## 2. 构建 macOS App

当前推荐直接使用 Xcode 工程打包，而不是走旧的 SwiftPM `build-app.sh`。

执行 Release 构建：

```bash
xcodebuild \
  -project WeatherIslandXcode/WeatherIsland.xcodeproj \
  -scheme WeatherIsland \
  -configuration Release \
  -derivedDataPath dist-dmg/DerivedData \
  -destination 'platform=macOS' \
  build
```

构建完成后，生成的 `.app` 在这里：

```bash
dist-dmg/DerivedData/Build/Products/Release/WeatherIsland.app
```

如果你只是想确认工程是否能正常编译，也可以用 Debug：

```bash
xcodebuild \
  -project WeatherIslandXcode/WeatherIsland.xcodeproj \
  -scheme WeatherIsland \
  -configuration Debug \
  -destination 'platform=macOS' \
  build
```

## 3. 准备 DMG staging 目录

先清理旧产物：

```bash
rm -rf dist-dmg/staging
rm -f dist-dmg/WeatherIsland-macOS.dmg
```

重新创建 staging 目录并复制应用：

```bash
mkdir -p dist-dmg/staging
cp -R dist-dmg/DerivedData/Build/Products/Release/WeatherIsland.app dist-dmg/staging/WeatherIsland.app
cp dist-dmg/README-install.txt dist-dmg/staging/README-install.txt
ln -s /Applications dist-dmg/staging/Applications
```

最终 staging 目录应大致如下：

```text
dist-dmg/staging/
  Applications -> /Applications
  README-install.txt
  WeatherIsland.app
```

## 4. 生成 DMG

使用 `hdiutil` 生成压缩 DMG：

```bash
hdiutil create \
  -volname "WeatherIsland" \
  -srcfolder dist-dmg/staging \
  -ov \
  -format UDZO \
  dist-dmg/WeatherIsland-macOS.dmg
```

生成结果：

```bash
dist-dmg/WeatherIsland-macOS.dmg
```

## 5. 验证产物

可以先看文件是否生成：

```bash
ls -lh dist-dmg/WeatherIsland-macOS.dmg
ls -lh dist-dmg/DerivedData/Build/Products/Release/WeatherIsland.app
```

也可以本地打开测试：

```bash
open dist-dmg/DerivedData/Build/Products/Release/WeatherIsland.app
open dist-dmg/WeatherIsland-macOS.dmg
```

## 6. 当前产物特点

- 当前包是未签名测试版。
- 首次打开时，macOS 可能提示无法验证开发者。
- 对外发送时，可以附带 `dist-dmg/README-install.txt` 里的安装说明。

## 7. 一次性完整命令

如果你想一次性从源码生成 `.dmg`，可以按顺序执行：

```bash
cd /Users/hexianji/Downloads/WeatherIsland

rm -rf dist-dmg/staging
rm -f dist-dmg/WeatherIsland-macOS.dmg

xcodebuild \
  -project WeatherIslandXcode/WeatherIsland.xcodeproj \
  -scheme WeatherIsland \
  -configuration Release \
  -derivedDataPath dist-dmg/DerivedData \
  -destination 'platform=macOS' \
  build

mkdir -p dist-dmg/staging
cp -R dist-dmg/DerivedData/Build/Products/Release/WeatherIsland.app dist-dmg/staging/WeatherIsland.app
cp dist-dmg/README-install.txt dist-dmg/staging/README-install.txt
ln -s /Applications dist-dmg/staging/Applications

hdiutil create \
  -volname "WeatherIsland" \
  -srcfolder dist-dmg/staging \
  -ov \
  -format UDZO \
  dist-dmg/WeatherIsland-macOS.dmg
```

## 8. 备注

- `build-app.sh` 是旧的 SwiftPM 打包脚本，目前不作为主流程推荐。
- 现阶段最稳的方式是直接基于 `WeatherIslandXcode/WeatherIsland.xcodeproj` 做 Release 构建再封装 DMG。
- 现在已经提供 `package.sh`，推荐优先使用这个脚本。
- 如果你不是先 `cd` 到仓库目录，请直接使用绝对路径运行：
  `bash /Users/hexianji/Downloads/WeatherIsland/package.sh`
