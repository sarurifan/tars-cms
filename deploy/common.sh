
# ================================================================
# common.sh — tars-cms 部署脚本公共库（被各 n0X 脚本 source）
#
# 作用：把「干净机可移植性」相关的取值逻辑集中到一处：
#   1. TARS ticket 获取（多级回退，不再硬依赖 c03-deploy-chisha.sh）
#   2. 网关地址 / 节点 IP / 构建目录（全部可用环境变量覆盖）
#   3. 统一的日志与断言函数
#
# 用法：在各脚本 env.sh 加载之后 source 本文件
#   _COMMON_SH="$(cd "$(dirname "$0")" && pwd)/common.sh"
#   [ -f "$_COMMON_SH" ] && . "$_COMMON_SH"
# ================================================================

# ── 目录（可用环境变量覆盖，默认沿用 /docker/tars）──
export CMS_BASE_DIR="${CMS_BASE_DIR:-/docker/tars}"
export CMS_BUILD_DIR="${CMS_BUILD_DIR:-$CMS_BASE_DIR/build/tars-cms}"
export CMS_SCRIPTS_DIR="${CMS_SCRIPTS_DIR:-$CMS_BASE_DIR/scripts}"

# ── 仓库根目录（common.sh 位于 deploy/，父目录即仓库根）──
# 用于替代脚本里的硬编码 /root/tars-cms（换机/换路径自动适配）
_CMS_COMMON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
if [ -n "${_CMS_COMMON_DIR:-}" ]; then
  export CMS_REPO_DIR="${CMS_REPO_DIR:-$(cd "$_CMS_COMMON_DIR/.." && pwd)}"
fi

# ── 网络 ──
# CMS_GATEWAY 优先（env.sh 可配）；否则按本机 IP 拼
if [ -z "${CMS_GATEWAY:-}" ]; then
  _LOCAL_IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
  export CMS_GATEWAY="http://${_LOCAL_IP:-127.0.0.1}:8200"
fi
export CMS_GW_PORT="${CMS_GW_PORT:-8200}"

# ── 容器名（可用环境变量覆盖）──
export CMS_MYSQL_CTN="${CMS_MYSQL_CTN:-tars-mysql}"
export CMS_FW_CTN="${CMS_FW_CTN:-tars-framework}"
export CMS_NODE_CTN="${CMS_NODE_CTN:-tars-node}"

# ── TARS 节点 IP（tarsnode 容器地址）──
if [ -z "${CMS_NODE_IP:-}" ]; then
  CMS_NODE_IP="$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' \
    "${CMS_NODE_CTN}" 2>/dev/null | head -1 || true)"
  export CMS_NODE_IP="${CMS_NODE_IP:-172.25.0.5}"
fi

# ── TarsWeb 管理端地址（容器内访问）──
export CMS_WEB_API="${CMS_WEB_API:-http://127.0.0.1:3000/pages/server/api}"

# ── GatewayWebServer API 地址（动态路由管理）──
# 自动探测 tars-framework 容器 IP；可用 CMS_GW_WEB_API 覆盖。
if [ -z "${CMS_GW_WEB_API:-}" ]; then
  _GW_FW_IP="$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "${CMS_FW_CTN}" 2>/dev/null | head -1 || true)"
  export CMS_GW_WEB_API="http://${_GW_FW_IP:-172.25.0.3}:${CMS_GW_WEB_PORT:-15535}/plugins/base/gateway/api"
fi
export CMS_GW_WEB_PORT="${CMS_GW_WEB_PORT:-15535}"

# ── 日志函数（若调用方已定义则不覆盖）──
if ! declare -F ok >/dev/null 2>&1; then
  C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_RED=$'\033[31m'; C_END=$'\033[0m'
  ok()   { echo "${C_GREEN}✔ $1${C_END}"; }
  warn() { echo "${C_YELLOW}⚠ $1${C_END}"; }
  err()  { echo "${C_RED}✘ $1${C_END}" >&2; }
fi

# ── TARS ticket 获取（多级回退）──
# 优先级：env.sh 的 TARS_TICKET > c03-deploy-chisha.sh（兼容旧环境）
# 干净机上请先跑 n00-get-token.sh 写入 env.sh
tars_ticket() {
  if [ -n "${TARS_TICKET:-}" ]; then
    printf '%s' "$TARS_TICKET"; return 0
  fi
  local f="$CMS_SCRIPTS_DIR/c03-deploy-chisha.sh"
  if [ -f "$f" ]; then
    local t; t="$(grep '^TOKEN=' "$f" | cut -d'"' -f2)"
    if [ -n "$t" ]; then printf '%s' "$t"; return 0; fi
  fi
  return 1
}

# 取 ticket，失败则明确报错并提示跑 n00
require_ticket() {
  local t
  if ! t="$(tars_ticket)"; then
    err "无法获取 TARS ticket（干净机请先跑: bash deploy/n00-get-token.sh）" >&2
    exit 1
  fi
  printf '%s' "$t"
}

# ── mysql 快捷执行（走容器）──
cms_mysql() {
  docker exec "$CMS_MYSQL_CTN" mysql -uroot -p"${CMS_DB_PASS}" "$@" 2>/dev/null
}

# ── 坑3：把 cms 运行环境写进 tars-node 容器的 /etc/profile.d/cms-env.sh ──
# CmsServer 的 tars_start.sh、CmsWeb/CmsBff 的包装脚本都依赖该文件取
# CMS_DB_PASS / CMS_UPLOAD_DIR 等。全新机上该文件不存在 → 服务起不来报
# "环境变量未设置"。必须在 n03/n06/n09 发布前调用本函数（幂等，可反复跑）。
init_node_env() {
  local ctn="${CMS_NODE_CTN:-tars-node}"
  docker inspect "$ctn" >/dev/null 2>&1 || { warn "init_node_env: 容器 $ctn 不存在，跳过"; return 0; }
  # 幂等：已存在且内容与期望一致则跳过（避免每次重复写）
  local want_pass="${CMS_DB_PASS:-tars@root.2026}"
  local cur
  cur=$(docker exec "$ctn" sh -c 'cat /etc/profile.d/cms-env.sh 2>/dev/null' || true)
  if echo "$cur" | grep -q "CMS_DB_PASS=$want_pass" && echo "$cur" | grep -q 'CMS_DB_NAME'; then
    ok "init_node_env: /etc/profile.d/cms-env.sh 已就绪"
    return 0
  fi
  docker exec -i "$ctn" sh -c "mkdir -p /etc/profile.d && cat > /etc/profile.d/cms-env.sh" <<EOF
# tars-cms 运行环境变量（init_node_env 写入，幂等）
export CMS_DB_HOST=${CMS_DB_HOST:-172.25.0.2}
export CMS_DB_PORT=${CMS_DB_PORT:-3306}
export CMS_DB_USER=${CMS_DB_USER:-root}
export CMS_DB_PASS=${want_pass}
export CMS_DB_NAME=${CMS_DB_NAME:-tars_cms}
export CMS_UPLOAD_DIR=${CMS_UPLOAD_DIR:-/data/tars/cms/uploads}
EOF
  docker exec "$ctn" chmod 600 /etc/profile.d/cms-env.sh 2>/dev/null || true
  # 校验写进去了
  if docker exec "$ctn" sh -c 'grep -q CMS_DB_PASS /etc/profile.d/cms-env.sh' 2>/dev/null; then
    ok "init_node_env: 已写入 $ctn:/etc/profile.d/cms-env.sh (600)"
  else
    err "init_node_env: 写入 $ctn:/etc/profile.d/cms-env.sh 失败" >&2
    return 1
  fi
}

# ── 坑2：patch_tars 后确保发布包真的解进了 bin/ ──
# 实测全新机坑：patch_tars 返回成功，但 tarsnode 有时不解压，
#   bin/ 只剩 tarsnode 生成的 tars_start.sh/tars_stop.sh，二进制缺失 → 启动
#   报 "find server exe 找不到"。本函数在 patch 后校验 bin/ 是否有可执行文件，
#   没有则从 BatchPatchingLoad 缓存的 tgz 手动解到 bin/。
# 用法: ensure_pkg_extracted <app.server> <server> <bin_name>
#   例: ensure_pkg_extracted cms.CmsServer CmsServer CmsServer
#       ensure_pkg_extracted cms.CmsWeb    CmsWeb    CmsWeb_bin
# 返回 0 = bin/ 已有可执行文件（或补解成功）；非 0 = 仍缺（调用方应报错）。
ensure_pkg_extracted() {
  local appsvr="$1" svr="$2" binname="${3:-$2}"
  local ctn="${CMS_NODE_CTN:-tars-node}"

  # 全新机与旧机的 tarsnode 数据目录路径不同，探测式兼容：
  #   全新机: /data/tars/tarsnode-data
  #   旧机 (.95): /usr/local/app/tars/tarsnode/data
  # 找「实际存着 <app.server>/bin 的基目录」为准（两路径可能互为挂载，任一存在即可）。
  local base=""
  for cand in /data/tars/tarsnode-data /usr/local/app/tars/tarsnode/data; do
    if docker exec "$ctn" sh -c "[ -d '$cand/$appsvr' ]" 2>/dev/null; then
      base="$cand"; break
    fi
  done
  if [ -z "$base" ]; then
    for cand in /data/tars/tarsnode-data /usr/local/app/tars/tarsnode/data; do
      docker exec "$ctn" sh -c "[ -d '$cand' ]" 2>/dev/null && { base="$cand"; break; }
    done
  fi
  [ -n "$base" ] || { err "ensure_pkg_extracted: 找不到 tarsnode 数据目录"; return 1; }
  local bindir="$base/${appsvr}/bin"
  local tgz="$base/tmp/download/BatchPatchingLoad/${appsvr}/${appsvr}.tgz"

  # 已含目标可执行文件则直接返回
  if docker exec "$ctn" sh -c "[ -f '$bindir/$binname' ] || ls '$bindir' | grep -qE 'bin$|${svr}'" 2>/dev/null \
     && docker exec "$ctn" sh -c "test -n \"\$(ls -A '$bindir' 2>/dev/null | grep -vE 'tars_(start|stop)\.sh')\"" 2>/dev/null; then
    ok "ensure_pkg_extracted: $appsvr/bin 已含发布文件"
    return 0
  fi

  warn "ensure_pkg_extracted: $appsvr/bin 缺二进制（全新机 tarsnode 未自动解压），手动解包..."
  docker exec "$ctn" sh -c "[ -f '$tgz' ]" 2>/dev/null \
    || { err "ensure_pkg_extracted: 找不到源包 $tgz"; return 1; }

  # tgz 顶层是 <Server>/，解到临时目录再铺进 bin/（二进制+tars_start/stop 平铺）
  docker exec "$ctn" sh -c "
    set -e
    tmp=\$(mktemp -d)
    tar -xzf '$tgz' -C \"\$tmp\"
    cp -a \"\$tmp/${svr}/.\" '$bindir/'
    chmod +x '$bindir/'* 2>/dev/null || true
    rm -rf \"\$tmp\"
  " 2>&1 || { err "ensure_pkg_extracted: 手动解包失败"; return 1; }

  if docker exec "$ctn" sh -c "test -n \"\$(ls -A '$bindir' 2>/dev/null | grep -vE 'tars_(start|stop)\.sh')\"" 2>/dev/null; then
    ok "ensure_pkg_extracted: 已手动解包到 $appsvr/bin"
    docker exec "$ctn" sh -c "ls -la '$bindir'" 2>/dev/null | sed 's/^/    /'
    return 0
  else
    err "ensure_pkg_extracted: 解包后 bin/ 仍为空" >&2
    return 1
  fi
}

# ── 坑4：工具链自动安装（go/node/npm/git）──
# 全新机没有 go/node 时，deploy.sh 前置检查会直接报"缺少依赖"退出。
# 本函数自动从 toolchain/ 目录（离线包自带）或本地缓存找安装包装好，
# 装到 /usr/local，写 /etc/profile.d，并 export 到当前会话 PATH。
# 返回 0 = 依赖就绪；非 0 = 仍缺（调用方应报错）。

# 解包到目标目录（非 root 自动 sudo；/usr/local 默认 root 属主）
_install_tarball() {
  local pkg="$1" dest="$2"
  if [ "$(id -u)" -eq 0 ]; then
    tar -C "$dest" -xzf "$pkg"
  else
    sudo tar -C "$dest" -xzf "$pkg"
  fi
}
ensure_toolchain() {
  local missing=()
  for c in docker git; do
    command -v "$c" >/dev/null 2>&1 || missing+=("$c")
  done
  if [ ${#missing[@]} -gt 0 ]; then
    err "ensure_toolchain: 系统依赖缺失: ${missing[*]}（请先安装）" >&2
    return 1
  fi

  # go
  if ! command -v go >/dev/null 2>&1; then
    local gopkg=""
    # 候选：deploy/toolchain/、仓库 toolchain/、离线包 toolchain/、/tmp
    for cand in "$CMS_REPO_DIR/deploy/toolchain"/go*.tar.gz "$CMS_REPO_DIR/toolchain"/go*.tar.gz /docker/offline-pack/toolchain/go*.tar.gz /tmp/go*.tar.gz; do
      [ -f "$cand" ] && { gopkg="$cand"; break; }
    done
    if [ -z "$gopkg" ]; then
      err "ensure_toolchain: 缺 go 且找不到 go*.tar.gz（放 deploy/toolchain/ 或离线包 toolchain/）" >&2
      return 1
    fi
    warn "ensure_toolchain: 安装 go from $gopkg ..."
    # 干净安装：先清旧 /usr/local/go（tar 覆盖非 root 属主会大量冲突/半覆盖）
    if [ -d /usr/local/go ]; then
      rm -rf /usr/local/go 2>/dev/null || sudo rm -rf /usr/local/go 2>/dev/null || true
    fi
    _install_tarball "$gopkg" /usr/local || { err "ensure_toolchain: go 解包失败" >&2; return 1; }
    # 写 profile + PATH（/etc 无权限则降级 ~/.profile，当前会话 PATH 必须 export）
    if [ -d /usr/local/go/bin ]; then
      local prof="/etc/profile.d/tars-toolchain.sh"
      if [ -w /etc/profile.d ]; then
        echo 'export PATH=/usr/local/go/bin:$PATH' > "$prof" 2>/dev/null || true
      else
        echo 'export PATH=/usr/local/go/bin:$PATH' | sudo tee "$prof" >/dev/null 2>&1 || true
      fi
      echo 'export PATH=/usr/local/go/bin:$PATH' >> "$HOME/.profile" 2>/dev/null || true
      export PATH=/usr/local/go/bin:$PATH
    else
      err "ensure_toolchain: go 解包后 /usr/local/go/bin 不存在" >&2
      return 1
    fi
  fi

  # node（npm 随 node 走）
  if ! command -v node >/dev/null 2>&1; then
    local nodepkg=""
    for cand in "$CMS_REPO_DIR/deploy/toolchain"/node*.tar.* "$CMS_REPO_DIR/toolchain"/node*.tar.* /docker/offline-pack/toolchain/node*.tar.* /tmp/node*.tar.*; do
      [ -f "$cand" ] && { nodepkg="$cand"; break; }
    done
    if [ -z "$nodepkg" ]; then
      err "ensure_toolchain: 缺 node 且找不到 node*.tar.*（放 deploy/toolchain/ 或离线包 toolchain/）" >&2
      return 1
    fi
    warn "ensure_toolchain: 安装 node from $nodepkg ..."
    local ndir; ndir=$(tar -tzf "$nodepkg" 2>/dev/null | head -1 | cut -d/ -f1)
    # 干净安装：先清旧 /usr/local/node*（覆盖冲突同 go）
    if [ -d /usr/local/node ] || [ -d "/usr/local/$ndir" ]; then
      rm -rf /usr/local/node "/usr/local/$ndir" 2>/dev/null \
        || sudo rm -rf /usr/local/node "/usr/local/$ndir" 2>/dev/null || true
    fi
    _install_tarball "$nodepkg" /usr/local || { err "ensure_toolchain: node 解包失败" >&2; return 1; }
    # 兼容带版本目录 /usr/local/node-v20.19.0-linux-x64 → 软链 /usr/local/node
    if [ -n "$ndir" ] && [ -d "/usr/local/$ndir" ]; then
      ln -sf "/usr/local/$ndir" /usr/local/node 2>/dev/null \
        || sudo ln -sf "/usr/local/$ndir" /usr/local/node 2>/dev/null || true
    fi
    if [ -x /usr/local/node/bin/node ]; then
      local prof2="/etc/profile.d/tars-toolchain.sh"
      if [ -w /etc/profile.d ]; then
        echo 'export PATH=/usr/local/node/bin:$PATH' >> "$prof2" 2>/dev/null || true
      else
        echo 'export PATH=/usr/local/node/bin:$PATH' | sudo tee -a "$prof2" >/dev/null 2>&1 || true
      fi
      echo 'export PATH=/usr/local/node/bin:$PATH' >> "$HOME/.profile" 2>/dev/null || true
      export PATH=/usr/local/node/bin:$PATH
    else
      err "ensure_toolchain: node 解包后 /usr/local/node/bin/node 不存在" >&2
      return 1
    fi
  fi

  # npm 随 node 走，最终校验
  for c in go node npm; do
    command -v "$c" >/dev/null 2>&1 || { err "ensure_toolchain: 仍缺 $c" >&2; return 1; }
  done

  # ── GOPROXY：国内机 proxy.golang.org 被墙/证书劫持，n02 编译必炸 ──
  # 判别：默认 GOPROXY 且能访问 goproxy.cn 时，切到 goproxy.cn（并持久化 ~/.bashrc）。
  if command -v go >/dev/null 2>&1; then
    local cur_gp="${GOPROXY:-}"
    if [[ "$cur_gp" != *goproxy.cn* ]] && curl -sI --max-time 4 https://goproxy.cn >/dev/null 2>&1; then
      warn "ensure_toolchain: 检测到国内网络，GOPROXY → https://goproxy.cn,direct"
      export GOPROXY="https://goproxy.cn,direct"
      grep -q "GOPROXY" "$HOME/.bashrc" 2>/dev/null \
        || echo 'export GOPROXY=https://goproxy.cn,direct' >> "$HOME/.bashrc" 2>/dev/null || true
    fi
  fi

  ok "工具链就绪 ($(go version 2>/dev/null | awk '{print $3}') / node $(node --version 2>/dev/null))"
  return 0
}

# ── 坑5：Docker 权限自动处理 ──
# 非 root 用户（如 sa）不在 docker 组时，docker inspect 直接 Permission denied，
# 前置检查误报"容器不存在"。本函数把当前用户加入 docker 组（需 sudo），
# 并提示重开 shell；当前会话若还不行则尝试 sudo docker 前缀。
ensure_docker_access() {
  if docker info >/dev/null 2>&1; then return 0; fi
  if [ "$(id -u)" -ne 0 ]; then
    # 试加 docker 组（newgrp 无法在脚本内生效，加完提示；当前会话用 sudo 兜底）
    if command -v sudo >/dev/null 2>&1 && ! groups 2>/dev/null | grep -qw docker; then
      warn "ensure_docker_access: 当前用户不在 docker 组，尝试 sudo usermod -aG docker ..."
      sudo usermod -aG docker "$USER" 2>/dev/null && ok "已加入 docker 组（重新登录后生效）"
    fi
    # 当前会话兜底：若 sudo docker 可用则定义 docker 别名
    if ! docker info >/dev/null 2>&1 && sudo -n docker info >/dev/null 2>&1; then
      warn "ensure_docker_access: 当前会话用 sudo docker 兜底"
      docker() { sudo docker "$@"; }
      export -f docker 2>/dev/null || true
    fi
  fi
  docker info >/dev/null 2>&1 || { err "ensure_docker_access: docker 仍不可用"; return 1; }
  return 0
}

# ── 坑6：目录可写自动处理 ──
# /docker/tars 默认 root 属主；非 root 部署时 mkdir/build 权限不足。
# 本函数确保 $CMS_BASE_DIR 存在且当前用户可写（sudo chown）。
ensure_dir_writable() {
  local d="${1:-$CMS_BASE_DIR}"
  if [ -d "$d" ] && [ -w "$d" ]; then return 0; fi
  if [ ! -d "$d" ]; then
    if ! mkdir -p "$d" 2>/dev/null; then
      sudo mkdir -p "$d" 2>/dev/null || { err "ensure_dir_writable: 无法创建 $d"; return 1; }
    fi
  fi
  if [ ! -w "$d" ] && [ "$(id -u)" -ne 0 ]; then
    warn "ensure_dir_writable: $d 不可写，sudo chown 当前用户 ..."
    sudo chown -R "$(id -u):$(id -g)" "$d" 2>/dev/null || { err "ensure_dir_writable: chown $d 失败"; return 1; }
  fi
  [ -w "$d" ] || { err "ensure_dir_writable: $d 仍不可写"; return 1; }
  ok "目录就绪: $d"
  return 0
}

# ── 坑7：MySQL 数据自愈（权限错 + 孤儿表）──
# 两类问题都会让 GatewayWeb 启动崩溃：
#   A. 数据卷属主漂移（如宿主 chown 后 1000:1000，而 mysqld 以 999:999 跑）
#      → SHOW TABLES FROM db_base 报 1018 Permission denied，建表报 1050。
#      修法：chown 数据目录为容器内 mysql uid（轻量，不删数据）。
#   B. 孤儿表（GatewayWeb 建表中断留 .ibd 无 .frm）
#      → CREATE TABLE IF NOT EXISTS 报 1050/1813。
#      修法：重建数据卷（bind mount，数据可重建）。
# 优先走 A（不毁数据），A 修不好再走 B。
ensure_mysql_data() {
  local ctn="${CMS_MYSQL_CTN:-tars-mysql}"
  docker inspect "$ctn" >/dev/null 2>&1 || { warn "ensure_mysql_data: $ctn 不存在，跳过"; return 0; }
  local data_dir
  data_dir=$(docker inspect -f '{{range .Mounts}}{{if eq .Destination "/var/lib/mysql"}}{{.Source}}{{end}}{{end}}' "$ctn" 2>/dev/null | head -1)
  [ -n "$data_dir" ] || { warn "ensure_mysql_data: 未找到 $ctn 数据目录（非 bind mount？）"; return 0; }

  # ── 探测：建临时表看报什么错（无 db_base 则跳过，全新库正常）──
  if ! docker exec "$ctn" mysql -uroot -p"${CMS_DB_PASS}" -e "USE db_base" >/dev/null 2>&1; then
    return 0  # db_base 不存在 = 全新库，正常
  fi
  local probe
  probe=$(docker exec "$ctn" mysql -uroot -p"${CMS_DB_PASS}" -e \
    "CREATE TABLE IF NOT EXISTS db_base.__probe (f_id INT)" 2>&1 || true)
  docker exec "$ctn" mysql -uroot -p"${CMS_DB_PASS}" -e \
    "DROP TABLE IF EXISTS db_base.__probe" >/dev/null 2>&1 || true

  # ── A. 权限错（1018 Permission denied / errno 13）→ 修属主 ──
  if echo "$probe" | grep -qE "1018|errno: 13|Permission denied"; then
    warn "ensure_mysql_data: db_base 权限错（1018/errno 13），修数据目录属主..."
    # mysqld 容器内以 mysql 用户跑（uid 999）；把 bind mount 属主改成它
    local muid
    muid=$(docker exec "$ctn" sh -c 'id -u mysql 2>/dev/null' 2>/dev/null | tr -d '\r')
    [ -n "$muid" ] || muid=999
    docker stop "$ctn" >/dev/null 2>&1 || true
    sleep 2
    if [ -d "$data_dir" ]; then
      sudo chown -R "$muid:$muid" "$data_dir" 2>/dev/null || chown -R "$muid:$muid" "$data_dir" 2>/dev/null || true
    fi
    docker start "$ctn" >/dev/null 2>&1
    local i
    for i in $(seq 1 30); do
      docker exec "$ctn" mysql -uroot -p"${CMS_DB_PASS}" -e "SELECT 1" >/dev/null 2>&1 && break
      sleep 2
    done
    ok "ensure_mysql_data: 数据目录属主已修为 $muid:$muid"
    return 0
  fi

  # ── B. 孤儿表（1050/1813）→ 重建数据卷 ──
  if echo "$probe" | grep -qE "1050|1813"; then
    warn "ensure_mysql_data: db_base 检测到孤儿表（1050/1813），重建 MySQL 数据卷..."
    warn "ensure_mysql_data: 停 $ctn → 清 $data_dir → 重启（bind mount 数据可重建）"
    docker stop "$ctn" >/dev/null 2>&1 || true
    sleep 2
    if [ -d "$data_dir" ]; then
      sudo rm -rf "$data_dir" 2>/dev/null || rm -rf "$data_dir" || true
    fi
    docker start "$ctn" >/dev/null 2>&1
    local j
    for j in $(seq 1 30); do
      docker exec "$ctn" mysql -uroot -p"${CMS_DB_PASS}" -e "SELECT 1" >/dev/null 2>&1 && break
      sleep 2
    done
    docker exec "$ctn" mysql -uroot -p"${CMS_DB_PASS}" -e "CREATE DATABASE IF NOT EXISTS db_base" >/dev/null 2>&1 || true
    ok "ensure_mysql_data: 数据卷已重建，db_base 就绪"
    return 0
  fi

  return 0  # 正常，无问题
}

