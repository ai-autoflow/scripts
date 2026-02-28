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

## 実行フロー（全工程詳細）

```
【手元 Mac でターミナルを開き、1行コマンドを実行】
  ★ユーザーが入力: bash <(curl -sSL .../bootstrap.sh)
  │
  │  bootstrap.sh が curl でダウンロードされ、bash で直接実行される
  │
  ▼
┌─────────────────────────────────────────────────────────────────┐
│ [PHASE 1] ファイルダウンロード                                    │
│   GitHub の raw URL から以下の 8 ファイルを /tmp/ に保存         │
│     ・ansible.cfg          （Ansible 設定）                      │
│     ・requirements.yml     （Galaxy コレクション定義）            │
│     ・site.yml             （メイン Playbook）                    │
│     ・roles/common/tasks/main.yml                               │
│     ・roles/user/tasks/main.yml                                 │
│     ・roles/security/tasks/main.yml                             │
│     ・roles/docker/tasks/main.yml                               │
│     ・roles/workdir/tasks/main.yml                              │
└─────────────────────────────────────────────────────────────────┘
  │
  ▼
┌─────────────────────────────────────────────────────────────────┐
│ [PHASE 2] Ansible 確認・インストール                               │
│   ① ansible コマンドが既にあるか確認                             │
│   ② なければ: python3 -m venv /tmp/vps_ansible_venv を作成      │
│   ③ pip install ansible（仮想環境内）                            │
│      ※ Homebrew 不要・全 Mac 対応                               │
│   ④ ansible-galaxy collection install                           │
│        community.general   （UFW モジュール等）                  │
│        ansible.posix        （authorized_key モジュール等）       │
└─────────────────────────────────────────────────────────────────┘
  │
  ▼
┌─────────────────────────────────────────────────────────────────┐
│ [PHASE 3] ウィザード（設定入力）                                   │
│                                                                 │
│   ★ユーザーが入力: VPS の IP アドレス                            │
│       例) 210.131.215.183                                       │
│                                                                 │
│   ★ユーザーが入力: 新しいユーザー名                               │
│       例) myuser                                                │
│                                                                 │
│   ★ユーザーが入力: パスワード（入力時は非表示）                    │
│   ★ユーザーが入力: パスワード（確認のため再入力）                  │
│                                                                 │
│   ★ユーザーが入力（または Enter でデフォルト）:                   │
│       ・SSH ポート番号   [デフォルト: 55555]                      │
│       ・SSH Config Host 名 [デフォルト: myvps]                   │
│       ・SSH 鍵ファイル名  [デフォルト: ssh_key_vps]               │
│       ・Docker インストール [デフォルト: yes]                     │
│       ・作業ディレクトリ名 [デフォルト: repo]                     │
└─────────────────────────────────────────────────────────────────┘
  │
  ▼
┌─────────────────────────────────────────────────────────────────┐
│ [PHASE 4] 設定確認画面                                            │
│   入力内容が一覧表示される                                        │
│                                                                 │
│   ★ユーザーが入力: y （続行）/ n （中止）                         │
└─────────────────────────────────────────────────────────────────┘
  │
  ▼
┌─────────────────────────────────────────────────────────────────┐
│ [PHASE 5] SSH 鍵ペア生成（手元 Mac 上で実行）                      │
│   ssh-keygen -t ed25519 -f ~/.ssh/ssh_key_vps -N ""             │
│     → ~/.ssh/ssh_key_vps     （秘密鍵）が生成される              │
│     → ~/.ssh/ssh_key_vps.pub （公開鍵）が生成される              │
│   ※ 同名の鍵が既にある場合はスキップ                             │
└─────────────────────────────────────────────────────────────────┘
  │
  ▼
┌─────────────────────────────────────────────────────────────────┐
│ [PHASE 6] VPS に接続（パスワード認証・★この1回だけ★）             │
│                                                                 │
│   ① SSH ControlMaster 接続を確立                                │
│      ssh -o ControlMaster=yes root@<IP> -p 22                   │
│                                                                 │
│      ★ユーザーが入力: VPS の root パスワード                     │
│         ※ これがパスワードを入力する唯一の機会                    │
│         ※ 以降はすべて SSH 鍵認証で自動実行                      │
│                                                                 │
│   ② ControlMaster 経由で公開鍵を VPS に送信・登録               │
│      ssh-copy-id を内部で呼び出し、                              │
│      VPS の /root/.ssh/authorized_keys に公開鍵を追記            │
│      ※ ControlMaster が生きているため追加パスワード入力は不要     │
│                                                                 │
│   ③ ControlMaster 接続を閉じる                                  │
└─────────────────────────────────────────────────────────────────┘
  │
  ▼
┌─────────────────────────────────────────────────────────────────┐
│ [PHASE 7] SSH 鍵認証テスト                                        │
│   3 秒待機後、鍵認証で接続確認                                    │
│   ssh -i ~/.ssh/ssh_key_vps -o BatchMode=yes root@<IP> "true"   │
│   ✓ 接続成功 → 次フェーズへ                                      │
│   ✗ 接続失敗 → エラーを表示してスクリプトを停止                   │
└─────────────────────────────────────────────────────────────────┘
  │
  ▼
┌─────────────────────────────────────────────────────────────────┐
│ [PHASE 8] Ansible 実行ファイル生成（手元 Mac 上で生成）            │
│   /tmp/vps_ansible/inventory.ini を生成                          │
│     [vps]                                                       │
│     <IP> ansible_user=root ansible_port=22 ...                  │
│                                                                 │
│   /tmp/vps_ansible/vars.yml を生成                               │
│     new_user: <ユーザー名>                                       │
│     new_user_password_b64: <パスワードの Base64>                 │
│     ssh_port: <新SSHポート>                                      │
│     install_docker: yes/no                                      │
│     work_dir_name: <作業Dir名>                                   │
│     local_pub_key_path: ~/.ssh/ssh_key_vps.pub                  │
└─────────────────────────────────────────────────────────────────┘
  │
  ▼
┌─────────────────────────────────────────────────────────────────┐
│ [PHASE 9] Ansible Playbook 実行（約 5〜10 分・全自動）            │
│  ansible-playbook -i inventory.ini site.yml -e @vars.yml        │
│                                                                 │
│  ┌── role: common （パッケージ更新・基本設定）───────────────────┐ │
│  │  ★ここから先はすべて VPS 上で自動実行される                   │ │
│  │                                                              │ │
│  │  [apt ロック対策]                                            │ │
│  │  ① unattended-upgrades サービスを一時停止                   │ │
│  │  ② apt-daily サービスを一時停止                             │ │
│  │  ③ apt-daily-upgrade サービスを一時停止                     │ │
│  │  ④ dpkg/apt ロックファイルの解放を待機（最大 180 秒）        │ │
│  │     ※ Ubuntu 24.04 起動直後の自動更新との競合を防ぐ          │ │
│  │                                                              │ │
│  │  [STEP 1: パッケージ更新]                                    │ │
│  │  ⑤ apt update（パッケージリスト更新）                       │ │
│  │  ⑥ apt upgrade（全パッケージを最新化）                      │ │
│  │     + autoremove（不要パッケージ削除）                       │ │
│  │     + autoclean（キャッシュ削除）                            │ │
│  │                                                              │ │
│  │  [STEP 2・8・11: 前提パッケージ導入・自動更新設定]            │ │
│  │  ⑦ apt install:                                             │ │
│  │     ・ca-certificates        （SSL証明書）                   │ │
│  │     ・curl                   （HTTPクライアント）             │ │
│  │     ・gnupg                  （GPG暗号化）                   │ │
│  │     ・lsb-release            （ディストリビューション情報）   │ │
│  │     ・software-properties-common（リポジトリ管理）           │ │
│  │     ・git                    （バージョン管理）               │ │
│  │     ・unattended-upgrades    （セキュリティ自動更新）         │ │
│  │                                                              │ │
│  │  ⑧ /etc/apt/apt.conf.d/20auto-upgrades を VPS に配置        │ │
│  │     APT::Periodic::Update-Package-Lists "1";  ← 毎日更新    │ │
│  │     APT::Periodic::Unattended-Upgrade "1";    ← 毎日適用    │ │
│  │     APT::Periodic::AutocleanInterval "7";     ← 7日クリア   │ │
│  └──────────────────────────────────────────────────────────────┘ │
│                                                                 │
│  ┌── role: user （ユーザー作成・公開鍵登録）─────────────────────┐ │
│  │  [STEP 3: ユーザー作成]                                      │ │
│  │  ① 一般ユーザーを作成（bash シェル・sudo グループ追加）       │ │
│  │  ② パスワードを設定（SHA-512 ハッシュ化して登録）             │ │
│  │                                                              │ │
│  │  [STEP 4: 公開鍵登録]                                       │ │
│  │  ③ /home/<ユーザー>/.ssh/ ディレクトリを作成（パーミッション 0700）│ │
│  │  ④ ~/.ssh/ssh_key_vps.pub を VPS に送信                     │ │
│  │     → /home/<ユーザー>/.ssh/authorized_keys に登録          │ │
│  └──────────────────────────────────────────────────────────────┘ │
│                                                                 │
│  ┌── role: security （UFW・SSH 設定）────────────────────────────┐ │
│  │  [STEP 5: UFW ファイアウォール設定]                          │ │
│  │  ① UFW インストール                                         │ │
│  │  ② デフォルトポリシー設定:                                  │ │
│  │     ・受信: deny（全て拒否）                                 │ │
│  │     ・送信: allow（全て許可）                                │ │
│  │  ③ 新 SSH ポートを許可（レートリミット付き・ブルートフォース対策）│ │
│  │  ④ 22番ポートを一時許可（★セットアップ中のみ・後で閉じる）   │ │
│  │  ⑤ UFW を有効化                                             │ │
│  │                                                              │ │
│  │  [STEP 6: SSH hardening 設定]                               │ │
│  │  ⑥ /etc/ssh/sshd_config.d/ ディレクトリを作成               │ │
│  │  ⑦ /etc/ssh/sshd_config の既存 Port 行をコメントアウト       │ │
│  │     （競合防止のため）                                       │ │
│  │  ⑧ 他の drop-in ファイルの Port 行もコメントアウト           │ │
│  │  ⑨ /etc/ssh/sshd_config.d/99-hardening.conf を VPS に配置  │ │
│  │     Port               <新ポート番号>                        │ │
│  │     PermitRootLogin    no   ← root ログイン禁止              │ │
│  │     PasswordAuthentication no ← パスワード認証禁止           │ │
│  │     PubkeyAuthentication  yes ← 鍵認証のみ許可              │ │
│  │  ⑩ sshd 構文チェック（sshd -t）→ エラーがあれば停止         │ │
│  │  ⑪ SSH サービスを再起動（新ポートで待受開始）                │ │
│  │     ※ 22番ポートはここでは閉じない                          │ │
│  │       （後続タスクの接続が切れるため post_tasks で閉じる）    │ │
│  └──────────────────────────────────────────────────────────────┘ │
│                                                                 │
│  ┌── role: docker （install_docker=yes の場合のみ）──────────────┐ │
│  │  [STEP 7: Docker CE インストール]                            │ │
│  │  ① /etc/apt/keyrings/ ディレクトリを作成                    │ │
│  │  ② アーキテクチャ検出（x86_64→amd64 / aarch64→arm64）       │ │
│  │  ③ Docker 公式 GPG キーを取得                               │ │
│  │     download.docker.com/linux/ubuntu/gpg                    │ │
│  │     → /etc/apt/keyrings/docker.asc に保存                   │ │
│  │  ④ Docker APT リポジトリを追加                              │ │
│  │     /etc/apt/sources.list.d/docker.list                     │ │
│  │  ⑤ apt update（Docker リポジトリ追加後）                    │ │
│  │  ⑥ apt install:                                             │ │
│  │     ・docker-ce              （Docker エンジン本体）         │ │
│  │     ・docker-ce-cli          （CLI ツール）                  │ │
│  │     ・containerd.io          （コンテナランタイム）           │ │
│  │     ・docker-buildx-plugin   （BuildKit 拡張）               │ │
│  │     ・docker-compose-plugin  （Compose V2）                  │ │
│  │  ⑦ Docker サービスを起動・自動起動設定（systemd enable）     │ │
│  │  ⑧ 一般ユーザーを docker グループに追加                     │ │
│  │     （sudo なしで docker コマンドを使えるようにする）          │ │
│  └──────────────────────────────────────────────────────────────┘ │
│                                                                 │
│  ┌── role: workdir （work_dir_name が空でない場合のみ）───────────┐ │
│  │  [STEP 9: 作業ディレクトリ作成]                              │ │
│  │  ① /home/<ユーザー>/<作業Dir名>/ を作成                     │ │
│  │     オーナー: <ユーザー>:<ユーザー>                          │ │
│  │     パーミッション: 0755                                     │ │
│  └──────────────────────────────────────────────────────────────┘ │
│                                                                 │
│  ┌── post_tasks （全 role 完了後の後処理）────────────────────────┐ │
│  │  [STEP 12: 最終パッケージ更新]                               │ │
│  │  ① apt update + apt upgrade（全 role 完了後の最終更新）      │ │
│  │     + autoremove + autoclean                                │ │
│  │  ② SSH サービスを再起動（最終更新後・カスタムポートを確実反映）│ │
│  │                                                              │ │
│  │  [STEP 13: 22番ポートを閉鎖]                                 │ │
│  │  ③ UFW: 22番ポートのルールを削除                            │ │
│  │     ※ 全タスク完了後のここで初めて閉じる（安全なタイミング）  │ │
│  │                                                              │ │
│  │  [STEP 10: 一時公開鍵を削除]                                 │ │
│  │  ④ root の /root/.ssh/authorized_keys から                  │ │
│  │     セットアップ用に登録した公開鍵を削除                      │ │
│  │     ※ 以降 root への SSH 鍵ログインは不可になる              │ │
│  │                                                              │ │
│  │  [再起動]                                                    │ │
│  │  ⑤ VPS を再起動（非同期実行・Ansible からの切断を無視）      │ │
│  └──────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
  │
  ▼
┌─────────────────────────────────────────────────────────────────┐
│ [PHASE 10] SSH config 更新（手元 Mac の ~/.ssh/config に追記）    │
│   Host myvps                                                    │
│     HostName     <IP アドレス>                                   │
│     User         <ユーザー名>                                    │
│     Port         <新 SSH ポート>                                 │
│     IdentityFile ~/.ssh/ssh_key_vps                             │
│   ※ 既に同名の Host がある場合は上書き                           │
└─────────────────────────────────────────────────────────────────┘
  │
  ▼
┌─────────────────────────────────────────────────────────────────┐
│ [PHASE 11] 接続テスト（VPS 再起動後）                             │
│   最大 2 分間（5 秒ごと）リトライしながら接続確認                  │
│   ssh -i ~/.ssh/ssh_key_vps -p <新ポート> <ユーザー>@<IP>        │
│                                                                 │
│   ✓ 接続成功 →「セットアップ完了！」メッセージを表示             │
│   ✗ タイムアウト → エラーを表示（手動で ssh myvps を試してください）│
└─────────────────────────────────────────────────────────────────┘
  │
  ▼
【完了】
  ssh myvps  で接続可能
  （= ssh -i ~/.ssh/ssh_key_vps -p <新ポート> <ユーザー名>@<IP> と同じ）
```

---

## ファイルライフサイクル（どこで作り・いつ送り・どこで実行するか）

### 手元 Mac 上で作成されるファイル

| ファイル | 作成タイミング | 作成方法 | 備考 |
|---------|--------------|---------|------|
| `/tmp/vps_setup_XXXX/ansible.cfg` | PHASE 1 | curl でダウンロード | Ansible 設定 |
| `/tmp/vps_setup_XXXX/requirements.yml` | PHASE 1 | curl でダウンロード | Galaxy コレクション定義 |
| `/tmp/vps_setup_XXXX/site.yml` | PHASE 1 | curl でダウンロード | メイン Playbook |
| `/tmp/vps_setup_XXXX/roles/*/tasks/main.yml` | PHASE 1 | curl でダウンロード（5ファイル） | 各 role の処理定義 |
| `/tmp/vps_setup_XXXX/setup_confirmation.sh` | PHASE 1 | curl でダウンロード | VPS 設定確認スクリプト |
| `/tmp/vps_setup_XXXX/venv/` | PHASE 2 | python3 -m venv | Ansible の Python 仮想環境 |
| `/tmp/vps_setup_XXXX/inventory.ini` | PHASE 8 | スクリプト内で生成 | Ansible 接続先（IP・ポート・鍵パス） |
| `/tmp/vps_ansible_vars_XXXX.yml` | PHASE 8 | スクリプト内で生成 | Ansible 変数（パスワードは base64） |
| `~/.ssh/ssh_key_vps` | PHASE 5 | ssh-keygen | SSH 秘密鍵（セットアップ後も保持） |
| `~/.ssh/ssh_key_vps.pub` | PHASE 5 | ssh-keygen | SSH 公開鍵（セットアップ後も保持） |
| `~/.ssh/config` | PHASE 10 | スクリプト内で追記 | SSH 接続設定（セットアップ後も保持） |

### VPS へ転送されるファイル（Mac → VPS）

| 内容 | 転送タイミング | 転送方法 | VPS 上の転送先 |
|------|--------------|---------|--------------|
| SSH 公開鍵の内容 | PHASE 6 | SSH コマンド経由で echo | `/root/.ssh/authorized_keys` に追記 |
| Ansible 各 role の Python モジュール | PHASE 9（タスク実行都度） | Ansible が SFTP で転送 → 実行 → 削除 | `/tmp/.ansible/tmp/XXXX/` （都度削除） |
| `99-hardening.conf` の内容 | PHASE 9（role: security） | Ansible copy モジュール | `/etc/ssh/sshd_config.d/99-hardening.conf` |
| `20auto-upgrades` の内容 | PHASE 9（role: common） | Ansible copy モジュール | `/etc/apt/apt.conf.d/20auto-upgrades` |
| `setup_confirmation.sh` | PHASE 11 | scp | `~/setup_confirmation.sh` |

> **pipelining = False の理由**
> `pipelining = True` では Ansible が Python コードを SSH の **stdin にそのまま流し込む**。
> Ubuntu 24.04 + OpenSSH 9.x はこのパターンを不正なパケットとみなして TCP RST を返す（`Connection reset by peer`）。
> `pipelining = False` にすることで Ansible は **SFTP でファイルとして転送 → 実行 → 削除** という正規の手順を踏む。

### VPS 上で実行されるもの

| 実行ファイル | 実行タイミング | 実行場所 | 実行ユーザー |
|-------------|--------------|---------|------------|
| Ansible Python モジュール（タスク単位） | PHASE 9（各タスク） | VPS（/tmp/.ansible/tmp/） | root |
| `99-hardening.conf` 配置・sshd 再起動 | PHASE 9（role: security） | VPS | root |
| `setup_confirmation.sh` | PHASE 11 | VPS（~/） | 新ユーザー |

### セットアップ後に削除されるファイル

**VPS 上:**

| ファイル | 削除タイミング | 削除理由 |
|---------|--------------|---------|
| `/tmp/.ansible/tmp/XXXX/` | 各タスク実行直後（Ansible が自動削除） | 一時ファイルを残さない |
| `/root/.ssh/authorized_keys` の一時公開鍵エントリ | PHASE 9 post_tasks | root への SSH 鍵ログインを禁止 |
| `~/setup_confirmation.sh` | PHASE 11 実行直後 | 確認スクリプトを残さない |

**Mac 上:**

| ファイル | 削除タイミング | 削除理由 |
|---------|--------------|---------|
| `/tmp/vps_setup_XXXX/`（全ファイル） | スクリプト終了時（trap EXIT） | 一時ファイルのクリーンアップ |
| `/tmp/vps_ansible_vars_XXXX.yml` | スクリプト終了時（trap EXIT） | base64 パスワードを含むため即削除 |

---



## ファイル構成

```
ansible/
├── bootstrap.sh          # エントリーポイント（購入者が実行する唯一のファイル）
├── ansible.cfg           # Ansible 設定（pipelining 無効・ControlMaster 無効）
├── requirements.yml      # Galaxy コレクション定義
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
- **pipelining = False**: Ubuntu 24.04 + OpenSSH 9.x では pipelining が `Connection reset by peer` を引き起こすため無効化
- **22番ポートの閉鎖タイミング**: `ControlMaster=no` では Ansible はタスクごとに新規 SSH 接続を開くため、security role 内で閉じると docker/workdir タスクが接続不能になる。全 role 完了後の post_tasks で閉じることで安全に処理する
- **apt ロック待機**: Ubuntu 24.04 は起動直後に unattended-upgrades が自動実行されるため、common role の最初で自動更新サービスを停止し dpkg ロックの解放を最大 180 秒待機する
- **GITHUB_RAW_URL の変更**: bootstrap.sh 29行目の変数を自分のリポジトリに変更すること
