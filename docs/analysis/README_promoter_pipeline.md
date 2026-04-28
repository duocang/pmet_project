# Promoter Extraction Pipeline — 知识点与修改记录

## 1. 基因组坐标系统

GFF3 和 BED 使用不同的坐标体系，混用会导致全局 off-by-one 错误。

GFF3 采用 1-based 闭区间，start 和 end 都包含在内。例如 AT1G01010 在 GFF3 中的坐标是 3631–5899，表示从第 3631 个碱基到第 5899 个碱基，两端都包含。

BED 采用 0-based 半开区间，start 包含但 end 不包含。同一个基因在 BED 中应表示为 3630–5899，其中 3630 是 0-based 的起始位置，5899 作为半开区间的右端实际上包含到第 5898 个 0-based 位置（即 1-based 的 5899）。

转换规则：BED_start = GFF3_start - 1，BED_end = GFF3_end（不变）。

原始脚本中的 parse_genelines.py 没有做这个转换，直接将 GFF3 的 start 写入 BED，导致所有下游坐标偏移 1bp。现已统一在 `scripts/python/gff3_to_gene_bed.py` 中完成 `start - 1` 的转换；`parse_genelines.py` 已归档（`scripts/archive/`）。


## 2. 正链与负链基因的结构

正链（+）基因的元素在基因组上从左到右排列为：启动子 → TSS → 5'UTR → exon/intron → 3'UTR。转录方向与坐标增大方向一致。TSS 位于基因的 start 端（小坐标端），启动子在 start 的左侧（更小坐标方向）。

负链（-）基因的元素在基因组上是镜像排列的：3'UTR 在左侧（小坐标端），5'UTR 和 TSS 在右侧（大坐标端）。转录方向与坐标增大方向相反。TSS 位于基因的 end 端（大坐标端），启动子在 end 的右侧（更大坐标方向）。

mRNA 始终按 5' → 3' 读取，但在基因组上的排列方向取决于链。BED 格式中 start 永远小于 end，不论正链还是负链。


## 3. 启动子的定义与推断

GFF3 注释文件中通常不包含启动子信息。启动子需要从基因坐标推断。

基本方法是利用基因间区（intergenic region）：对于正链基因，启动子是 TSS（gene start）到上游邻近基因 end 之间的区域；对于负链基因，启动子是 TSS（gene end）到下游邻近基因 start 之间的区域。

两种实际策略：

第一种是固定窗口法，即取 TSS 上游固定长度（如 1000bp）。本管道使用 `bedtools flank -l $length -r 0 -s` 实现，简单通用，但可能侵入邻近基因体。

第二种是可变窗口法，即取 min(固定长度, 到邻近基因的距离)。需要预先计算每个基因的 TSS 到最近邻居的距离（length_to_tss.txt），然后逐个生成不同长度的启动子区间。本管道计算了 length_to_tss.txt 但未使用，而是通过事后的 bedtools subtract 切除重叠部分来补救。

特殊情况：当两个基因 head-to-head（背靠背）排列时，它们共享同一段基因间区作为各自的启动子。当一个基因完全嵌套在另一个基因体内时（如 AT1G03997 嵌套在 AT1G01050 内），嵌套基因的可用启动子空间为 0，会被后续步骤过滤掉。


## 4. GFF3 中的 gene-level feature type

GFF3 第 3 列的 feature type 并非只有 "gene"。常见的 gene-level feature 还包括 ncRNA_gene、pseudogene、transposable_element_gene、tRNA_gene、rRNA_gene、snRNA_gene 等。

原始脚本使用精确匹配 `$3 == "gene"`，导致 ncRNA_gene 等被遗漏。以 TAIR10 为例，AT1G03987 的 feature type 是 ncRNA_gene，被遗漏后 AT1G01020 的启动子边界会错误地延伸过这个 lncRNA。

`gff3_to_gene_bed.py` 通过 `--feature-regex` 参数同时支持两种语义：
- `--feature-regex 'gene$'`（默认）匹配 `gene`、`ncRNA_gene`、`pseudogene` 等所有以 `gene` 结尾的 feature。`03_promoter.sh`、`05_promoter_gap.sh` 用这个；
- `--feature-regex '^gene$'` 严格匹配仅 `gene` 一种。`02_benchmark_parameters.sh` 用这个，以保留它的 narrower scope。

建议运行前先看一眼 GFF3 实际有哪些 gene-level feature：`awk -F'\t' '$3 ~ /gene/' sorted.gff3 | cut -f3 | sort -u`。


## 5. GFF3 属性字段解析

GFF3 第 9 列是分号分隔的 key=value 属性对。不同来源的 GFF3 使用不同的键名：TAIR/Ensembl 用 `ID=gene:AT1G01010`，有些用 `gene_id=AT1G01010`，NCBI 用 `ID=gene-LOC123456`。

注意 Ensembl 风格的值带有 `gene:` 前缀。如果后续需要用基因名匹配其他数据（如表达矩阵），需要清理前缀：`gsub(/^[Gg]ene[:\-]/, "", name)`。

原始的 parse_utrs.py 使用 `'gene' in annot[i, :]` 检查整行是否包含字符串 "gene"，但属性列中几乎每行都有 gene_id 之类的字段，导致误匹配。修改为只检查第 3 列。


## 6. 多转录本与 TSS 选择

同一个基因可能有多个转录本（isoform），每个转录本的 5'UTR 长度不同，因此 TSS 位置也不同。

以 AT1G01020（负链）为例：AT1G01020.1 的 5'UTR 为 8667–9130（TSS=9130），AT1G01020.2 的 5'UTR 为 8667–8737（TSS=8737）。

gene-level 坐标（6788–9130）取的是所有转录本的最外层边界，对应最上游的 TSS。用 gene 行坐标来定位 TSS 等于自动选择了最长 5'UTR 对应的转录本，这是最保守也最常见的做法。

如果需要精确到每个转录本的 TSS，需要解析 mRNA/transcript 行而非 gene 行，下游复杂度会显著增加，对批量启动子分析来说收益不大。


## 7. 5'UTR 与启动子的关系

5'UTR 不是启动子的一部分。TSS 是转录起始位点，5'UTR 从 TSS 开始到翻译起始密码子（CDS start）之间，是 mRNA 的一部分。启动子在 TSS 的上游。

本管道可选地将启动子区间延伸到 CDS 起始位置（包含 5'UTR），用于更广义的顺式调控元件分析。parse_utrs.py 负责这一步，取所有转录本中最外层的 CDS 边界进行延伸。


## 8. bedtools getfasta 的 -s 参数

bedtools getfasta 默认提取正链序列。对于负链基因的启动子，虽然坐标是正确的，但提取的序列方向是错的——转录因子结合的是反向互补链上的 motif。

必须加 `-s` 参数让 bedtools 对负链区间自动做反向互补。不加 `-s` 会导致负链基因的 motif 分析结果全部错误。

加 `-s` 后，FASTA header 格式可能变为 `>gene(+)::chr:start-end` 或 `>gene::chr:start-end(+)`（取决于 bedtools 版本）。清理 header 时需要同时处理两种情况：`sed -e 's/::.*//g' -e 's/([+-])$//g'`。


## 9. 染色体命名一致性

GFF3 和 FASTA 文件可能使用不同的染色体命名：GFF3 用 "1" 而 FASTA 用 "Chr1"，或反过来。命名不一致会导致 bedtools flank、bedtools getfasta 等工具静默输出空结果，不会报错。

修改为在 Preflight 阶段就检查：从 GFF3 第一条数据行取染色体名，与 FASTA 第一条 header 比对，不匹配就立即报错退出，避免浪费时间。


## 10. 染色体长度的获取

bedtools flank 需要染色体长度文件（-g 参数）来防止坐标超出染色体边界。

获取方式按优先级：首先从 GFF3 的 `##sequence-region` 头部提取（`grep '^##sequence-region' | awk '{print $2"\t"$4}'`）；如果 GFF3 没有这些头部（不是所有 GFF3 都有），回退到 samtools faidx 生成 .fai 索引文件，取前两列。


## 11. Python 脚本的必要性评估

随着 R 阶段（重构）和 Stage 4–8 的推进，Python helper 已经从"补丁式工具"
演进为"管线主干"。当前 `scripts/python/` 下活跃的脚本：

`gff3_to_gene_bed.py`（GFF3→BED 转换）：曾经只是 `parse_genelines.py`
的替身，现在统一处理 feature 过滤、属性键解析（`gene_id=` → `ID=`
fallback）、GFF3→BED 坐标转换、重复名去重、`start ≥ end` 过滤。
03/05/02 + 测试都通过它。`parse_genelines.py` 已归档。

`genome_chrom_lengths.py`（染色体长度文件 + 命名一致性 preflight）：
合并了原 `calculate_chromosome_length.py` 和 inline grep+awk 回退到
`samtools faidx` 的逻辑。03/05 用它。`calculate_chromosome_length.py`
已归档。

`build_promoters.py`（promoter BED + FASTA + bg + lengths + universe）：
单 CLI 替代 02/03/05 三处 inline 的 `flank → subtract → assess →
UTR → getfasta -s → bg` 序列。CDS/intron/UTR 等不影响。

`run_homotypic.py`（端到端 homotypic stage）：组合上面所有 helper +
`build/index_fimo_fused`。03 和 05 现在 homotypic stage 只是一个 Python
CLI 调用。

`check_homotypic_contract.py`（5 个契约文件 schema 校验）：每个产生
homotypic 输出的 pipeline 末尾都跑一次。

`calculate_length_to_tss.py`（计算 TSS 到邻近基因距离）：涉及分组、
排序、前后邻居查找，逻辑较复杂；保留。被 `run_homotypic.py` 内部
调用。

`assess_integrity.py`（解决 split promoter）：涉及状态跟踪和链方向
判断；P1 修过相邻假设的 bug。被 `build_promoters.py` 内部调用。

`parse_utrs.py`（5'UTR 延伸）：原始版本有多个 bug（下标对齐、整行
字符串匹配、坐标混用），已重写。使用字典映射替代数组下标对齐，修
正坐标转换，去除 universe 文件依赖。被 `build_promoters.py` 内部
调用。

`calculateICfrommeme_IC_to_csv.py`：原 P1 的 append-mode bug 已修。
被 `run_homotypic.py` 内部调用。

`parse_memefile.py` / `parse_memefile_batches.py`：把 MEME 切成单
motif 文件 / N 批，给 IC 计算和 FIMO 并行用。

归档的（`scripts/archive/`）：`parse_genelines.py`、
`calculate_chromosome_length.py`、`calculateICfrommeme.py`、
`parse_matrix_n*.py`、`parse_mRNAlines.py`、`parse_promoter_lengths.py`、
`parse_promoters.py`、`promoter_add_gap.py`、`promoter_remove_overlap.py`、
`strip_newlines.py`。各自的废弃理由：要么逻辑被新 helper 吸收，要么
活跃 pipeline 已不调用它。


## 12. bedtools subtract 与 split promoter

当使用 `bedtools subtract` 切除启动子与基因体的重叠部分时，如果启动子区间内嵌了一个小基因，subtract 后启动子会被切成多个不连续的片段。

assess_integrity.py 处理这种情况：对于同一个基因名的多个片段，只保留离 TSS 最近的那个。正链保留坐标最大的片段（靠近 TSS 右端），负链保留坐标最小的片段（靠近 TSS 左端）。

这个步骤只在执行了 overlap removal（bedtools subtract）之后才需要。如果用户选择 AllowOverlap，则跳过。


## 13. awk 的 -F'\t' 参数

所有处理 BED/GFF3 文件的 awk 命令都应显式指定 `-F'\t'`（tab 分隔符）。虽然 awk 默认按空白分割在大多数情况下表现一致，但如果染色体名或基因名包含空格，不指定分隔符会导致字段错位。统一使用 `-F'\t'` 是防御性编程的好习惯。
