#!/bin/bash

# Load shared color utilities and helper functions
script_dir=$(cd -- "$(dirname "$0")" && pwd)
source "$script_dir/scripts/lib/print_colors.sh"
echo -e "\n\n"
print_middle "The purpose of this script is to                                      \n"
print_middle "  1. assign execute permissions to all users for bash and perl files    "
print_middle "  2. compile binaries needed by Shiny app                               "
print_middle "  3. install python package                                             "
print_middle "  4. check needed tools                                               \n"
print_middle "                                                                      \n"

if [ -d .git ]; then
    git config core.fileMode false
fi


############################ 1. linux dependences #############################
# Helper function to install packages with error handling
install_package() {
    local pkg="$1"
    if sudo apt -y install "$pkg" > /dev/null 2>&1; then
        return 0
    else
        print_red "    Failed to install $pkg"
        return 1
    fi
}

# Helper function to install multiple packages
install_packages() {
    local packages=("$@")
    for pkg in "${packages[@]}"; do
        install_package "$pkg"
    done
}

if [ true ]; then
    print_green "\n1. Adding some necessary dependencies, please wait a moment..."
    print_orange_no_br "  Do you want to install Ubuntu dependencies? [y/N]: "
    read dependency
    dependency=${dependency:-N}

    if [[ "$dependency" =~ ^[Yy]$ ]]; then
        print_orange "Installing dependencies..."

        # Check for MacOS
        if [[ "$OSTYPE" == "darwin"* ]]; then
            print_red "This is MacOS. No support!"
        # Check for Linux
        elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
            if [ -f /etc/os-release ]; then
                . /etc/os-release

                if [[ "$ID" == "ubuntu" || "$ID_LIKE" == "debian" ]]; then
                    print_green "Installing on Debian/Ubuntu: $PRETTY_NAME"

                    sudo apt update && sudo apt upgrade -y > /dev/null
                    sudo add-apt-repository -y ppa:alex-p/tesseract-ocr-devel > /dev/null 2>&1 || \
                        print_red "    Failed to add PPA for tesseract"

                    # Define packages to install
                    local build_tools=(
                        "openjdk-21-jdk" "dpkg" "zip" "build-essential" "zlib1g-dev"
                        "libgdbm-dev" "autotools-dev" "automake" "nodejs" "npm"
                    )

                    local xml_libs=(
                        "libxml2-dev" "libxml2" "libxslt-dev"
                    )

                    local image_libs=(
                        "cmake" "libjpeg-dev" "librsvg2-dev" "libpoppler-cpp-dev"
                        "freetype2-demos" "libmagick++-dev" "libavfilter-dev"
                    )

                    local text_libs=(
                        "cargo" "libharfbuzz-dev" "libfribidi-dev"
                        "libtesseract-dev" "libleptonica-dev" "tesseract-ocr-eng"
                    )

                    local compression_libs=(
                        "libbz2-dev" "libpcre2-dev" "libreadline-dev" "libssl-dev"
                        "glibc-source" "libstdc++6"
                    )

                    local ncurses_libs=(
                        "libncurses5-dev" "libncursesw5-dev"
                    )

                    # Install all packages
                    install_packages "${build_tools[@]}" "${xml_libs[@]}" "${image_libs[@]}" \
                                     "${text_libs[@]}" "${compression_libs[@]}" "${ncurses_libs[@]}"

                    # Add and update security repositories
                    echo "deb http://security.ubuntu.com/ubuntu focal-security main" | \
                        sudo tee /etc/apt/sources.list.d/focal-security.list > /dev/null
                    sudo apt update

                    # Install security and math libraries
                    install_packages \
                        "libssl1.1" "libcurl4-openssl-dev" \
                        "libopenblas-dev" "gfortran" "ufw"

                    # Configure BLAS alternative
                    sudo update-alternatives --config libblas.so.3-$(arch)-linux-gnu > /dev/null 2>&1

                elif [[ "$ID" == "fedora" || "$ID_LIKE" == "fedora" || "$ID" == "rhel" || "$ID_LIKE" == "rhel" ]]; then
                    print_green "Red Hat based distribution detected: $PRETTY_NAME"
                    print_orange "Support for Red Hat distributions is not yet implemented"
                else
                    print_orange "Unsupported Linux distribution: $PRETTY_NAME"
                fi
            else
                print_red "Linux distribution detected but /etc/os-release not found"
            fi
        elif [[ "$OSTYPE" == "cygwin" ]]; then
            print_red "This is Windows with Cygwin. No support!"
        elif [[ "$OSTYPE" == "msys" ]]; then
            print_red "This is Windows with MinGW. No support!"
        else
            print_red "Unknown Operating System. No support!"
        fi
    else
        print_fluorescent_yellow "    No Linux dependencies installed"
    fi
fi


############################ 2. assign execute permissions #############################
print_green_no_br "\n2. Would you like to assign execute permissions to all users for bash and perl files? [Y/n]: "
read answer
answer=${answer:-Y}

if [[ "$answer" =~ ^[Yy]$ ]]; then
    print_orange "Setting execute permissions for .sh and .pl files..."

    # Find and count files before changing permissions
    file_count=$(find . -type f \( -name "*.sh" -o -name "*.pl" \) | wc -l)

    # Set execute permissions for all .sh and .pl files
    find . -type f \( -name "*.sh" -o -name "*.pl" \) -exec chmod a+x {} \;

    print_green "    Execute permissions set for $file_count files"
else
    print_orange "    Skipped setting execute permissions"
fi

################################## 3. install R #################################
if ! command -v R >/dev/null 2>&1; then
    print_green "\n3. R is not installed."
    print_green_no_br "   Would you like to install R (/opt/R/R-4.3.2/bin/R) as Root? [y/N]: "
    read answer
    answer=${answer:-N}

    if [[ "$answer" =~ ^[Yy]$ ]]; then
        print_orange "Installing R 4.3.2... This may take several minutes."

        local tool_dir="R-4.3.2"
        local tool_link="https://cran.rstudio.com/src/base/R-4/R-4.3.2.tar.gz"

        wget "$tool_link" > /dev/null 2>&1 || print_red "    Failed to download R tar file"
        tar -xzvf "$tool_dir.tar.gz" > /dev/null 2>&1 || print_red "    Failed to extract tar file"
        rm "$tool_dir.tar.gz"

        cd "$tool_dir"
        ./configure \
            --prefix="/opt/R/$tool_dir" \
            --enable-R-shlib=yes \
            --enable-memory-profiling \
            --with-blas \
            --with-lapack \
            --with-readline=yes \
            --with-x=no > /dev/null 2>&1 || print_red "    Failed to configure"

        make > /dev/null 2>&1 || print_red "    Failed to make"
        sudo make install > /dev/null 2>&1 || print_red "    Failed to make install"

        sudo ln -sf "/opt/R/$tool_dir/bin/R" /usr/local/bin/R
        sudo ln -sf "/opt/R/$tool_dir/bin/Rscript" /usr/local/bin/Rscript
        cd ..
        rm -rf "$tool_dir"

        print_green "    R successfully installed"
    else
        print_orange "    Skipped R installation"
    fi
else
    print_green "\n3. R is already installed."
fi

################################## 4. install python #################################
if ! command -v python3 >/dev/null 2>&1; then
    print_green "\n4. Python3 is not installed."
    print_green_no_br "   Would you like to install Python3 as Root? [y/N]: "
    read answer
    answer=${answer:-N}

    if [[ "$answer" =~ ^[Yy]$ ]]; then
        print_orange "Installing Python3 and pip..."
        sudo apt -y install python3 > /dev/null 2>&1 || print_red "    Failed to install python3"
        sudo apt -y install python3-pip > /dev/null 2>&1 || print_red "    Failed to install python3-pip"
        print_green "    Python3 successfully installed"
    else
        print_orange "    Skipped Python3 installation"
    fi
else
    print_green "\n4. Python3 is already installed."
fi


################################## 5. compile binary #################################
print_green_no_br "\n5. Would you like to compile PMET and PMETindex binaries? [y/N]:"
if [ true ]; then
    read -p " " answer
    answer=${answer:-N} # Default to 'N' if no input provided
    if [[ "$answer" =~ ^[Yy]$ ]]; then
        if [ -f "scripts/pmetindex" ]; then
            chmod a+x scripts/pmetindex
            chmod a+x scripts/pmet
            chmod a+x scripts/fimo
            while true; do
                print_orange       "  PMET and PMETindex exist."
                print_orange_no_br "  Do you want to recompile PMET and PMETindex? [y/N]: "
                read -p " " recompile
                recompile=${recompile:-N} # Default to 'N' if no input provided
                # 检查用户输入是否为 Y, y, N, 或 n
                if [[ "$recompile" =~ ^[YyNn]$ ]]; then
                    break  # 如果输入有效，跳出循环
                else
                    print_red "    Invalid input. Please enter Y/y for yes or N/n for no."
                fi
            done
        else
            print_red "  PMETindex and PMET not found. Compile will start..."
            recompile=y
        fi

        if [[ "$recompile" =~ ^[Yy]$ ]]; then
            print_orange_no_br "  Do you still want to combile PMET and PMETindex? [y/N]: "
            read -p "" compile_still
        fi
        compile_still=${compile_still:-N}


        if [[ "$recompile" =~ ^[Yy]$ &&  "$compile_still" =~ ^[Yy]$ ]]; then

            print_fluorescent_yellow "Compiling... It takes minutes."

            rm -f scripts/pmetindex
            rm -f scripts/pmetParallel
            rm -f scripts/pmet
            rm -f scripts/fimo

            ############################# 2.1 fimo with pmet index
            print_orange "2.1 Compiling FIMO with PMET homotopic (index) integtated..."
            cd src/meme-5.5.3

            make distclean > /dev/null 2>&1 #|| print_red "    Failed to make distclean"
            aclocal        > /dev/null 2>&1 || print_red "    Failed to aclocal "
            automake       > /dev/null 2>&1 || print_red "    Failed to automake"

            currentDir=$(pwd)
            if [ -d "$currentDir/build" ]; then
                rm -rf "$currentDir/build"
            fi
            mkdir -p $currentDir/build

            chmod a+x ./configure
            ./configure --prefix=$currentDir/build  --enable-build-libxml2 --enable-build-libxslt  > /dev/null 2>&1 || print_red "    Failed to configure"
            make           > /dev/null 2>&1 || print_red "    Failed to make"
            make install   > /dev/null 2>&1 || print_red "    Failed to make install"
            cp build/bin/fimo ../../scripts/
            make distclean > /dev/null 2>&1 || print_red "    Failed to make distclean"
            rm -rf build
            # print_orange "make distclean finished...\n"


            ################################### 2.2 pmetindex
            print_orange "2.2 Compiling PMET homotypic (index) binary..."
            cd ../indexing

            bash build.sh > /dev/null 2>&1
            mv bin/pmetindex ../../scripts/
            rm -rf bin/*

            ################################## 2.3 pmetParallel
            print_orange "2.3 Compiling PMET heterotypic parallel (pair) binary..."
            cd ../pmetParallel

            bash build.sh > /dev/null 2>&1
            mv bin/pmetParallel ../../scripts/
            rm -rf bin/*

            # pmet
            print_orange "2.4 Compiling PMET heterotypic (pair) binary..."
            cd ../pmet

            bash build.sh > /dev/null 2>&1
            mv bin/pmet ../../scripts/
            rm -rf bin/*

            # back to home directory
            cd ../..

            ################### 2.4 Check if the compilation was successful
            exists=""
            not_exists=""

            for file in scripts/pmetindex scripts/pmetParallel scripts/pmet scripts/fimo; do
                if [ -f "$file" ]; then
                    exists="$exists\n    $file"
                else
                    not_exists="$not_exists\n    $file"
                fi
            done

            if [ ! -z "$exists" ]; then
                echo -e "\n"
                print_green "Compilation Success:$exists"
            fi
            if [ ! -z "$not_exists" ]; then
                echo -e "\n"
                print_red "Compilation Failure:$not_exists"
            fi

            ############# 2.5 Give execute permission to all users for the file
            chmod a+x scripts/pmetindex
            chmod a+x scripts/pmetParallel
            chmod a+x scripts/pmet
            chmod a+x scripts/fimo
        fi # if [[ "$recompile" =~ ^[Yy]$ &&  "$compile_still" =~ ^[Yy]$ ]]; then
    else
        print_orange "    No tools compiled"
    fi # if [[ "$answer" =~ ^[Yy]$ ]]; then
fi

############################# 6. install python packages ##############################
if [ true ]; then
    print_green_no_br "\n6. Would you like to install python packages? [y/N]: "
    read -p " " answer
    answer=${answer:-N} # Default to 'N' if no input provided

    if [ "$answer" == "Y" ] || [ "$answer" == "y" ]; then
        print_orange "Installing python packages... It takes minutes."
        pip install numpy     > /dev/null 2>&1 || echo "Failed to install numpy"
        pip install pandas    > /dev/null 2>&1 || echo "Failed to install pandas"
        pip install scipy     > /dev/null 2>&1 || echo "Failed to install scipy"
        pip install bio       > /dev/null 2>&1 || echo "Failed to install bio"
        pip install biopython > /dev/null 2>&1 || echo "Failed to install biopython"
    else
        print_orange "    No python packages installed"
    fi
fi

################################ 7. check needed tools #################################
if [ true ]; then
    print_green "\n7. Checking the execution of GNU Parallel, bedtools, samtools and MEME Suite"
    tools=("parallel --version" "bedtools --version" "samtools --version" "fimo -h") # List of tools and their version check commands
    missing_tools=()  # Initialize an empty array to store tools that cannot be executed
    all_tools_found=true

    # Iterate over each tool and check if it can be executed
    for tool in "${tools[@]}"; do
        # Use 'command -v' to check if the tool command is available in the PATH
        if ! command -v $tool &> /dev/null; then
            echo "    $tool could not be found"
            all_tools_found=false
            missing_tools+=($tool)  # Add the tool to the missing tools array
        fi
    done

    # If all tools were found, print a positive message
    if $all_tools_found; then
        print_orange "    All tools were found!"
    else
        print_fluorescent_yellow_no_br "Would you like to install missing tools? [Y/n]: "
        read -p " " answer
        answer=${answer:-Y} # Default to 'N' if no input provided

        if [ "$answer" == "Y" ] || [ "$answer" == "y" ]; then
            # Install the missing tools
            for tool in "${missing_tools[@]}"; do
                if [ "$tool" == "parallel" ]; then
                    if [[ "$(uname)" == "Darwin" ]]; then
                        brew install parallel > /dev/null 2>&1 || print_red "    Failed to install bedtools"
                    elif [[ -f /etc/os-release ]]; then
                        . /etc/os-release
                        case $ID in
                            centos|fedora|rhel)
                                yum install parallel  > /dev/null 2>&1 || print_red "    Failed to install bedtools"
                                ;;
                            debian|ubuntu)
                                sudo apt update               > /dev/null 2>&1 || print_red "    Failed to apt update"
                                sudo apt -y install parallel  > /dev/null 2>&1 || print_red "    Failed to install bedtools"
                                ;;
                            *)
                                echo "Unsupported Linux distribution"
                                ;;
                        esac
                        parallel --citation              > /dev/null 2>&1 || print_red "    Failed to run parallel --citation"
                    else
                        echo "Unsupported OS"
                    fi
                fi

                if [ "$tool" == "bedtools" ]; then
                    if [[ "$(uname)" == "Darwin" ]]; then
                        brew install bedtools > /dev/null 2>&1 || print_red "    Failed to install bedtools"
                    elif [[ -f /etc/os-release ]]; then
                        . /etc/os-release
                        case $ID in
                            centos|fedora|rhel)
                                yum install BEDTools  > /dev/null 2>&1 || print_red "    Failed to install bedtools"
                                ;;
                            debian|ubuntu)
                                sudo apt update               > /dev/null 2>&1 || print_red "    Failed to apt update"
                                sudo apt -y install bedtools  > /dev/null 2>&1 || print_red "    Failed to install bedtools"
                                ;;
                            *)
                                echo "Unsupported Linux distribution"
                                ;;
                        esac
                    else
                        echo "Unsupported OS"
                    fi
                fi

                if [ "$tool" == "samtools" ]; then
                    print_green_no_br "\n1. Would you like to install samtools (~/tools/samtools-1.17/)? [y/N]: "
                    read -p "" answer
                    answer=${answer:-Y} # Default to 'Y' if no input provided

                    if [ "$answer" == "Y" ] || [ "$answer" == "y" ]; then
                        # 创建 ~/tools 目录，如果运行脚本的用户不是 shiny，则需要修改路径
                        mkdir -p ~/tools

                        tool_dir=samtools-1.17
                        tool_link=https://github.com/samtools/samtools/releases/download/1.17/samtools-1.17.tar.bz2

                        # 下载并解压 samtools
                        wget $tool_link -O $tool_dir.tar.bz2 > /dev/null 2>&1 || echo "    Failed to download samtools tar file"
                        tar -xjf $tool_dir.tar.bz2           > /dev/null 2>&1 || echo "    Failed to unzip tar file"
                        rm $tool_dir.tar.bz2

                        # 进入 samtools 目录并编译
                        cd $tool_dir && mkdir -p build
                        ./configure --prefix=$(pwd)/build    > /dev/null 2>&1 || echo "    Failed to configure"
                        make                                 > /dev/null 2>&1 || echo "    Failed to make"
                        sudo make install                    > /dev/null 2>&1 || echo "    Failed to make install"

                        # 返回到原始目录并将 samtools 目录移动到 ~/tools 下
                        cd ..
                        mv $tool_dir ~/tools/

                        # 更新 ~/.bashrc 和 ~/.zshrc，添加 samtools 到 PATH
                        echo "export PATH=~/tools/$tool_dir/build/bin:\$PATH" >> ~/.bashrc
                        echo "export PATH=~/tools/$tool_dir/build/bin:\$PATH" >> ~/.zshrc
                        echo "export PATH=~/tools/$tool_dir/build/bin:\$PATH" >> ~/.bash_profile
                        sudo chown -R shiny:shiny-apps ~/tools/$tool_dir/build/
                        print_green "    samtools successfully installed"
                    else
                        print_red "    Please install samtools later!"
                    fi # if [ "$answer" == "Y" ] || [ "$answer" == "y" ]; then
                fi # if [ "$tool" == "samtools" ]; then

                if [ "$tool" == "fimo" ]; then
                    print_green_no_br "\n1. Would you like to install MEME suite (~/tools/meme-5.5.2/)? [y/N]: "
                    read -p "" answer
                    answer=${answer:-Y} # Default to 'Y' if no input provided

                    if [ "$answer" == "Y" ] || [ "$answer" == "y" ]; then
                        mkdir -p ~/tools

                        tool_dir=meme-5.5.2
                        tool_link=https://meme-suite.org/meme/meme-software/5.5.2/meme-5.5.2.tar.gz

                        wget $tool_link           > /dev/null 2>&1 || print_red "    Failed to download fimo tar file"
                        tar zxf meme-5.5.2.tar.gz > /dev/null 2>&1 || print_red "    Failed to unzip tar file"
                        rm meme-5.5.2.tar.gz

                        # 进入 samtools 目录并编译
                        cd $tool_dir && mkdir -p build
                        ./configure                \
                            --prefix=$(pwd)/build  \
                            --enable-build-libxml2 \
                            --enable-build-libxslt > /dev/null 2>&1 || echo "    Failed to install configure"
                        make                       > /dev/null 2>&1 || print_red "    Failed to make"
                        make install               > /dev/null 2>&1 || print_red "    Failed to make install"

                        cd ..
                        mv $tool_dir ~/tools/

                        echo "export PATH=~/tools/$tool_dir/build/bin:\$PATH"                >> ~/.bashrc
                        echo "export PATH=~/tools/$tool_dir/build/bin:\$PATH"                >> ~/.zshrc
                        echo "export PATH=~/tools/$tool_dir/build/bin:\$PATH"                >> ~/.bash_profile
                        echo "export PATH=~/tools/$tool_dir/build/libexec/meme-5.5.2:\$PATH" >> ~/.bashrc
                        echo "export PATH=~/tools/$tool_dir/build/libexec/meme-5.5.2:\$PATH" >> ~/.zshrc
                        echo "export PATH=~/tools/$tool_dir/build/libexec/meme-5.5.2:\$PATH" >> ~/.bash_profile
                        sudo chown -R shiny:shiny-apps ~/tools/$tool_dir/build/
                        print_green "    MEME Suite successfully installed"
                    else
                        print_red "    Please install MEME suite later!"
                    fi # if [ "$answer" == "Y" ] || [ "$answer" == "y" ]; then
                fi # # if [ "$tool" == "fimo" ]; then
            done
        fi
    fi
fi

################################## 8. install R packages #################################
if [ true ]; then
    # 检查 R 是否已安装
    if command -v R >/dev/null 2>&1; then
        print_green_no_br "8. Would you like to install R packages? [y/N]: "
        # read -p "Would you like to install R packages? [y/N]: " answer
        read -p "" answer
        answer=${answer:-N} # Default to 'N' if no input provided

        if [ "$answer" == "Y" ] || [ "$answer" == "y" ]; then
            # 使用 R 脚本检查 rJava 是否已安装
            if ! Rscript -e "if (!requireNamespace('rJava', quietly = TRUE)) {quit(status = 1)}"; then
                # echo "rJava is not installed. Installing..."
                # 重新配置 Java 环境
                sudo R CMD javareconf                                         > /dev/null 2>&1
                curl -LO https://rforge.net/rJava/snapshot/rJava_1.0-6.tar.gz > /dev/null 2>&1
                tar fxz rJava_1.0-6.tar.gz                                    > /dev/null 2>&1
                R CMD INSTALL rJava                                           > /dev/null 2>&1 || print_red "    Failed to install rJava"
                rm rJava_1.0-6.tar.gz
                rm -rf rJava
            fi

            print_orange "Installing R packages... It takes minutes..."
            chmod a+x scripts/r/install_packages.R
            # Rscript R/utils/install_packages.R
            Rscript scripts/r/install_packages.R 2>&1 | tee log_R_packages_installation.log | grep -E "\* DONE \("
            awk '/The installed packages are as follows:/{flag=1} flag' log_R_packages_installation.log
        else
            print_orange "    No R packages installed"
        fi
    else
        print_red                "\n7. No R packages installed because there is no R installed."
        print_fluorescent_yellow "    Run 'scripts/r/install_packages.R' to install R packages later. "
    fi # if command -v R >/dev/null 2>&1; then
fi

print_green "\nDONE"
