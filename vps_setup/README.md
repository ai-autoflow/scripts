# VPS セットアップ ウィザード（Ansible版）

Ubuntu 24.04 LTS の VPS を **1行のコマンド** で自動セットアップするツールです。
ターミナルのウィザードに答えるだけで、セキュアな VPS 環境が完成します。

---

## 対応環境

| 項目 | 要件 |
|------|------|
| 実行環境（手元PC） | **macOS 専用**（Apple Silicon / Intel どちらも対応） |
| VPS OS | Ubuntu 24.04 LTS |
| 必要なもの | VPS の IP アドレス・root パスワード |
| 事前インストール | 不要（Ansible も自動インストール） |

> **注意**: Windows には対応していません。

---

## 使い方（購入者向け）

ターミナルで以下の **1行** を実行するだけです：

```bash
bash <(curl -sSL https://raw.githubusercontent.com/ai-autoflow/scripts/main/vps_setup/bootstrap.sh)
```

---

## ウィザードの入力項目

### 必須項目（3つ）

| 項目 | 説明 | 例 |
|------|------|----|
| VPS の IP アドレス | VPS のパブリック IP | `210.131.215.183` |
| 新しいユーザー名 | 作成する一般ユーザー名（英小文字・数字・`_-`） | `myuser` |
| パスワード | sudo 用パスワード（8文字以上） | `MyPass123!` |

### 任意項目（Enterでデフォルト値）

| 項目 | デフォルト | 説明 |
|------|-----------|------|
| SSH ポート番号 | `55555` | 変更後の SSH ポート（49152〜65535） |
| SSH Config Host 名 | `myvps` | `ssh myvps` で接続する時の名前 |
| SSH 鍵ファイル名 | `ssh_key_vps` | `~/.ssh/` に作成される鍵の名前 |
| Docker インストール | `yes` | Docker CE をインストールするか |
| 作業ディレクトリ名 | `repo` | `/home/<ユーザー>/repo` を作成（`none` で作成しない） |

---

## 全工程ツリー

```
凡例:
  [DL]         GitHub から curl でダウンロード（Mac の /tmp/ に保存）
  [生成]        スクリプトが Mac 上でローカル生成
  [→VPS]       Mac から VPS へファイルを転送
  [実行@Mac]    Mac 上で実行
  [実行@VPS]    VPS 上で実行（ユーザー: root）
  [実行@VPS:u]  VPS 上で実行（ユーザー: 新ユーザー）
  [削除@Mac]    Mac 上のファイルを削除
  [削除@VPS]    VPS 上のファイルを削除
  ★            ユーザーが手動で入力
```

```
★ ターミナルで実行: bash <(curl -sSL .../bootstrap.sh)
│
│   bootstrap.sh 本体が curl でダウンロードされ bash で直接実行される
│
├─[PHASE 1]── ファイルダウンロード ──────────────────────── [実行@Mac]
│
│   [DL] GitHub → /tmp/vps_setup_XXXX/ に保存（curl、9ファイル）
│     ├─ ansible.cfg                    # Ansible 設定
│     ├─ requirements.yml               # Galaxy コレクション定義
│     ├─ site.yml                       # メイン Playbook
│     ├─ roles/common/tasks/main.yml    # パッケージ更新・基本設定
│     ├─ roles/user/tasks/main.yml      # ユーザー作成・公開鍵登録
│     ├─ roles/security/tasks/main.yml  # UFW・SSH hardening
│     ├─ roles/docker/tasks/main.yml    # Docker CE インストール
│     ├─ roles/workdir/tasks/main.yml   # 作業ディレクトリ作成
│     └─ setup_confirmation.sh          # VPS 設定確認スクリプト
│
├─[PHASE 2]── Ansible 確認・インストール ──────────────────── [実行@Mac]
│
│   ① 既存の ansible コマンドを確認 → あればスキップ
│   ② なければ:
│      [生成] /tmp/vps_setup_XXXX/venv/  （python3 -m venv）
│             pip install ansible（仮想環境内・Homebrew 不要）
│   ③ ansible-galaxy collection install
│        community.general  （UFW モジュール等）
│        ansible.posix       （authorized_key モジュール等）
│
├─[PHASE 3]── ウィザード（設定入力） ─────────────────────── [実行@Mac]
│
│   ★ 入力: VPS の IP アドレス
│   ★ 入力: 新しいユーザー名
│   ★ 入力: パスワード（非表示） + 確認のため再入力
│   ★ 入力: SSH ポート番号    [Enter → 55555]
│   ★ 入力: SSH Config Host 名  [Enter → myvps]
│   ★ 入力: SSH 鍵ファイル名   [Enter → ssh_key_vps]
│   ★ 入力: Docker インストール [Enter → yes]
│   ★ 入力: 作業ディレクトリ名  [Enter → repo]
│
├─[PHASE 4]── 設定確認画面 ───────────────────────────────── [実行@Mac]
│
│   入力内容が一覧表示される（パスワードは *** でマスク）
│   ★ 入力: y（続行） / n（中止）
│
├─[PHASE 5]── SSH 鍵ペア生成 ─────────────────────────────── [実行@Mac]
│
│   [生成] ~/.ssh/ssh_key_vps      （秘密鍵・セットアップ後も保持）
│   [生成] ~/.ssh/ssh_key_vps.pub  （公開鍵・セットアップ後も保持）
│   ※ 同名の鍵が既にある場合は .bak.XXXX にリネームしてから新規生成
│
├─[PHASE 6]── VPS に接続（★パスワード認証・この1回だけ） ─── [実行@Mac]
│
│   known_hosts クリア（VPS 再構築時の古いホストキー対策）
│     [削除@Mac] ~/.ssh/known_hosts の <IP> エントリ（あれば）
│     [削除@Mac] ~/.ssh/known_hosts の [<IP>]:<新ポート> エントリ（あれば）
│
│   SSH ControlMaster 接続確立（port 22・パスワード認証）
│     ★ 入力: VPS の root パスワード ← これが唯一のパスワード入力
│
│   公開鍵を VPS に書き込み（ControlMaster 経由・追加パスワード不要）
│     [→VPS] ~/.ssh/ssh_key_vps.pub の内容
│            SSH コマンド経由で echo
│            → /root/.ssh/authorized_keys に追記
│
│   ControlMaster 接続を切断
│
├─[PHASE 7]── SSH 鍵認証テスト ───────────────────────────── [実行@Mac]
│
│   3 秒待機後、鍵認証で接続確認
│     ✓ 成功 → 次フェーズへ
│     ✗ 失敗 → エラーを表示してスクリプトを停止
│
├─[PHASE 8]── Ansible 実行ファイル生成 ───────────────────── [実行@Mac]
│
│   [生成] /tmp/vps_setup_XXXX/inventory.ini
│          → Ansible の接続先定義（VPS IP・port 22・秘密鍵パス）
│
│   [生成] /tmp/vps_ansible_vars_XXXX.yml
│          → Ansible 変数ファイル（パスワードは base64 エンコード済み）
│
├─[PHASE 9]── Ansible Playbook 実行（約 5〜10 分） ─────────── [実行@Mac]
│
│   ansible-playbook site.yml -i inventory.ini -e @vars.yml
│
│   ┌─ Ansible の通信方式（pipelining = False）──────────────────────┐
│   │  Python コードを SSH の stdin に流し込まない                    │
│   │  タスクごとに SFTP でファイル転送 → 実行 → 削除 という正規手順  │
│   │    [→VPS]     Python モジュールを /tmp/.ansible/tmp/ に転送    │
│   │    [実行@VPS] 転送したモジュールを実行                         │
│   │    [削除@VPS] 実行後に /tmp/.ansible/tmp/XXXX/ を即削除        │
│   └────────────────────────────────────────────────────────────────┘
│
│   ┌─ role: common ── パッケージ更新・基本設定 ──── [実行@VPS]
│   │
│   │   [apt ロック対策]
│   │   ① unattended-upgrades / apt-daily / apt-daily-upgrade を停止
│   │   ② dpkg/apt ロックファイルの解放を待機（最大 180 秒）
│   │      ※ Ubuntu 24.04 起動直後の自動更新との競合防止
│   │
│   │   [STEP 1: パッケージ更新]
│   │   ③ apt update（パッケージリスト更新）
│   │   ④ apt upgrade + autoremove + autoclean
│   │
│   │   [STEP 2・8・11: 前提パッケージ導入]
│   │   ⑤ apt install:
│   │      ca-certificates / curl / gnupg / lsb-release
│   │      software-properties-common / git / unattended-upgrades
│   │
│   │   [→VPS 配置] /etc/apt/apt.conf.d/20auto-upgrades
│   │      APT::Periodic::Update-Package-Lists "1";  ← 毎日更新
│   │      APT::Periodic::Unattended-Upgrade "1";    ← 毎日自動適用
│   │      APT::Periodic::AutocleanInterval "7";     ← 7日キャッシュ削除
│   │
│   ├─ role: user ── ユーザー作成・公開鍵登録 ──────── [実行@VPS]
│   │
│   │   [STEP 3: ユーザー作成]
│   │   ① ユーザー作成（bash シェル・sudo グループ追加）
│   │   ② パスワード設定（SHA-512 ハッシュ化）
│   │
│   │   [STEP 4: 公開鍵登録]
│   │   ③ /home/<user>/.ssh/ ディレクトリ作成（0700）
│   │   [→VPS 配置] ~/.ssh/ssh_key_vps.pub の内容
│   │      → /home/<user>/.ssh/authorized_keys（0600）
│   │
│   ├─ role: security ── UFW・SSH hardening ─────────── [実行@VPS]
│   │
│   │   [STEP 5: UFW 設定]
│   │   ① UFW インストール
│   │   ② デフォルト: 受信 deny / 送信 allow
│   │   ③ 新 SSH ポートを許可（レートリミット付き・ブルートフォース対策）
│   │   ④ 22番ポートを一時許可（★後続タスクの接続維持のため）
│   │   ⑤ UFW 有効化
│   │
│   │   [STEP 6: SSH hardening]
│   │   ⑥ /etc/ssh/sshd_config.d/ ディレクトリ作成
│   │   ⑦ 既存 sshd_config の Port 行をコメントアウト（競合防止）
│   │   [→VPS 配置] /etc/ssh/sshd_config.d/99-hardening.conf
│   │      Port               <新ポート番号>
│   │      PermitRootLogin    no
│   │      PasswordAuthentication no
│   │      PubkeyAuthentication   yes
│   │   ⑧ sshd 構文チェック（sshd -t）→ エラーがあれば停止
│   │   ⑨ SSH サービス再起動（新ポートで待受開始）
│   │      ※ 22番ポートはここではまだ閉じない
│   │        （後続タスクが port 22 で接続するため post_tasks まで維持）
│   │
│   ├─ role: docker ── install_docker=yes の場合のみ ── [実行@VPS]
│   │
│   │   [STEP 7: Docker CE インストール]
│   │   ① /etc/apt/keyrings/ ディレクトリ作成
│   │   ② アーキテクチャ検出（x86_64→amd64 / aarch64→arm64）
│   │   ③ Docker 公式 GPG キーを取得
│   │      → /etc/apt/keyrings/docker.asc に保存
│   │   ④ Docker APT リポジトリを追加
│   │      → /etc/apt/sources.list.d/docker.list
│   │   ⑤ apt update（Docker リポジトリ追加後）
│   │   ⑥ apt install:
│   │      docker-ce / docker-ce-cli / containerd.io
│   │      docker-buildx-plugin / docker-compose-plugin
│   │   ⑦ Docker サービス起動・自動起動設定（systemd enable）
│   │   ⑧ 一般ユーザーを docker グループに追加
│   │
│   ├─ role: workdir ── work_dir_name が空でない場合のみ ─ [実行@VPS]
│   │
│   │   [STEP 9: 作業ディレクトリ作成]
│   │   ① /home/<user>/<work_dir>/ を作成
│   │      オーナー: <user>:<user> / パーミッション: 0755
│   │
│   └─ post_tasks ── 全 role 完了後の後処理 ──────────── [実行@VPS]
│
│       [STEP 12: 最終パッケージ更新]
│       ① apt update + upgrade + autoremove + autoclean
│       ② SSH サービス再起動（最終更新後・カスタムポートを確実反映）
│
│       [STEP 13: 22番ポート閉鎖]
│       ③ UFW: 22番ポートのルールを削除
│          ★全タスク完了後のここで初めて閉じる（安全なタイミング）
│
│       [STEP 10: 一時公開鍵を削除]
│       [削除@VPS] /root/.ssh/authorized_keys の一時鍵エントリ
│          → 以降 root への SSH 鍵ログインは不可
│
│       [再起動]
│       ④ VPS を再起動（非同期・Ansible からの切断を無視）
│
├─[PHASE 10]── SSH config 更新 ───────────────────────── [実行@Mac]
│
│   [生成/更新] ~/.ssh/config に追記
│     Host myvps
│       HostName     <IP アドレス>
│       User         <ユーザー名>
│       Port         <新 SSH ポート>
│       IdentityFile ~/.ssh/ssh_key_vps
│   ※ 同名 Host が既にある場合はバックアップして上書き
│
├─[PHASE 11]── 接続テスト ────────────────────────────── [実行@Mac]
│
│   最大 2 分間（5 秒ごと）リトライしながら新ポートで接続確認
│     ✓ 成功 → 次フェーズへ
│     ✗ タイムアウト → warn を表示して完了へ
│
├─[PHASE 12]── 設定確認スクリプト実行 ────────────────── [実行@Mac]
│
│   [→VPS] /tmp/vps_setup_XXXX/setup_confirmation.sh を転送（scp）
│          → VPS の ~/setup_confirmation.sh
│
│   [実行@VPS:u] ~/setup_confirmation.sh（ssh -t でTTY付き実行）
│     全 20 項目をチェック:
│     OS / パッケージ更新状態 / ユーザー / パスワード / グループ
│     公開鍵 / SSH ディレクトリ権限 / UFW / SSH ポート / SSH 設定
│     SSH サービス / Docker / Docker Compose / Docker サービス
│     Git / 作業ディレクトリ / 一時鍵削除確認 / 22番ポート
│     セキュリティ自動更新 / インストール済みパッケージ（全13個）
│
│   [削除@VPS] ~/setup_confirmation.sh（実行後に即削除）
│
└─[PHASE 13]── クリーンアップ（trap EXIT・スクリプト終了時） ─ [実行@Mac]

    [削除@Mac] /tmp/vps_setup_XXXX/ （全ファイル）
               ansible.cfg / site.yml / roles/* / venv/ 等
    [削除@Mac] /tmp/vps_ansible_vars_XXXX.yml
               ※ base64 パスワードを含むため終了時に確実に削除

【完了】
  ssh myvps  で接続可能
  （= ssh -i ~/.ssh/ssh_key_vps -p <新ポート> <ユーザー名>@<IP> と同じ）
```

---

## shell 版スクリプトとの処理対応表

| shell 版 STEP | 内容 | Ansible での実装場所 |
|--------------|------|---------------------|
| STEP 1 | apt update / upgrade | role: common |
| STEP 2 | 前提パッケージ導入 | role: common |
| STEP 3 | ユーザー作成・パスワード設定 | role: user |
| STEP 4 | 公開鍵を authorized_keys に登録 | role: user |
| STEP 5 | UFW 設定 | role: security |
| STEP 6 | SSH hardening | role: security |
| STEP 7 | Docker CE インストール | role: docker |
| STEP 8 | git インストール | role: common（前提パッケージに含む） |
| STEP 9 | 作業ディレクトリ作成 | role: workdir |
| STEP 10 | root の一時公開鍵を削除 | site.yml post_tasks |
| STEP 11 | セキュリティ自動更新有効化 | role: common |
| STEP 12 | 最終パッケージ更新・SSH再起動 | site.yml post_tasks |
| STEP 13 | 22番ポートを閉鎖 | site.yml post_tasks |

---

## ファイル構成

```
ansible/
├── bootstrap.sh          # エントリーポイント（購入者が実行する唯一のファイル）
├── ansible.cfg           # Ansible 設定（pipelining 無効・ControlMaster 無効）
├── requirements.yml      # Galaxy コレクション定義
├── setup_confirmation.sh # VPS 設定確認スクリプト（セットアップ後に VPS 上で実行）
├── site.yml              # メイン Playbook
└── roles/
    ├── common/
    │   └── tasks/main.yml    # apt update・全パッケージ・git・自動更新
    ├── user/
    │   └── tasks/main.yml    # ユーザー作成・パスワード・公開鍵登録
    ├── security/
    │   └── tasks/main.yml    # UFW・SSH hardening（22番閉鎖は site.yml post_tasks）
    ├── docker/
    │   └── tasks/main.yml    # Docker CE インストール（条件付き）
    └── workdir/
        └── tasks/main.yml    # 作業ディレクトリ作成（条件付き）
```

---

## セットアップ後の VPS 状態

| 項目 | 設定値 |
|------|--------|
| SSH ポート | 22 → **55555**（デフォルト・任意変更可） |
| root ログイン | **無効化** |
| パスワード認証 | **無効化**（鍵認証のみ） |
| SSH 鍵方式 | ed25519 |
| ファイアウォール | UFW 有効（新 SSH ポートのみ開放） |
| セキュリティ自動更新 | **有効**（毎日自動適用） |
| Docker | CE + Compose Plugin（選択時のみ） |
| 作業ディレクトリ | `/home/<user>/repo`（選択時のみ） |

---

## セットアップ後の接続方法

```bash
ssh myvps
# = ssh -i ~/.ssh/ssh_key_vps -p 55555 <ユーザー名>@<IP> と同じ
```

---

## 技術メモ（販売者向け）

- **Ansible の自動インストール**: `python3 -m venv` で一時 venv を作成し `pip install ansible`。Homebrew 不要で全 Mac で動作する
- **パスワード認証は 1 回だけ**: ControlMaster で SSH 多重化し、公開鍵登録後は鍵認証のみ
- **pipelining = False**: `pipelining = True` では Ansible が Python コードを SSH の stdin にそのまま流し込む。Ubuntu 24.04 + OpenSSH 9.x はこれを不正なパケットとみなして TCP RST を返す（`Connection reset by peer`）。`False` にすることで SFTP でファイルとして転送 → 実行 → 削除 という正規手順を踏む
- **22番ポートの閉鎖タイミング**: `ControlMaster=no` では Ansible はタスクごとに新規 SSH 接続を開くため、security role 内で閉じると docker/workdir タスクが接続不能になる。全 role 完了後の post_tasks で閉じることで安全に処理する
- **apt ロック待機**: Ubuntu 24.04 は起動直後に unattended-upgrades が自動実行されるため、common role の最初で自動更新サービスを停止し dpkg ロックの解放を最大 180 秒待機する
- **GITHUB_RAW_URL の変更**: bootstrap.sh 29行目の変数を自分のリポジトリに変更すること
