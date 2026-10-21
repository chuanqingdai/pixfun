# Pixfun × VisionFlow 本地联调

基于 Pixfun `bf698f8`，已有网页 `/library` 与 SwiftUI 原生客户端两条入口，复用 vf-agent 统一镜头库。未替换 Pixfun 的完整导演引擎。

## SwiftUI 接入（2026-10-17）

原生 Media 页已接入 330 个真实素材、380 个镜头、714 段可用转写。统一库另有 12 条已排除且没有源文件的生成素材占位，不导入；6 段识别或时间存在疑点的转写不进入搜索与剪辑文本。本机原有 5 个文件保留，因此界面显示 335 local files。

- 关键词搜索、Visual search 自然语言画面搜索、镜头详情中的本次旅行/全部旅行相似检索已接通。命中显示小图和时间，点击跳到对应位置。
- 复用当前封面、原片/代理、镜头区间、评分、地点和人工封面锁定状态；不复制视频或向量，不重新扫描。旧扫描评分仍标示来源，不视为 HDR 修复后的重新评分。
- 原生 SQLite 保存可刷新元数据投影和本地编辑状态；统一库仍是镜头证据来源。首次同步前备份，刷新保留人工标题、收藏、删除状态和已有分析。可用 Refresh catalog 手动同步。
- 本地模型接入 Qwen3-VL-4B 4bit、Qwen3-ASR-1.7B bf16、SigLIP2 Base，以及 OpenCV/OCR 工具。仅用现有缓存，离线、默认 2 线程；模型工具串行执行且调用后释放，语义搜索结束释放统一库编码器。原生图片缓存限制 128 MiB / 160 张。
- 播放前核对源文件指纹，按 playback.origin 映射时间，保留视频方向。打开已有目录素材不自动触发重新分析。

先启动下文统一素材库服务，然后在 pixfun 目录构建本机开发包：

```bash
CLANG_MODULE_CACHE_PATH="$PWD/build-native/cache/clang" \
SWIFTPM_MODULECACHE_OVERRIDE="$PWD/build-native/cache/swift" \
swift build --package-path native --scratch-path build-native \
  --cache-path build-native/cache -c release --disable-sandbox -j 2

/opt/homebrew/Caskroom/miniconda/base/envs/clawtrading/bin/python \
  scripts/assemble-native-dev.py \
  --python /opt/homebrew/Caskroom/miniconda/base/envs/clawtrading/bin/python \
  --model-python /opt/homebrew/Caskroom/miniconda/base/bin/python \
  --vf-root ../vf-agent \
  --catalog-state ../sampling-pilot-2026-10-16/run-unified/shot-library/server.json

open "$(cat build-native/connected-app-path.txt)"
```

这是引用本机仓库和 Python 环境的开发包，不是可独立分发的安装包。统一库服务须保持运行，才能刷新目录、获取封面和使用语义/相似搜索。原生人工标签与封面写回、完整多镜头成片流程仍待后续验收。

验证：原生适配器 5 项测试通过；桥接器 8 项通过；原有 desktop service 8 项通过、2 项跳过（分批运行）；Swift release 构建和 native 检查通过。真实 HTTP 检查覆盖封面 JPEG、视频 Range、鉴权、30 条同旅行相似结果、30 条语义结果及刷新保留修改。SwiftUI 实际打开素材、播放视频和相似搜索通过。Qwen3-VL、SigLIP2、Qwen3-ASR 与 OCR 均已执行本地推理；这只验证接入，不代表内容准确性或审美验收。

```bash
python tests/vf-native.test.py
python tests/vf-bridge.test.py
/path/to/python3.11 tests/vf-native-live.py
node scripts/test-native.cjs
```

私人验证证据保留在被 Git 忽略的 `data/vf-integration/native-http-check.json` 和 `native-model-check.json`。

### 列表封面回归修复

原生语义/相似检索曾将 `item.coverUrl` 替换为未统一转换的搜索命中帧，返回 Media 仍保持相似结果，造成“默认封面再次过曝”的观感。现改为卡片始终使用目录当前封面，搜索只改变排序和播放跳转时间；结果页明确显示搜索模式，Show all media 清空搜索状态。没有将搜索帧冒充已重新调色，也未修改原片。

封面 URL 带显示图片内容版本；同一 frame ID 安装修复图后刷新目录即可重载，避免 SwiftUI 已加载视图继续保留旧图。接口禁止 HTTP 缓存。新增封面与跳转时间独立、退出搜索和版本更新回归：原生模型检查 401 项、适配器 6 项通过。全库封面审计及实际 HTTP 对照保存在 `../sampling-pilot-2026-10-17/cover-audit/`。默认封面修复不代表旧代理视频、全部候选和全部搜索帧都已完成 HDR 重处理；该部分仍属于 L1。

## 网页启动

不需要 npm 构建或 Electron。需要 Python **3.9–3.12**、Pillow、FFmpeg/ffprobe；Python 3.13+ 不支持现有 `app.py` 的 `cgi` 模块。前端服务不安装或加载视觉/ASR 模型。

先在另一个终端启动统一素材库（vf-agent 使用其现有 Python 环境，要求 3.11+）：

```bash
cd /path/to/vf-agent
python -m vf_agent library serve --db /path/to/run-unified/shot-library --port 62600
```

再启动 Pixfun：

```bash
cd /path/to/pixfun
export VF_LIBRARY_STATE=/path/to/run-unified/shot-library/server.json
export PIXFUN_PYTHON=/path/to/python3.11
bash scripts/start-vf.sh
```

打开 <http://127.0.0.1:8765/library>。端口可用 `PIXFUN_PORT` 改；地址使用 `127.0.0.1`，不要改成 `localhost`。服务只绑定回环地址。停止对应终端即可；停止前端不会删除素材库。两端应使用同一台机器；前端从 server.json 读取后端当前访问路径，不把 token 写进浏览器。

本工作区启动命令（在 visionflow 根目录）：

```bash
bash sampling-pilot-2026-10-16/run-unified/start-library.sh
# 上一行已启动服务时，不重复运行；以下在另一终端执行：
VF_LIBRARY_STATE="$PWD/sampling-pilot-2026-10-16/run-unified/shot-library/server.json" \
PIXFUN_PYTHON=/opt/homebrew/Caskroom/miniconda/base/envs/clawtrading/bin/python \
bash pixfun/scripts/start-vf.sh
```

此处复用本机已有 Python 3.11 和 Pillow，没有向这个环境安装依赖。联调副本、项目、输出默认保存在 `pixfun/data/vf-integration/`，已被仓库忽略规则排除。可通过 `PIXFUN_DATA_DIR` 指定其他目录。新部署建议用独立虚拟环境。

## 已接通

- 分页列出真实 shots；默认文字检索，也支持本地自然语言/混合检索和标签筛选。
- 相似镜头在卡片下展开小图，可查看具体命中时间；复用 LanceDB 向量。
- 封面使用 vf-agent 当前代表帧，包括人工锁定和 HDR 显示覆盖；不重新选封面。
- 详情包含原片时间区间、元信息、评分、候选、标签、可信状态和 ASR。未评分保持缺失，不伪造为 0。
- 预览通过 Range 转接原库播放接口；带入 `playback.origin`，源文件变化/离线由原库拒绝播放。
- “用于创作”：生成所选 shot 的 H.264/AAC 编辑副本，最长边不超过 1280，保留宽高比。原片只读。只做这一段的转码，不重扫、不重跑 ASR、不重建向量。
- 进入现有 Pixfun 网页工作台，可以查看时间线/转写、保存创作指令、使用原型导出功能。两线程转码，选段和导出互斥。

## 时间与可信度约定

vf-agent 的 shot 时间是 video-relative，实际播放时间 = `shot.start/end + playback.origin`。编辑副本统一从 0 开始；ASR 的 shot 交集减去 `shot.start` 后带入。跨镜头句子保留全文，明确记录 `clipped` 和原始句子时间，不假装有逐字对齐。

`searchable=false` 或 `timing_status=legacy_clock_unverified` 的转写只在待复核详情中展示，不进入剪辑文本。正常机器转写也不等于人工真值。完整原库证据保存在项目 `analysis.catalogEvidence`，镜头引用保存在 `vfSource`。

副本 job ID 根据镜头、时间、源指纹、封面与证据快照生成。重用副本前再次请求原库检查源指纹；输入改变会生成新的 job。此缓存不覆盖原片、旧副本、人工标签或封面选择。

## 接口

| Pixfun 同源接口 | 后端行为 |
|---|---|
| `GET /api/vf/status` | 原库 `api/status`，增加 `ok` |
| `GET /api/vf/search?q=&mode=text&tag=&k=49&offset=0` | 原库 `api/search`，返回 `{ok, shots}`；单页最多 100 |
| `GET /api/vf/search?similar=<shot_id>&k=6` | 相似镜头；排除参考 shot |
| `GET /api/vf/shot?shot_id=...` | 原库新增 `api/shot`：按稳定 ID 获取当前详情 |
| `GET /api/vf/frame/<encoded_frame_id>` | 当前封面/命中帧；完整编码 ID，保留时间基准中的 `/` |
| `GET /api/vf/video/<shot_id>` | 流式转接视频及 206/416 Range 状态 |
| `POST /api/vf/use-shot` | JSON `{shot_id}`，单任务生成编辑副本，返回 `jobId/analysis/sourceUrl` |
| `GET /api/vf/job?id=...` | 读取已保存的目录镜头项目；不重分析 |

适配器固定读取配置的本地服务，不接受客户端指定的 URL、路径或转发目标，不使用环境 HTTP 代理，不跟随重定向。API 验证 Host、Origin 和 Fetch-Site；首次顶层页面导航允许从外部页面进入，但不放开跨站 API。此模式关闭 `/api/vision` 云分析。

## 验证与证据（2026-10-17）

```bash
python tests/vf-bridge.test.py
python tests/vf-clip-media.test.py
node tests/studio.test.cjs
python tests/vf-live-smoke.py --semantic --output data/vf-integration/live-smoke.json
```

- vf-agent `tests/test_shot_library.py`：66 项通过，包含新增稳定 ID 详情查询。
- Pixfun adapter：8 项通过，覆盖时间映射、转写隔离、地址限制、帧 ID 编码/Range、缓存、失败不发布和单任务锁。
- FFmpeg 真实回归：取合成素材 2.04–3.96 秒，解码 48 帧全部为目标蓝色段，未混入前后红/绿段；音画起点均为 0，时长差 <40ms，方向/尺寸为 160×90。
- 原有 studio 控制器回归通过。
- 真实 HTTP 验证：5 个素材集、342 assets、380 个唯一 shots、97,773 缓存帧、720 转写段；70 个 shot 有 HDR 显示修复；保留 5 个被标记的 ASR 关联记录。
- “霍比屯”返回 3 个镜头，“新西兰之行”标签返回 83 个镜头，相似检索返回 6 个其他镜头；三张代表图 JPEG 可解码，视频 Range 206/416 正常。语义查询“湖边的风景”返回 6 个结果，本机该次调用约 6.45 秒，非性能基准或质量验收。
- Chrome 实际点击：中文搜索 → 相似小图 → 镜头预览 → 用于创作 → 指令 → 导出。真实 13.380 秒霍比屯镜头生成 1280×720 编辑副本，导出 720×1280，浏览器两者都能播放；音画起点均为 0，视频 13.380033 秒、音频 13.376 秒。
- 本地证据：`data/vf-integration/live-smoke.json`、`studio-export.jpg`、`library.jpg`。这些含私人素材信息，不纳入 Git。

## 本轮边界与接续

1. 网页端当前一次只选一个 shot。多镜头 selects/时间线、直接导出剪映/Resolve 待后续实现；原生素材库接入情况见文首。
2. Pixfun 网页创作指令仍使用其原型规则，不是 vf-agent 或云端模型的导演决策。导出沿用竖屏加字/留边功能，不代表自动完成一部旅行片。刷新工作台会重新载入镜头分析，尚未完整恢复编辑会话。
3. 仅复用已完成的封面显示修复；未改变旧代理的色彩或评分，也未解决所有原片曝光问题。编辑副本沿用目录播放源的色彩。
4. 本次以只读镜头库接入为主；在原素材库修改人工标签/封面后，刷新 Pixfun 读取新结果。本页尚未提供写回控件。
5. 没有启动新扫描、模型训练或定时任务。原有 L1–L7 和模型迭代 session 保持各自状态。
6. 本地检出省略了完整演示长视频和原生离线示例；库与真实素材工作台不依赖它们。打包或检查宣传案例全片前应补全相应 Git/LFS 资源。
