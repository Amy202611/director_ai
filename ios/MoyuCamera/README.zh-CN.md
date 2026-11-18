# MoyuCamera：SideStore 名称修复版

原生 Swift + SwiftUI 基础工程，应用内为中文；桌面和安装名称为英文 MoyuCamera。
此仓库已重新初始化，当前原生基础工程不包含安卓相机的完整功能。
已有：照片导入、本地水印预览、日期时间及地址输入、三种外观。
拍照、GPS 和视频导出尚未移植到此 iOS 基础版本。

## 本次修复

SideStore 报错 SideSign.DeveloperPortalError 10：
An invalid value '摸鱼相机' was provided for the parameter 'appIdName'。

将 CFBundleName、CFBundleDisplayName 统一固定为 ASCII MoyuCamera，
避免 SideStore 向 Apple Developer Portal 提交中文 App ID 名称。
不添加 InfoPlist.strings 的中文名称覆盖，应用内部导航和按钮仍可正常使用中文。
这不是仅修改 IPA 文件名。

构建后的 IPA 会重新读取二进制 Info.plist 校验两种名称，
并核对真机 ARM64、iPhoneOS、最低 iOS 16.0、无签名和无加密。
此修复包内部版本为 1.0.1，构建号从 101 起。
实际 Apple ID 注册和 iPhone 安装仍需在 SideStore 验证。

## Windows 下载及安装

打开 Actions → iOS Unsigned IPA → 最近绿色运行 → Artifacts。
下载 MoyuCamera-SideStore-Fix-arm64-编号 ZIP 并解压，
取得 MoyuCamera-SideStore-Fix.ipa。把它传到 iPhone“文件”中，
在 SideStore 的 My Apps 点加号，重新选择这个新的 IPA。
不要再次选择旧的中文名称安装包。

桌面显示 MoyuCamera，进入应用后显示“摸鱼相机”中文界面。
免费 Apple ID 的签名期限和数量限制仍由 Apple 决定。
本工程最低 iOS 16.0，截图里 wloc 要求 iOS 27 的报错属于另一个应用。
SideStore 自身准备、配对、VPN 或开发者模式请参考其当前官方说明：
https://docs.sidestore.io/ 。

## 自动打包

修改 ios/MoyuCamera 中的应用代码并推送到 main 后自动编译；
也可进入 Actions → iOS Unsigned IPA → Run workflow 手动触发。

macos-15 运行器使用 Xcode + XcodeGen。
通过 iphoneos SDK 对 arm64 执行 archive，关闭自动代码签名和必需签名，
不调用需要签名资料的 exportArchive；直接把归档 .app 装入 Payload 形成 IPA。
正常打包不需要 Apple ID、开发者证书、Mac 或付费开发者会员。

project.yml 是工程配置来源，不提交自动生成的 .xcodeproj。
构建会上传 IPA、校验报告、SHA256；失败保留编译日志与错误分类，
临时网络或数据库错误最多自动清理重试一次。
运行器配额和费用以 GitHub 当前规则为准。

## 可选 AI 自动修复

已提供 ios-ai-repair.yml，默认不开启。
如需要，仓库 Settings → Secrets and variables → Actions 中：
- Secret OPENAI_API_KEY：仅在 GitHub 设置中填写，不发到聊天或写进源码。
- Variable IOS_AI_REPAIR：设为 true。
- 若要自动创建 PR，在 Actions 设置允许创建 Pull Request。

API 可能单独计费，未配置时不宣称任意代码问题都能自动修复。
启用后只处理本仓库默认分支的受信任失败，不处理外部 fork PR，
限制源码改动范围，重新构建校验通过才上传修复包并保存独立分支，
不自动合并，不无限循环。首次安装报错请优先看 SideStore 的最新错误记录。

## 维护

不要在公开仓库上传 Apple ID、密码、证书或 API Key。
仓库被删除重建会丢失源代码、工作流历史和原 Artifact；
后续更新请在现有仓库直接提交代码。
