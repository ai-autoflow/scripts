#!/bin/bash
# Ubuntu 24.04 LTS VPS初期設定 確認スクリプト
# 用途: ubuntu24_04_setup2.sh 完了後、一般ユーザーで実行して全設定を確認する
# 使い方: chmod +x setup_confirmation.sh && ./setup_confirmation.sh

# --- エラーで即停止しない（各チェックは独立して動く） ---

CURRENT_USER=$(logname 2>/dev/null || whoami)
SSH_PORT=$(grep -h '^Port' /etc/ssh/sshd_config.d/99-hardening.conf 2>/dev/null | awk '{print $2}' | head -n1)
[ -z "$SSH_PORT" ] && SSH_PORT=$(grep -h '^Port' /etc/ssh/sshd_config /etc/ssh/sshd_config.d/*.conf 2>/dev/null | awk '{print $2}' | head -n1)
[ -z "$SSH_PORT" ] && SSH_PORT=22

PASS=0
FAIL=0

ok()   { echo "  ✅ $*"; PASS=$((PASS + 1)); }
ng()   { echo "  ❌ $*"; FAIL=$((FAIL + 1)); }
info() { echo "  ℹ️  $*"; }

echo "========================================"
echo " VPS 初期設定 確認（ユーザー: $CURRENT_USER）"
echo "========================================"
echo ""

# sudo パスワードキャッシュを先に取得（以降の sudo でパスワードが聞かれない）
echo "=== sudo 認証 ==="
sudo -v 2>/dev/null && echo "  ✅ sudo 認証OK" || echo "  ⚠️  sudo 認証に失敗（一部チェックがスキップされる可能性あり）"
echo ""

# --- 1. OSバージョン ---
echo "=== 1. OSバージョン ==="
lsb_release -d 2>/dev/null || grep PRETTY_NAME /etc/os-release 2>/dev/null || info "取得できません"
echo ""

# --- 2. パッケージ更新状態 ---
echo "=== 2. パッケージ更新状態 ==="
APT_SIM=$(apt-get -s upgrade 2>/dev/null)
UPGRADABLE=$(echo "$APT_SIM" | grep -c '^Inst' || true)
KEPT_BACK=$(echo "$APT_SIM" | sed -n '/kept back/,/^[^ ]/p' | grep -v 'kept back\|^[^ ]' | wc -w || true)
PHASING=$(echo "$APT_SIM" | sed -n '/deferred due to phasing/,/^[^ ]/p' | grep -v 'deferred due to phasing\|^[^ ]' | wc -w || true)
UPGRADABLE="${UPGRADABLE:-0}"
KEPT_BACK="${KEPT_BACK:-0}"
PHASING="${PHASING:-0}"
if [ "$UPGRADABLE" -eq 0 ] 2>/dev/null; then
  ok "全パッケージ最新"
else
  info "アップグレード可能: ${UPGRADABLE}件"
fi
if [ "$PHASING" -gt 0 ] 2>/dev/null; then
  info "段階的配信待ち: ${PHASING}件（Ubuntuが順次配信中、数日で自動適用）"
fi
if [ "$KEPT_BACK" -gt 0 ] 2>/dev/null; then
  info "保留中: ${KEPT_BACK}件（カーネル等、apt-get upgrade では更新されないパッケージ）"
fi
echo ""

# --- 3. ユーザー ---
echo "=== 3. ユーザー ==="
if id "$CURRENT_USER" >/dev/null 2>&1; then
  id "$CURRENT_USER"
  ok "ユーザー ${CURRENT_USER} は存在します"
else
  ng "ユーザー ${CURRENT_USER} が見つかりません"
fi
echo ""

# --- 4. パスワード状態 ---
echo "=== 4. パスワード状態 ==="
PASSWD_STATUS=$(sudo passwd -S "$CURRENT_USER" 2>/dev/null)
if [ -n "$PASSWD_STATUS" ]; then
  echo "  $PASSWD_STATUS"
  echo "$PASSWD_STATUS" | grep -qw P && ok "パスワード設定済み" || info "パスワード未設定（鍵認証のみ）"
else
  ng "パスワード状態を取得できません"
fi
echo ""

# --- 5. sudo/dockerグループ ---
echo "=== 5. グループ所属 ==="
USER_GROUPS=$(groups "$CURRENT_USER" 2>/dev/null)
echo "  所属: $USER_GROUPS"
echo "$USER_GROUPS" | grep -qw sudo   && ok "sudoグループに所属"   || ng "sudoグループに未所属"
echo "$USER_GROUPS" | grep -qw docker && ok "dockerグループに所属" || ng "dockerグループに未所属"
echo ""

# --- 6. 公開鍵 ---
echo "=== 6. 公開鍵 ==="
AUTH_KEYS="/home/$CURRENT_USER/.ssh/authorized_keys"
if [ -f "$AUTH_KEYS" ]; then
  KEY_COUNT=$(wc -l < "$AUTH_KEYS")
  if [ "$KEY_COUNT" -gt 0 ] 2>/dev/null; then
    ok "authorized_keys に ${KEY_COUNT} 件の鍵が登録済み"
  else
    ng "authorized_keys は存在するが空です"
  fi
else
  ng "authorized_keys が存在しません"
fi
echo ""

# --- 7. SSHディレクトリ パーミッション ---
echo "=== 7. SSHディレクトリ パーミッション ==="
SSH_DIR="/home/$CURRENT_USER/.ssh"
if [ -d "$SSH_DIR" ]; then
  SSH_DIR_PERM=$(stat -c '%a' "$SSH_DIR" 2>/dev/null)
  AUTH_KEYS_PERM=$(stat -c '%a' "$AUTH_KEYS" 2>/dev/null)
  [ "$SSH_DIR_PERM" = "700" ]    && ok ".ssh ディレクトリ: $SSH_DIR_PERM"       || ng ".ssh ディレクトリ: $SSH_DIR_PERM (期待値: 700)"
  [ "$AUTH_KEYS_PERM" = "600" ]  && ok "authorized_keys: $AUTH_KEYS_PERM"       || ng "authorized_keys: $AUTH_KEYS_PERM (期待値: 600)"
else
  ng ".ssh ディレクトリが存在しません"
fi
echo ""

# --- 8. UFW ---
echo "=== 8. UFW ==="
UFW_STATUS=$(sudo ufw status verbose 2>/dev/null)
if echo "$UFW_STATUS" | grep -q "Status: active"; then
  echo "$UFW_STATUS"
  ok "UFW は有効です"
  # SSHポートのルール確認
  if echo "$UFW_STATUS" | grep -q "${SSH_PORT}/tcp"; then
    ok "UFW: ${SSH_PORT}/tcp が許可されています"
  else
    ng "UFW: ${SSH_PORT}/tcp のルールがありません"
  fi
  # 22番ポートのルール確認
  if echo "$UFW_STATUS" | grep -q "22/tcp"; then
    info "UFW: 22/tcp がまだ許可されています（不要なら閉じてください）"
  else
    ok "UFW: 22/tcp は許可されていません"
  fi
else
  ng "UFW が無効です"
fi
echo ""

# --- 9. SSHポート ---
echo "=== 9. SSHポート（設定値: $SSH_PORT） ==="
if sudo ss -lnt | grep -q ":${SSH_PORT} "; then
  sudo ss -lnt | grep ":${SSH_PORT} "
  ok "ポート ${SSH_PORT} で待受中"
else
  ng "ポート ${SSH_PORT} は待受していません"
fi
echo ""

# --- 10. SSH設定（99-hardening.conf） ---
echo "=== 10. SSH設定（99-hardening.conf） ==="
HARDENING="/etc/ssh/sshd_config.d/99-hardening.conf"
if [ -f "$HARDENING" ]; then
  grep -v "^#" "$HARDENING" | grep -v "^[[:space:]]*$"
  ok "99-hardening.conf が存在します"
  # 個別チェック（conf ファイルの記載順に合わせる）
  grep -q "^Port ${SSH_PORT}"           "$HARDENING" && ok "SSHポート: ${SSH_PORT}"              || ng "SSHポート ${SSH_PORT} が未設定"
  grep -q "^PermitRootLogin no"         "$HARDENING" && ok "rootログイン: 禁止"                   || ng "rootログイン禁止が未設定"
  grep -q "^PasswordAuthentication no"  "$HARDENING" && ok "パスワード認証: 禁止"                 || ng "パスワード認証禁止が未設定"
  grep -q "^PubkeyAuthentication yes"   "$HARDENING" && ok "公開鍵認証: 有効"                     || ng "公開鍵認証が未設定"
else
  ng "99-hardening.conf が存在しません"
fi
echo ""

# --- 11. SSHサービス ---
echo "=== 11. SSHサービス ==="
SSH_ACTIVE=$(systemctl is-active ssh 2>/dev/null || systemctl is-active sshd 2>/dev/null || echo "unknown")
if [ "$SSH_ACTIVE" = "active" ]; then
  ok "SSHサービスは稼働中"
else
  ng "SSHサービスが停止しています: $SSH_ACTIVE"
fi
echo ""

# --- 12. Docker ---
echo "=== 12. Docker ==="
if command -v docker >/dev/null 2>&1; then
  ok "$(docker --version)"
else
  ng "Docker が未インストール"
fi
echo ""

# --- 13. Docker Compose ---
echo "=== 13. Docker Compose ==="
if docker compose version >/dev/null 2>&1; then
  ok "$(docker compose version)"
else
  ng "Docker Compose が未インストール"
fi
echo ""

# --- 14. Dockerサービス ---
echo "=== 14. Dockerサービス ==="
DOCKER_ACTIVE=$(systemctl is-active docker 2>/dev/null || echo "unknown")
if [ "$DOCKER_ACTIVE" = "active" ]; then
  ok "Dockerサービスは稼働中"
else
  ng "Dockerサービスが停止しています: $DOCKER_ACTIVE"
fi
echo ""

# --- 15. Git ---
echo "=== 15. Git ==="
if command -v git >/dev/null 2>&1; then
  ok "$(git --version)"
else
  ng "Git が未インストール"
fi
echo ""

# --- 16. 作業ディレクトリ ---
echo "=== 16. 作業ディレクトリ ==="
HOME_DIR="/home/${CURRENT_USER}"
WORK_DIRS=$(find "$HOME_DIR" -maxdepth 1 -mindepth 1 -type d ! -name '.*' 2>/dev/null)
if [ -n "$WORK_DIRS" ]; then
  for dir in $WORK_DIRS; do
    DIR_NAME=$(basename "$dir")
    ls -ld "$dir"
    ok "${HOME_DIR}/${DIR_NAME} 作成済み"
  done
else
  info "作業ディレクトリは未作成（.env で WORK_DIR_NAME が空の場合は正常です）"
fi
echo ""

# --- 17. 一時鍵の削除確認 ---
echo "=== 17. 一時鍵の削除確認 ==="
if [ -f /root/my_key.pub ]; then
  ng "/root/my_key.pub がまだ残っています"
else
  ok "/root/my_key.pub は削除済み"
fi
echo ""

# --- 18. 22番ポート ---
echo "=== 18. 22番ポート ==="
if sudo ss -lnt | grep -q ":22 "; then
  ng "22番ポートがまだ待受中です（閉じることを推奨）"
  sudo ss -lnt | grep ":22 "
else
  ok "22番ポートは閉じています"
fi
echo ""

# --- 19. セキュリティ自動更新 ---
echo "=== 19. セキュリティ自動更新 ==="
if dpkg -l unattended-upgrades 2>/dev/null | grep -q '^ii'; then
  ok "unattended-upgrades がインストール済み"
else
  ng "unattended-upgrades が未インストール"
fi
if [ -f /etc/apt/apt.conf.d/20auto-upgrades ]; then
  if grep -q 'Unattended-Upgrade "1"' /etc/apt/apt.conf.d/20auto-upgrades; then
    ok "セキュリティ自動更新が有効"
  else
    ng "セキュリティ自動更新が無効"
  fi
else
  ng "20auto-upgrades 設定ファイルが存在しません"
fi
echo ""

# --- 20. インストール済みパッケージ ---
echo "=== 20. インストール済みパッケージ（全13個） ==="
PKG_ALL_OK=true
for pkg in ca-certificates curl gnupg lsb-release software-properties-common \
           ufw unattended-upgrades \
           docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin \
           git; do
  if dpkg -s "$pkg" 2>/dev/null | grep -q 'ok installed'; then
    ok "$pkg"
  else
    ng "$pkg が未インストール"
    PKG_ALL_OK=false
  fi
done
echo ""

# --- サマリ ---
TOTAL=$((PASS + FAIL))
echo "========================================"
echo " 確認完了: 全20項目（チェックポイント ${TOTAL}件）"
echo " ✅ ${PASS}件 OK / ❌ ${FAIL}件 NG"
if [ "$FAIL" -eq 0 ]; then
  echo " 🎉 全チェック通過！"
else
  echo " ⚠️  NGの項目を確認してください"
fi
echo "========================================"
