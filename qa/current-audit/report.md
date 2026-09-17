# Pixfun 页面与流程走查

走查日期：2026-09-16。范围：本地首页、五步滚动演示、HOW IT WORKS、FAQ、上传后的四步工作区，以及桌面和手机窄屏布局。

## 结论

本地视频上传 → 查看分镜 → 保存创作方向 → 编辑文字 → 导出 MP4 已实际跑通。已修复标题横排、分析画面与轨道相互遮挡、英文表单提示不一致等问题。当前是可用的本地文字编辑与导出工具，不是已接入人物替换、翻译或生成式视频的完整产品。

## 1. 首页与模块标题 — 已修复

原问题是旧样式仍将小标题和主标题按横向 flex 排列，单独设置 text-align 无法解决。现在共享标题容器明确使用纵向居中布局，并统一宽度、间距和响应式字号。

![修正后的模块标题](/Users/daichuanqing/Documents/ChatGPT/爆款神器/爆款神器-app/qa/current-audit/02-features-fixed.png)

手机视口中的标题、链接输入和上传按钮没有观察到明显横向溢出。并未覆盖所有设备尺寸。

![手机首页](/Users/daichuanqing/Documents/ChatGPT/爆款神器/爆款神器-app/qa/current-audit/07-mobile-hero.png)

## 2. 五步演示 — 已修复，动画回归通过

分析阶段重新预留轨道高度并调整视频位置，播放器底部不再与时间线相互遮挡。轨道使用四张不同镜头。隐藏的 Before/After 标签同步设置 aria-hidden，避免同时出现在辅助技术读取内容中。

![分析步骤：视频与轨道分开](/Users/daichuanqing/Documents/ChatGPT/爆款神器/爆款神器-app/qa/current-audit/15-analysis-fixed.png)

自动化测试覆盖五个章节、1,001 个可逆滚动状态和若干舞台尺寸。此为几何和状态验证，不代表所有真实设备上的帧率均已测试。

## 3. HOW IT WORKS、FAQ 与底部行动区 — 基本正常

标题上下排列且居中，三张说明卡信息分组清晰。FAQ 的导入说明可展开，展开后的可访问性状态和说明内容已确认。底部行动区保持背景图、标题和单一按钮，没有额外的宣传段落。

![操作说明与 FAQ 标题](/Users/daichuanqing/Documents/ChatGPT/爆款神器/爆款神器-app/qa/current-audit/06-faq.png)

![FAQ 下部与底部行动区](/Users/daichuanqing/Documents/ChatGPT/爆款神器/爆款神器-app/qa/current-audit/05-footer-faq.png)

以上第二张截图用于布局证据，不作为本轮新增展开操作的截图证据。FAQ 明确区分当前功能与 AI 演示能力，建议保留这项说明。

## 4. Review — 正常

用新生成的七秒测试视频实际上传；当前步骤只显示原视频、元数据和分镜，不提前显示生成结果。手机和桌面均检查过。修正单个分镜显示为 “1 segments” 的问题，现在使用 “1 segment”。

![桌面 Review](/Users/daichuanqing/Documents/ChatGPT/爆款神器/爆款神器-app/qa/current-audit/09-desktop-review.png)

## 5. Customize — 可用，能力边界清楚

可保存创作方向与语言偏好，支持跳过，不要求用户填写无关信息。人物替换和翻译尚未执行，仅保存需求。

![填写创作方向](/Users/daichuanqing/Documents/ChatGPT/爆款神器/爆款神器-app/qa/current-audit/10-customize.png)

该截图记录了修复前原生文件选择按钮跟随系统语言的现象。已改为英文 Choose files 按钮并补充说明关联；此最后一项修正经过代码和回归检查，尚未重新完整走通系统文件选择器。

## 6. Edit text — 正常，校验已补强

测试填写西班牙语 Hook、Message 和 CTA。表单保持单列，每次只呈现当前步骤。必填错误改为页面内英文提示，并增加 aria-invalid 和错误说明关联，避免依赖系统语言的原生提示。

![编辑西班牙语文字](/Users/daichuanqing/Documents/ChatGPT/爆款神器/爆款神器-app/qa/current-audit/11-edit-text.png)

输入错误、返回修改、草稿保留由自动化状态测试覆盖；最后补充的英文错误提示尚未重新进行完整浏览器实测。

## 7. Export — 实际生成成功

导出前显示确认信息与 Create video；生成成功后才出现结果和下载入口。输出文件经 ffprobe 检查为 720 × 1280、H.264 视频、AAC 音频、7 秒 MP4。

![导出确认](/Users/daichuanqing/Documents/ChatGPT/爆款神器/爆款神器-app/qa/current-audit/12-export-confirm.png)

![生成成功与下载入口](/Users/daichuanqing/Documents/ChatGPT/爆款神器/爆款神器-app/qa/current-audit/13-export-ready.png)

修改文字后，原结果标记为 Previous version，主按钮变为 Update video，避免把旧文件误认为新结果。手机端也检查了此状态。

![手机端旧版本标记](/Users/daichuanqing/Documents/ChatGPT/爆款神器/爆款神器-app/qa/current-audit/14-mobile-stale-result.png)

测试输出：`data/outputs/783387de9275/variant-1789572574.mp4`。本轮使用自建测试素材，没有修改用户源视频。

## 验证与剩余事项

- `node tests/motion.test.cjs`：通过。
- `node tests/studio.test.cjs`：通过，包括步骤锁定、输入校验、草稿保留、旧结果标记、失败重试、分镜跳转和新项目重置。
- 已检查的浏览器日志没有 JavaScript 错误；这不代表所有路径都无错误。
- 尚未验证 YouTube 等外部平台在当前网络下的链接导入兼容性。
- 页面刷新后没有编辑会话自动恢复；同页内返回与继续可保留草稿。建议后续补充本地项目列表与恢复能力。
- 人物替换、自动翻译、配音、自动转录及自动发布仍未接入。页面演示不能等同于实际生成能力。
- 本轮不是完整无障碍认证；尚未完成键盘全流程、屏幕阅读器、200% 缩放和全部颜色对比度测量。
- 截图 03、04、16、17 存在状态或命名与目标不对应的情况，未采用为本报告证据。

本轮依据 Product Design audit 的截图先行方法，针对观察到的布局与交互问题做局部修复，保留既有深色品牌、素材和功能范围。
