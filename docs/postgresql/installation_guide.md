# PostgreSQL 16インストールと設定手順

以下の手順では、ConoHa VPSでの新しいサーバーのプロビジョニングからPostgreSQL 16のインストール、基本設定の適用までを詳細に説明します。

## ConoHa VPSで新しいサーバーをプロビジョニング

```bash
# ConoHa APIを使用して新しいVPSを作成する場合
# APIトークンを取得してから以下のコマンドを実行
curl -X POST \
  -H "Accept: application/json" \
  -H "Content-Type: application/json" \
  -H "X-Auth-Token: あなたのAPIトークン" \
  -d '{
    "server": {
      "name": "mastodon-db",
      "imageRef": "Ubuntu 22.04 LTS",
      "flavorRef": "g-c3m4d100", 
      "security_groups": [
        {
          "name": "default"
        },
        {
          "name": "gncs-ipv4-all"
        }
      ],
      "metadata": {
        "instance_name_tag": "mastodon-postgresql"
      }
    }
  }' \
  https://compute.tyo1.conoha.io/v2/あなたのテナントID/servers

# または、ConoHaコントロールパネルからGUIで作成する場合:
# 1. ConoHaにログイン
# 2. VPSメニューから「サーバー追加」を選択
# 3. イメージタイプ: Linux
# 4. OS: Ubuntu 22.04 LTS
# 5. プラン: 4GB以上のメモリを推奨 (g-c3m4d100など)
# 6. ホスト名: mastodon-db
# 7. 「追加」ボタンをクリック
```

## サーバーへの接続とセットアップ

```bash
# サーバーにSSH接続
ssh root@サーバーのIPアドレス

# システムの更新
apt update && apt upgrade -y

# 必要なパッケージのインストール
apt install -y curl ca-certificates gnupg lsb-release
```

## PostgreSQL 16のインストール

```bash
# PostgreSQLの公式リポジトリを追加
sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'

# リポジトリの署名キーを追加
wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add -

# パッケージリストを更新
apt update

# PostgreSQL 16をインストール
apt install -y postgresql-16 postgresql-contrib-16

# PostgreSQLサービスが起動していることを確認
systemctl status postgresql
```

## 基本設定を適用

```bash
# PostgreSQLの設定ファイルを編集
nano /etc/postgresql/16/main/postgresql.conf

# 以下の設定を変更または追加
# listen_addresses = '*'          # すべてのIPアドレスからの接続を許可
# max_connections = 100           # 同時接続数
# shared_buffers = 1GB            # 共有バッファ（サーバーのメモリの1/4程度）
# effective_cache_size = 3GB      # キャッシュサイズ（サーバーのメモリの3/4程度）
# work_mem = 16MB                 # 作業メモリ
# maintenance_work_mem = 256MB    # メンテナンス作業用メモリ
# random_page_cost = 1.1          # SSDを使用している場合
# effective_io_concurrency = 200  # SSDを使用している場合
# wal_buffers = 16MB              # WALバッファサイズ
# default_statistics_target = 100 # 統計情報の詳細度
# checkpoint_completion_target = 0.9
# max_wal_size = 2GB
# min_wal_size = 1GB

# クライアント認証設定ファイルを編集
nano /etc/postgresql/16/main/pg_hba.conf

# 以下の行を追加して、特定のIPアドレスからの接続を許可
# host    all             all             マストドンサーバーのIP/32         md5

# PostgreSQLサービスを再起動
systemctl restart postgresql

# Mastodon用のデータベースとユーザーを作成
sudo -u postgres psql -c "CREATE USER mastodon WITH PASSWORD 'あなたのパスワード';"
sudo -u postgres psql -c "CREATE DATABASE mastodon_production OWNER mastodon;"
sudo -u postgres psql -c "ALTER USER mastodon CREATEDB;"

# 設定が正しく適用されたか確認
sudo -u postgres psql -c "SHOW listen_addresses;"
sudo -u postgres psql -c "SHOW max_connections;"
```

## セキュリティ設定

```bash
# ファイアウォールの設定（UFWを使用）
apt install -y ufw
ufw allow ssh
ufw allow from マストドンサーバーのIP to any port 5432
ufw enable

# ファイアウォールの状態を確認
ufw status
```

以上の手順でConoHa VPS上にPostgreSQL 16をインストールし、Mastodonで使用するための基本設定が完了します。
