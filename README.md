# fio 存储测试 · iOS 15 移植版

把 Android 的 **com.fiobench** 六页存储测试应用移植为 iOS 15 可用的 SwiftUI 工程，无 XML、无第三方运行时库、无 CocoaPods/SPM 依赖。

> 当前仓库是**可构建工程**，不是已经签名的 IPA。Windows 没有 macOS/Xcode，不能直接产出可安装的 iOS 包。按下面「一键得到 IPA」用 GitHub 的 macOS runner 构建，或用自己的 Mac 构建。

---

## 一键得到 IPA

1. 新建一个 GitHub 仓库，把本目录（`FioBench-iOS/`）里的全部内容推到仓库根目录。
2. 打开仓库的 **Actions** → **Build unsigned IPA** → **Run workflow**。
3. 等 3–6 分钟，进入这次运行，下载 **FioBench-unsigned-ipa** artifact。
4. 解压得到 `FioBench-unsigned.ipa`。

如果本机有 Git：

```bash
cd FioBench-iOS
git init
git add .
git commit -m "fio bench iOS port"
git branch -M main
git remote add origin https://github.com/<你的账号>/<仓库名>.git
git push -u origin main
```

推送后工作流会自动跑一次；之后也可以手动 Run workflow。工作流优先使用 Xcode 16.4，构建前会打印实际 Xcode/Swift 版本。

### 不会 Git / 只在网页上传

1. 打开 `FioBench-iOS` 文件夹，按 `Ctrl+A` 全选里面的**内容**（要包含 `.github` 文件夹），不要只拖 `FioBench-iOS` 这个外层文件夹。
2. 在 GitHub 新建 Public 仓库，点 **uploading an existing file**，把这些内容拖进去，Commit。
3. 打开仓库的 **Actions**。第一次可能需要点 “I understand my workflows, go ahead and enable them”。
4. 选 **Build unsigned IPA** → **Run workflow**；push 成功时也会自动跑。
5. 运行完成后页面底部 **Artifacts** 里下载 `FioBench-unsigned-ipa`，它本身是一个 zip，解压后里面才是 `.ipa`。

### 安装（iOS 15.0–15.4.1）

- **已装 TrollStore**：直接把 IPA 用 TrollStore 打开安装。TrollStore 会处理临时签名。
- **没有 TrollStore**：用 AltStore / Sideloadly / Feather 等工具，配合自己的 Apple ID 签名安装。免费 Apple ID 通常 7 天需要重签。
- 未签名 IPA **不能**直接双击安装到普通未越狱设备，这是 iOS 的签名机制，不是包损坏。

### 没有 Mac 也能构建

工作流使用 `macos-15` + XcodeGen，不需要付费 Apple 开发者账号，构建阶段完全关闭签名。产物就是未签名 IPA。

---

## 本地构建（有 Mac）

```bash
brew install xcodegen
python3 scripts/make_icon.py
xcodegen generate
open FioBench.xcodeproj
```

在 Xcode 里选择自己的 Team / 真机，Run 即可。若要生成未签名 IPA：

```bash
xcodebuild -project FioBench.xcodeproj -scheme FioBench \
  -configuration Release -sdk iphoneos \
  -destination 'generic/platform=iOS' -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO ONLY_ACTIVE_ARCH=NO
bash scripts/package_ipa.sh
```

---

## 页面与功能

| 标签 | 内容 |
|---|---|
| 基准 | 14 项（顺序 1M、4K Q1T1/Q2T1/Q4T1/Q4T4 的读/写/混合 R70/W30），每项 8 秒，项间可冷却 0–30 秒；按权重几何平均算 1000 分基准；颜色按参考值绿/黄/红；历史与诊断 |
| CDM | 4 行 × 3 列，每格 8 秒；数据大小 64 MiB–2 GiB、1/3/5 次、四种混合比例；标题跟随 MB/s / IOPS |
| AS SSD | 固定 1024 MB，Seq 1M QD32、4K QD1、4K-64Thrd；访问时间取 4K QD1 平均延迟；自建读/写分公式 |
| 自定义 | 顺序卡与随机卡分开运行；顺序跑完整个文件，随机每项 20 秒，显示带宽 + IOPS + 延迟 |
| 压力 | 1 GB 分块持续写入，实时百分比、速度、平均速度和 200dp 自绘曲线；停止立即中断并删文件 |
| 裸读 | 只读、不写；自动探测 iOS 块设备，失败显示需要 root；三项各 8 秒 |

公共框架同样是：单页单 Activity 概念的 SwiftUI 根视图、顶部标题栏、6 个标签、3dp 不确定进度条、状态行、全局 MB/s / IOPS 切换、同一时间只跑一个测试、实时刷新、结束删测试文件。

成绩保存到应用 Documents 下：

```text
Documents/FioBench/
├── bench/                         # 测试临时文件，启动和每次测试后清理
├── history.txt                    # 最近成绩摘要，界面显示最近 12 条
└── fio_yyyyMMdd.txt               # 当天完整报告追加
```

App 的 `UIFileSharingEnabled` 已开启，可在「文件」App 的“我的 iPhone / fio 存储测试”里查看。

---

## iOS 平台适配（重要）

原需求有几项是 Android/Linux 专属能力，iOS 上不能原样实现：

1. **不嵌入可执行的 fio 二进制**
   iOS 普通应用被沙盒和代码签名限制，禁止 `fork/exec` 第三方二进制。即使把交叉编译的 fio 放进 `.app`，非越狱设备也无法执行。工程改用进程内的 **native-posix** 引擎，按 fio 的参数语义完成 pread/pwrite、多线程并发、固定时长、混合读写、延迟统计和结果格式。界面会在「环境诊断」里明确标注这一点。

2. **direct=1**
   Darwin 没有 `O_DIRECT`。实现映射到 `fcntl(fd, F_NOCACHE, 1)`，让文件页尽量不进入统一缓存，这是 iOS 上最接近 direct I/O 的可用手段。

3. **外置 SD**
   iOS 没有 Android 的 `/storage/...` 可写挂载点。目标选择保留，但「外置 SD」不可选，测试固定写入 App 容器。

4. **裸读 / root**
   普通 iOS 没有 root，也没有 `/dev/block/by-name/userdata`。页面会依次尝试 `/dev/disk0`、`/dev/rdisk0` 和两个 Android 兼容路径；TrollStore 本身不是越狱，不提供块设备读取能力。只有真正越狱且内核/沙箱允许时，这一页才可能工作。

5. **drop_caches**
   CDM 的 root 下 `sync; echo 3 > drop_caches` 在 iOS 上不可用，未实现。`direct=1` 时使用 `F_NOCACHE` 降低缓存影响。

除这些平台硬限制外，六页布局、参数、8 秒规则、14 项权重与几何平均、CDM 4×3、AS SSD 公式、压力分块与曲线、结果单位切换、历史/报告路径语义都保留了。

---

## 目录结构

```text
FioBench-iOS/
├── project.yml                       # XcodeGen 工程定义（iOS 15.0）
├── Support/Info.plist
├── FioBench/
│   ├── FioBenchApp.swift
│   ├── Core/
│   │   ├── Models.swift              # 标签、14 项目录、CDM 目录、格式化
│   │   ├── AppModel.swift            # 全局状态、并发调度、报告/历史
│   │   ├── EngineTypes.swift         # StopToken、路径、错误
│   │   ├── DiskIO.swift              # POSIX 测量原语、F_NOCACHE、填充文件
│   │   ├── BenchmarkEngine.swift
│   │   ├── CDMEngine.swift
│   │   ├── ASSSDEngine.swift
│   │   ├── CustomEngine.swift
│   │   ├── StressEngine.swift
│   │   └── RawEngine.swift
│   ├── Bridge/
│   │   ├── FioBridge.h
│   │   └── FioBridge.c               # 块设备大小 ioctl、越狱探测
│   ├── UI/
│   │   ├── Theme.swift
│   │   ├── ContentView.swift
│   │   ├── BenchmarkPage.swift
│   │   ├── CDMPage.swift
│   │   ├── ASSSDPage.swift
│   │   ├── CustomPage.swift
│   │   ├── StressPage.swift
│   │   └── RawPage.swift
│   └── Assets.xcassets/
├── scripts/
│   ├── make_icon.py                  # 纯标准库生成 1024 图标
│   └── package_ipa.sh
└── .github/workflows/build-ipa.yml
```

---

## 计分与参考值

14 项与权重：

- 顺序 1M 读/写：各 5%
- 4K Q1T1 读/写/混合：各 10%
- 4K Q2T1 读/写/混合：各 6.667%
- 4K Q4T1 读/写/混合：各 6.667%
- 4K Q4T4 读/写/混合：各 6.667%

```text
ratio = 实测带宽 / 参考值（下限 0.02）
分数 = 1000 × exp( Σ 权重×ln(ratio) / Σ权重 )
```

参考值（MB/s）：`1200, 600, 25, 20, 22, 45, 35, 38, 70, 55, 60, 180, 140, 150`。

AS SSD 风格自建公式：

```text
读分 = 0.2×顺序 + 8.0×4K + 0.8×4K-64Thrd
写分 = 0.2×顺序 + 12.0×4K + 0.8×4K-64Thrd
```

---

## 已知限制

- 这是**进程内基准**，不是把 Android 的 `libfio_nr.so` 搬过来；参数与统计对齐，但 fio 内部的精确调度、ETA、日志格式不同。
- iOS 的 I/O 调度、APFS 压缩和热管理会影响结果；不同机型/温度下分数差异很大。
- 并发用多线程模拟 QD；随机高 QD 最多 32 个工作线程，顺序测试最多 8 个。这是移动端避免过度调度的取舍。
- 压力测试默认 10 GB，可能写满可用空间；开始前会检查，空间不足会直接报错。
- 测试期间切到后台可能被系统挂起；请保持应用在前台，屏幕会自动常亮。
- 未签名 IPA 的安装工具兼容性取决于 TrollStore/AltStore 版本；如果安装失败，改用 Xcode 真机 Run 验证代码。

---

## 构建失败排查

- **`xcodegen: command not found`**：`brew install xcodegen`。
- **AppIcon 编译报错**：确认执行过 `python3 scripts/make_icon.py`，PNG 在 `FioBench/Assets.xcassets/AppIcon.appiconset/`。
- **桥接头找不到**：`project.yml` 里是 `FioBench/Bridge/FioBridge.h`，确认从项目根目录执行 `xcodegen generate`。
- **TrollStore 安装失败**：确认 iOS 在支持范围（15.0–15.4.1）且是 TrollStore 支持的类型；也可以先用 Sideloadly 签名安装验证。
