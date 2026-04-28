~~# TODO: 跨平台（macOS vs Linux）结果一致性问题~~

~~## 问题背景~~

~~`indexing/fused_fimo` 编译后在 macOS 和 Linux 上运行结果存在细微差异。以下为排查出的潜在原因，按影响程度排序。~~

~~---~~

~~## 1. `qsort()` 不稳定排序 — 严重~~

~~- **文件**: `pmet-index-ScoreLabelPairVector.c`, `pmet-index-MotifHitVector.c`~~
~~- **原因**: C 标准不要求 `qsort` 是稳定排序。macOS libc 和 glibc 实现不同，当多个元素 score 相同时，排序后顺序在两个平台上不一致。~~
~~- **影响**: 输出文件中基因排列顺序不同。~~
~~- **修复方案**: 在比较函数中加入 tie-breaker：`comparePairs` 以 label 字典序作为次要排序键；`compareMotifHitsByPVal` 以 sequence_name + startPos 作为次要排序键。~~
~~- [x] 已修复~~

~~## 2. `log()`/`exp()`/`pow()` 数学函数精度差异 — 较严重~~

~~- **文件**: `pmet-index-FimoFile.c` 中的 `binomialCDF()` 和 `geometricBinTest()`~~
~~- **原因**: macOS libm 和 Linux glibc 的数学函数实现不同，最后一两位有效数字可能不一致，循环累积后差异被放大。~~
~~- **影响**: binomial threshold score 在两个平台上不完全一致。~~
~~- **修复方案**: 在 `geometricBinTest()` 中对 geometric mean 和 binomP 中间结果四舍五入到 10 位有效数字（与 FIMO 自身的 RND 策略一致）。~~
~~- [x] 已修复~~

~~## 3. 哈希表遍历顺序 + 不稳定排序的组合效应 — 较严重~~

~~- **文件**: `pmet-index-FimoFile.c` 的 `processFimoFile()`~~
~~- **原因**: 哈希表遍历顺序不确定，加上 `qsort` 不稳定，最终输出顺序取决于排序前的插入顺序。~~
~~- **影响**: score 相同的基因排列顺序不同。~~
~~- **修复方案**: 问题 1 的 tie-breaker 修复后，排序结果不再依赖插入顺序，此问题自动消除。~~
~~- [x] 已修复（随问题 1 一起解决）~~

~~## 4. FIMO 的 `__APPLE__` 条件编译 — 中等~~

~~- **文件**: `mtwist.h`~~
~~- **原因**: 部分随机数函数原型在 macOS 上被 `#ifndef __APPLE__` 跳过。FIMO 虽已对 score/pvalue 做了 10 位有效数字四舍五入，但不保证下游 pmet-index 计算一致。~~
~~- **影响**: 可能影响随机数生成的精度。~~
~~- **修复方案**: 将 `#ifndef __APPLE__` 改为 `#if !defined(__GNUC__) && !defined(__clang__)`，使 GCC/Clang 平台统一跳过 extern 声明。~~
~~- [x] 已修复~~

~~## 5. 浮点输出格式化不统一 — 中等~~

~~- **文件**: 多个文件混用 `%f`、`%lf`、`%.3e`、`%.15f` 等格式~~
~~- **原因**: 内存中的 double 值因平台差异在最低位不同时，不同格式化方式输出也会不同。~~
~~- **影响**: 输出文件中数值字符串不一致。~~
~~- **修复方案**: 统一使用固定精度格式（如 `%.10e` 或 `%.15e`）。~~
~~- [x] 已修复~~

~~---~~

~~# TODO: Indexing 性能优化~~

~~## 🔴 高优先级（预计整体提升 50-70%）~~

~~### 1. PromoterLength 链表查找改用哈希表~~

~~- **文件**: `PromoterLength.c/h`, `FimoFile.c`, `main.c`~~
~~- **问题**: `findPromoterLength()` 使用链表 O(n) 线性搜索，对每个基因调用一次。5000 基因 × 5000 promoter = 2500 万次 `strcmp`。~~
~~- **方案**: 用现有 `HashTable` 存储 promoter length，查找变为 O(1)。~~
~~- [x] 已完成~~

~~### 2. MotifHitVector 深拷贝改 move 语义~~

~~- **文件**: `MotifHitVector.c/h`, `FimoFile.c`~~
~~- **问题**: `pushMotifHitVector()` 对 4 个字符串字段逐个 `new_strdup()` 深拷贝，push 后立刻 `deleteMotifHitContents()` 释放源。每行 FIMO = 8 次 malloc + 4 次 free。~~
~~- **方案**: 新增 `pushMotifHitVectorMove()` 转移指针所有权，避免复制后销毁。~~
~~- [x] 已完成~~

~~### 3. Overlap 检测 O(n²) 改 mark-compact~~

~~- **文件**: `FimoFile.c`, `MotifHitVector.c/h`~~
~~- **问题**: 嵌套循环检测 overlap，`removeHitAtIndex()` 每次删除 memmove 整个数组尾部 + realloc。O(k × n²)。~~
~~- **方案**: 标记要保留的 hit，一次压缩数组，O(k × n)。~~
~~- [x] 已完成~~

~~## 🟡 中等优先级（预计提升 20-30%）~~

~~### 4. binomialCDF 增量计算~~

~~- **文件**: `FimoFile.c`~~
~~- **问题**: `geometricBinTest()` 每次调用 `binomialCDF(k+1, ...)` 内部 O(k) 循环，总计 O(n²)。~~
~~- **方案**: 增量复用上一次 CDF 结果，仅追加一项。总计 O(n)。~~
~~- [x] 已完成（外层循环加入 early termination，内层 CDF 加入 saturation 提前退出）~~

~~### 5. FIMO 文件多线程并行处理~~

~~- **文件**: `main.c`, `CMakeLists.txt`~~
~~- **问题**: 串行处理每个 FIMO 文件，各文件之间完全独立。~~
~~- **方案**: OpenMP `#pragma omp parallel for`，写 binomial_thresholds.txt 加锁或最后合并。~~
~~- [x] 已完成（OpenMP parallel for + critical section 保护文件写入，无 OpenMP 时自动退化为单线程）~~

~~## 🟢 低优先级（预计提升 5-10%）~~

~~### 6. MotifHitVector 初始容量调大~~

~~- **文件**: `MotifHitVector.c`~~
~~- **问题**: 初始容量 10，对于每个基因通常有上百个 hit 会触发多次 realloc。~~
~~- **方案**: 初始容量改为 128。~~
~~- [x] 已完成~~

~~### 7. removeHitAtIndex 去掉循环内 realloc~~

~~- **文件**: `MotifHitVector.c`~~
~~- **问题**: `removeHitAtIndex()` 在 `size < capacity/2` 时 realloc 缩小，在 overlap 删除循环中反复触发。~~
~~- **方案**: 去掉缩小 realloc，仅在最终 `retainTopKMotifHits` 时统一缩小。~~
~~- [x] 已完成~~

~~---~~

~~# TODO: Pairing 性能优化~~

~~## 🔴 高优先级~~

~~### 1. motif 对象整体拷贝改为引用~~

~~- **文件**: `utils.cpp`（`outputParallel` 函数第 363、365 行）~~
~~- **问题**: `motif motif1 = (*allMotifs)[i]` 和 `motif motif2 = (*allMotifs)[j]` 每次循环**整体拷贝** motif 对象，包含 `unordered_map<string, vector<motifInstance>>` 全部数据。N 个 motif 产生 O(N²) 次深拷贝。~~
~~- **方案**: 改为 `const motif& motif1 = (*allMotifs)[i]`，传引用而非拷贝。`findIntersectingGenes` 等函数签名同步改为 const 引用。~~
~~- [x] 已完成~~

~~### 2. Overlap 检测 O(m₁×m₂) 嵌套循环~~

~~- **文件**: `motifComparison.cpp`（`findIntersectingGenes` 第 51-62 行）~~
~~- **问题**: 对每个共享基因，用嵌套循环比较 motif1 的所有 instance 和 motif2 的所有 instance，复杂度 O(m₁×m₂)。~~
~~- **方案**: 两组 instance 各按位置排序后，用双指针扫描仅检查位置接近的 pair。区间不重叠时跳过，复杂度降至 O((m₁+m₂)·log)。~~
~~- [x] 已完成~~

~~### 3. geometricMean 重复计算 → 增量累加~~

~~- **文件**: `motifComparison.cpp`（`geometricBinomialTest` 第 180-188 行）~~
~~- **问题**: 每次 k 增加 1 时，`geometricMean()` 从头遍历 [begin, i+1) 重新求 log 总和，总计 O(k²)。~~
~~- **方案**: 维护一个 `logSum` 累加变量，每次只加一个 `log(pVal)`，几何均值 = `exp(logSum / n)`。总计 O(k)。~~
~~- [x] 已完成~~

~~## 🟡 中等优先级~~

~~### 4. IC score 重复计算 → 预计算前缀和~~

~~- **文件**: `motif.cpp`（`getForwardICScore` / `getReverseICScore`，第 153-170 行）~~
~~- **问题**: 每次 overlap 检测都调用 `getForwardICScore()` / `getReverseICScore()`，对 overlap 区间线性求和 O(overlapLength)，同一 motif 的 IC 区间被反复计算。~~
~~- **方案**: 读入 IC 值后预计算前缀和数组，区间查询 O(1)。~~
~~- [x] 已完成~~

~~### 5. outputParallel 函数参数大量值传递~~

~~- **文件**: `utils.cpp`（`outputParallel` 函数签名，第 357-361 行）~~
~~- **问题**: `clusters`（map）、`promSizes`（unordered_map）、`motifsIndxVector`（vector）均按值传入，每个线程调用时都整体拷贝一次。~~
~~- **方案**: 函数参数改为 `const &` 引用传递。~~
~~- [x] 已完成~~

~~### 6. log factorial 表重复构建~~

~~- **文件**: `motifComparison.cpp`（`colocTest` 第 239-241 行）~~
~~- **问题**: 每次调用 `colocTest()` 都构建 `vector<double> logf(universeSize+2)`，universeSize 是常量，表却在每对 motif 的每个 cluster 中重建一次。~~
~~- **方案**: 在 `motifComparison` 对象中构建一次 logf 表，后续复用。~~
~~- [x] 已完成~~

~~## 🟢 低优先级~~

~~### 7. fairDivision 负载均衡算法优化~~

~~- **文件**: `utils.cpp`（`fairDivision` 第 250-282 行）~~
~~- **问题**: 每次迭代分配任务时重新计算各组总和并分配临时 vector，O(n × T × m)。~~
~~- **方案**: 用最小堆（priority_queue）维护各组当前负载，O(n·log T)。~~
~~- [x] 已完成~~

~~### 8. CMakeLists.txt 缺少优化编译选项~~

~~- **文件**: `CMakeLists.txt`~~
~~- **问题**: 未指定 `-O3` 等优化标志。~~
~~- **方案**: 添加 `set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -O3")`。~~
~~- [x] 已完成~~

~~# FIMO 代码精简分析计划~~

~~## 当前事实~~

~~- 实际目录为 `src/indexing/fused_fimo/src/fimo`，当前有 `51` 个 `.c` 文件。~~
~~- `CMakeLists.txt` 通过 `file(GLOB)` 把 `src/fimo/*.c` 全量编进 target；这会把“能编过但运行路径根本不会走到”的文件一并带上。~~
~~- 当前 PMET 脚本只走这一条调用路径：~~
~~ `--topk 5 --topn 5000 --no-qvalue --text --thresh 0.05 --verbosity 1 --bgfile <bg> --oc <out> <motif> <promoter.fa> <promoter_lengths.txt>`~~
~~- `fimo.c` 已经不是原版 FIMO 入口语义，而是强制要求 `3` 个位置参数：~~
~~ `motif file + sequence file + promoter_length file`~~
~~- 测试数据确认当前输入是：~~
~~ MEME text 格式、DNA alphabet、预计算 `.bg` 背景文件；没有看到 MEME XML、PSP/WIG、q-value 输出、HTML/XML/GFF 输出的实际使用。~~

~~## 思路调整~~

~~原来的“先扫调用链、再扫函数、最后给建议”方向没错，但还可以更快更稳：~~

~~1. 先从“真实运行路径”裁剪，而不是先做全量函数级分析。~~
~~2. 先做“文件级整块删除”，再做“结构体/参数级瘦身”。~~
~~3. 不要把“是否保留原版 FIMO 通用能力”和“是否保留 PMET 当前能力”混在一起。~~
~~4. 先把目标明确成 `PMET-only minimal FIMO`：~~
~~ 只服务当前 PMET indexing，不追求兼容原版 FIMO 全部 CLI 和输出格式。~~

~~## 推荐分层~~

~~### A 层：可直接从编译列表剔除~~

~~这层的标准是：不改业务逻辑，先从编译源里移除，要求仍能编译并跑通。~~

~~### B 层：先收窄 CLI / 输入格式，再整块删除功能链~~

~~这层不应该一开始就删文件，而应该先在 `fimo.c` 明确“我们不支持什么”：~~
~~只保留 PMET 当前需要的选项和输入格式，然后删掉与之绑定的整个模块链。~~

~~### C 层：核心数据结构脱离原版 FIMO~~

~~这是最能变“小”的一层，但也最容易误伤。~~
~~重点不是继续删零碎函数，而是把当前扫描流程对 `cisml.*` 这类原版结果结构的依赖切断。~~

~~## 已确认可剔除~~

~~以下结论已经做过两层验证：~~

~~- 符号依赖分析：这些 `.c` 在当前 target 中没有实际运行依赖，或其导出符号没有被项目代码使用。~~
~~- 临时副本验证：从构建列表移除后，仍可成功编译、运行；并且与原始二进制在测试数据上的输出目录完全一致。~~

~~可直接从 `src/indexing/fused_fimo/src/fimo/` 的编译源列表剔除：~~

~~1. `fasta-io.c`~~
~~2. `html-data.c`~~
~~3. `mhmm-state.c`~~
~~4. `mp.c`~~

~~补充说明：~~

~~- `fasta-io.c` 当前没有被项目内任何代码实际调用。~~
~~- `html-data.c` 当前无项目内调用。~~
~~- `mhmm-state.c` 的实现当前未被链接路径使用；但 `mhmm-state.h` 仍被头文件包含，头文件先保留更稳。~~
~~- `mp.c` 仅服务 `PARALLEL` 场景，当前构建没有启用。~~

~~## 条件性可剔除~~

~~以下部分都不是 PMET 当前主路径的核心算法，但还和现有 CLI、输入格式或数据结构缠在一起。~~
~~建议按功能链整块删除，不要零散删函数。~~

~~### 1. 原版 FIMO 输出链~~

~~前提：把 `insert_site_into_store` 从 `fimo-output.c` 挪到 `pmet_index` 或单独的新文件。~~

~~随后可删除：~~

~~1. `fimo-output.c`~~
~~2. `fimo-output.h`~~
~~3. `fimo-html-string.h`~~

~~原因：~~

~~- 当前 `fimo.c` 对 `fimo-output.c` 的唯一实际调用，只剩你自定义的 `insert_site_into_store`。~~
~~- HTML/XML/GFF/TSV 生成逻辑，PMET 当前路径都没有用到。~~

~~### 2. q-value / reservoir 链~~

~~前提：明确只支持 `--no-qvalue`，并移除非 `text_only` 路径。~~

~~随后可删除候选：~~

~~1. `qvalue.c`~~
~~2. `qvalue.h`~~
~~3. `reservoir.c`~~
~~4. `reservoir.h`~~
~~5. `heap.c`~~
~~6. `heap.h`~~
~~7. `hash_table.c`~~
~~8. `hash_table.h`~~

~~原因：~~

~~- 当前脚本固定传 `--no-qvalue --text`。~~
~~- `reservoir.*` 只服务非 text 模式下的 q-value 采样。~~
~~- 通用 `hash_table.*` 当前是被 `heap.c` 间接带着走，不是 PMET 自己的哈希表实现。~~

~~### 3. PSP / prior 链~~

~~前提：明确不支持 `--psp`、`--prior-dist`。~~

~~随后可删除候选：~~

~~1. `prior-dist.c`~~
~~2. `prior-dist.h`~~
~~3. `prior-reader-from-psp.c`~~
~~4. `prior-reader-from-psp.h`~~
~~5. `prior-reader-from-wig.c`~~
~~6. `prior-reader-from-wig.h`~~
~~7. `wiggle-reader.c`~~
~~8. `wiggle-reader.h`~~

~~原因：~~

~~- 当前 PMET 路径没有使用 position-specific priors。~~
~~- 这条链只属于原版 FIMO 的增强 scoring 能力，不属于 PMET 当前最小实现。~~

~~### 4. MEME XML 输入链~~

~~前提：明确只支持 MEME text motif 文件。~~

~~随后可删除候选：~~

~~1. `motif-in-meme-xml.c`~~
~~2. `motif-in-meme-xml.h`~~
~~3. `meme-sax.c`~~
~~4. `meme-sax.h`~~
~~5. `sax-parser-utils.c`~~
~~6. `sax-parser-utils.h`~~

~~原因：~~

~~- 当前测试和脚本都只使用 MEME text。~~
~~- `motif-in.c` 现在同时注册了 `MEME XML` 与 `MEME text` 两套 reader；对 PMET 最小版来说没有必要。~~

~~### 5. CisML / XML / XSLT 输出链~~

~~前提：先把扫描主流程从 `cisml.*` 结果结构上解耦。~~

~~随后可删除候选：~~

~~1. `cisml-sax.c`~~
~~2. `xml-out.c`~~
~~3. `xml-out.h`~~
~~4. `xml-util.c`~~
~~5. `xml-util.h`~~

~~进一步重构后，`cisml.c` 也可以大幅拆小，甚至整体退出主路径。~~

~~原因：~~

~~- 当前 `fimo.c` 在 `--text` 模式下仍然分配 `CISML_T`，但 PMET 结果写出基本不依赖原版 XML 输出链。~~
~~- 一旦这条链被移除，`libxml2` / `libxslt` 也有机会从 CMake 依赖里删掉。~~

~~### 6. 背景自动计算 / 序列翻译链~~

~~前提：明确最小版只支持 DNA + 显式背景文件，不支持从序列现算背景，也不支持字母表转换。~~

~~随后可删除候选：~~

~~1. `fasta-get-markov.c`~~
~~2. `xlate-in.c`~~

~~但这一组不能直接删文件，还需要同步精简 `alphabet.c` / `motif-in.c` 内对应分支。~~

~~## 当前最小内核应保留什么~~

~~如果目标是“保留 PMET indexing，去掉原版 FIMO 通用能力”，当前建议保留的核心大致是：~~

~~1. `fimo.c`~~
~~2. `alphabet.c` / `alph-in.c`~~
~~3. `array.c` / `array-list.c` / `matrix.c`~~
~~4. `motif.c`~~
~~5. `motif-in.c`~~
~~6. `motif-in-common.c`~~
~~7. `motif-in-meme-text.c`~~
~~8. `pssm.c`~~
~~9. `seq-reader-from-fasta.c`~~
~~10. `data-block.c`~~
~~11. `data-block-reader.c`~~
~~12. `seq.c`~~
~~13. `scanned-sequence.c`~~
~~14. `simple-getopt.c`~~
~~15. `utils.c`~~
~~16. `linked-list.c`~~
~~17. `parser-message.c`~~
~~18. `regex-utils.c`~~
~~19. `string-builder.c`~~
~~20. `red-black-tree.c`~~
~~21. `binary-search.c`~~
~~22. `string-match.c`~~
~~23. `src/pmet_index/*`~~

~~注意：~~

~~- `cisml.c` 目前还不能直接删，因为 `MATCHED_ELEMENT_T`、`SCANNED_SEQUENCE_T`、`PATTERN_T` 这批运行期结构仍在被 `fimo.c` 使用。~~
~~- 真正想做到“最精简”，下一步应该是把这批结构换成 PMET 自己的轻量结构，而不是继续把 `cisml.c` 整个背着。~~

~~## 结构体与参数瘦身~~

~~`FIMO_OPTIONS_T` 里有一批字段，在 PMET-only 版本里可以直接删除或折叠：~~

~~### 明确可删除~~

~~1. `seq_name`~~
~~2. `html_path`~~
~~3. `text_path`~~
~~4. `gff_path`~~
~~5. `best_site_path`~~
~~6. `xml_path`~~
~~7. `cisml_path`~~
~~8. `HTML_FILENAME`~~
~~9. `TSV_FILENAME`~~
~~10. `GFF_FILENAME`~~
~~11. `BEST_SITE_FILENAME`~~
~~12. `XML_FILENAME`~~
~~13. `CISML_FILENAME`~~

~~这些字段当前只服务原版输出链。~~

~~### PMET-only 后大概率可删除~~

~~1. `allow_clobber`~~
~~2. `compute_qvalues`~~
~~3. `best_site_only`~~
~~4. `max_strand`~~
~~5. `threshold_type`~~
~~6. `selected_motifs`~~
~~7. `psp_filename`~~
~~8. `prior_distribution_filename`~~
~~9. `pval_lookup_filename`~~
~~10. `command_line`~~
~~11. `max_stored_scores`~~
~~12. `alpha`~~

~~说明：~~

~~- `selected_motifs` 对应 `--motif` 过滤；如果 PMET 不需要按 motif 子集执行，可以一起删。~~
~~- `alpha` 只在 prior 相关逻辑中有意义；如果 PSP/prior 整条链拿掉，也可以一起删。~~
~~- `max_stored_scores` 只服务非 text / 非 PMET 的原版结果存储逻辑。~~

~~### 建议保留~~

~~1. `bg_filename`~~
~~2. `meme_filename`~~
~~3. `output_dirname`~~
~~4. `seq_filename`~~
~~5. `promoter_length`~~
~~6. `topk`~~
~~7. `topn`~~
~~8. `pseudocount`~~
~~9. `output_threshold`~~
~~10. `alphabet`~~

~~### 2026-04-07 实测已确认可剔除~~

~~下面这些不是“理论上可能没用”，而是已经从 `src/indexing/fused_fimo/CMakeLists.txt` 主构建中移除，并重新编译、跑 `data/indexing/demo` 后与原始基线目录 `diff -rq` 一致：~~

~~1. `fasta-io.c`~~
~~2. `html-data.c`~~
~~3. `mhmm-state.c`~~
~~4. `mp.c`~~
~~5. `fimo-output.c`~~
~~6. `motif-in-meme-xml.c`~~
~~7. `meme-sax.c`~~
~~8. `cisml-sax.c`~~
~~9. `hash_table.c`~~
~~10. `heap.c`~~
~~11. `prior-dist.c`~~
~~12. `prior-reader-from-psp.c`~~
~~13. `prior-reader-from-wig.c`~~
~~14. `qvalue.c`~~
~~15. `reservoir.c`~~
~~16. `sax-parser-utils.c`~~
~~17. `wiggle-reader.c`~~
~~18. `xml-out.c`~~
~~19. `xml-util.c`~~
~~20. `fasta-get-markov.c`~~
~~21. `xlate-in.c`~~

~~另外，`libxml2` 和 `libxslt` 也已经可以从 `fused_fimo` 的构建依赖里移除。~~

~~### 当前最小版仍应保留的核心~~

~~如果目标是“PMET 可用的最小 FIMO”，那现在真正还在承担核心功能的主要是：~~

~~1. `fimo.c`~~
~~2. `pssm.c`~~
~~3. `motif-in*.c` 中的 MEME text reader~~
~~4. `seq-reader-from-fasta.c`~~
~~5. `motif.c`~~
~~6. `alphabet.c`~~
~~7. `cisml.c` 的轻量运行时结构~~
~~8. `pmet-index-SiteStore.c`~~

~~这说明后续如果还要继续缩，不该再优先盯 `xml/xlate/prior`，而应该盯：~~

~~1. `alphabet.c`~~
~~2. `pssm.c`~~
~~3. `fimo.c`~~

~~也就是继续做“核心内核再拆分”，而不是继续清外围壳层。~~
~~11. `scan_both_strands`~~
~~12. `skip_matched_sequence`~~
~~13. `parse_genomic_coord`（除非确认永远不用）~~

~~## 实施顺序~~

~~1. 把 `CMakeLists.txt` 从 `GLOB` 改成显式源文件列表，拆成 `CORE_SOURCES` 和 `OPTIONAL_SOURCES`。~~
~~2. 先删除“已确认可剔除”的 4 个 `.c` 文件编译项。~~
~~3. 把 `insert_site_into_store` 从 `fimo-output.c` 拆出来，清掉原版输出链。~~
~~4. 固化 PMET-only CLI，只保留当前脚本真实使用的选项。~~
~~5. 删除 q-value / prior / MEME XML 这三条可选功能链。~~
~~6. 最后再处理 `cisml.c`，把扫描结果结构替换成 PMET 自己的轻量实现。~~

~~## 当前结论~~

~~不是“很多函数可能没用”，而是已经可以分成三类：~~

~~1. 有 4 个 `.c` 文件已经确认可以直接从编译列表剔除。~~
~~2. 有几整条功能链可以在 PMET-only 目标下整块删除。~~
~~3. 真正决定最小体积上限的，不是继续清零碎函数，而是把 `fimo.c` 对 `cisml.*` 的运行时依赖切掉。~~

# TODO: 下一阶段可优化项

## Indexing

### 1. ~~`fused_fimo` 做 motif 级并行~~

- ~~**文件**: `src/indexing/fused_fimo/src/fimo/fimo.c`~~
- ~~**问题**: 当前主循环本质上仍是逐个 motif 扫全量 promoter，CPU 利用率还有明显上升空间。~~
- ~~**方案**: 以 motif 为粒度并行，线程本地累积 `binomial_thresholds` / `fimohits` 结果，最后统一合并写盘。~~
- ~~**预期收益**: 高~~
- ~~**风险**: 中~~
- [x] 已完成：`fimo_score_each_motif()` 现已按 motif 粒度分发任务，结果在线程本地处理后统一汇总写盘；无 OpenMP 时自动退化为单线程。

### 2. `standlone` FIMO 文本解析替换 `strtok_r + sscanf`

- **文件**: `src/indexing/standlone/src/FimoFile.c`
- **问题**: 大 FIMO 文本文件解析仍偏重，`sscanf` 在热路径上开销明显。
- **方案**: 改为手写 tab parser 或按行原地切字段，减少格式化解析成本。
- **预期收益**: 中高
- **风险**: 中

### 3. `standlone` 文件调度继续做负载均衡

- **文件**: `src/indexing/standlone/src/main.c`
- **问题**: 各 motif 文件大小不均时，按文件并行会出现线程尾部不平衡。
- **方案**: 按文件大小排序后调度，或进一步调整 OpenMP 调度策略。
- **预期收益**: 中
- **风险**: 低

### 4. ~~`fused_fimo` 扫描阶段减少短生命周期分配~~

- ~~**文件**: `src/indexing/fused_fimo/src/fimo/fimo.c`, `src/indexing/fused_fimo/src/pmet_index/pmet-index-SiteStore.c`~~
- ~~**问题**: 虽然 hit 入栈已经优化，但 sequence / motif 级临时对象和路径字符串分配仍然较多。~~
- ~~**方案**: 复用 sequence-scoped buffer、减少短命字符串构造、必要时引入轻量对象池。~~
- ~~**预期收益**: 中~~
- ~~**风险**: 中~~
- [x] 已完成：扫描窗口的 matched-sequence 改为复用 buffer，去掉每个 site 的临时 forward/reverse sequence 分配；同一任务耗时从 4 分 20 秒降到 3 分 22 秒。

### 5. ~~`fused_fimo` 减少每个 hit 对 motif / gene 元数据的重复拷贝~~

- ~~**文件**: `src/indexing/fused_fimo/src/pmet_index/pmet-index-SiteStore.c`, `src/indexing/fused_fimo/src/pmet_index/pmet-index-MotifHit.c`, `src/indexing/fused_fimo/src/pmet_index/pmet-index-MotifHitVector.c`~~
- ~~**问题**: 当前每个 hit 仍会重复 `strdup` 相同的 `motif_id`、`motif_alt_id`、`sequence_name`，在高命中场景下会带来明显分配和释放开销。~~
- ~~**方案**: 让 hit 共享 motif / sequence 元数据引用，或引入更轻量的 intern / ownership 方案，只保留 `matched_sequence` 为逐 hit 独有字符串。~~
- ~~**预期收益**: 中高~~
- ~~**风险**: 中~~
- [x] 已完成：`motif_id` / `motif_alt_id` 已改为按 hit 借用共享引用，`sequence_name` 已收敛为按 vector 共享的一份字符串；后续又进一步将 `matched_sequence` 调整为默认跳过、仅在显式要求时保留。

### 6. ~~`fused_fimo` promoter length 查找改成 O(log n)~~

- ~~**文件**: `src/indexing/fused_fimo/src/pmet_index/pmet-index-PromoterLength.c`, `src/indexing/fused_fimo/src/fimo/fimo.c`~~
- ~~**问题**: 当前 `findPromoterLength()` 仍是链表线性搜索，在 motif task 热路径里会重复做大量 `strcmp`。~~
- ~~**方案**: 将 promoter lengths 读入排序数组，并使用二分查找替代链表遍历。~~
- ~~**预期收益**: 中高~~
- ~~**风险**: 低~~
- [x] 已完成：`PromoterList` 已由链表切换为排序数组，`findPromoterLength()` 改为二分查找，现主路径与旧副路径都会共享这条 O(log n) 查询逻辑。

### 7. ~~`fused_fimo` 在线维护 topN promoter，避免全量缓存后再裁剪~~

- ~~**文件**: `src/indexing/fused_fimo/src/fimo/fimo.c`~~
- ~~**问题**: 当前每个 motif task 会先把所有 promoter 的 `MotifHitVector` 和 binomial score 全量缓存下来，最后再 `sort + retainTopN`，会额外放大内存、哈希表操作和 cache miss。~~
- ~~**方案**: 扫描时直接维护一个大小为 `N` 的有界堆，仅保留当前最优 promoter；较差候选当场释放。~~
- ~~**预期收益**: 中高~~
- ~~**风险**: 中~~
- [x] 已完成：`fused_fimo` 现已在 motif 扫描过程中在线维护 topN promoter，仅在最终输出前对保留集合排序；不再为非 topN promoter 持有整份 `MotifHitVector` 和额外哈希表缓存。

### 8. ~~`fused_fimo` 每个 motif 输出文件只打开一次~~

- ~~**文件**: `src/indexing/fused_fimo/src/fimo/fimo.c`, `src/indexing/fused_fimo/src/pmet_index/pmet-index-MotifHitVector.c`, `src/indexing/fused_fimo/src/pmet_index/pmet-index-FimoFile.c`~~
- ~~**问题**: 当前按 promoter vector 写 `fimohits` 时会反复 `fopen("a") / fclose()`，在 topN promoter 较多时会产生明显的系统调用开销。~~
- ~~**方案**: 提供写入已打开 `FILE*` 的 helper，并让每个 motif 复用一个输出句柄完成整份 `fimohits` 写盘。~~
- ~~**预期收益**: 中~~
- ~~**风险**: 低~~
- [x] 已完成：`fused_fimo` 主路径与旧副路径现在都会在每个 motif 级别复用一个输出文件句柄，避免按 promoter vector 反复打开和关闭文件。

### 9. ~~默认跳过 `matched_sequence`，并让 pairing 接受无 sequence 输入~~

- ~~**文件**: `src/indexing/fused_fimo/src/fimo/fimo.c`, `src/indexing/fused_fimo/src/pmet_index/pmet-index-MotifHit.c`, `src/indexing/fused_fimo/src/pmet_index/pmet-index-MotifHitVector.c`, `src/pairing/src/motif.hpp`, `src/pairing/src/motif.cpp`~~
- ~~**问题**: `pairing` 当前并不消费 `matched_sequence`，但 indexing 仍会为每个 hit 构造、保存、写出这段字符串，随后 pairing 又会再读入并保存在内存里，整条链路都有额外开销。~~
- ~~**方案**: 让 `fused_fimo` 默认跳过 matched sequence 构造与输出，仅在显式要求时保留；同时让 pairing 兼容 7 列和 8 列的 `fimohits` 输入，并移除未使用的 sequence 成员。~~
- ~~**预期收益**: 中高~~
- ~~**风险**: 中~~
- [x] 已完成：`fused_fimo` 现已默认关闭 matched sequence 输出，但保留显式开关恢复旧行为；`pairing` 现已兼容有无 matched sequence 的 `fimohits` 输入，并移除了未参与计算的 sequence 存储。

### 10. ~~`fused_fimo` 对 sequence 做 alphabet index 预编码~~

- ~~**文件**: `src/indexing/fused_fimo/src/fimo/fimo.c`~~
- ~~**问题**: 当前最内层 scoring 会在每个 motif position 上重复调用 `alph_indexc()`，导致同一段 promoter 在不同 motif 扫描里被重复编码。~~
- ~~**方案**: 在共享 sequence 库加载阶段一次性完成 alphabet index 预编码，后续 score loop 直接消费 `SEQ_T` 里的已编码序列。~~
- ~~**预期收益**: 中~~
- ~~**风险**: 中~~
- [x] 已完成：`fused_fimo` 现已在共享 sequence 库加载阶段完成 alphabet index 预编码，`fimo_score_site()` 直接使用 `SEQ_T` 中的已编码序列；当前测试采样从 3.29 秒降到 2.62 秒。

### 11. ~~`fused_fimo` 不再为每个 motif 重扫整份 FASTA~~

- ~~**文件**: `src/indexing/fused_fimo/src/fimo/fimo.c`, `src/indexing/fused_fimo/src/fimo/pmet-sequence-library.c`~~
- ~~**问题**: 当前 motif 级并行虽然能吃到 CPU，但每个 task 仍会重复创建 FASTA reader、重新解析同一批 promoter，并重复做 sequence 相关准备工作。~~
- ~~**方案**: 在进入 OpenMP 前把 FASTA 读成共享只读 sequence 库，绑定 promoter length 并保留预编码结果；各 motif task 只遍历共享库，不再各自重扫 FASTA。~~
- ~~**预期收益**: 高~~
- ~~**风险**: 中高~~
- [x] 已完成：`fused_fimo` 现已在并行前构建共享只读 `SEQ_T` 库，各 motif task 改为直接遍历共享序列与已编码数据，不再各自创建 FASTA reader 和重扫整份输入；当前测试采样约为 2.62 秒。

### 12. ~~`fused_fimo` 改为按 motif batch 做 sequence-major 扫描~~

- ~~**文件**: `src/indexing/fused_fimo/src/fimo/fimo.c`~~
- ~~**问题**: 即使共享了 FASTA 与预编码序列，当前主路径仍是“一个 motif 扫完整个 sequence library”，当 motif 很多时，序列遍历的局部性和调度粒度都不够理想。~~
- ~~**方案**: 引入 motif runtime 和自动 batch 切分，让每个 OpenMP 任务改为“一个 motif batch 扫完整个 sequence library”；这样把 sequence 遍历挪到 batch 外层，减少多 motif 场景下的重复外层循环和序列访问抖动。~~
- ~~**预期收益**: 高~~
- ~~**风险**: 中高~~
- [x] 已完成：`fused_fimo` 现已按 motif batch 做 sequence-major 扫描，并支持 `PMET_MOTIF_BATCH_SIZE` 环境变量覆盖 batch 大小；当前主路径会打印 batch 数和每批 motif 上限，方便后续继续压测调参。

### 13. ~~给 `standlone` / `fused_fimo` 加结果一致性回归~~

- ~~**文件**: `scripts/` 下运行脚本与测试基线~~
- ~~**问题**: 两条独立实现后续继续同步优化时，容易再次出现”只改一边”。~~
- ~~**方案**: 固化对比流程，自动比较 indexing 输出目录、threshold 文件和 `fimohits/` 结果。~~
- ~~**预期收益**: 工程收益高~~
- ~~**风险**: 低~~
- [x] 已完成：`scripts/compare_branches.sh` 自动构建当前工作区与 HEAD 的全部 5 个引擎（indexing c/cpp/fused + pairing original/parallel），结果存入 `branch-compare/` 供手工比对。

### 14. `fused_fimo` MEME Suite 死代码清理

- **文件**: `CMakeLists.txt`, `utils.c`, `seq.c`, `motif.c`, `pssm.c`, `array.c`, `array-list.c`, `matrix.c`, `string-builder.c`, `fimo.c`, `seq.h`
- **问题**: `src/fimo/` 来自 MEME Suite 通用库，647 个导出函数中有 383 个（59%）从未被 PMET 调用路径触达。
- **方案**: 通过 `nm` + 链接器死代码分析识别死函数，分层清理：先移除 4 个 100% 死代码文件（`mtwist.c`、`ushuffle.c`、`io.c`、`binary-search.c`），再逐文件移除级联死函数。
- **结果**: 净删除 1,957 行代码，二进制从 298KB 减至 275KB（-8%），运行结果与清理前完全一致。
- [x] 已完成

## Pairing

### 1. ~~gene / motif universe 做整数 ID 化~~

- ~~**文件**: `src/pairing/src/motif.cpp`, `src/pairing/src/motifComparison.cpp`, `src/pairing/src/utils.cpp`~~
- ~~**问题**: 热路径里仍大量依赖 `string` 查表、排序、交集和哈希访问。~~
- ~~**方案**: 先把 universe gene 映射成整数 ID，后续交集、查表和 cluster 统计都走整数容器。~~
- ~~**预期收益**: 高~~
- ~~**风险**: 中高~~
- [x] 已完成：pairing 计算链路内部已统一使用 `GeneId`、整数化 promoter lookup、motif gene 交集与 cluster 交集，输出阶段再映射回基因名。

### 2. ~~cluster 结构改为整数向量或位图~~

- ~~**文件**: `src/pairing/src/utils.cpp`, `src/pairing/src/motifComparison.cpp`~~
- ~~**问题**: 每对 motif 都要对每个 cluster 做字符串集合操作，重复成本较高。~~
- ~~**方案**: 将 cluster 改为 `vector<int>` 或位图表示，加速交集与计数。~~
- ~~**预期收益**: 高~~
- ~~**风险**: 中~~
- [x] 已完成：cluster 当前已改为 `vector<int>` 表示，并参与整数化交集流程。

### 3. `fairDivision` 按真实工作量分配

- **文件**: `src/pairing/src/utils.cpp`
- **问题**: 当前线程分配更接近按 motif index 平衡，不是真正按比较成本平衡。
- **方案**: 以 `numGenesWithMotif`、instance 数量或剩余比较数作为权重重新划分任务。
- **预期收益**: 中
- **风险**: 低

### 4. `poissonCDF` 改递推实现

- **文件**: `src/pairing/src/motifComparison.cpp`
- **问题**: Poisson 模式下当前实现仍有重复乘除计算。
- **方案**: 用递推 PMF/CDF，避免每轮从头算 `lambda^i / i!`。
- **预期收益**: 中
- **风险**: 低

### 5. ~~`Output` / 结果缓存进一步瘦身~~

- ~~**文件**: `src/pairing/src/Output.hpp`, `src/pairing/src/main.cpp`~~
- ~~**问题**: 结果对象仍然保存字符串名和较重的内存结构，比较数大时压力会上升。~~
- ~~**方案**: 计算阶段先只存 motif 索引与核心统计量，输出阶段再回填名字。~~
- ~~**预期收益**: 中~~
- ~~**风险**: 中~~
- [x] 已完成：`Output` 计算阶段已改为保存 motif 索引和 `GeneId` 列表，导出阶段再映射回 motif 名与 gene 名，避免在线程结果缓存中重复持有大量字符串。

## 建议优先级

### 第一梯队

- `fused_fimo` motif 级并行
- `standlone` FIMO 文本解析优化

### 第二梯队

- `fairDivision` 按真实工作量分配

### 工程保障

- 给 `standlone` / `fused_fimo` 加结果一致性回归
