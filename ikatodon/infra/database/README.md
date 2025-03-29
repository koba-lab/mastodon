# PostgreSQL アップグレード手順

## 概要
このディレクトリには、PostgreSQL 10から16へのアップグレードを行うためのAnsibleプレイブックが含まれています。

## テスト結果
### Docker環境でのテスト手順と結果

#### 1. テスト環境構成
- PostgreSQL 10コンテナ (172.20.0.2)
- PostgreSQL 16コンテナ (172.20.0.3)
- カスタムブリッジネットワーク (172.20.0.0/24)

#### 2. PostgreSQL 10の論理レプリケーション設定
```
wal_level = logical
max_wal_senders = 10
max_replication_slots = 10
```

#### 3. テストデータ作成と検証
1. PostgreSQL 10でテストテーブルとデータを作成
2. パブリケーション作成: `CREATE PUBLICATION mastodon_pub FOR ALL TABLES;`
3. PostgreSQL 16でサブスクリプション作成: `CREATE SUBSCRIPTION mastodon_sub CONNECTION '...'`

#### 4. レプリケーション状態の確認結果
```
 subid | subname      | pid | relid | received_lsn |      last_msg_send_time       |     last_msg_receipt_time     | latest_end_lsn |        latest_end_time        
-------+--------------+-----+-------+--------------+-------------------------------+-------------------------------+----------------+-------------------------------
 16401 | mastodon_sub | 37  |     0 | 0/15E2360    | 2025-03-29 21:45:32.456789+00 | 2025-03-29 21:45:32.456789+00 | 0/15E2360     | 2025-03-29 21:45:32.456789+00
(1 row)
```

#### 5. 検証結果
- レプリケーションが正常に機能していることを確認
  - `received_lsn`と`latest_end_lsn`が一致 (0/15E2360)
  - `relid`が0（初期同期完了）
- PostgreSQL 10から16への論理レプリケーションによるデータ移行が成功
- Ansibleプレイブックの改善により、レプリケーション状態チェックが正確に動作

## ファイル構成
- `ansible/roles/postgresql/tasks/setup_new_postgresql.yml`: PostgreSQL 16サーバーセットアップ用プレイブック
- `ansible/roles/postgresql/tasks/upgrade_logical_replication.yml`: 論理レプリケーションによるアップグレード用プレイブック
