# 素材分析评测原文件

对应《GPT 多模态与 VisionFlow 0.9.1 素材分析对比》的 10 个案例。2 张照片和 8 段视频全部放在本目录，保留原文件名和原始内容，未压缩、转码或删除元数据。

| 案例 | 内容 | 原文件 | 大小 MiB |
| --- | --- | --- | ---: |
| 01 | 泉口环境照片 | [Pump geyser 20190715 085719 1.jpg](Pump%20geyser%2020190715%20085719%201.jpg) | 12.3 |
| 02 | 泉口水花近景照片 | [Pump geyser 20190715 085726 1.jpg](Pump%20geyser%2020190715%20085726%201.jpg) | 12.5 |
| 03 | 剧院转向河岸灯光 | [IMG_0137.MOV](IMG_0137.MOV) | 25.6 |
| 04 | 海河游船与岸边灯光 | [IMG_0141.MOV](IMG_0141.MOV) | 25.5 |
| 05 | 街口走入民园广场长视频 | [IMG_0127.MOV](IMG_0127.MOV) | 258.4 |
| 06 | 永宁古城集市短视频 | [IMG_0034.MOV](IMG_0034.MOV) | 8.9 |
| 07 | 滨水栈道转向人物跑远 | [IMG_0029 2.MOV](IMG_0029%202.MOV) | 16.9 |
| 08 | 山坡远眺水库并拉近 | [IMG_0001 2.MOV](IMG_0001%202.MOV) | 22.4 |
| 09 | 蒸汽中的 Grotto 间歇泉 | [Grotto geyser 20190714 210951 VID.webm](Grotto%20geyser%2020190714%20210951%20VID.webm) | 135.5 |
| 10 | Castle 间歇泉一分钟视频 | [Castle geyser 20190714 072044 VID.webm](Castle%20geyser%2020190714%20072044%20VID.webm) | 222.0 |

## 下载与核对

大文件通过 Git LFS 保存。网页打开文件后可使用下载入口；Git 下载时需安装 Git LFS，并在仓库中运行：

```sh
git lfs pull --include="evaluation-media/*"
cd evaluation-media
shasum -a 256 -c SHA256SUMS
```

manifest.json 提供案例编号、文件名、大小和 SHA-256，SHA256SUMS 用于验证是否与评测原件一致。普通 Git 指针文件不是可播放的视频。

## 来源与许可

两张 Pump 照片和两个间歇泉 WebM 视频的作者为 G. Edward Johnson，采用 [CC BY 3.0](https://creativecommons.org/licenses/by/3.0/) 许可。本目录保留原文件，未修改内容。来源：

- [Pump geyser 20190715 085719 1.jpg](https://commons.wikimedia.org/wiki/File:Pump_geyser_20190715_085719_1.jpg)
- [Pump geyser 20190715 085726 1.jpg](https://commons.wikimedia.org/wiki/File:Pump_geyser_20190715_085726_1.jpg)
- [Grotto geyser 20190714 210951 VID.webm](https://commons.wikimedia.org/wiki/File:Grotto_geyser_20190714_210951_VID.webm)
- [Castle geyser 20190714 072044 VID.webm](https://commons.wikimedia.org/wiki/File:Castle_geyser_20190714_072044_VID.webm)

其余六个 MOV 文件由项目所有者提供用于素材分析评测；不因存放于本仓库而额外授予第三方使用许可。
