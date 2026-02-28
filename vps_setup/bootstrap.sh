#!/bin/bash
#========================================================
# bootstrap.sh v1.1.0（Mac側）
#
# 使い方（購入者向け）:
#   bash <(curl -sSL https://raw.githubusercontent.com/YOUR_USER/YOUR_REPO/main/bootstrap.sh)
#
# 目的:
# - 必要ファイルを GitHub から自動ダウンロード
# - ウィザード形式で設定を収集（バリデーション付き）
# - Ansible の確認/インストール
# - SSH鍵ペア生成
# - VPS root へ一時公開鍵を登録（Ansible接続用）
# - Ansible playbook を実行（VPS全設定）
# - SSH config を更新・接続テスト
#
# ※ 販売者設定: GITHUB_RAW_URL を自分のリポジトリに変更してください
#========================================================
set -euo pipefail

# bash <(curl ...) 実行時は PATH が通らないため Homebrew パスを明示追加
export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/local/sbin:$PATH"

VERSION="1.1.0"

#========================================================
# ★ 販売者設定（ここだけ変更する）
#========================================================
GITHUB_RAW_URL="https://raw.githubusercontent.com/ai-autoflow/scripts/main/vps_setup"

#── デフォルト値 ──────────────────────────────────────
DEFAULT_SSH_PORT="55555"
DEFAULT_SSH_CONFIG_HOST="myvps"
DEFAULT_SSH_KEY_NAME="ssh_key_vps"
DEFAULT_INSTALL_DOCKER="yes"
DEFAULT_WORK_DIR_NAME="repo"

#── 内部定数 ──────────────────────────────────────────
SSH_KEY_DIR="$HOME/.ssh"
VPS_ROOT_USER="root"
VPS_SSH_PORT_BEFORE="22"
CTRL_SOCKET="/tmp/vps_ansible_$$"
VARS_FILE="/tmp/vps_ansible_vars_$$.yml"
WORK_DIR=""   # mktemp で後から設定

TEST_RETRIES=24
TEST_SLEEP=5

#── カラー ────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
ok()    { echo -e "  ${GREEN}✓${NC} $*"; }
ng()    { echo -e "  ${RED}✗${NC} $*"; }

#── クリーンアップ ────────────────────────────────────
cleanup() {
  rm -f "$VARS_FILE" 2>/dev/null || true
  [[ -n "$WORK_DIR" && -d "$WORK_DIR" ]] && rm -rf "$WORK_DIR" 2>/dev/null || true
  if [[ -S "$CTRL_SOCKET" ]]; then
    ssh -o ControlPath="$CTRL_SOCKET" -O exit \
      "${VPS_ROOT_USER}@${VPS_HOST:-localhost}" 2>/dev/null || true
  fi
}
trap cleanup EXIT

#========================================================
# ファイルダウンロード
#========================================================
download_files() {
  info "セットアップファイルをダウンロード中..."

  WORK_DIR="$(mktemp -d /tmp/vps_setup_XXXXXX)"

  # ダウンロード対象ファイルリスト
  local files=(
    "ansible.cfg"
    "requirements.yml"
    "site.yml"
    "roles/common/tasks/main.yml"
    "roles/user/tasks/main.yml"
    "roles/security/tasks/main.yml"
    "roles/docker/tasks/main.yml"
    "roles/workdir/tasks/main.yml"
    "setup_confirmation.sh"
  )

  for file in "${files[@]}"; do
    local dest="${WORK_DIR}/${file}"
    mkdir -p "$(dirname "$dest")"
    if ! curl -sSL --fail "${GITHUB_RAW_URL}/${file}" -o "$dest"; then
      error "ダウンロードに失敗しました: ${file}"
      error "URL を確認してください: ${GITHUB_RAW_URL}/${file}"
      exit 1
    fi
  done

  info "ダウンロード完了（${#files[@]}ファイル）"
}

#========================================================
# バリデーション関数
#========================================================
validate_ip() {
  local ip="$1"
  [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
  IFS='.' read -ra parts <<< "$ip"
  for p in "${parts[@]}"; do
    (( p >= 0 && p <= 255 )) || return 1
  done
}

validate_username() {
  [[ "$1" =~ ^[a-z_][a-z0-9_-]*$ ]] && [[ ${#1} -le 32 ]] || return 1
}

validate_password() {
  [[ ${#1} -ge 8 ]] || return 1
}

validate_port() {
  [[ "$1" =~ ^[0-9]+$ ]] || return 1
  (( $1 >= 49152 && $1 <= 65535 )) || return 1
}

validate_name() {
  [[ "$1" =~ ^[a-zA-Z0-9_-]+$ ]] || return 1
}

#========================================================
# 入力関数
#========================================================

# 必須入力（空不可・バリデーション・リトライ）
ask_required() {
  local varname="$1" label="$2" validator="$3" errmsg="$4" secret="${5:-no}"
  local value=""

  while true; do
    if [[ "$secret" == "yes" ]]; then
      read -s -p "$(echo -e "${BOLD}> ${label}${NC}: ")" value </dev/tty
      echo ""
    else
      read -p "$(echo -e "${BOLD}> ${label}${NC}: ")" value </dev/tty
    fi

    if [[ -z "$value" ]]; then
      ng "必須項目です。入力してください。"; continue
    fi

    if $validator "$value" 2>/dev/null; then
      ok ""; break
    else
      ng "$errmsg"
    fi
  done
  printf -v "$varname" "%s" "$value"
}

# 任意入力（Enterでデフォルト・バリデーション付き）
ask_optional() {
  local varname="$1" label="$2" default="$3" validator="${4:-}" errmsg="${5:-}"
  local value=""

  while true; do
    read -p "$(echo -e "${BOLD}> ${label}${NC} [Enter → ${default}]: ")" value </dev/tty

    if [[ -z "$value" ]]; then
      value="$default"; info "デフォルト値を使用: $value"; break
    fi

    if [[ -z "$validator" ]] || $validator "$value" 2>/dev/null; then
      ok ""; break
    else
      ng "$errmsg"
    fi
  done
  printf -v "$varname" "%s" "$value"
}

# yes/no 入力
ask_yesno() {
  local varname="$1" label="$2" default="$3"
  local value=""

  while true; do
    read -p "$(echo -e "${BOLD}> ${label}${NC} (yes/no) [Enter → ${default}]: ")" value </dev/tty

    if [[ -z "$value" ]]; then
      value="$default"; info "デフォルト値を使用: $value"; break
    fi

    if [[ "$value" == "yes" || "$value" == "no" ]]; then
      ok ""; break
    else
      ng "yes または no で入力してください"
    fi
  done
  printf -v "$varname" "%s" "$value"
}

#========================================================
# OS チェック
#========================================================
check_os() {
  if [[ "$(uname)" != "Darwin" ]]; then
    error "このスクリプトは macOS 専用です。"
    exit 1
  fi
}

#========================================================
# Ansible 確認・インストール
# 優先順位: 既存インストール済み → Python venv → Homebrew
#
# Python venv を使う理由:
# - macOS には必ず Python3 が入っている（Homebrew 不要）
# - 一時フォルダ内にインストール → システムを汚さない
# - PATH 変更不要（絶対パスで呼び出す）
# - 全Mac共通で動作する
#========================================================
check_ansible() {
  if command -v ansible-playbook &>/dev/null; then
    info "Ansible を確認しました: $(ansible --version 2>/dev/null | head -1)"
    return 0
  fi

  warn "Ansible が見つかりません。インストールします..."

  # Python venv でインストール（Homebrew 不要・全 Mac で動作）
  if command -v python3 &>/dev/null; then
    info "Python 仮想環境に Ansible をインストール中（初回のみ数分かかります）..."
    local venv_dir="${WORK_DIR}/venv"

    python3 -m venv "$venv_dir"
    "${venv_dir}/bin/pip" install --quiet --upgrade pip
    "${venv_dir}/bin/pip" install --quiet ansible

    # venv の bin を PATH の先頭に追加
    export PATH="${venv_dir}/bin:$PATH"

    if command -v ansible-playbook &>/dev/null; then
      info "Ansible のインストールが完了しました"
      return 0
    fi
  fi

  # Python3 がない場合は Homebrew を試みる
  if command -v brew &>/dev/null; then
    info "Homebrew で Ansible をインストール中..."
    brew install ansible
    info "Ansible のインストールが完了しました"
    return 0
  fi

  error "Ansible をインストールできませんでした。"
  error "Xcode Command Line Tools をインストールしてから再実行してください:"
  error "  xcode-select --install"
  exit 1
}

#========================================================
# Ansible Galaxy コレクション インストール
#========================================================
check_galaxy() {
  info "Ansible Galaxy コレクションを確認中..."
  ansible-galaxy collection install -r "${WORK_DIR}/requirements.yml" --upgrade 2>/dev/null || \
  ansible-galaxy collection install -r "${WORK_DIR}/requirements.yml"
}

#========================================================
# ControlMaster 確立（パスワード認証・1回だけ）
#========================================================
establish_control_master() {
  info "VPS に接続します（root@${VPS_HOST}:${VPS_SSH_PORT_BEFORE}）"
  info "root パスワードを入力してください"
  echo ""

  SSH_ASKPASS="" DISPLAY="" \
  ssh -p "$VPS_SSH_PORT_BEFORE" \
    -o ControlMaster=yes \
    -o "ControlPath=$CTRL_SOCKET" \
    -o ControlPersist=600 \
    -o StrictHostKeyChecking=accept-new \
    -o PubkeyAuthentication=no \
    -o PasswordAuthentication=yes \
    -o PreferredAuthentications=password \
    -o GSSAPIAuthentication=no \
    -o ConnectTimeout=30 \
    "${VPS_ROOT_USER}@${VPS_HOST}" true

  if ! ssh -o "ControlPath=$CTRL_SOCKET" -O check \
      "${VPS_ROOT_USER}@${VPS_HOST}" 2>/dev/null; then
    error "VPS への接続に失敗しました。IP アドレスと root パスワードを確認してください。"
    exit 1
  fi

  info "VPS への接続を確認しました"
}

#========================================================
# SSH config 更新（~/.ssh/config）
#========================================================
update_ssh_config() {
  local cfg="$HOME/.ssh/config"

  if [[ ! -f "$cfg" ]]; then
    touch "$cfg"; chmod 600 "$cfg"
    info "~/.ssh/config を作成しました"
  fi

  # 既存の同名 Host を削除
  if grep -q "^Host ${SSH_CONFIG_HOST}$" "$cfg" 2>/dev/null; then
    local bak="${cfg}.bak.$(date +%s)"
    cp "$cfg" "$bak"
    awk -v host="^Host ${SSH_CONFIG_HOST}$" \
      '/^Host /{if($0~host){del=1;next}else{del=0}} !del{print}' \
      "$cfg" > "${cfg}.tmp" && mv "${cfg}.tmp" "$cfg"
    info "既存の Host ${SSH_CONFIG_HOST} を上書きしました（バックアップ: $bak）"
  fi

  # 新しい Host 設定を追加
  {
    echo ""
    echo "# Generated by vps_setup ansible v${VERSION} on $(date '+%Y-%m-%d %H:%M:%S')"
    echo "Host ${SSH_CONFIG_HOST}"
    echo "  HostName ${VPS_HOST}"
    echo "  User ${NEW_USER}"
    echo "  Port ${NEW_SSH_PORT}"
    echo "  IdentityFile ${SSH_KEY_DIR}/${SSH_KEY_NAME}"
    echo "  IdentitiesOnly yes"
  } >> "$cfg"

  info "SSH config に Host ${SSH_CONFIG_HOST} を追加しました"
  info "次回の接続: ssh ${SSH_CONFIG_HOST}"
}

#========================================================
# 接続テスト（新ポート・新ユーザー）
#========================================================
test_new_connection() {
  info "新ポートでの接続テストを開始します（最大 $((TEST_RETRIES * TEST_SLEEP))秒）..."
  echo ""

  local connected="no"
  for i in $(seq 1 "$TEST_RETRIES"); do
    if ssh -o BatchMode=yes \
           -o ConnectTimeout=5 \
           -o StrictHostKeyChecking=accept-new \
           "$SSH_CONFIG_HOST" "echo ok" >/dev/null 2>&1; then
      connected="yes"; break
    fi
    warn "(${i}/${TEST_RETRIES}) まだ接続できません。${TEST_SLEEP}s 後に再試行..."
    sleep "$TEST_SLEEP"
  done

  if [[ "$connected" == "yes" ]]; then
    info "新ポートでの接続を確認しました ✓"
  else
    warn "自動テストで接続を確認できませんでした。手動で確認してください:"
    warn "  ssh ${SSH_CONFIG_HOST}"
  fi
}

#========================================================
# 設定確認スクリプト実行（セットアップ後の全設定を VPS 上でチェック）
#========================================================
run_confirmation_script() {
  local confirm_script="${WORK_DIR}/setup_confirmation.sh"

  if [[ ! -f "$confirm_script" ]]; then
    warn "setup_confirmation.sh が見つかりません。確認スクリプトをスキップします。"
    return
  fi

  info "設定確認スクリプトを VPS で実行します..."

  # VPS への転送（リトライ付き：接続テスト直後なので基本1回で成功する）
  local confirm_ok="no"
  for i in $(seq 1 "$TEST_RETRIES"); do
    if scp -o StrictHostKeyChecking=accept-new \
           "$confirm_script" \
           "${SSH_CONFIG_HOST}:~/setup_confirmation.sh" 2>/dev/null; then
      confirm_ok="yes"
      break
    fi
    warn "(${i}/${TEST_RETRIES}) 確認スクリプトの転送に失敗。${TEST_SLEEP}s 後に再試行..."
    sleep "$TEST_SLEEP"
  done

  if [[ "$confirm_ok" == "yes" ]]; then
    ssh -t -o StrictHostKeyChecking=accept-new \
        "$SSH_CONFIG_HOST" \
        "chmod +x ~/setup_confirmation.sh && ~/setup_confirmation.sh"
    ssh -o StrictHostKeyChecking=accept-new \
        "$SSH_CONFIG_HOST" \
        "rm -f ~/setup_confirmation.sh" 2>/dev/null || true
    info "VPS 上の確認スクリプトを削除しました"
  else
    warn "確認スクリプトの転送に失敗しました。手動で確認してください:"
    warn "  scp setup_confirmation.sh ${SSH_CONFIG_HOST}:~/"
    warn "  ssh ${SSH_CONFIG_HOST}"
    warn "  chmod +x ~/setup_confirmation.sh && ~/setup_confirmation.sh"
  fi
}

#========================================================
# メイン処理
#========================================================
check_os

echo ""
echo -e "${BOLD}===================================${NC}"
echo -e "${BOLD}  VPS セットアップ ウィザード v${VERSION}${NC}"
echo -e "${BOLD}===================================${NC}"
echo ""

# ① ファイルダウンロード
download_files
echo ""

# ② Ansible 確認
check_ansible
check_galaxy
echo ""

#── 必須項目（3つ）────────────────────────────────────
echo -e "${BOLD}--- 必須項目（3つ）---${NC}"
echo ""

echo "[1/3] VPS の IP アドレス"
ask_required VPS_HOST "IP アドレス" validate_ip \
  "IP アドレスの形式が正しくありません（例: 210.131.215.183）"
echo ""

echo "[2/3] 新しいユーザー名（英小文字・数字・_- のみ）"
ask_required NEW_USER "ユーザー名" validate_username \
  "英小文字・数字・アンダーバー・ハイフンのみ使用可（例: myuser）"
echo ""

echo "[3/3] パスワード（sudo用・8文字以上）"
ask_required NEW_USER_PASSWORD "パスワード" validate_password \
  "8文字以上で入力してください" "yes"
echo ""

#── 任意項目（Enterでデフォルト）────────────────────
echo -e "${BOLD}--- 任意項目（Enterでデフォルト値）---${NC}"
echo ""

echo "[4/8] SSH ポート番号（49152〜65535）"
ask_optional NEW_SSH_PORT "SSH ポート" "$DEFAULT_SSH_PORT" \
  validate_port "49152〜65535 の数値で入力してください"
echo ""

echo "[5/8] SSH Config の Host 名（ssh <名前> で接続する時の名前）"
ask_optional SSH_CONFIG_HOST "Host 名" "$DEFAULT_SSH_CONFIG_HOST" \
  validate_name "英数字・アンダーバー・ハイフンのみ使用可"
echo ""

echo "[6/8] SSH 鍵のファイル名（拡張子なし）"
ask_optional SSH_KEY_NAME "鍵ファイル名" "$DEFAULT_SSH_KEY_NAME" \
  validate_name "英数字・アンダーバー・ハイフンのみ使用可"
echo ""

echo "[7/8] Docker をインストールする？"
ask_yesno INSTALL_DOCKER "Docker インストール" "$DEFAULT_INSTALL_DOCKER"
echo ""

echo "[8/8] 作業ディレクトリ名"
echo "      （Enter → repo で作成 / \"none\" と入力 → 作成しない）"
read -p "$(echo -e "${BOLD}> 作業ディレクトリ名${NC} [Enter → ${DEFAULT_WORK_DIR_NAME}]: ")" _work_input </dev/tty
if [[ -z "$_work_input" ]]; then
  WORK_DIR_NAME="$DEFAULT_WORK_DIR_NAME"
  info "デフォルト値を使用: $WORK_DIR_NAME"
elif [[ "$_work_input" == "none" ]]; then
  WORK_DIR_NAME=""; info "作業ディレクトリは作成しません"
else
  WORK_DIR_NAME="$_work_input"; ok ""
fi
echo ""

# 内部自動設定（ユーザーに聞かない）
SSH_KEY_COMMENT="$(whoami)@$(hostname -s)"
SSH_KEY_PASSPHRASE=""

#── 確認画面 ──────────────────────────────────────────
echo ""
echo -e "${BOLD}─────────────────────────────────${NC}"
echo -e "${GREEN}✅ 設定内容の確認${NC}"
echo ""
printf "  %-16s %s\n" "VPS IP:"         "$VPS_HOST"
printf "  %-16s %s\n" "ユーザー名:"     "$NEW_USER"
printf "  %-16s %s\n" "パスワード:"     "$(printf '%s' "$NEW_USER_PASSWORD" | sed 's/./*/g')"
printf "  %-16s %s\n" "SSH ポート:"     "$NEW_SSH_PORT"
printf "  %-16s %s\n" "Config Host名:"  "$SSH_CONFIG_HOST"
printf "  %-16s %s\n" "SSH 鍵の名前:"   "$SSH_KEY_NAME"
printf "  %-16s %s\n" "Docker:"         "$INSTALL_DOCKER"
if [[ -n "$WORK_DIR_NAME" ]]; then
  printf "  %-16s %s\n" "作業Dir:"      "/home/${NEW_USER}/${WORK_DIR_NAME}"
else
  printf "  %-16s %s\n" "作業Dir:"      "作成しない"
fi
echo -e "${BOLD}─────────────────────────────────${NC}"
echo ""

read -p "$(echo -e "${BOLD}この内容で進めますか？ (y/n): ${NC}")" _confirm </dev/tty
if [[ "$_confirm" != "y" && "$_confirm" != "Y" ]]; then
  echo "中止しました。もう一度実行してください。"; exit 0
fi
echo ""

#── SSH 鍵生成 ────────────────────────────────────────
LOCAL_PRIVKEY="${SSH_KEY_DIR}/${SSH_KEY_NAME}"
LOCAL_PUBKEY="${LOCAL_PRIVKEY}.pub"

info "SSH 鍵を生成中..."
mkdir -p "$SSH_KEY_DIR"; chmod 700 "$SSH_KEY_DIR"

if [[ -f "$LOCAL_PRIVKEY" ]] || [[ -f "$LOCAL_PUBKEY" ]]; then
  local_bak=".bak.$(date +%s)"
  [[ -f "$LOCAL_PRIVKEY" ]] && mv "$LOCAL_PRIVKEY" "${LOCAL_PRIVKEY}${local_bak}"
  [[ -f "$LOCAL_PUBKEY"  ]] && mv "$LOCAL_PUBKEY"  "${LOCAL_PUBKEY}${local_bak}"
  info "既存の鍵をバックアップしました"
fi

ssh-keygen -t ed25519 -C "$SSH_KEY_COMMENT" \
  -f "$LOCAL_PRIVKEY" -N "$SSH_KEY_PASSPHRASE" >/dev/null 2>&1
chmod 600 "$LOCAL_PRIVKEY"; chmod 644 "$LOCAL_PUBKEY"
info "SSH 鍵を生成しました: ${LOCAL_PRIVKEY}"
echo ""

#── known_hosts クリア ────────────────────────────────
info "known_hosts から古いホストキーを削除中（存在する場合）..."
ssh-keygen -R "$VPS_HOST" 2>/dev/null || true
ssh-keygen -R "[${VPS_HOST}]:${NEW_SSH_PORT}" 2>/dev/null || true

#── VPS root へ公開鍵登録（Ansible 接続用）─────────────
establish_control_master

info "公開鍵を root の authorized_keys に登録中..."
_pubkey_content="$(cat "$LOCAL_PUBKEY")"
ssh -o ControlPath="$CTRL_SOCKET" \
    -p "$VPS_SSH_PORT_BEFORE" \
    "${VPS_ROOT_USER}@${VPS_HOST}" \
    "mkdir -p ~/.ssh && chmod 700 ~/.ssh && \
     echo '${_pubkey_content}' >> ~/.ssh/authorized_keys && \
     chmod 600 ~/.ssh/authorized_keys"
info "公開鍵を登録しました"

ssh -o ControlPath="$CTRL_SOCKET" -O exit \
    "${VPS_ROOT_USER}@${VPS_HOST}" 2>/dev/null || true
info "パスワード認証セッションを終了しました"
echo ""

#── SSH 鍵認証テスト（Ansible 実行前の確認）─────────────
info "SSH 接続を安定させるため 3 秒待機中..."
sleep 3

info "SSH 鍵認証テストを実施中..."
if ! ssh \
     -i "$LOCAL_PRIVKEY" \
     -o BatchMode=yes \
     -o ConnectTimeout=15 \
     -o StrictHostKeyChecking=accept-new \
     -o IdentitiesOnly=yes \
     -o PasswordAuthentication=no \
     -o PubkeyAuthentication=yes \
     -o ControlMaster=no \
     -p "$VPS_SSH_PORT_BEFORE" \
     "${VPS_ROOT_USER}@${VPS_HOST}" "true"; then
  error "SSH 鍵認証テストに失敗しました。"
  error "authorized_keys への登録が正常に行われていない可能性があります。"
  error "手動で確認: ssh -i ${LOCAL_PRIVKEY} -p ${VPS_SSH_PORT_BEFORE} root@${VPS_HOST}"
  exit 1
fi
info "SSH 鍵認証 OK ✓"
echo ""

#── inventory.ini 生成 ────────────────────────────────
INVENTORY_FILE="${WORK_DIR}/inventory.ini"
cat > "$INVENTORY_FILE" <<EOF
[vps]
target ansible_host=${VPS_HOST} ansible_port=${VPS_SSH_PORT_BEFORE} ansible_user=root ansible_ssh_private_key_file=${LOCAL_PRIVKEY}
EOF

#── Ansible 変数ファイル生成 ──────────────────────────
_b64_pass="$(printf '%s' "$NEW_USER_PASSWORD" | base64)"
cat > "$VARS_FILE" <<EOF
new_user: "${NEW_USER}"
new_user_password_b64: "${_b64_pass}"
ssh_port: ${NEW_SSH_PORT}
local_pub_key_path: "${LOCAL_PUBKEY}"
install_docker: "${INSTALL_DOCKER}"
work_dir_name: "${WORK_DIR_NAME}"
EOF

info "設定ファイルを準備しました"
echo ""

#── Ansible playbook 実行 ─────────────────────────────
info "Ansible playbook を実行します（約5〜10分）..."
echo ""

cd "$WORK_DIR"
ANSIBLE_CONFIG="${WORK_DIR}/ansible.cfg" \
ansible-playbook \
  -i "$INVENTORY_FILE" \
  --extra-vars "@${VARS_FILE}" \
  "${WORK_DIR}/site.yml"

echo ""
info "Ansible playbook が完了しました"
echo ""

#── SSH config 更新 ───────────────────────────────────
update_ssh_config
echo ""

#── 接続テスト ────────────────────────────────────────
test_new_connection
echo ""

#── 設定確認スクリプト ────────────────────────────────
run_confirmation_script
echo ""

#── 完了メッセージ ────────────────────────────────────
echo ""
echo -e "${BOLD}===== セットアップ完了 =====${NC}"
echo ""
echo "────────────────────────────────────"
echo "接続コマンド: ssh ${SSH_CONFIG_HOST}"
echo "────────────────────────────────────"
echo ""
