# 应用内更新与下载加速

## 当前行为

- 未配置镜像时使用 GitHub Releases；优先读取接口内的 `digest`，缺少时兼容原有 `.sha256` 文件。
- 根据 Dart VM 当前实际运行的 Android ABI 选择对应安装包；无法识别或该版本没有对应包时使用通用 APK。这样不会把其他架构的 APK 发给当前设备。
- 配置镜像后，先请求镜像的 `latest.json`（5 秒超时），失败或清单无效时回退 GitHub API。
- APK 优先从镜像下载，连接超时（15 秒）、连续 30 秒没有实际字节、HTTP 错误或完整性校验失败时尝试 GitHub 的同一文件。切换时重新下载，不跨源拼接部分文件。
- 有备用源时还会识别持续低速：先预热 10 秒，再按最近 10 秒的速度判断；连续 15 秒低于 32 KiB/s 时切换。已下载达到 80% 或剩余不超过 2 MiB 时保留当前进度，最后一个源不会因低速被中断。
- 下载进度显示百分比和本次线路的平均速度。下载期间可明确取消，返回键或点击弹窗外部不会隐藏进度。
- SHA-256 通过后才调用系统安装页；完成未知来源授权或取消系统安装后，都可点“重试安装”复用已校验的缓存 APK，无须重新下载。
- APK 保存在应用私有缓存，取消和失败会清理部分文件。当前不支持跨进程断点续传。

## 构建与旧版本兼容

每个正式版本分发以下安装包，均使用同一个正式签名、`versionName` 和 `versionCode`：

| 文件 | 用途 |
|---|---|
| `hormone-vX.Y.Z-android.apk` | 通用包，供旧版更新器和未知架构使用 |
| `hormone-vX.Y.Z-arm64-v8a.apk` | ARM 64 位 |
| `hormone-vX.Y.Z-armeabi-v7a.apk` | ARM 32 位 |
| `hormone-vX.Y.Z-x86_64.apk` | x86 64 位 |

分架构文件名不含 `android`，以兼容旧版更新器对该词的优先选择规则。不要删除或重命名通用包。

构建脚本分别使用 `--target-platform`，不使用 `--split-per-abi`：Flutter 的后者会给不同架构增加 `versionCode` 偏移，导致未来回到通用包时可能被 Android 判为降级。Gradle 同时按目标架构过滤依赖中的原生库；CI 检查每份 APK 的签名、版本代码与实际架构。

本地执行 `powershell -NoProfile -File scripts/build_signed_android.ps1`。脚本读取现有的本机签名配置，最终可分发文件在 `build/release/`，包括各 APK 的校验文件、AAB 和更新清单。构建依赖 Python 3.11+。`build/app/outputs/flutter-apk/app-release.apk` 会被各架构构建覆盖，**发布时使用 `build/release/` 中的文件**。

本地签名构建还会自动检查四份 APK 的包名、版本号、版本代码和固定签名证书。也可单独运行 `scripts/verify_signed_apks.ps1`，不匹配时直接报错。

原生安装入口保存在 `native_templates/android/app/src/main/kotlin/com/aetikyue/hormone/MainActivity.kt`。重建 Android 平台目录时，须连同 Manifest 与 `res/xml/filepaths.xml` 一并应用；发布流程和本地签名脚本均已包含这一步。

## 接入自有下载源

需要一个自己控制的 HTTPS 静态下载目录。URL 为公开信息，密钥只保存在发布环境中。未配置时无需存储账号，应用继续使用 GitHub。

目录示例：

```text
https://updates.example.com/hormone/
  latest.json
  vX.Y.Z/
    hormone-vX.Y.Z-android.apk
    hormone-vX.Y.Z-arm64-v8a.apk
    hormone-vX.Y.Z-armeabi-v7a.apk
    hormone-vX.Y.Z-x86_64.apk
    ...各 APK 的 .sha256 文件
```

`latest.json` 由 `scripts/prepare_update_manifest.py` 从构建后的实际文件生成，包含版本、更新日志、文件大小和 SHA-256，保留 GitHub 原始下载 URL 作为备用。必须先上传全部版本文件，再替换 `latest.json`；不要手工编造哈希或让未完成上传的版本成为最新版本。

### GitHub Actions 可选的 S3 兼容上传

在仓库 Settings → Secrets and variables → Actions 配置：

| 类型 | 名称 | 内容 |
|---|---|---|
| Variable | `HORMONE_UPDATE_BASE_URL` | 公开 HTTPS 下载目录，例如 `https://updates.example.com/hormone/` |
| Variable | `HORMONE_UPDATE_S3_URI` | 对应上传目录，例如 `s3://your-bucket/hormone` |
| Variable | `HORMONE_UPDATE_S3_ENDPOINT` | 服务商 S3 兼容接口地址；AWS S3 可留空 |
| Variable | `HORMONE_UPDATE_S3_REGION` | 服务商要求的 region；默认 `us-east-1` |
| Secret | `HORMONE_UPDATE_S3_ACCESS_KEY_ID` | 仅允许写入该发布目录的访问密钥 ID |
| Secret | `HORMONE_UPDATE_S3_SECRET_ACCESS_KEY` | 对应访问密钥 |

公开下载目录必须映射到该 S3 URI，且允许用户通过 HTTPS 读取文件。某些对象存储需要额外启用 S3 兼容接口；不支持该协议时，保留相同目录布局，使用服务商上传工具替换 workflow 的上传步骤。

只有设置 `HORMONE_UPDATE_BASE_URL` 才启用自动镜像上传。GitHub Release 发布完成后上传镜像；重建旧标签时，不覆盖新版本的 `latest.json`。上传失败会使发布任务报错；应用仍能回退到 GitHub。

带 CDN 时，让 `latest.json` 不缓存或每次重新验证，版本文件可长期缓存。已发布的版本文件应保持不变，修复请发新版本，以免客户端清单与缓存中的 APK 校验不一致。

本地构建注入同一地址：

```powershell
powershell -NoProfile -File scripts/build_signed_android.ps1 -UpdateBaseUrl 'https://updates.example.com/hormone/'
```

以上域名只是示例，不是已部署服务。首次启用本功能需要先把含新更新器的版本送到用户设备，之后的更新才会自动选择小包与镜像。旧版本仍按原逻辑下载通用包。

## 验证

```text
dart run build_runner build --delete-conflicting-outputs
flutter analyze --fatal-infos --fatal-warnings
flutter test
python -m unittest discover -s scripts -p "test_*.py"
```

发布前在 Android 上验证：首次授权后安装、已有授权时安装、取消下载、断网后的回退，以及从旧版本覆盖升级。自动测试覆盖下载与校验逻辑，不能代替系统安装器的实机确认。
