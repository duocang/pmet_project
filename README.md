# PMET — Promoter Motif Enrichment Tool

## 这个工具做什么

PMET 回答一个问题：

> 在一组你感兴趣的基因里，哪些转录因子（TF）**成对地**出现在启动子中，
> 比随机期望更频繁？

成对出现意味着两个 TF 可能在物理上协同调控同一组基因。大多数 TF 不单独
结合 DNA — 它们需要 partner 挨着绑定，组合才能产生调控输出。PMET 就是来
找出这些 TF pair 的。

## 基因的物理结构

以拟南芥一个正链基因为例，它在基因组上长这样：

```
        ─── 上游基因间区 ───┐                        ┌── 下游基因间区

                            TSS     CDS_start              CDS_end
                             │       │                       │
      │       5'UTR          │ 外显子1  │   内含子   │ 外显子2  │       3'UTR         │
      ├──────────────────────┼─────────┼────────────┼─────────┼──────────────────────┤
                              └────── mRNA (primary transcript) ──────────────────────┘
                                    └───────── CDS ─────────┘

  ←── 启动子 (promoter) ──→|
         ~ 1000 bp
```

几个概念：

| 元素 | 是什么 | GFF3 第3列名 |
|---|---|---|
| **启动子 (promoter)** | TSS 上游 ~1 kb，TF 在这里结合开启转录 | (需要推断，GFF3 没有) |
| **5'UTR** | TSS 之后、翻译起始前，不编码但出现在 mRNA 中 | `five_prime_UTR` |
| **外显子 (exon)** | 编码片段 + UTR 片段 | `exon` |
| **内含子 (intron)** | 剪接掉的部分，不在成熟 mRNA 中 | (隐含在 mRNA 减去 CDS 里) |
| **CDS** | 真正翻译成蛋白质的编码区（仅外显子中的编码部分） | `CDS` |
| **3'UTR** | 翻译终止后到 polyA 位点 | `three_prime_UTR` |
| **mRNA** | 全长度初级转录本，从 TSS 到转录终止 | `mRNA` |

转录因子结合的 motif 散落在这些区域中。PMET 的核心逻辑就是在你指定的区域里
扫描已知的 motif 集合，找那些**成对富集**的组合。

## 算法：两步走

```
         step 1: INDEXING (homotypic)              step 2: PAIRING (heterotypic)
        ┌─────────────────────────────┐        ┌──────────────────────────────────┐
        │ genome + GFF3 + MEME motifs │        │ 我的基因列表 (感兴趣的一群基因)    │
        └────────────┬────────────────┘        └───────────────┬──────────────────┘
                     │                                         │
                     ▼                                         ▼
         ┌───────────────────────┐                 ┌────────────────────────────┐
         │  提取 promoter 序列    │                 │  在这些基因里，哪两个 motif  │
         │  FIMO 扫描所有 motif   │                 │  同时出现的次数比预期高？     │
         │  按基因保留 top hits   │                 │                            │
         │  (maxk 个最佳 hit)     │                 │  超几何检验 + 多重检验校正    │
         └───────────┬───────────┘                 └─────────────┬──────────────┘
                     │                                           │
                     ▼                                           ▼
         输出 homotypic index:                      输出 motif_output.txt:
         · fimohits/*.bin        ◄─────────── 供配对阶段消费  · motif1 | motif2 | raw_p | adj_p | ...
         · binomial_thresholds.txt
         · IC.txt
         · universe.txt
         · promoter_lengths.txt                       ┌──────────┐
                                                      │ heatmaps │ (R, 可选)
                                                      └──────────┘
```

**Step 1 — Indexing（同型搜索）**：拿出你指定的区域（启动子/UTR/CDS/...），
用 FIMO 把 MEME 文件里每一个 motif 扫一遍，对每个基因保留最好的几个 hit（
二项分布筛选），输出一个 "索引"。

**Step 2 — Pairing（异型配对）**：读 step 1 的索引，对你的基因列表做成对富集
检验：每一对 motif (m₁, m₂) 在你的基因群里共同出现的次数，相对于全基因组背景，
是不是显著偏高？用的统计方法是超几何分布检验，输出 p-value 和多重检验校正后的
adjusted p-value。

## 四种分析场景

PMET 可以在四种不同的「区域」上扫描 motif pair：

### 1. 启动子 — `promoter.sh`

最经典的场景。扫描每个基因 TSS 上游 ~1 kb + 5'UTR：

```
  TF1 ───┐         ┌─── TF2        ← 两个 TF 在启动子中挨着结合
  ───────┼─────────┼────────────────────────────────────►
         │  启动子  │           基因体
```

该脚本调用 `run_homotypic.py` 完成全部 GFF3 解析 → BED 构建 → promoter 提取 →
去重叠 → UTR 延伸 → 链方向纠正 → FIMO 扫描 → 索引 → contract 验证。

```bash
bash pipeline/workflows/promoter.sh                                    # 用默认 TAIR10
bash pipeline/workflows/promoter.sh -s my_genome.fa -a my_annot.gff3   # 换成你自己的物种
```

### 2. 任意区间 — `intervals.sh`

当你的分析单位不是「基因的启动子」而是 ATAC-seq / ChIP-seq peak 时：

```
  peak1  ████████████
  peak2     ████████████████        ← 每个 peak 被当作一个独立的扫描单元
  peak3  ██████████
```

直接把 FASTA 文件喂进去，FIMO 逐条扫描，interval name 就是分析单元。
支持 `:` 字符自动清理（FIMO 和 binary fimohits 格式不认冒号）。

```bash
bash pipeline/workflows/intervals.sh \
    -s data/demo_intervals/intervals.fa \
    -m data/demo_intervals/motif.meme \
    -g data/demo_intervals/peaks.txt
```

### 3. 基因组元素 — `elements.sh`

不局限在启动子。可以对 GFF3 里的任何 feature type 建索引：5'UTR / CDS / exon / mRNA。
一个基因可能有多个转录本（isoform），提供两种聚合策略：

```
  基因 ATCG00010
     isoform .1         5'UTR   ████████████
     isoform .2         5'UTR   ██████

  -s longest → 选 .1，因为它 5'UTR 总长度更大
  -s merged  → 取两个片段在基因组上的并集
```

对每个基因列表（`data/genes/*.txt`）逐一跑 pair_parallel + heatmaps。

```bash
bash pipeline/workflows/elements.sh -s longest -e 5UTR -t 8
```

`-e mRNA` 时还有 `-m Yes|No` 控制是否保留 UTR：

```
  -e mRNA -m Yes   完整 mRNA（UTR + CDS，每基因一段）
  -e mRNA -m No    mRNA 减去 UTR（CDS span，每基因一段，与 -e CDS 不同）
  -e CDS / exon    每个 CDS 片段 / 外显子单独成段（无聚合）
```

`-m` 仅在 `-s longest -e mRNA` 时有效，其他组合下被忽略。

### 4. 复用已有索引 — `pair_only.sh`

如果索引已经建好了，换个基因列表重跑 pairing 即可：

```bash
bash pipeline/workflows/pair_only.sh \
    -d results/promoter/01_homotypic \
    -g data/genes/my_new_clusters.txt \
    -o results/repaired
```

跳过 indexing，直接做 step 2。Web 的 `promoters_pre` 模式背后也是这个脚本。

## 关键参数

### 同型阶段 (indexing)

| 参数 | 默认值 | 脚本 | 含义 |
|---|---|---|---|
| `-n` / `--topn` | 5000 | promoter / intervals / elements | 每个 motif 在全基因组保留 top n 个基因 |
| `-k` / `--maxk` | 5 | 全部 | 每个基因每个 motif 最多保留 k 个最佳 hit |
| `-f` / `--thresh` | 0.05 | 全部 | FIMO p-value 阈值，高于此值的 hit 直接丢弃 |
| `-p` / `--length` | 1000 | promoter | 启动子长度 (bp)，从 TSS 向上游延伸 |
| `-v` / `--overlap` | NoOverlap | promoter | AllowOverlap 或 NoOverlap：相邻基因的启动子是否允许重叠 |
| `-u` / `--utr` | Yes | promoter | 是否将 5'UTR 包含进启动子区间 |
| `-s` | longest | elements | 转录本聚合策略：`longest`（取最长 isoform）/ `merged`（全 isoforms 求并集） |
| `-e` | — | elements | 基因组元素类型：`5UTR` / `3UTR` / `CDS` / `mRNA` / `exon` |

### 异型阶段 (pairing)

| 参数 | 默认值 | 脚本 | 含义 |
|---|---|---|---|
| `-i` / `--ic_threshold` | 4 | 全部 | IC 阈值：过于 simple 的 motif（低信息量）被排除，不做配对 |
| `-t` / `--threads` | 4 | 全部 | OpenMP 线程数，同时控制 FIMO 和 pair_parallel |
| `-g` | — | 全部 | 感兴趣的基因列表文件，每行一个基因名 |

### 输出

配对阶段的最终输出是 `motif_output.txt`（TAB 分隔，11 列）：

```
Cluster  Motif 1  Motif 2  n_genes_with_both  total_with_both  n_in_cluster  raw_p  adj_p_BH  adj_p_Bonf  adj_p_global  genes
cortex   AHL12    AHL12_2  3                  248              442           0.784  0.784     1.0         1.0           AT1G05680;AT2G20120;AT4G02170;
```

按 `adj_p_BH` 排序，每一行告诉你：在 cluster `cortex` 中，motif pair `(AHL12, AHL12_2)`
的共同出现是否是显著的协同信号。

---

# 以下为项目操作内容

---

PMET (Promoter Motif Enrichment Tool) — unified repo for the C/C++ engines, the bash + python + R pipeline glue, the FastAPI/Next.js web app, and deploy assets.

## Layout

```
core/          C/C++ engines (indexing, pairing) + CMake
pipeline/      shared bash + python + R helpers; workflows
apps/
  cli/         command-line entry points
  backend/     FastAPI + Celery worker
  frontend/    Next.js
deploy/        docker-compose, nginx, dockerfiles
data/          demo / fixtures only (large data is gitignored)
tests/         baseline fingerprints + integration tests
docs/
legacy/        retired code preserved by source of origin
build/         binaries (gitignored)
```

## Quick start (local CLI)

```bash
make build       # builds core engines into ./build/
make demo        # runs indexing + pairing against data/*/demo
make baseline    # captures fingerprints for regression checks
```

## Pipeline workflows

All workflows live under [`pipeline/workflows/`](pipeline/workflows/) and
expect the **repo root as cwd** (they `cd` there themselves). Helpers
come from `pipeline/{lib,python,r}/`. Output lands under `results/`
(gitignored).

**Pre-flight (run once):**

```bash
make build                                          # produce ./build/* binaries
bash pipeline/workflows/cli/00_env_check.sh         # check tools, fetch TAIR10 if missing
```

**Two ways to run, e.g. `promoter.sh`:**

```bash
# A) Direct — defaults reproduce the canonical TAIR10 demo, all overridable via getopts:
bash pipeline/workflows/promoter.sh

# B) Interactive menu — pick from the listed workflows:
bash apps/cli/run.sh
```

Each script's `-h` prints the full option list. Common promoter override:

```bash
bash pipeline/workflows/promoter.sh \
    -s data/TAIR10.fasta \
    -a data/TAIR10.gff3 \
    -m data/Franco-Zorrilla_et_al_2014.meme \
    -g data/genes/genes_cell_type_treatment.txt \
    -t 8
```

Heatmaps (stage [3]) need `Rscript` + the R packages listed in
[`pipeline/r/install_packages.R`](pipeline/r/install_packages.R); the
data stages [1]+[2] still produce `motif_output.txt` if Rscript is
missing — the heatmap stage is skipped with a warning.

**Workflow index**:

| script | location | purpose |
|---|---|---|
| `promoter.sh`            | `pipeline/workflows/`     | **Full promoter pipeline** — homotypic + heterotypic + heatmaps. Used by CLI demo and web `promoters` mode. |
| `intervals.sh`           | `pipeline/workflows/`     | **Full interval pipeline** — same flow on user-supplied intervals (e.g. ATAC-seq peaks). Used by web `intervals` mode. |
| `elements.sh`            | `pipeline/workflows/`     | **Genomic-element pipeline** (UTR / CDS / mRNA / exon). `-s longest \| merged` selects the isoform-aggregation strategy. Loops over every gene list in `data/genes/*.txt`. |
| `pair_only.sh`           | `pipeline/workflows/`     | **Re-pair an existing homotypic index** — skips the expensive indexing stage. Used by web `promoters_pre` mode and CLI re-runs. |
| `00_env_check.sh`        | `pipeline/workflows/cli/` | Tool/dep check; downloads TAIR10 if absent |
| `01_perf_cpu.sh`         | `pipeline/workflows/cli/` | Perf benchmark: single-cpu vs parallel heterotypic |
| `02_perf_params.sh`      | `pipeline/workflows/cli/` | Perf benchmark: sweep PMET parameters on promoters |
| `05_promoter_gap.sh`     | `pipeline/workflows/cli/` | Promoter gap-extension analysis |

`pipeline/workflows/cli/` underscore-prefixed files (`_common.sh`,
`_pmet_index_element.sh`) are libraries / sub-workflows sourced by 06/07;
they don't appear in the launcher menu.

## Deploy the web app

The web app (FastAPI + Celery + Next.js + nginx, behind redis) ships as a
docker-compose stack under `deploy/`. From the repo root:

```bash
make up          # build images + start the stack (5-10 min on first run)
make logs        # tail logs from all services
make ps          # show container status
make down        # stop the stack
make rebuild     # rebuild images and restart (after editing app code)
```

Once `make up` finishes, open **http://localhost:5960** — nginx fronts the
frontend (`/`) and the API (`/api/...`). Container layout:

| service  | role                             | host port |
|----------|----------------------------------|-----------|
| nginx    | reverse proxy                    | **5960**  |
| frontend | Next.js                          | (internal 3000) |
| api      | FastAPI                          | (internal 8000) |
| worker   | Celery worker                    | —         |
| redis    | Celery broker + result backend   | —         |

What gets bind-mounted from the host (so edits take effect without rebuild):

- `apps/pmet_backend/` → `/app/pmet_backend` (uvicorn auto-reloads; worker needs `make restart-worker`)
- `pipeline/`         → `/app/pipeline`     (workflow scripts, python/R helpers)
- `data/`             → `/app/data`         (genomes, pre-computed indexing, demo)
- `deploy/result/`    → `/app/result`       (per-task outputs)

The frontend is **baked into its image** at build time (no bind mount), so
frontend edits need `make rebuild` (or `cd deploy && make rebuild-frontend`
for just the frontend).

### First-time data setup

The pre-computed species indexes (~GBs) aren't shipped in the repo. Run
once on the host (not in a container):

```bash
cd deploy && make fetch-data
```

This downloads TAIR10 + per-species indexes into `data/indexing/` (16G if
you grab everything).

### Email notifications

The backend sends per-task completion emails. Configure SMTP credentials
at `data/configure/email_credential.txt` (gitignored — never commit it).
Format is 5 lines: `username`, `password` (Gmail app-password recommended),
`from_address`, `smtp_server`, `port`.

### More deploy targets

`make up` / `make down` cover the common path. For finer-grained control
(rebuild a single service, restart nginx after editing `nginx.conf`, etc.):

```bash
cd deploy && make help
```

## Migration status

This repo was unified from three separate subdirs (`PMET_project`,
`pmet_analysis_pipeline`, `pmet_shiny_app`) at tag `v0.1.0-monorepo`. See
`tests/baseline/README.md` for the fingerprints used to verify no
regressions across the move.
