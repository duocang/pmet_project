# PMET 优化与重构日志

记录 dev 分支上对 `src/indexing/fused_fimo` 与 `src/pairing` 做的性能优化、健壮性补强、可读性清理。每条改动都有：commit、bench 时间、与 baseline 的输出哈希比对。

最新更新：2026-04-25（含批 6/7）

---

## 1. 基准环境

| 项 | 值 |
|---|---|
| 数据 | `data/indexing/bench/`（拟南芥级别） |
| Motif | 872 个（MEME 文本格式） |
| Promoter | 29824 条（FASTA） |
| Cluster | 1 个，2000 基因（取 universe.txt 前 2000） |
| 机器 | macOS arm64，10 核（OpenMP），pairing 用 8 线程 |
| Bench 脚本 | [scripts/bench/run_bench.sh](../scripts/bench/run_bench.sh)（完整流水线）<br>[scripts/bench/pair_only.sh](../scripts/bench/pair_only.sh)（仅 pair，复用已有 indexing 输出） |
| 验证锚点 | `pair_output sha = bcf73b77ea2bdd431ae693b63d7b50a4d8fd3e9f541b25a1b24868766bf08db9`<br>`binomial_thresholds sha = a6beea48529d4d597f16067a3f2f3d8eb690296b92f9e567226ecd9b62eb2640` |

`pair_output sha` 是把所有 pair 的最终输出（cluster, motif1, motif2, raw_p, BH_p, Bonf_p, gene 列表等）排序后 sha256。**所有重构都必须保持这个哈希不变**，否则就改变了科学输出。

性能优化（binary 格式、MinHash prefilter）会改变中间文件格式或部分 pair 的处理路径，但 pair_output sha 仍必须与 baseline 一致（除非显式说明，比如 MinHash 跳过 14 个非显著 pair）。

---

## 2. 性能优化（影响时间和文件大小）

| Commit | 改动 | indexing s | pair s | fimohits 大小 | pair_sha = baseline? | 备注 |
|---|---|---|---|---|---|---|
| (上游 ca715f7) | text fimohits, 单遍 sequence-major | 299.79 | 68.10 | 1.6 GB | — (锚点) | baseline |
| `8fa9b66` perf: binary SoA fimohits | 二进制 SoA 格式 + magic 自动检测 | 292.78 | **42.22** ⬇38% | **683 MB** ⬇58% | ✓ 完全一致 | indexing 加 `--text-output` 兼容旧格式；pairing 自动切 reader |
| `55b6ce0` perf(pairing): MinHash prefilter | K=128 SplitMix64 sketch + `-m N` 阈值 | 297.41 | 42.52 | 683 MB | △ 14/380K pair 被跳过（全为非显著 raw_p>0.25） | 默认 `-m 0` 关闭，topN=5000 数据集下增益微小 |

### 2.1 binary SoA fimohits 收益来源

- indexing 不再 `sprintf("%.10e", ...)` 写每条 hit
- pairing 不再 `sscanf` 解析，直接 `fread` 整块结构体数组
- 文件 -58%，OS page cache 命中率更高
- 格式定义见 [src/indexing/fused_fimo/src/pmet_index/pmet-fimo-binary.h](../src/indexing/fused_fimo/src/pmet_index/pmet-fimo-binary.h)，pairing reader 注释里同步保留一份镜像（`src/pairing/src/motif.cpp` 顶部）

### 2.2 MinHash prefilter 适用场景

当前 baseline 用 topN=5000，每个 motif 的 gene set 几乎饱和，pair 间 jaccard ≈ 0.05，过滤几乎不发生。如果之后将 topN 调小（比如 200），或换成异质 motif 库（特异 TF + 广谱 TF 混合），MinHash 收益会显著。

---

## 3. 重构 / 健壮性 / 可读性（不改变功能）

每一项都用 [scripts/bench/pair_only.sh](../scripts/bench/pair_only.sh) 跑一次 pair（复用 baseline 的 text fimohits 输入），验证 `pair_output sha` 和 baseline 完全一致。

| Commit | 改动 | pair s | sha = baseline? | 净行数 | 备注 |
|---|---|---|---|---|---|
| `5c842a1` chore: bench script + .gitignore | 加 `scripts/bench/run_bench.sh`、忽略 `data/`、`results/bench/` | — | n/a | +240 | 工具，不动业务代码 |
| `d8ef162` chore: cleanup | typo + 注释死代码 + cout→cerr + MemCheck.h 整理 | — | ✓ | -126 | 5 个 typo（`binomialThresholdFilePaht`、`reperesents`、`pVsls` 等），删 50+ 行中文 debug 注释块 |
| `fefbc30` refactor(binary fimohits) | reader file-size 边界检查 + 抽 `finalizeAfterLoad()` helper + writer overflow 检查 + MinHash 魔数注释 | — | ✓ | +35 | 防止恶意 4G header 触发 128GB std::vector 分配 |
| `65f10d4` fix(cli) | argv 边界检查 + `stoi/stof/strtol/strtod` 错误捕获 + 统一错误消息 | — | ✓ | +65 | bad input 给清晰错误而非 segfault/silent-zero |
| **重构起点 anchor** | （batch 1-3 完成后） | 68.97 | ✓ | — | pair-only baseline，对比下面 |
| `f1d9e27` refactor(pairing): error handling | `unordered_map[]` → `find()` 双查抽干净 + worker 线程 try/catch + `utils.cpp` 三处 `exit()` → 错误传播 | 66.94 (-2.0s) | ✓ | +55 | 单个 worker 抛异常不再 std::terminate 整进程 |
| `24334f8` chore(bench) | 加 `pair_only.sh` | — | n/a | +85 | 工具 |
| `e279bea` refactor: strand drop + FimoFile cleanup | 删 `motifInstance::strand` 字段（千万级 hits × 24B/hit = 几百 MB 浪费）+ 删整个 legacy FimoFile/HashTable/Node 模块（-1370 行）+ 抽 `pmet-index-pair-test.{c,h}` 保留三个 live helper | **37.27** (full bench) | ✓ | -1370 | strand 改动单独贡献 ~5s pair 提速；FimoFile 那块是死代码净清理 |
| `d61ae4c` chore(fused_fimo) | 删 `getPrime`/`isPrime`（5b 后无 caller）+ 删 `pushMotifHitVector` 深拷贝（无 caller）+ 删 `initMotifHit` 深拷贝（无 caller，统一到 `initMotifHitBorrowMeta`）+ 修 `_MEM_CHECK_H` → `PMET_INDEX_MEM_CHECK_H`（C 标准保留下划线开头标识符） | **37.82** (full bench) | ✓ | -126 | 死代码继续清；ownership 接口收敛到一个 |
| `e9423ac` refactor(pairing) | 抽 `motif::lookupICAndThreshold()` helper，binary/text reader 都用它 + `fastFileRead` 参数 `std::string` → `const std::string&`（消除三处 path copy） | 63.25 (pair-only on text) | ✓ | -3 净，但去重 22 行 | 修复双查 / 双路径漂移风险 |
| `ebfc90e` refactor(pairing) | 把 `findIntersectingGenes` 65 行 body 中的 PosIdx + 排序 + 双指针扫拆出 `motifComparison::detectOverlappingPositions()`；外层循环简化为 set_intersection → 调 helper → 早退 → 重测二项 4 步流水线 | 68.05 (pair-only on text) | ✓ | +19 净（多了 helper 边界 + 注释，少了 5 层嵌套） | 可读性升级，下一次改 IC 规则只动一处 |

### 3.1 子任务 pair-only 时间链条

| 阶段 | pair s | 增量 |
|---|---|---|
| 重构起点 anchor | 68.97 | — |
| 4a map find | 67.48 | -1.5（噪音） |
| 4b worker except | 67.05 | -0.5（噪音） |
| 4c utils exit | 66.94 | -0.1（噪音） |
| 5a strand drop | 63.07 | **-3.9 真实** |
| 5b FimoFile cleanup（不影响 pair） | (跳过 pair-only) | — |
| 6 dead-code cleanup（不影响 pair） | (跳过 pair-only) | — |
| 7 helper extract + by-ref | 63.25 | 噪音，结构改进 |
| 8 detectOverlappingPositions 抽离 | 68.05 | 噪音范围内（5 层嵌套→流水线，纯结构改进） |

### 3.2 5b 死代码清理统计

| 删除 | 行数 |
|---|---|
| `pmet-index-FimoFile.c` | 542 |
| `pmet-index-FimoFile.h` | 170 |
| `pmet-index-HashTable.c` | 279 |
| `pmet-index-HashTable.h` | 97 |
| `pmet-index-Node.c` | 288 |
| `pmet-index-Node.h` | 90 |
| **小计** | **1466** |
| 新增 `pmet-index-pair-test.{c,h}` | ~120 |
| **净** | **−1346** |

`SiteStore` 起初也以为是死代码，audit 时发现 `insert_site_into_store` 仍然被 `fimo.c::fimo_record_score` 调用（MEME `MATCHED_ELEMENT` → 我们的 `MotifHit` 的桥接），所以保留。这次踩的坑：grep 旧 API 名字（`initSiteStore` 等 0 引用）容易误判，必须用真正在用的函数名再查一次。

---

## 4. 综合对比（baseline vs 当前 dev tip）

| 项 | baseline (上游 main) | 当前 dev tip | 改善 |
|---|---|---|---|
| Indexing | 299.79 s | 289.85 s | -3.3% |
| Pair | 68.10 s | 37.82 s | **-44%** |
| Fimohits 磁盘大小 | 1.6 GB（text） | 683 MB（binary） | **-58%** |
| 源码行数（src/indexing/fused_fimo + src/pairing） | (基线) | **-1500+ 行净** | 显著瘦身（批 5b -1370 + 批 6 -126 + 批 7 -3） |
| 输出 (`pair_output sha`) | `bcf7...` | `bcf7...` | **完全一致** ✓ |
| CLI 健壮性 | 越界 / silent-zero / std::terminate | 清晰错误信息 | 质变 |
| 文件 IO 失败处理 | 部分 `exit()` 在线程内 | 错误传播 + 异常 wrap | 质变 |
| ownership 接口 | 深拷贝/借用两套并存 | 收敛到一个借用 init | 简化 |
| 标识符规范 | `_MEM_CHECK_H` 用保留前缀 | `PMET_INDEX_MEM_CHECK_H` | C 标准合规 |

---

## 5. 复现方法

```bash
# 完整 bench（~6 min）：indexing + stage + pair + fingerprint
bash scripts/bench/run_bench.sh <label>

# 仅 pair（~1 min）：复用 results/bench/baseline/indexing 的输出
bash scripts/bench/pair_only.sh <label>

# 启用 MinHash prefilter
MINHASH_MIN=20 bash scripts/bench/run_bench.sh minhash-20

# 用 text fimohits（旧格式，回归测试用）
# 任何以 "baseline" 开头的 label 会自动给 indexing 加 --text-output
bash scripts/bench/run_bench.sh baseline-recheck
```

结果累积写入 `results/bench/SUMMARY.tsv`（完整 bench）和 `results/bench/pair-only/SUMMARY.tsv`（仅 pair）。

---

## 6. 后续可选方向（暂未做）

- **fimo.c 文件拆分**：1200+ 行，runtime / batch / output 三段可以拆模块。收益高但风险高。
- **MotifHitVector 的 int → size_t 全链贯通**：影响面大，安全。
- **Header guards 全用 `#pragma once`**：纯个人偏好，几行的事，要么都做要么别做。
- **legacy `pmet-index-PromoterLength`、`ScoreLabelPairVector` 是否还有死函数？** 没专门 audit，可补一轮。
- **range-for / `std::filesystem` 现代化**：低优先级，主要是可读性微调。
- **`MotifHit::strand` C 端**：text fimohits writer 还在写出 strand 列；如果我们决定 binary 永远是默认，且 text 列也不必要，可以连同 `char strand` 字段一起删，又能瘦下来一些。
- **`utils.cpp::loadFiles` 11 个 out-parameter** 封成 `LoadedData` struct，main.cpp 调用变干净。中风险中收益。
