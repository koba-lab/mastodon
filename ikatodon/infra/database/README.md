# イカトドン PostgreSQLサーバー構築

このリポジトリには、イカトドンのPostgreSQLサーバーを構築するためのAnsibleプレイブックとTerraformコードが含まれています。

## 概要

このプロジェクトは、Mastodonインスタンス（イカトドン）のPostgreSQLサーバーを構築・管理するためのインフラストラクチャコードです。ConoHa VPSでの実行を前提としています。PostgreSQL 16を使用した新しいサーバーを構築し、既存のPostgreSQL 10からのデータ移行を容易にします。

## 構成

```
mastodon/
├── ikatodon/               # イカトドン独自の定義を管理するディレクトリ
│   ├── infra/              # イカトドンのインフラを管理する
│   │   ├── database/       # データベースサーバーのインフラを管理する
│   │   │   ├── ansible/    # Ansibleコード
│   │   │   │   ├── inventory/          # インベントリファイル
│   │   │   │   ├── roles/              # ロール定義
│   │   │   │   │   ├── common/         # 共通設定
│   │   │   │   │   ├── postgresql/     # PostgreSQL設定
│   │   │   │   │   ├── backup/         # バックアップ設定
│   │   │   │   │   ├── mastodon/       # Mastodon連携設定
│   │   │   │   │   └── monitoring/     # モニタリング設定
│   │   │   │   ├── group_vars/         # グループ変数
│   │   │   │   ├── host_vars/          # ホスト変数
│   │   │   │   ├── playbooks/          # プレイブックファイル
│   │   │   │   └── templates/          # テンプレートファイル
│   │   │   └── terraform/              # Terraformコード
│   │   │       ├── modules/            # モジュール
│   │   │       └── environments/       # 環境設定
```

## 前提条件

- Ansible 2.9以上
- Terraform 1.0以上
- ConoHa APIアクセス権限
- SSH接続情報

## 使用方法

### 1. インフラストラクチャのプロビジョニング（Terraform）

```bash
cd mastodon/ikatodon/infra/database/terraform/environments/production
terraform init
terraform plan
terraform apply
```

### 2. PostgreSQLサーバーの設定（Ansible）

```bash
cd mastodon/ikatodon/infra/database/ansible
ansible-playbook -i inventory/production playbooks/postgresql-setup.yml
```

### 3. PostgreSQLアップグレード手順

PostgreSQL 10から16へのアップグレード手順は、GitHubのIssueやGistに保存されています。以下のリンクを参照してください：

- [PostgreSQL 10から16へのアップグレード手順](https://gist.github.com/koba-lab/upgrade-postgresql-10-to-16)
- [アップグレード時のトラブルシューティング](https://gist.github.com/koba-lab/postgresql-upgrade-troubleshooting)

※ 上記リンクは例示です。実際のGistリンクに置き換えてください。

## カスタマイズ

各環境に合わせて以下のファイルを編集してください：

- `ansible/group_vars/all.yml` - 共通変数
- `ansible/host_vars/` - ホスト固有の変数
- `terraform/environments/production/terraform.tfvars` - Terraform変数

## ライセンス

MIT
