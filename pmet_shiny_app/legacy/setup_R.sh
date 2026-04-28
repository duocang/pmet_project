#!/bin/bash
# Setup R environment: CRAN mirror, OpenBLAS, littler

set -e

CRAN=${1:-${CRAN:-"https://cran.r-project.org"}}
PURGE_BUILDDEPS=${PURGE_BUILDDEPS:-true}
ARCH=$(uname -m)

# shellcheck source=/dev/null
source /etc/os-release

# Install apt packages if not present
apt_install() {
    for pkg in "$@"; do
        dpkg -s "$pkg" &>/dev/null && continue
        [[ $(find /var/lib/apt/lists/* 2>/dev/null | wc -l) -eq 0 ]] && apt-get update
        apt-get install -y --no-install-recommends "$pkg"
    done
}

# Force source install for arm64
CRAN_SOURCE=${CRAN/"__linux__/${UBUNTU_CODENAME}/"/""}
[[ "$ARCH" == "aarch64" ]] && CRAN=$CRAN_SOURCE

# Configure Rprofile.site
cat >> "${R_HOME}/etc/Rprofile.site" <<EOF
options(repos = c(CRAN = '${CRAN}'), download.file.method = 'libcurl')
options(HTTPUserAgent = sprintf("R/%s R (%s)", getRversion(), paste(getRversion(), R.version["platform"], R.version["arch"], R.version["os"])))
EOF

# Install OpenBLAS
if ! dpkg -l | grep -q libopenblas-dev; then
    apt_install libopenblas-dev
    update-alternatives --set "libblas.so.3-${ARCH}-linux-gnu" \
        "/usr/lib/${ARCH}-linux-gnu/openblas-pthread/libblas.so.3"
fi

# Install littler
if ! command -v r &>/dev/null; then
    builddeps=(libpcre2-dev libdeflate-dev liblzma-dev libbz2-dev zlib1g-dev libicu-dev)
    apt_install "${builddeps[@]}"
    Rscript -e "install.packages(c('littler','docopt'), repos='${CRAN_SOURCE}')"

    # Cleanup build deps
    [[ "$PURGE_BUILDDEPS" == "true" ]] && apt-get remove --purge -y "${builddeps[@]}"
    apt-get autoremove -y && apt-get autoclean -y
fi

# Symlinks for littler
ln -sf "${R_HOME}/site-library/littler/bin/r" /usr/local/bin/r
ln -sf "${R_HOME}/site-library/littler/examples/installGithub.r" /usr/local/bin/installGithub.r

# Use custom install2.r if exists
if [[ -f "scripts/install/install2.r" ]]; then
    ln -sf "$(pwd)/scripts/install/install2.r" /usr/local/bin/install2.r
else
    ln -sf "${R_HOME}/site-library/littler/examples/install2.r" /usr/local/bin/install2.r
fi

rm -rf /var/lib/apt/lists/*

echo "R $(R --version | head -1 | cut -d' ' -f3) configured with littler"
