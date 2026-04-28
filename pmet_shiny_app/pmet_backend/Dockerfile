FROM python:3.11-slim

WORKDIR /app

# Install system dependencies: build tools + PMET runtime dependencies.
# bedtools, samtools, parallel, zip are invoked by the PMET shell scripts;
# perl runs gff3sort.pl and several MEME helper scripts; curl fetches the
# MEME tarball; zlib1g-dev is needed by MEME's configure. r-base-core +
# the libfontconfig/harfbuzz/freetype/etc. dev headers are for the heatmap
# step in scripts/pipeline/03_promoter.sh — `hrbrthemes`/`ggplot2` build
# their text/font code against these.
RUN apt-get update && apt-get install -y \
    gcc g++ cmake make git pkg-config \
    libxml2-dev libxslt1-dev zlib1g-dev \
    bedtools samtools parallel zip \
    curl perl \
    r-base-core \
    libfontconfig1-dev libharfbuzz-dev libfribidi-dev \
    libfreetype6-dev libpng-dev libtiff5-dev libjpeg-dev \
    libcurl4-openssl-dev libssl-dev \
    && rm -rf /var/lib/apt/lists/*

# R packages needed by scripts/r/draw_heatmap.R (heatmap step).
# The first batch is `library()` calls in the helper scripts; the second
# batch (reshape2 / tibble / ggasym) comes from `pkg::fn()` calls inside
# motif_pair_diagonal.R and process_pmet_result.R, which don't show up in
# `library()` greps but break the pipeline if missing. ggasym was archived
# from CRAN, so install it from GitHub. Nothing else from the Shiny-era
# install_packages.R is required.
RUN R -e "install.packages(c('dplyr','data.table','stringr','ggplot2','ggpubr','hrbrthemes','reshape2','tibble','remotes'), repos='https://cloud.r-project.org', Ncpus=parallel::detectCores())" \
 && R -e "remotes::install_github('jhrcook/ggasym', upgrade='never', quiet=TRUE)"

# Build MEME suite from source — the `meme` apt package was dropped from
# Debian 12. fasta-get-markov is invoked directly by the shell pipeline;
# a full MEME install keeps the pipeline resilient to script additions.
# Steps are split so failures surface on the actual failing command and
# not hidden behind a shell pipe (curl | tar swallows curl failures).
ENV MEME_VERSION=5.5.9
RUN set -eux \
    && curl -fL -o /tmp/meme.tar.gz \
       "https://meme-suite.org/meme/meme-software/${MEME_VERSION}/meme-${MEME_VERSION}.tar.gz" \
    && tar -xzf /tmp/meme.tar.gz -C /tmp \
    && rm /tmp/meme.tar.gz \
    && cd "/tmp/meme-${MEME_VERSION}" \
    && ./configure --prefix=/opt/meme \
                   --enable-build-libxml2 \
                   --enable-build-libxslt \
    && make -j"$(nproc)" \
    && make install \
    && cd / && rm -rf "/tmp/meme-${MEME_VERSION}"
ENV PATH="/opt/meme/bin:/opt/meme/libexec/meme-${MEME_VERSION}:${PATH}"

# Install Python dependencies
COPY pmet_backend/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Fetch and compile PMET_project. PMET_REF is the upstream commit SHA
# (resolved by `make build` via git ls-remote); changing it busts this
# layer's cache. Defaults to `main` if the image is built directly without
# Make. Binaries land in /app/pmet_pipeline/build/ — that path is the
# canonical runtime location all the workspace shell scripts autodetect
# (alongside ./build/), and config.PMET_SCRIPTS_DIR points there for the
# binary-architecture preflight in executor.py.
ARG PMET_REF=main
RUN git clone https://github.com/duocang/PMET_project.git /tmp/PMET_project \
    && cd /tmp/PMET_project \
    && git checkout "$PMET_REF" \
    && bash scripts/build_all.sh \
    && mkdir -p /app/pmet_pipeline/build \
    && cp build/index_fimo_fused \
          build/pair_parallel \
          build/pair_original \
          build/index_c \
          build/index_cpp \
          /app/pmet_pipeline/build/ \
    && chmod +x /app/pmet_pipeline/build/* \
    && rm -rf /tmp/PMET_project

# Copy application code. data/ is excluded via .dockerignore and mounted
# at runtime from the host (GB-scale). pmet_pipeline/ no longer exists on
# the host — only /app/pmet_pipeline/build/ inside the image, populated
# by the PMET_project compile step above.
COPY pmet_backend/ ./pmet_backend/
COPY scripts/ ./scripts/

RUN mkdir -p result result/indexing result/tasks

EXPOSE 8000

CMD ["uvicorn", "pmet_backend.api.main:app", "--host", "0.0.0.0", "--port", "8000"]
