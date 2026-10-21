# Pixfun 0.3.0 × VisionFlow

面向 `codex/media-0.3.0` 的本地接入。SwiftUI 与网页素材库复用 vf-agent 0.9.1 / 0.9.2 的镜头目录；原片只读，不复制视频或重新建立向量库。

## 已接通及修复

- 导入已有 shots、时间区间、评分、可用转写、地点、封面和人工封面锁定状态；素材 ID 稳定。刷新保留标题、收藏、人工标签、地点修正和删除状态。
- 原生文字、语义和相似镜头搜索使用统一目录。默认封面始终使用目录当前代表帧，搜索命中只改变排序和播放起点；图片内容版本变化会刷新缓存。
- 播放及编辑前验证源文件指纹。目录时间转为播放时间：`shot.start/end + playback.origin`；疑似错误转写和未验证时钟不进入剪辑文本。
- 故事初选、替换建议和语音裁剪参考可复用保存的镜头区间、上下文、评分及过滤后的转写。它们明确标为目录证据，不生成假的精细审片签名、主体判断或审美结论。明确执行“分析”时仍走完整分析。
- 混合目录/新分析素材时，只有具有本地分析帧的候选参加新排序；目录候选保留且标明未重排，不补零分、不丢素材。目录语义检索继续使用已有向量。
- 旧检测标签映射为带镜头区间的“细节”标签，支持人工隐藏；不会把背景物体自动升级为主体/行为，也不把行程地点当作画面标签。
- 地图的明确元信息读取会访问目录关联原片，校验读取期间文件未变；只返回拍摄事实，不覆盖代理时钟/尺寸、不自动更改人工地点。日期标签不补造拍摄时刻，地点文字不补造 GPS。
- 修复 SQLite 并发创建/关闭连接时的卡住：串行化连接生命周期，查询仍使用独立 WAL 连接。测试要求正常退出，强制杀进程不算通过。
- FFmpeg 解码、过滤、编码线程池各限制为 2。开发包默认串行重任务，模型调用后释放，图片缓存最多 128 MiB / 160 张。
- 开发包保留 Python 虚拟环境启动器路径，包含静态标题/字幕渲染器及中文资源。能力检测检查实际配置解释器的模块；缺失依赖不再显示为已安装，不自动下载模型或回退到云端。
- 旧目录不自动重复分析；开发包设置 `PIXFUN_AUTO_ANALYZE_EXISTING=0`。新导入和明确重分析仍可执行。
- 关联原片与播放代理不同时，原片导出明确拒绝；预览保留。不会把代理放大后冒称原片导出。

## 构建和启动 SwiftUI

需要 macOS、Swift/Xcode 工具链、FFmpeg/ffprobe，以及两个已准备好的 Python 环境：

- 服务 Python 3.9–3.12，安装 Pillow；当前 `app.py` 仍依赖 `cgi`，不能用 Python 3.13 运行服务。
- 模型 Python 使用已有 vf-agent/MLX 环境与本地权重缓存。抽帧需要 PyAV、PySceneDetect、OpenCV；本地模型分别需要 MLX/VLM、ASR 和 Torch/Transformers 等对应依赖。模型环境可以使用 Python 3.13。

先启动一个统一素材库服务：

```bash
cd /path/to/vf-agent
python -m vf_agent library serve --db /path/to/shot-library --port 62600
```

在 Pixfun 仓库构建开发包：

```bash
CLANG_MODULE_CACHE_PATH="$PWD/build-native/cache/clang" \
SWIFTPM_MODULECACHE_OVERRIDE="$PWD/build-native/cache/swift" \
swift build --package-path native --scratch-path build-native \
  --cache-path build-native/cache -c release --disable-sandbox -j 2

/path/to/service-python scripts/assemble-native-dev.py \
  --python /path/to/service-python \
  --model-python /path/to/model-venv/bin/python \
  --vf-root /path/to/vf-agent \
  --catalog-state /path/to/shot-library/server.json

open "$(cat build-native/connected-app-path.txt)"
```

脚本编译并打包 `pixfun-title`，执行临时签名校验；当前 FFmpeg 路径为 Homebrew Apple Silicon 默认路径。配置只写入被忽略的开发产物，虚拟环境路径不解析到基础解释器。这是引用本机代码和环境的开发包，不是独立发行安装包。

原生数据库在 `~/Library/Application Support/Pixfun/Library/`。首次接入前自动创建 SQLite 备份。更新前建议另外备份该目录。统一服务需保持运行，才能刷新、获取缩略图和做语义搜索。

## 网页入口

无需 npm 构建。在统一服务运行后：

```bash
VF_LIBRARY_STATE=/path/to/shot-library/server.json \
PIXFUN_PYTHON=/path/to/service-python bash scripts/start-vf.sh
```

打开 `http://127.0.0.1:8765/library`，端口可用 `PIXFUN_PORT` 修改。网页列出 shots、筛选、展开相似小图，并可生成单镜头编辑副本进入现有工作台；该入口尚不支持完整多镜头导演编排。

编辑副本从 0 开始，时长最多 10 分钟，保留宽高比，最长边不超过 1280；原片不变。跨镜头语句保留完整文本但明确记录裁剪及原始句子区间，不冒充逐字对齐。只转码所选段，不重扫、不重建向量；缓存绑定源指纹和证据版本。

## 本地接口及安全边界

原生 `/api/desktop/vf/status`、`search`、`sync`、`frame/<encoded_id>` 使用现有桌面鉴权；搜索复用统一服务。网页 `/api/vf/` 提供 status、search、shot、frame、video、use-shot 和 job。

固定读取配置的回环服务地址，不接受浏览器指定任意目标 URL/源路径；不使用环境代理，不跟随重定向。保留 Host、Origin、Fetch-Site 检查和视频 Range 行为。网页目录模式关闭云端视觉入口。

## 验证（2026-10-21）

运行测试需使用服务 Python；`PIXFUN_TEST_PYTHON` 指向该解释器，`PIXFUN_MODEL_PYTHON` 指向完整模型环境，`PIXFUN_VF_ROOT` 指向兼容仓库。导出测试需将编译好的 `pixfun-title` 所在目录加入 PATH。合成素材通过 `node scripts/prepare-media-test.cjs` 准备；AVFoundation 测试可用 `PIXFUN_TEST_VIDEO` 指定本地合成视频。

| 验证 | 结果 |
|---|---|
| 目录投影 / HTTP 桥接 | 13 / 8 项通过 |
| 分析队列 / 资源调度 / 工具边界 | 23 / 15 / 7 项通过 |
| 真实 vf-agent CPU 编辑辅助 / 故事编译 | 18 / 14 项通过 |
| 桌面 HTTP | 21 项通过，1 项因可选长视频样本未下载而跳过 |
| 同步单元检查 / 同步导入归档重启循环 | 43 项通过 / 连续 20 轮正常退出 |
| 真实视频导出 / 非零起点裁剪 | 9 / 1 项通过，含 1080p/4K、字幕、取消、源变化拒绝 |
| Swift release / 签名 / 原生检查 | 构建和签名通过；867 模型、2 字体、13 输入框、172 快捷键、13 技能检查通过 |
| AVFoundation | 真实像素、暂停起点、seek、播放、取消通过 |
| 现有目录隔离验证 | 330 素材、380 shots、714 可用转写、6 段隔离；JPEG、Range、鉴权、关联原片文件头、搜索及刷新保留编辑通过 |

本地证据、截图、数据库备份位于忽略的 `data/vf-integration/`，不提交私人媒体或元数据。实库测试 `tests/vf-native-live.py` 可通过参数指定预期数量，操作自己的临时原生数据库。上述结果验证接入和执行正确性，不代表视觉理解、歌词或剪辑审美已经人工验收。

最后核对时 vf-agent 工作区已发布 0.9.2；主服务和 worker 使用相同的显式版本白名单，目录返回实际引擎版本。0.9.2 的 CPU 编辑、故事、采样与 HTTP 接口重新验证；此兼容范围不代表其全部新增创作能力均已接入。

## 后续事项

1. **原片回链导出**：目录目前只有播放源指纹，没有完整、源绑定的代理→原片映射。需在 vf-agent 输出可核验的原片身份、时间偏移、音画起点、旋转及 HDR 处理策略，再启用对应导出。本地样本有 226 项路径不同，当前全部受保护。
2. **精细视觉复核与成片验收**：目录上下文不等于逐镜头视觉描述。需要按需细看候选，再用真实旅行项目验收完整多镜头流程；未开启新的云端调用或合成。
3. **更完整的地图/分类**：原片缺少 GPS/明确拍摄时间时继续显示未知；更多主体/行为分类需要真实视觉证据。不得用地名、文件名或背景检测补造这些事实。
4. **统一库写回与发行**：原生人工标签/封面目前保存在 Pixfun，尚未回写统一库；发行包、HyperFrames 及私有美学能力另行验证。本轮未改 vf-agent 工作区、原片或暂停的自动任务。
