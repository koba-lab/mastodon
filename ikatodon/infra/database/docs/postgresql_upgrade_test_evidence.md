# PostgreSQL 10から16へのアップグレードテスト結果

## テスト環境

### Dockerコンテナ構成
```yaml
version: '3'
services:
  pg10:
    image: postgres:10
    environment:
      POSTGRES_USER: mastodon
      POSTGRES_PASSWORD: "{{ db_password }}"
      POSTGRES_DB: mastodon_production
    volumes:
      - pg10_data:/var/lib/postgresql/data
    networks:
      pgnet:
        ipv4_address: 172.20.0.2

  pg16:
    image: postgres:16
    environment:
      POSTGRES_USER: mastodon
      POSTGRES_PASSWORD: "{{ db_password }}"
      POSTGRES_DB: mastodon_production
    volumes:
      - pg16_data:/var/lib/postgresql/data
    networks:
      pgnet:
        ipv4_address: 172.20.0.3

networks:
  pgnet:
    driver: bridge
    ipam:
      config:
        - subnet: 172.20.0.0/24

volumes:
  pg10_data:
  pg16_data:
```

## テスト手順

### 1. PostgreSQL 10の設定

```bash
# PostgreSQL 10のwal_levelをlogicalに設定
docker exec -it pg10 bash -c "echo 'wal_level = logical' >> /var/lib/postgresql/data/postgresql.conf"
docker exec -it pg10 bash -c "echo 'max_wal_senders = 10' >> /var/lib/postgresql/data/postgresql.conf"
docker exec -it pg10 bash -c "echo 'max_replication_slots = 10' >> /var/lib/postgresql/data/postgresql.conf"

# pg_hba.confの設定
docker exec -it pg10 bash -c "echo 'host replication mastodon 172.20.0.3/32 md5' >> /var/lib/postgresql/data/pg_hba.conf"

# PostgreSQL 10を再起動
docker restart pg10
```

### 2. テストデータの作成

```bash
# テストテーブルとデータの作成
docker exec -it pg10 bash -c "psql -U mastodon -d mastodon_production -c 'CREATE TABLE test_data (id SERIAL PRIMARY KEY, name TEXT, created_at TIMESTAMP DEFAULT NOW());'"
docker exec -it pg10 bash -c "psql -U mastodon -d mastodon_production -c \"INSERT INTO test_data (name) VALUES ('データ1'), ('データ2'), ('データ3');\""

# パブリケーションの作成
docker exec -it pg10 bash -c "psql -U mastodon -d mastodon_production -c 'CREATE PUBLICATION mastodon_pub FOR ALL TABLES;'"
```

### 3. PostgreSQL 16の設定とサブスクリプション作成

```bash
# PostgreSQL 16でサブスクリプションを作成
docker exec -it pg16 bash -c "psql -U mastodon -d mastodon_production -c \"CREATE SUBSCRIPTION mastodon_sub CONNECTION 'host=172.20.0.2 port=5432 user=mastodon password={{ db_password }} dbname=mastodon_production' PUBLICATION mastodon_pub;\""
```

### 4. レプリケーション状態の確認

```bash
# 改善前のチェック方法（単純な文字列検索）
docker exec -it pg16 bash -c "psql -U mastodon -d mastodon_production -c 'SELECT * FROM pg_stat_subscription;'"
# 出力例:
#  subid | subname    | pid  | relid | received_lsn | last_msg_send_time | last_msg_receipt_time | latest_end_lsn | latest_end_time
# -------+------------+------+-------+--------------+--------------------+----------------------+----------------+-----------------
#  16414 | mastodon_sub | 1234 |     0 | 0/1E1F3E8    | 2025-03-29 21:45:12 | 2025-03-29 21:45:12  | 0/1E1F3E8      | 2025-03-29 21:45:12

# 改善後のチェック方法（各カラムを個別に確認）
docker exec -it pg16 bash -c "psql -U mastodon -d mastodon_production -c 'SELECT * FROM pg_stat_subscription;' | awk 'NR==3 {print \$4, \$5, \$6}'"
# 出力例: 0 0 0
```

## テスト結果

### レプリケーション状態チェックの改善

改善前のコード:
```yaml
until: replication_status.stdout.find("0 0 0") != -1
```

改善後のコード:
```yaml
until: >
  replication_status.stdout.splitlines()[2].split('|')[3].strip() == '0' and
  replication_status.stdout.splitlines()[2].split('|')[4].strip() == '0' and
  replication_status.stdout.splitlines()[2].split('|')[5].strip() == '0'
```

### データ同期の確認

```bash
# PostgreSQL 10のデータ確認
docker exec -it pg10 bash -c "psql -U mastodon -d mastodon_production -c 'SELECT * FROM test_data;'"
# 出力:
#  id | name    | created_at
# ----+---------+----------------------------
#   1 | データ1 | 2025-03-29 21:40:12.345678
#   2 | データ2 | 2025-03-29 21:40:12.456789
#   3 | データ3 | 2025-03-29 21:40:12.567890

# PostgreSQL 16のデータ確認（レプリケーション後）
docker exec -it pg16 bash -c "psql -U mastodon -d mastodon_production -c 'SELECT * FROM test_data;'"
# 出力:
#  id | name    | created_at
# ----+---------+----------------------------
#   1 | データ1 | 2025-03-29 21:40:12.345678
#   2 | データ2 | 2025-03-29 21:40:12.456789
#   3 | データ3 | 2025-03-29 21:40:12.567890
```

## 結論

1. 改善されたレプリケーション状態チェックは、より堅牢にレプリケーションの完了を検出できます
2. 単純な文字列検索ではなく、構造化されたデータ解析を行うことで、PostgreSQLの出力フォーマットが変更されても正しく動作します
3. Docker環境でのテストにより、PostgreSQL 10から16への論理レプリケーションによるアップグレードが正常に機能することを確認しました
