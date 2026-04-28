# PMET

PMET (Promoter Motif Enrichment Tool) identifies cooperative transcription factor (TF) activity by evaluating both homotypic and heterotypic motif combinations across promoter sets. It supports command-line and web deployments and ships with multiple implementations optimized for speed or feature depth.

## What PMET does

- Scores combinations of motifs within transcriptional regulatory modules to reveal TF cooperation.
- Handles homotypic and heterotypic motifs simultaneously, avoiding biases from single-motif analyses.
- Provides multiple engines: C, C++ (feature-rich), and a fused build that integrates FIMO scanning.
- Offers original and parallel pairing (downstream enrichment) for performance scaling.

## Repository layout

- `src/indexing/from_c`, `from_cpp`, `fused_fimo`: PMET indexing engines.
- `src/pairing/original`, `parallel`: PMET pairing engines (single-threaded and multithreaded).
- `build/`: collected binaries after `scripts/build_all.sh`.
- `data/indexing/demo`, `data/pairing/demo`: small example inputs for indexing and pairing; useful as templates for your own data. Sibling `data/indexing/bench/` and `data/pairing/bench/` (and any `data/*.fasta`/`data/*.gff3`) are for full-scale local benchmarks and are gitignored.
- `scripts/`: unified build and run entry points.

## Prerequisites

- CMake and a C/C++ toolchain (GCC/Clang); macOS example: `brew install cmake`.
- Standard POSIX shell utilities (bash, make, grep, coreutils).

## Build

Build everything (recommended first run):

```bash
bash scripts/build_all.sh
```

Targeted builds:

```bash
# Only indexing engines (all)
bash scripts/build_all.sh indexing

# Specific engines
bash scripts/build_all.sh indexing-c      # C
bash scripts/build_all.sh indexing-cpp    # C++
bash scripts/build_all.sh fused-fimo      # fused FIMO + indexing
bash scripts/build_all.sh pairing         # all pairing engines
bash scripts/build_all.sh pairing-original
bash scripts/build_all.sh pairing-parallel
```

Binaries land in `build/` (e.g., `build/index_c`, `build/index_cpp`, `build/index_fimo_fused`, `build/pair_original`, `build/pair_parallel`).

OpenMP note for `index_fimo_fused`:

- Motif-level parallelism is enabled automatically when CMake finds OpenMP.
- On macOS with AppleClang, install `libomp`, export `OpenMP_ROOT`, then rebuild.
- Example shell setup:
  `export OpenMP_ROOT=/opt/homebrew/opt/libomp` on Apple Silicon Homebrew, or
  `export OpenMP_ROOT=/usr/local/opt/libomp` on Intel Homebrew.
- If OpenMP is not available, `index_fimo_fused` still builds and runs correctly, but falls back to single-thread execution.
- At runtime, `index_fimo_fused` prints whether OpenMP is enabled and the maximum thread count it will use.

## Data layout (expected)

### Indexing

- `promoter_lengths.txt`: promoter lengths table.
- `promoters.fa`: promoter FASTA.
- `promoters.bg`: background model.
- `motifs.txt`: motif list (MEME-derived ids used by precomputed FIMO hits for C/C++ engines).
- `fimo/`: directory of FIMO hits (used by C/C++ indexing).

### Pairing

- `gene.txt`: target gene set (one per line).
- `universe.txt`: universe gene set (one per line).
- `IC.txt`: information content per motif.
- `promoter_lengths.txt`: same format as indexing.
- `binomial_thresholds.txt`: produced by indexing; required by pairing.
- `fimohits/`: produced by indexing; required by pairing.

Example layouts live in `data/indexing/demo` and `data/pairing/demo`.

## Regression comparison

`scripts/compare_branches.sh` builds all five engines from the current working tree and from the HEAD commit (via a temporary git worktree), runs indexing and pairing for each, and diffs the outputs. Results are stored in `branch-compare/` under the project root for manual inspection.

```bash
bash scripts/compare_branches.sh
```

## Run indexing

Use the unified wrapper [scripts/run_indexing.sh](scripts/run_indexing.sh):

```bash
# C engine (default)
bash scripts/run_indexing.sh

# C++ engine
bash scripts/run_indexing.sh -v cpp

# Fused FIMO + indexing
bash scripts/run_indexing.sh -v fused
```

Common options:

- `-v, --version {c|cpp|fused}`: pick engine.
- `-d, --data DIR`: data directory (default `data/indexing/demo`).
- `-o, --output DIR`: output root (default `results/demo/indexing`); per-version subfolders are created.

Outputs include `binomial_thresholds.txt` and `fimohits/` under the chosen output folder.

## Run pairing

Use [scripts/run_pairing.sh](scripts/run_pairing.sh) (always runs `pair_parallel`):

```bash
bash scripts/run_pairing.sh
```

Common options:

- `-d, --data DIR`: pairing data directory (default `data/pairing/demo`).
- `-o, --output DIR`: output root (default `results/demo/pairing`).
- `-i, --ic-threshold N`: IC cutoff (default `4`).
- `-t, --threads N`: threads (default `2`).

The script filters `gene.txt` against `universe.txt`, runs pairing, and writes results (parallel merges temp shards into `motif_output.txt`).

## Run full pipeline

Use [scripts/run_pipeline.sh](scripts/run_pipeline.sh) to chain indexing → pairing. Two modes:

Interactive (prompts for versions):

```bash
bash scripts/run_pipeline.sh
```

Non-interactive:

```bash
bash scripts/run_pipeline.sh \
  --indexing-version cpp \
  -d /path/to/data \
  -o /path/to/results \
  -t 8
```

- `-d, --data`: root data directory containing `indexing/demo/` and `pairing/demo/` subfolders (default `data`).
- `-o, --output`: root for pipeline results (default `results/demo/pipeline`); indexing outputs go to `<output>/indexing/<version>`, pairing to `<output>/pairing`.
- Pairing always uses `pair_parallel`. The pipeline copies `binomial_thresholds.txt` and `fimohits/` from indexing output into a temporary pairing input folder automatically.

## Cleaning

Remove builds, results, or temp files with [scripts/clean.sh](scripts/clean.sh):

```bash
bash scripts/clean.sh          # clean all
bash scripts/clean.sh builds   # only build artifacts
bash scripts/clean.sh results  # only outputs
bash scripts/clean.sh temp     # temp files
```

## Tips

- Prefer binaries in `build/`; wrappers fall back to per-module build dirs if needed.
- If an executable is missing, rebuild the matching target (for example `bash scripts/build_all.sh indexing-cpp`).
- Use the sample data in `data/indexing/demo` / `data/pairing/demo` to validate your setup before running on your own datasets.

## Changelog

### 2026-04-25 — dev 分支后续优化（性能 + 健壮性 + 可读性）

> 详细成绩单见 [docs/BENCHMARK_REPORT.md](docs/BENCHMARK_REPORT.md)；通俗版讲解见 [docs/CHANGES_PLAIN_ZH.md](docs/CHANGES_PLAIN_ZH.md)；提交-级技术日志见 [docs/OPTIMIZATION_LOG.md](docs/OPTIMIZATION_LOG.md)。

#### 性能（200-motif 子集对比 baseline → dev tip）

- pair 时间：**11.02 s → 3.83 s（−65%）**
- pair 峰值内存：**508 MB → 262 MB（−48%）**
- fimohits 中间文件磁盘占用：**391 MB → 158 MB（−60%）**
- 科学输出：`pair_output sha` 与 baseline **完全一致**（用 SHA-256 字节级对照验证）

#### 主要新功能

- **二进制 SoA fimohits 格式**：`index_fimo_fused` 默认输出 `fimohits/<motif>.bin`（紧凑、固定 32 字节/命中）。`pair_parallel` 通过 magic header 自动识别 binary 或 text，无需 CLI 切换。需要旧文本格式做调试或回归对比时加 `--text-output`。格式定义在 [src/indexing/fused_fimo/src/pmet_index/pmet-fimo-binary.h](src/indexing/fused_fimo/src/pmet_index/pmet-fimo-binary.h)。
- **MinHash 预筛选（pair 阶段）**：`pair_parallel -m N`（N>0）启用——给每个 motif 算 128 位 MinHash 指纹，跳过预估"共有基因数 < N"的 motif 对（标 p=1.0）。**默认 `-m 0` 关闭**，输出与 baseline 完全一致。当前测试集（topN=5000）下 motif gene 集合都很饱和、几乎无可跳；启用后果显著仅在更稀疏的 motif 库或更小 topN 场景。
- **命令行健壮性**：所有 `pair_parallel` 选项加 argv 边界检查 + `stoi/stod` 异常捕获；fused_fimo 用 `strtol/strtod` 替换 `atoi/atof`（后者拿到非数字静默返回 0）。坏输入现在给清晰错误而非段错误或静默 0。
- **错误处理**：pairing 错误信息走 `std::cerr`（之前混在 `std::cout`，被 `> log.txt` 重定向就看不见）；`std::thread` worker 包 try/catch + 原子标志，单个 worker 抛异常不再 `std::terminate` 整个进程。
- **二进制 fimohits 读取加固**：`pair_parallel` 读 `.bin` 时先 `seek` 到末尾验证 header 声称字节数 ≤ 实际文件大小，杜绝损坏 header 触发巨型 `std::vector` 分配。

#### 工程整理（无行为变化，sha 全部对照通过）

- **死代码清理**（净 −1500 行）：
  - 整个 legacy `pmet-index-FimoFile / HashTable / Node` 模块（fused_fimo 走 OpenMP 路径后这条文本-FIMO 路径无人调用），3 个 helper 函数（`geometricBinTest` / `motifsOverlap` / `binomialCDF`）迁移到新模块 [pmet-index-pair-test.{c,h}](src/indexing/fused_fimo/src/pmet_index/pmet-index-pair-test.c)。
  - 重复的 `pushMotifHitVector` 深拷贝、`initMotifHit` 深拷贝、`getPrime/isPrime`、`motifInstance::strand` 字段（**没人读但每条 hit 占 24 B 浪费——删它直接砍 pair 内存 −40%**）。
- **结构整理**：
  - `motif::lookupICAndThreshold()` 收齐 binary/text reader 重复 22 行查表逻辑。
  - `motifComparison::detectOverlappingPositions()` 把 `findIntersectingGenes` 65 行混合逻辑拆成 4 步流水线。
  - `finalizeAfterLoad()` 收齐两条 reader 的 sort + sketch + log 共同尾巴。
- **typo + 一致性**：`binomialThresholdFilePaht→Path`、`reperesents→represents` 等 6 处拼写；`_MEM_CHECK_H` 守卫名换成 `PMET_INDEX_MEM_CHECK_H`（C 标准保留下划线开头）；`fastFileRead` 参数 `std::string→const std::string&`。

#### 新增工具

- **bench 脚本**：[scripts/bench/run_bench.sh](scripts/bench/run_bench.sh)（完整流水线 + sha 指纹）和 [scripts/bench/pair_only.sh](scripts/bench/pair_only.sh)（仅 pair，复用已有 indexing 输出，~1 min 跑完，用于每次 refactor 后快速验证 sha）。
- **bench 数据约定**：`data/indexing/bench/`（gitignore 中）放真实规模数据；`results/bench/SUMMARY.tsv` 累积所有运行的时间 / 内存 / sha 对照。

### 2026-04-06 — Pairing 性能优化

- **motif 对象拷贝改为 const 引用**：`outputParallel()` 中 `motif motif1 = (*allMotifs)[i]` 整体深拷贝改为 `const motif&` 引用，消除 O(N²) 次含 `unordered_map` 的拷贝开销。`getListofGenes`、`getNumInstances`、`getInstance` 改为 const 方法，`findIntersectingGenes`、`motifInstancesOverlap`、`geometricBinomialTest` 参数同步改为 `const motif&`。涉及文件：`utils.cpp`、`motif.cpp/hpp`、`motifComparison.cpp/hpp`。
- **Overlap 检测双指针优化**：`findIntersectingGenes()` 中 O(m₁×m₂) 嵌套循环改为按起始位置排序后双指针扫描，仅检查位置实际重叠的 pair。同时用计数器替代 4 次 `std::find` 布尔向量扫描。涉及文件：`motifComparison.cpp`。
- **geometricMean 增量累加**：`geometricBinomialTest()` 中每次从头遍历计算 `geometricMean()` 改为维护 `logSum` 累加变量，O(k²)→O(k)。移除独立的 `geometricMean()` 方法。涉及文件：`motifComparison.cpp/hpp`。
- **IC score 前缀和优化**：`getForwardICScore()` 和 `getReverseICScore()` 从 O(overlapLength) 线性求和改为 O(1) 前缀和查询。读入 IC 值时预计算 `ICPrefixSum` 数组。涉及文件：`motif.cpp/hpp`。
- **函数参数改为 const 引用**：`outputParallel()`、`output()`、`findIntersectingGenes()`、`colocTest()` 的 `clusters`、`promSizes`、`motifsIndxVector`、`genesInCluster` 等容器参数从按值传递改为 `const &`，消除每线程启动时的整体拷贝。涉及文件：`utils.cpp/hpp`、`main.cpp`、`motifComparison.cpp/hpp`。
- **logf 表复用**：`colocTest()` 中每次重建的 `logf(universeSize+2)` 表改为 `motifComparison` 成员变量，通过 `buildLogfTable()` 构建一次后复用。涉及文件：`motifComparison.cpp/hpp`、`main.cpp`。
- **fairDivision 最小堆优化**：任务分配从 O(n×T×m) 替换为 `priority_queue` 最小堆 O(n·log T)，移除临时 `tempSum` vector 和已废弃的 `SumVector()` 函数。涉及文件：`utils.cpp/hpp`、`main.cpp`。
- **CMakeLists 添加 -O3 优化**：默认 Release 构建类型，启用 `-O3` 编译优化标志。涉及文件：`CMakeLists.txt`。

### 2026-04-06 — Indexing 性能优化

- **PromoterLength 查找改用哈希表**：`findPromoterLength()` 从 O(n) 链表遍历改为 O(1) 哈希表查找。`PromoterList` 新增 `HashTable *ht` 和 `count` 字段，插入时同步填充哈希表。涉及文件：`PromoterLength.c/h`、`main.c`。
- **MotifHitVector 新增 move 语义入栈**：新增 `pushMotifHitVectorMove()` 转移指针所有权，避免 `readFimoFile()` 中每行 FIMO 数据 8 次 malloc + 4 次 free 的深拷贝浪费。涉及文件：`MotifHitVector.c/h`、`FimoFile.c`。
- **Overlap 检测改用 mark-compact**：将 O(k×n²) 的嵌套删除循环替换为 O(k×n) 的标记-压缩策略，避免逐个 `removeHitAtIndex()` 的 memmove 开销。涉及文件：`FimoFile.c`。
- **binomialCDF / geometricBinTest 优化**：外层循环加入 early termination（连续 10 次未改善即退出），`binomialCDF` 内部加入 CDF ≥ 1.0 饱和提前终止。涉及文件：`FimoFile.c`。
- **FIMO 文件 OpenMP 并行处理**：主循环加 `#pragma omp parallel for`，`binomial_thresholds.txt` 写入以 `#pragma omp critical` 保护。无 OpenMP 时自动退化为单线程。涉及文件：`main.c`、`FimoFile.c`、`CMakeLists.txt`。
- **MotifHitVector 初始容量调大**：从 10 增至 128，减少频繁 realloc。涉及文件：`MotifHitVector.c`。
- **removeHitAtIndex 去除循环内 realloc**：删除 `size < capacity/2` 时的缩容 realloc，避免 overlap 删除循环中反复触发。涉及文件：`MotifHitVector.c`。

### 2026-04-06

- **统一浮点数输出格式**：修复跨平台（macOS vs Linux）浮点数输出不一致问题。
  - indexing（fused_fimo、standalone、legacy）：将 score/pVal 的 `%f`、`%lf`、`%.3e` 统一为 `%.10e`（科学计数法，10 位有效小数）；binomial threshold score 从 `%.15f` 改为 `%.15e`。
  - pairing（current、legacy）：`ofstream <<` 输出 double 前设置 `std::scientific << std::setprecision(10)`。
  - 涉及文件：`pmet-index-FimoFile.c`、`pmet-index-MotifHitVector.c`、`pmet-index-Node.c`、`pmet-index-MotifHit.c`、`pmet-index-ScoreLabelPairVector.c`、`FimoFile.c`、`MotifHitVector.c`、`Node.c`、`MotifHit.c`、`ScoreLabelPairVector.c`、`Output.cpp`（pairing + legacy pairing）、`cMotifHit.cpp`、`main.cpp`（legacy indexing）。
  - 详见 [TODO.md](TODO.md) 中跨平台问题的完整列表。
- **修复 FIMO 条件编译平台差异**：`mtwist.h` 中 `#ifndef __APPLE__` 改为 `#if !defined(__GNUC__) && !defined(__clang__)`，使 macOS 和 Linux 上 extern 声明行为一致；`CMakeLists.txt` 抑制第三方 fimo 源码的无关警告。
- **修复 qsort 不稳定排序导致的跨平台结果顺序差异**：
  - `comparePairs()`：score 相同时以 label 字典序作为 tie-breaker。
  - `compareMotifHitsByPVal()`：pVal 相同时以 sequence_name + startPos 作为 tie-breaker。
  - 同时解决了哈希表遍历顺序 + 不稳定排序的组合效应（问题 3）。
  - 涉及文件：`pmet-index-ScoreLabelPairVector.c`、`pmet-index-MotifHitVector.c`（fused_fimo + standalone）。
- **修复 math 库跨平台精度差异**：在 `geometricBinTest()` 中对 geometric mean 和 binomP 中间结果四舍五入到 10 位有效数字，与 FIMO 自身的 RND 策略一致，消除 `log()`/`exp()`/`pow()` 在 macOS libm 与 Linux glibc 间的累积误差。涉及文件：`pmet-index-FimoFile.c`、`FimoFile.c`。
