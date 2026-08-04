# AIGC 生图/生视频能力盘点（权威版）—— 以 iplex 生产数据 + Lambda 源码为准

> 2026-08-04 编制。数据源：
> ① Beta 生产 CSV：service_catalog（103 行有效）+ provider_configs（40 条）
> ② infra/lambdas/* 源码（实际请求体逐字段核对）
> ③ PPIO key 实测连通（`GenPpioApiKey`，见 iplex/infra/sst-secrets.local；api.ppio.com / api.ppinfra.com 均 200）
> 结论：**PPIO 覆盖绝大多数能力（含 Veo 3.1）**，公开文档目录不全，以本文为准。

## 0. PPIO 通用异步协议

- Base URL：`https://api.ppio.com/v3`
- 认证：`Authorization: Bearer <PPIO_API_KEY>`
- 提交：`POST /v3/async/<model-mode>`（部分生图是 `POST /v3/<model>` 同步返回）→ `{ task_id }`
- 查询：`GET /v3/async/task-result?task_id=<id>`
  - 状态枚举：`TASK_STATUS_QUEUED / TASK_STATUS_PROCESSING / TASK_STATUS_SUCCEED / TASK_STATUS_FAILED`
  - 结果：`{ task: {status}, images: [{image_url}] }` 或视频 URL 字段
- 错误分类参考 `provider-http-error.ts`：429→busy、408/504→timeout、401/403→未配置、其余 4xx→输入被拒、5xx→busy；另有内容审核 code

---

## 1. PPIO 生图（源码核实的真实请求体）

### 1.1 Seedream 4.0 / 4.5 / 5.0-lite（`seedream-ppio-generate.ts`）
- 端点：`POST /v3/seedream-4.0` | `/v3/seedream-4.5` | `/v3/seedream-5.0-lite`（同步返回 `{images:[url|{url}]}`）
- 请求体：

| 字段 | 必填 | 说明 |
|---|---|---|
| prompt | ✓ | 非空字符串 |
| size | — | `WxH`，如 `2048x2048`（目录档位 2K/3K/4K） |
| image（4.5/5.0-lite）/ images（4.0） | — | 参考图 URL 列表，**注意 4.0 用复数字段名** |
| watermark | — | 目录默认 false |
| sequential_image_generation(+_options) | — | 组图，透传 |

- 多输出策略：不用 n 参数，`runPerItem` 每张一请求并发扇出
- 目录约束：maxRefs=4；numOutputs 1-4；积分 4.5-2k=18、5.0-lite-2k/3k=16

### 1.2 Nano Banana 2 / Pro（Gemini 原生协议，`nano-banana-ppio-native-generate.ts`）
- 端点：`POST /v3/gemini-image/v1beta1/models/<model>:generateContent`
- 模型白名单：`gemini-3.1-flash-image(-preview)`、`gemini-3-pro-image(-preview)`
- 请求体（Gemini 格式）：`contents[0]={role:"user", parts:[{text},{inlineData:{mimeType,data:base64}}...]}`；
  `generationConfig={ responseModalities:["IMAGE"], candidateCount:1, imageConfig:{ aspectRatio?, imageSize?("1K"/"2K"/"4K") } }`
- 输入图：**必须 base64 内联**（先下载 presigned URL 再编码）
- 响应：`candidates[0].content.parts[].inlineData`（base64 图）
- 目录：maxRefs=4、numOutputs 1-4；nano-banana-2 2K=51 分、pro 2K=67 分

### 1.3 GPT Image 2（`ppio-gpt-image-2-generate.ts`）
- 端点：T2I `POST /v3/gpt-image-2-text-to-image`；编辑 `POST /v3/gpt-image-2-edit`
- 请求体：prompt✓、n=1（硬编码）、image（编辑时 URL 列表）、moderation="low"（硬编码降误杀）、其余透传（quality: low/medium/high 等）
- 响应：`{ images:[url] }`
- 目录：1K/2K/4K × low/medium/high 九档，比例白名单随档位（1K/2K: 1:1,2:3,3:2…；4K: 16:9,9:16）；价格 3~214 分

### 1.4 Qwen 图像编辑（`qwen-image-edit-generate.ts`）
- 端点：`POST /v3/async/qwen-image-edit` → task_id 轮询
- 请求体：image✓（单图 URL）、prompt✓

### 1.5 PPIO 超分（`ppio-image-upscale-generate.ts`）
- 端点：`POST /v3/async/image-upscaler` → task_id 轮询
- 请求体：image✓（URL）、resolution（`2k/4k/8k`）、output_format（`png`）

## 2. PPIO 生视频（源码核实）

### 2.1 Kling v3.0 pro/std + Kling-o1（`kling-prepare.ts`）
- 端点：`POST /v3/async/${model}-${mode}`，model∈{kling-v3.0-pro, kling-v3.0-std, kling-o1}，mode∈{t2v, i2v, ref2v(仅 o1)}
- 请求体按模式：

| 字段 | t2v | i2v | ref2v(o1) | 说明 |
|---|---|---|---|---|
| prompt | ✓ | ✓ | ✓ | |
| duration | ○ | ○ | ○ | 秒；目录枚举 3-15s（o1 仅 5/10s） |
| aspect_ratio | ○ | ✗（跟随首帧） | ○ | 16:9 / 9:16 / 1:1 |
| image | | ✓ 首帧 | | URL |
| end_image（pro/std）/ last_image（o1） | | ○ 尾帧 | | **字段名按模型不同** |
| images | | | ✓ | 参考图列表（o1 目录 max 7） |
| sound | ○ | ○ | ✗ | 仅 pro/std；目录有 audio-on/off 两档价（pro 68/45 分，std 51/34 分） |

### 2.2 Hailuo 2.3（`hailuo-prepare.ts`）
- 端点：`POST /v3/async/minimax-hailuo-2.3-t2v` | `-i2v`
- 请求体：prompt✓、image（i2v 首帧）、duration（6/10s；**1080P 仅 6s**）、resolution（`768P`/`1080P` 需大写）、aigc_watermark
- 目录：无 aspect_ratio；FLF 仅首帧（max 1 图）

### 2.3 Veo 3.1（PPIO 路由，`ppio-veo-prepare.ts`——720p/1080p；4K 仍走 Google）
- 端点（两个覆盖全模式）：
  - 纯文生：`POST /v3/async/veo-3.1-generate-text2video`
  - 图生/首尾帧/参考图统一：`POST /v3/async/veo-3.1-generate-img2video`（按传了哪些媒体自动区分）
- 请求体：

| 字段 | 说明 |
|---|---|
| prompt ✓ | |
| generate_audio ✓ | 默认 true（PPIO 必填） |
| image | 首帧 URL |
| last_image | 尾帧 URL |
| reference_images | `[{image:url, reference_type:"asset"}]` ≤3；**设了参考图 duration 强制 8s** |
| duration_seconds | 常规 8s |
| aspect_ratio | 16:9 / 9:16 |
| resolution | **仅 720p/1080p**（4K 会被 prepare 拒绝，走 Google 直连） |
| sample_count | 1-4，可选 |

- 目录价：720p=200 分、1080p=320 分（PPIO）；4K=480 分（Google）

## 3. 重要：PPIO = api.ppio.com（国内）+ api.novita.ai（国际，Novita 即 PPIO 海外品牌）

最新代码（2026-08-01/02，晚于 7/21 CSV 快照）证实**双域名同平台、数据级切换**（seed.ts 注释原话：`config:{}` 默认 PPIO 国内 `api.ppio.com/v3`，运维改行数据指到 Novita `https://api.novita.ai/v3` 即可，注意必须带 `/v3`，裸域名 404）。因此：

- **Seedance 2.0（含 Fast/FLF）已在 PPIO 系**：走 `https://api.novita.ai/v3/bytedance`（seed.ts:527-571）。参数要点：参考图 max 9 + **视频参考 max 3**（每段 2-15s 总 15s）maxRefs=12，时长 5-15s，480p~4K，提交返回 `{id}`
- **Kling / nano-banana 等都留了多后端可切**（PPIO 国内 ↔ Novita ↔ Google SDK 回滚行，全用数据切换，无需重启）
- LLM 文本也走 Novita：`api.novita.ai/v3/openai`

**截至最新代码仍直连原厂的少数**（CarryMe 可视需要用 PPIO/Novita 目录上的对应货替代）：

| 能力 | 现直连 | 协议要点 |
|---|---|---|
| MiniMax H3 | `api.minimax.io` | Bearer；`{task_id, base_resp:{status_code}}`（0=成功）；5-30s 长视频 |
| HappyHorse 1.1 | `dashscope-intl.aliyuncs.com/api/v1` | Bearer + **`X-DashScope-Async: enable` 必带**；`{output:{task_id}}`；3-15s |
| Veo 3.1 4K 档 | Google | `x-goog-api-key` 头；`:predictLongRunning` → operations 轮询；参考图 base64 |
| PixVerse v6/c1 | PixVerse 官方 | **`API-KEY` 头** + `Ai-trace-id`；`{Resp:{video_id:int}}`；540p~1080p，5/8/10/15s |
| Flux Fill / BiRefNet / SeedVR / Qwen 多角度 | `fal.run` | `Authorization: Key`；同步返回 |

> 对 CarryMe：**一把 PPIO key 已能吃下 Seedream、nano-banana、gpt-image-2、qwen-edit、超分、Kling 全系、Hailuo、Veo(≤1080p)、Seedance 2.0**——这就是全部主力能力，直连原厂的部分是尾部/特例。

## 4. 目录级约束速查（CSV 生产数据）

- **时长枚举（ms）**：Kling 3000-15000 全档；Hailuo 6000/10000（1080P 仅 6000）；Veo 固定 8000；Seedance/HappyHorse 5000-15000（HappyHorse 从 3000 起）；PixVerse 5000/8000/10000/15000
- **参考图上限**：Seedream/nano-banana/gpt-image-2 = 4；Kling-o1 = 7；Seedance = 9 图+3 视频；Veo = 3（FLF 2）；PixVerse c1 = 7、v6 = 1
- **多输出**：仅生图支持（1-4），全部按每张一请求扇出，不靠供应商 n 参数
- **积分**（代表值）：Seedream 4.5-2k 18｜5.0-lite 16｜nano-banana-2 51｜gpt-image-2 3~214｜Kling pro 68/45（有声/无声）｜Veo 720p 200｜PixVerse v6-720p 28｜超分 seedvr 5
- **outpaint 用 Seedream 4.5 实现**（比例白名单 21:9~9:16）；inpaint 用 nano-banana-2；multigrid 用 gpt-image-2（2x2/2x3/3x3，2048x2048 png）

## 5. CarryMe 移动端 Agent 工具设计建议

1. `generate_image(model, prompt, size?, refs?, n?)` → Seedream 5.0-lite 默认；nano-banana/gpt-image-2 备选
2. `edit_image(op, image, prompt, mask?)` → op: edit(qwen)/inpaint(nano-banana)/outpaint(seedream)/upscale(ppio-upscaler)
3. `generate_video(model, mode, prompt, media?, duration?, aspect_ratio?, audio?)` → Kling v3.0 / Hailuo 2.3 / Veo 3.1(≤1080p)，统一 task_id 轮询
4. 轮询统一：`GET /v3/async/task-result?task_id=`，3s 间隔；聊天气泡显示进度
5. Key：`PPIO_API_KEY`（dev 可先复用 GenPpioApiKey，正式走后端中转）
6. 注意坑：Seedream 4.0 字段名 images（复数）；Hailuo resolution 要大写；Veo PPIO 必须带 generate_audio、参考图锁 8s；Kling 尾帧字段名 pro/std=end_image、o1=last_image；nano-banana 图必须 base64 内联
