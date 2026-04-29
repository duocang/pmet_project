# PMET 优化通俗版说明

这份文档用日常语言讲清楚每一次代码改动**做了什么**、**为什么有用**、**会不会改变结果**。
技术细节请看 [OPTIMIZATION_LOG.md](OPTIMIZATION_LOG.md)。

完整流水线 = **indexing**（扫描 motif 在每个基因 promoter 上的命中位置）+ **pairing**（统计哪些 motif 对会一起在某簇基因上富集）。

---

## 我们关心的两个数字

每次改完代码，我都会跑同一份固定数据（872 个 motif × 29824 个 promoter，跟拟南芥一个量级），然后看两件事：

| 指标 | 是什么 | 为什么重要 |
|---|---|---|
| **运行时间** | indexing 用了几秒、pairing 用了几秒 | 看跑得快不快 |
| **结果指纹（sha）** | 把所有最终输出排序后算个哈希值 | 任何 1 个字节不一样，sha 就不一样。**只要 sha 跟原版一致，就证明改动没影响科学结论** |

未优化的原版（baseline）跑完产生的 sha 是 `bcf7…`。下面每一项改动都在跑完后对比这个 sha——一致就是 ✓，不一致就是 ✗。

---

## 性能优化：跑得更快、文件更小

### 优化 A：把中间文件从文字改成"二进制紧凑格式"
*（commit `8fa9b66`）*

**原来怎么做：** indexing 把每条命中（一个基因上的一个 motif 命中位置）写成一行文本，比如 `"AHL20 AT2G07981 46 53 + 11.142857 1.867e-04"`。pairing 启动时再把这种文本一行行解析回数字。

**问题：** 文字格式存浮点数浪费空间（`1.867e-04` 占 9 个字节但实际只需要 8 字节就能存这个 double），写的时候要把数字转字符串、读的时候要把字符串转回数字，两边都慢。

**怎么改：** 改成定长二进制格式，每条命中固定 32 字节，结构体直接 fwrite/fread，不用任何字符转换。

**类比：** 就像本来用电子表格存数据要写 `=A1+B1` 这种公式字符串，改成直接存内存里的 double 数值。

| 指标 | 原版 | 改后 | 变化 |
|---|---|---|---|
| pair 阶段时间 | 68.10s | 42.22s | **-38%** |
| fimohits 文件总大小 | 1.6 GB | 683 MB | **-58%** |
| 结果 sha | `bcf7…` | `bcf7…` | ✓ 完全一致 |

向后兼容：加了 `--text-output` 开关，需要回到旧文本格式做对比时随时能切。

---

### 优化 B：MinHash 预筛选不可能显著的 motif 对
*（commit `55b6ce0`）*

**原来怎么做：** pairing 要做 M×M/2 ≈ 38 万对 motif 比较，每对都要算位置重叠 + 二项式检验 + 超几何检验。

**思路：** 如果两个 motif 各自命中的基因集合几乎不相交，那么它俩"共同结合"的统计显著性就几乎不可能，跑完整检验是浪费。

**怎么改：** 给每个 motif 算一个 128 位的 MinHash 指纹（约 1KB/motif，加载时算一次），两个指纹一比就能粗估交集大小。交集太小的 pair 直接跳过完整检验。

**类比：** 就像找两个班级的共同好朋友 —— 先各自报 5 个最熟的人，发现完全没重合，就基本不用查通讯录了。

| 指标 | 原版 | 改后 | 变化 |
|---|---|---|---|
| pair 阶段时间 | 68.10s | 42.52s | -38%（主要来自上面的 binary 格式） |
| 被跳过的 pair 数 | 0 | 14（共 38 万对）| 都是 raw_p > 0.25 的非显著对 |
| 结果 sha | `bcf7…` | `0a4c…` ⚠️ | 略变（但被跳过的都不是显著结果） |

注：在我们这份测试数据里效果不明显，因为 indexing 用 topN=5000 让每个 motif 的基因集都很大、重叠率很高。**默认关闭（`-m 0`）**，需要时用 `-m 20` 之类显式打开。

---

## 健壮性补强：让程序更不容易崩

### 加固 C：命令行参数缺值/写错时给清楚的报错
*（commit `65f10d4`）*

**原来：** 用户写 `pair_parallel -i`（忘了写值）会越界读 argv，崩溃信号；写 `pair_parallel -i abc`（值不是数字）会抛 `std::terminate`，终端只看到一个莫名其妙的"已退出"。

**怎么改：** 解析每个参数前先检查 `i+1 < argc`，数字解析全部包 try-catch，报错说"哪个选项需要数字、收到了 'abc'"。fused_fimo 的 C 端也一样，用 `strtol`/`strtod` 替换 `atoi`/`atof`（后者拿到非数字时静默返回 0，比报错还烦）。

**类比：** 之前是"卡了"或"莫名其妙退出"，现在是"-i 这个选项需要一个数字，你给的是 abc，这样不行"。

结果 sha：✓（功能没变，只是错误处理变好了）

---

### 加固 D：worker 线程崩了不会带垮整个进程
*（commit `f1d9e27`）*

**原来：** pairing 用 `std::thread` 派 8 个 worker 干活。任何一个 worker 抛异常没人接，C++ 标准要求直接 `std::terminate()` —— 整个进程立刻死，连其他 worker 在干啥都不知道。

**怎么改：** 每个 worker 包一层 try-catch，抛了就标记一个原子标志位 + 打印是哪个 worker、什么错。其他 worker 接着跑完，主线程 join 之后看到标志位就 return 1。export 阶段同样处理。

**类比：** 之前一个工人受伤就关掉整个工厂、不留事故记录；现在那个工人停下、报告"我搞砸了，原因是 X"，其他人继续干完后再统一说"今天有 1 处事故，输出可能不全"。

同时：utils.cpp 里几处 `exit(1)` 在线程内也做了同样处理——文件打不开时改成抛异常或返回 false 让上层处理，不直接干掉进程。

结果 sha：✓

---

### 加固 E：错误信息走 cerr，不会被 `> log.txt` 吞掉
*（commit `d8ef162`）*

**原来：** 大量错误用 `std::cout << "Error: ..."`，跟正常进度信息混在 stdout 流。用户做 `pair_parallel ... > out.log` 想留进度日志，错误就看不见了，因为 stdout 被重定向走了。

**怎么改：** 28 处 "Error: ..." 全改 `std::cerr`，错误信息总会出现在终端。

**类比：** 之前所有话都用同一个广播喇叭说，关广播就什么都听不到；现在错误用应急喇叭单说，关日常广播也听得见警报。

结果 sha：✓

---

### 加固 F：二进制 fimohits 加 header 边界检查
*（commit `fefbc30`）*

**原来：** pairing 读二进制 fimohits 时直接信任 header 写的"我有 N 条命中"。如果文件被损坏、N 写成了 40 亿（uint32 上限），pairing 会先 `std::vector<BinHit>(N)` 申请 128 GB 内存，等申请失败才报错——这中间机器可能就动弹不得。

**怎么改：** 打开文件先 `seek` 到末尾问磁盘文件多大，再校对 header 声称的字节数有没有超出实际文件大小。超了就直接报错"header 说要 X 字节但文件只有 Y 字节"。

**类比：** 别人说"我寄给你 100 个箱子"，你之前是傻乎乎清空整个仓库腾地方；现在先看一眼物流单上的总重量，发现根本装不下 100 箱才腾。

结果 sha：✓（合法文件下行为完全不变）

---

## 可读性 / 整理：代码瘦身

### 整理 G：删掉一大堆没人调用的死代码
*（commit `e279bea` + `d61ae4c`）*

仔细 grep 之后发现：
- `pmet-index-FimoFile`：542 行，处理旧版"先用 FIMO 工具单独跑出文本文件再读进来"那条路径，自从 fused_fimo 走 OpenMP 直接扫之后没人调用了
- `pmet-index-HashTable` + `pmet-index-Node`：是 FimoFile 的内部数据结构，跟着死
- `motifInstance::strand`：pairing 加载每条命中时存了 strand 字段（"+" / "-"），但代码里**根本没有任何地方读它**
- `pushMotifHitVector` 深拷贝版、`initMotifHit` 深拷贝版：留着的是借用版，深拷贝版没人用
- `getPrime` / `isPrime`：以前给 hash table 算桶数用，删了 hash table 之后变成孤儿
- `_MEM_CHECK_H`：C 标准规定下划线开头是给编译器内部用的，自定义代码用了是 UB（未定义行为）

合计 **删了 ~1500 行**，加回 ~120 行（把还活着的 `geometricBinTest` / `motifsOverlap` 三个函数搬到一个新的小文件 `pmet-index-pair-test.{c,h}`）。

**类比：** 大扫除发现仓库里好几柜子是上一个项目用的工具，跟现在干的活完全没关系；清出去之后不仅占地少了，新人来翻文件也不会被吓到。

| 指标 | 原版 | 改后 |
|---|---|---|
| 源码行数（仅这两个模块） | 基线 | **-1500 行** |
| 结果 sha | `bcf7…` | `bcf7…` ✓ |
| pair 时间 | 68.10s | 37.27s（**-45%**！）|

那 -45% 时间怎么来的？主要来自删 `motifInstance::strand` 字段——本来每条命中要塞一个 `std::string`（24 字节 struct overhead），22M 条命中 × 24 字节 ≈ 数百 MB 的"假塞进去再没人看"内存。删掉后 cache 友好很多。

---

### 整理 H：拼写错误、注释中文 debug 块、cout/cerr 一致性
*（commit `d8ef162`）*

修了 5 处拼错（`binomialThresholdFilePaht` → `Path`、`reperesents` → `represents` 之类），删了 3 处早期开发留下的注释掉的中文调试 printf 块，统一了错误流。

**类比：** 给文档校对一遍，纠正笔误，删掉草稿纸。

结果 sha：✓

---

### 整理 I：把重复 22 行的 IC + threshold 查表抽出来
*（commit `e9423ac`）*

**原来：** pairing 里的 binary reader 和 text reader 末尾各写了 22 行差不多的 "查 IC 值、检查长度、建前缀和、查 threshold" 逻辑。

**怎么改：** 抽到 `motif::lookupICAndThreshold()` 私有方法，两条路径都用它。以后改 IC 校验规则只动一处，不会出现一边改了一边没改的"漂移"。

顺手把 `fastFileRead(std::string)` 改成 `const std::string&`，省下三次没必要的 string copy。

结果 sha：✓

---

### 整理 J：拆 `findIntersectingGenes` 60 行 body
*（commit `ebfc90e`）*

**原来：** pairing 的核心函数 `findIntersectingGenes` 一个 for 循环 body 65 行，里面塞着五件事：
1. 取出两个 motif 的命中位置数组
2. 按起始位置排序（构建辅助 PosIdx 结构 + 两次 sort）
3. 双指针扫一遍找重叠
4. 翻转 keep 标志
5. 决定基因要不要保留

读起来必须屏住呼吸读到底。

**怎么改：** 把第 2、3、4 步抽成 `detectOverlappingPositions()` 私有方法，外层 for 循环现在变成 4 步流水线：
```
set_intersection → detectOverlappingPositions → 两边都没剩? 跳过 → 全留? 直接收 / 部分留? 重测二项再决定
```

**类比：** 一段流水账分了小标题，每小段做一件事，注释也跟过来了。

结果 sha：✓ ；pair 时间 68.05s（在 baseline 噪音范围内，没变快也没变慢）

---

## 综合对比

| 维度 | 优化前 baseline | 当前 dev | 变化 |
|---|---|---|---|
| Indexing 阶段 | 299.79s | 289.85s | -3.3% |
| Pairing 阶段 | 68.10s | 37.82s | **-44%** |
| fimohits 中间文件 | 1.6 GB | 683 MB | **-58%** |
| 源码净行数 | 基线 | **−1500 多行** | 显著瘦身 |
| **科学输出** | sha `bcf7…` | sha `bcf7…` | **完全一致** ✓ |
| CLI 错误时表现 | 越界 / 静默 0 / terminate | 清晰错误信息 | 质变 |
| 线程崩溃时表现 | 整进程死 | 标记 + 跑完 + 报告 | 质变 |
| 错误信息可见性 | 跟 stdout 混 | 走 cerr 不会被吞 | 质变 |

---

## 怎么自己跑一次验证

```bash
# 整条流水线（约 6 分钟）
bash scripts/bench/run_bench.sh my-test

# 只跑 pair（约 1 分钟，复用已有 indexing 输出）
bash scripts/bench/pair_only.sh my-test
```

跑完去 `results/bench/SUMMARY.tsv` 看一行新数据。最后一列就是 `pair_output sha`，跟 `bcf73b77ea2bdd431ae693b63d7b50a4d8fd3e9f541b25a1b24868766bf08db9` 比就能确认输出没变。
