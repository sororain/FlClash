#!/usr/bin/env bash
# ============================================================================
# Sororain — Linux VM 从零到发布的产线脚本（Ubuntu 24.04 LTS 起）
#
# 本脚本自动处理以下几类「跨 LTS 版本漂移」问题，无需手工干预：
#   · 仓库从 Windows 拷贝导致的 shell 脚本 CRLF 换行 / 缺可执行位
#   · 新版 clang 对第三方 pub 插件报更严格警告，叠加 Linux 模板的 -Werror
# （rpm >= 4.20 包专属 %builddir 的兼容修复已在自有 fork 中完成，见 setup.dart）
# 仍可能随系统/上游变化而需手工介入的：apt 包名更名、Go 与 Flutter 的最低版本要求、
# 以及 flutter_distributor 上游源码结构变动（届时 step7 会打印修补失败告警）。
#
# 用法（在 Linux 实机/虚拟机中，进入项目根目录执行）:
#   bash build_linux_vm.sh            依次全自动执行步骤 1..7
#   bash build_linux_vm.sh 3          只单独执行某一步
# 产物: dist/Sororain-<版本>-linux-amd64.{deb,AppImage,rpm}
# 建议磁盘 >= 40GB、内存 >= 8GB；脚本幂等，失败可重复执行。
#
# 步骤: 1 apt 依赖  2 Flutter  3 Go  4 Rust  5 仓库准备  6 pub+core  7 打包
# ----------------------------------------------------------------------------
set -euo pipefail
STEP="${1:-all}"

FLUTTER_VER="${FLUTTER_VER:-3.44.9}"   # ★ 硬锁，禁止升到 3.47.x
# Go 版本与 build_env_checklist.txt 记录的参考版本保持一致
GO_VER="${GO_VER:-1.26.5}"
# 官方 sha256，取自 https://go.dev/dl/?mode=json&include=all
# （注意 go.dev/dl/<file>.sha256 返回的是 HTML 跳转页，不是哈希值）
# 下面这组只对应 GO_SHA256_VER；用 GO_VER= 覆盖成其他版本时会自动跳过校验。
GO_SHA256_VER="1.26.5"
GO_SHA256_AMD64="5c2c3b16caefa1d968a94c1daca04a7ca301a496d9b086e17ad77bb81393f053"
GO_SHA256_ARM64="fe4789e92b1f33358680864bbe8704289e7bb5fc207d80623c308935bd696d49"

has() { command -v "$1" >/dev/null 2>&1; }

# 幂等写入 PATH 行到 .bashrc（原脚本 Flutter/Go 两处行为不一致，这里统一）
add_path_line() {
  local line="$1"
  grep -qF "$line" "$HOME/.bashrc" 2>/dev/null || echo "$line" >> "$HOME/.bashrc"
}

# 把已知的工具链目录补进当前进程的 PATH。
# 单独执行某一步时不会读取 .bashrc，若不补会出现
# "/bin/sh: 1: go: not found" 之类的失败（setup.dart 用 sh -c 调 go build）。
ensure_paths() {
  local d
  for d in "$HOME/flutter/bin" "$HOME/.cargo/bin" "/usr/local/go/bin"; do
    [ -d "$d" ] || continue
    case ":$PATH:" in
      *":$d:"*) ;;
      *) export PATH="$d:$PATH" ;;
    esac
  done
}

# 预取 sudo 凭证：setup.dart 内部会自行 sudo 安装 libfuse2、放置 appimagetool，
# 凭证过期会在打包中途弹密码提示，破坏“全自动”。
require_sudo() {
  if ! sudo -v; then
    echo "  ✗ 需要 sudo 权限，请先在终端执行一次 sudo -v"
    exit 1
  fi
}

preflight() {
  echo "== [0/7] 环境预检 =="
  local avail_gb mem_gb
  avail_gb=$(df -Pk . | awk 'NR==2 {print int($4/1048576)}')
  mem_gb=$(awk '/MemTotal/ {print int($2/1048576)}' /proc/meminfo)
  [ "${avail_gb:-0}" -ge 40 ] || echo "  ⚠ 可用磁盘 ${avail_gb}GB < 40GB，构建可能失败"
  [ "${mem_gb:-0}" -ge 8 ] || echo "  ⚠ 内存 ${mem_gb}GB < 8GB，Go/链接阶段可能 OOM"
  echo "  磁盘 ${avail_gb}GB / 内存 ${mem_gb}GB"
  require_sudo
}

step1_apt() {
  echo "== [1/7] apt 依赖（update + 安装）=="
  require_sudo
  sudo DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a apt update
  # pkg-config / liblzma-dev：Flutter Linux 官方依赖清单
  # wget：步骤 3 下载 Go，且 setup.dart 出 AppImage 时内部也调用 wget
  sudo DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a apt install -y \
    cmake build-essential clang \
    ninja-build pkg-config libgtk-3-dev liblzma-dev \
    libayatana-appindicator3-dev \
    libkeybinder-3.0-dev \
    locate \
    rpm patchelf \
    wget curl xz-utils zip unzip git file
}

step2_flutter() {
  echo "== [2/7] Flutter ${FLUTTER_VER}（若未装）=="
  if ! has flutter; then
    has git || { echo "  ✗ 缺少 git，请先执行步骤 1"; exit 1; }
    if [ -d "$HOME/flutter" ] && [ ! -x "$HOME/flutter/bin/flutter" ]; then
      # 只清理确有 Flutter 痕迹的目录，避免误删用户其他内容
      if [ -d "$HOME/flutter/.git" ]; then
        echo "  清理不完整的 $HOME/flutter"
        rm -rf "$HOME/flutter"
      else
        echo "  ✗ $HOME/flutter 已存在且不像是 Flutter 目录，请手动处理后重跑"
        exit 1
      fi
    fi
    if [ -x "$HOME/flutter/bin/flutter" ]; then
      echo "  发现 $HOME/flutter 下已有 Flutter，直接启用"
    else
      git clone -b "$FLUTTER_VER" --depth 1 https://github.com/flutter/flutter.git "$HOME/flutter"
    fi
    export PATH="$HOME/flutter/bin:$PATH"
  fi
  add_path_line 'export PATH="$HOME/flutter/bin:$PATH"'

  # 全新克隆首次运行会先下载 Dart SDK、构建 flutter_tools，其间输出的是进度文本。
  # 必须先完整跑一遍完成引导，否则版本检测会读到进度行而误判。
  echo "  首次引导（下载 Dart SDK / 构建 flutter_tools），可能需要几分钟..."
  if ! flutter --version >/dev/null 2>&1; then
    echo "  ✗ flutter 引导失败，请手动执行 flutter --version 查看具体报错"
    exit 1
  fi

  # ★ 版本校验：3.47.x 的 Windows 引擎有崩溃 bug；pubspec 要求 Dart >= 3.8.0
  # 只认行首的 "Flutter x.y.z"，避免误取 Dart / DevTools 的版本号
  local ver_out cur
  ver_out=$(flutter --version 2>/dev/null || true)
  cur=$(printf '%s\n' "$ver_out" | sed -nE 's/^Flutter ([0-9]+\.[0-9]+\.[0-9]+).*/\1/p' | head -1)
  if [ "$cur" != "$FLUTTER_VER" ]; then
    echo "  ✗ 当前 Flutter 版本 ${cur:-未知} != 锁定版本 ${FLUTTER_VER}"
    echo "    请将 PATH 中的 Flutter 换成 ${FLUTTER_VER}，或删掉旧 SDK 后重跑本步"
    echo "    flutter --version 实际输出："
    printf '%s\n' "$ver_out" | sed 's/^/      /'
    exit 1
  fi
  echo "  Flutter 版本校验通过: $cur"

  flutter config --enable-linux-desktop
  flutter --version
}

step3_go() {
  echo "== [3/7] Go ${GO_VER} =="

  # 已装版本 >= GO_VER 才跳过；低于目标版本时执行升级
  # （只用 `has go` 判断会导致旧版本永远不会被升级）
  local need_install=1 cur=""
  if has go; then
    cur=$(go version 2>/dev/null | sed -nE 's/.*go([0-9]+\.[0-9]+(\.[0-9]+)?).*/\1/p' | head -1)
    if [ -n "$cur" ] && [ "$(printf '%s\n%s\n' "$GO_VER" "$cur" | sort -V | head -1)" = "$GO_VER" ]; then
      need_install=0
      echo "  已安装 go${cur}（>= ${GO_VER}），跳过"
    else
      echo "  已安装 go${cur:-未知}，升级到 ${GO_VER}"
    fi
  fi

  if [ "$need_install" -eq 1 ]; then
    has wget || { echo "  ✗ 缺少 wget，请先执行步骤 1"; exit 1; }

    # 按主机架构选包（原脚本硬编码 amd64，arm64 主机会装错架构）
    local arch
    case "$(uname -m)" in
      x86_64)        arch=amd64 ;;
      aarch64|arm64) arch=arm64 ;;
      *) echo "  ✗ 不支持的架构: $(uname -m)"; exit 1 ;;
    esac

    # 官方 sha256 只覆盖 GO_SHA256_VER；用 GO_VER 覆盖成其他版本时跳过校验
    local sha_expected=""
    if [ "$GO_VER" = "$GO_SHA256_VER" ]; then
      [ "$arch" = "amd64" ] && sha_expected="$GO_SHA256_AMD64"
      [ "$arch" = "arm64" ] && sha_expected="$GO_SHA256_ARM64"
    fi

    local pkg="go${GO_VER}.linux-${arch}.tar.gz"
    wget -q "https://go.dev/dl/${pkg}" -O /tmp/go.tgz

    if [ -n "$sha_expected" ]; then
      local got
      got=$(sha256sum /tmp/go.tgz | awk '{print $1}')
      if [ "$got" != "$sha_expected" ]; then
        echo "  ✗ Go 压缩包 sha256 校验失败"
        echo "    expected: $sha_expected"
        echo "    actual:   $got"
        exit 1
      fi
      echo "  sha256 校验通过"
    else
      echo "  ⚠ 非默认 GO_VER，跳过 sha256 校验"
    fi

    # 整目录替换：旧版残留会让 go 命令与 GOROOT 不一致
    sudo rm -rf /usr/local/go
    sudo tar -C /usr/local -xzf /tmp/go.tgz
    add_path_line 'export PATH=$PATH:/usr/local/go/bin'
    export PATH=$PATH:/usr/local/go/bin
  fi
  go version
}

step4_rust() {
  echo "== [4/7] Rust（rustup，若未装）=="
  # plugins/rust_api 在 Linux 上是构建期由 cargokit 现编 librust_api.so，
  # 且 cargokit 硬依赖 rustup（见 cargokit/build_tool/lib/src/util.dart:
  #   RustupNotFoundException -> "rustup not found in PATH"）。
  # 只装 apt 的 cargo 包不够——cargokit 会调用 rustup toolchain/target。
  if ! has rustup; then
    has curl || { echo "  ✗ 缺少 curl，请先执行步骤 1"; exit 1; }
    echo "  安装 rustup（--no-modify-path：PATH 由本脚本统一管理）"
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path
  fi
  if [ -f "$HOME/.cargo/env" ]; then
    # shellcheck disable=SC1091
    . "$HOME/.cargo/env"
  fi
  export PATH="$HOME/.cargo/bin:$PATH"
  add_path_line 'export PATH="$HOME/.cargo/bin:$PATH"'
  rustup --version
  cargo --version
}

step5_repo() {
  echo "== [5/7] 仓库准备（脚本权限/换行 + CMake 兼容 + 子模块）=="

  # 1) 本仓库若来自 Windows 拷贝，shell 脚本会带 CRLF 换行、且丢失可执行位。
  #    带 \r 的 shebang 在 Linux 上会报 "bash\r: No such file or directory"。
  #    构建期由 CMake 直接调用的插件脚本首当其冲：
  #      plugins/setup/buildkit/run_build_tool.sh    (Go 内核 + 资源)
  #      plugins/rust_api/cargokit/run_build_tool.sh (Rust FFI)
  #    android/gradlew 缺执行位则 Android 构建会失败。
  local f changed=0
  while IFS= read -r f; do
    if grep -q $'\r' "$f" 2>/dev/null; then
      sed -i 's/\r$//' "$f"
      echo "  修正 CRLF: $f"
      changed=1
    fi
    if [ ! -x "$f" ]; then
      chmod +x "$f"
      echo "  补执行位: $f"
      changed=1
    fi
  done < <(
    find plugins -name '*.sh' -type f 2>/dev/null
    if [ -f android/gradlew ]; then echo android/gradlew; fi
  )
  if [ "$changed" -eq 0 ]; then
    echo "  脚本换行符与执行权限正常"
  fi

  # 2) Ubuntu 24.04+ 的 clang 对第三方插件代码报出更严格的警告
  #    （deprecated-declarations / sometimes-uninitialized 等），
  #    Linux 模板默认的 -Werror 会把它变成硬错误，而这些 pub 插件源码
  #    无法在本地修补。这里只降级 -Werror，保留 -Wall。
  if [ -f linux/CMakeLists.txt ] &&
     grep -q 'PRIVATE -Wall -Werror' linux/CMakeLists.txt; then
    sed -i 's/PRIVATE -Wall -Werror/PRIVATE -Wall/' linux/CMakeLists.txt
    echo "  已移除 linux/CMakeLists.txt 中的 -Werror"
  fi

  # 3) 子模块：本目录可能是直接拷贝的目录而非 git 检出（无 .git / .gitmodules），
  #    此时 git submodule 会 fatal 退出。只要 ClashMeta 源码已在位就跳过。
  has git || { echo "  ✗ 缺少 git，请先执行步骤 1"; exit 1; }
  local top
  top=$(git rev-parse --show-toplevel 2>/dev/null || true)
  if [ "${top:-}" != "$(pwd -P)" ]; then
    if [ -e core/Clash.Meta/go.mod ]; then
      echo "  ⚠ 当前目录不是 git 仓库根目录，跳过子模块更新"
      echo "    core/Clash.Meta 源码已就位，Go 构建可直接使用"
      return 0
    fi
    echo "  ✗ 非 git 仓库且 core/Clash.Meta 缺失"
    echo "    请用 git clone 获取完整仓库（含子模块）后再构建"
    exit 1
  fi
  git submodule update --init --recursive
}

step6_pub() {
  echo "== [6/7] flutter pub get + 品牌同步 + Go core/manifest =="
  flutter pub get
  # 先只编 core 作为快速失败检查点；步骤 7 的 --out app 内部会再编一次 core
  dart setup.dart linux --out core
}

step7_build() {
  echo "== [7/7] 打包 deb + appimage + rpm =="
  require_sudo

  # rpm >= 4.20 包专属 %builddir 的兼容修复，已并入自有 fork
  # （sororain/flutter_distributor @ v0.6.11-sororain.1，由 setup.dart 激活），
  # 所以这里不再需要在运行时修补第三方源码。
  dart setup.dart linux --out app
  echo "---- 产物 ----"
  ls -lh dist/ 2>/dev/null || true
}

# 无论单独执行哪一步，都先补齐工具链 PATH，
# 使每个步骤都能独立运行、不依赖 .bashrc 是否已生效。
ensure_paths

case "$STEP" in
  0) preflight ;;
  1) step1_apt ;;
  2) step2_flutter ;;
  3) step3_go ;;
  4) step4_rust ;;
  5) step5_repo ;;
  6) step6_pub ;;
  7) step7_build ;;
  all)
    preflight
    step1_apt
    step2_flutter
    step3_go
    step4_rust
    step5_repo
    step6_pub
    step7_build
    ;;
  *) echo "usage: bash build_linux_vm.sh [0..7|all]"; exit 1 ;;
esac
