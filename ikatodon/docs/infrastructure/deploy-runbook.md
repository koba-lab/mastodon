# デプロイ運用手順

issue #876 で実装したデプロイ自動化の運用手順です。設計の詳細・検討過程は
[`deploy-design.md`](deploy-design.md) を参照してください。

---

## 初回セットアップ（実機情報の投入）

コードの実装だけでは動かず、以下を実機で確認して埋める必要があります。

### GitHub Secrets

`IKATODON_` 接頭辞に統一しています（既存の `IKATODON_PROMOTE_TOKEN` と揃えています）。

| 名前                          | 内容                                                                              |
| ----------------------------- | --------------------------------------------------------------------------------- |
| `IKATODON_ENV_PRODUCTION`     | `.env.production` の全文（複数行の secret 1個）                                   |
| `IKATODON_DEPLOY_SSH_KEY`     | デプロイ専用に新規発行した秘密鍵                                                  |
| `IKATODON_DEPLOY_KNOWN_HOSTS` | 2台分の known_hosts（`ssh-keyscan` で取得し、`StrictHostKeyChecking=yes` で使用） |

未設定なら `ikatodon-deploy.yml` / `ikatodon-nginx.yml` は最初のステップで fail-closed に
落ちます。

### Ansible 変数

| 変数                                | 置き場所                                                                | 確認方法                                                                                                             |
| ----------------------------------- | ----------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------- |
| `mastodon_compose_project_name`     | `ikatodon/ansible/group_vars/all.yml`                                   | `docker inspect --format '{{ index .Config.Labels "com.docker.compose.project" }}' <稼働中コンテナ名>`               |
| `mastodon_private_ip`（ホストごと） | `ikatodon/ansible/host_vars/web1.yml` / `web2.yml`（vault 暗号化）      | `ip -4 addr`（結果は秘密管理下で確認し、このコマンドの出力自体は公開 PR に貼らないこと。infrastructure.md 10節参照） |
| `ikatodon_maintenance_allow_ips`    | `ikatodon/ansible/roles/nginx/defaults/main.yml` を上書き（vault 推奨） | 実機の `geo $allow_ip`（`sudo nginx -T`）                                                                            |

プライベート IP・メンテナンス許可 IP は `ansible-vault encrypt_string` で値単位に暗号化します
（ファイル全体の暗号化はしません。理由は [`../infrastructure.md`](../infrastructure.md)
の GitHub Secrets の節を参照）。

```bash
cd ikatodon/ansible
ansible-vault encrypt_string --ask-vault-pass '<PRIVATE_IP>' --name 'mastodon_private_ip'
# 出力される `mastodon_private_ip: !vault | ...` ブロックを host_vars/web1.yml へ貼り付ける
```

vault パスワードは Ansible 実行者の間で別途共有してください（本ドキュメントには書きません）。

---

## 通常のデプロイ

1. `ikatodon-deploy.yml` を `workflow_dispatch` で実行する
   - `version`: デプロイ対象のタグ名（例 `v4.6.5`）
   - `dry_run`: 初回や不安があるときは `true` にして checkout・pull までで止める
2. ワークフローが自動で行うこと:
   - タグ・イメージ（`ikatodon` / `ikatodon-streaming`）の存在確認
   - ssh 到達性確認
   - 2台の稼働バージョン一致確認、migration 要否判定
   - `web1` → `web2` の順に、drain → checkout → override/`.env.production` 配布 → pull →
     （1台目のみ pre migration）→ `up -d` → ヘルスチェック → undrain
   - 全台入替後、1台目で post migration
3. 完了後、`https://ika.queloud.net/health` と両ホストでの `docker compose ps` /
   `git describe --tags` を確認する

## ロールバック

専用の経路はありません。**前バージョンのタグを指定して通常のデプロイを実行するだけ**です。

- pre-deployment migration の後（post migration 実行前）であれば安全に戻せます
- post-deployment migration 実行後にアプリだけ戻すのは安全ではありません（`db/post_migrate`
  にスキーマ削除を伴う migration が含まれ得るため）。forward fix を検討してください

## nginx 設定の変更

`ikatodon-nginx.yml` を `workflow_dispatch` で実行します。`dry_run`（既定 `true`）で
`--check --diff` の差分を確認してから、`false` にして適用してください。

---

## 障害時の対応

| 事象                                             | 対応                                                                                                                                               |
| ------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------- |
| デプロイ開始前チェックで中断（バージョン不一致） | 前回のデプロイが中途半端に終わっている。両ホストの `git describe --tags` と `docker inspect` を比較し、手動で揃えてから再実行する                  |
| ヘルスチェックが通らない                         | ワークフローはそのホストの undrain を実行せずに失敗する。ログを確認し、必要なら前バージョンで再デプロイする                                        |
| migration が失敗                                 | 自動では戻さない。`db:migrate` は `disable_ddl_transaction!` を使う migration もあり DB が部分的に更新されている可能性がある。個別に調査する       |
| `git checkout` が作業ツリーの汚れで失敗          | サーバー上で誰かが手作業した可能性がある。内容を確認してから対応する（強制的な上書きはしない）                                                     |
| certbot 証明書の更新失敗                         | [`../infrastructure.md`](../infrastructure.md) 5節・[`nginx-audit.md`](nginx-audit.md) 2.2節を参照。`authenticator = nginx` の迂回で通常は救われる |

---

## 既知の制約

- `mastodon_private_ip` が未投入の間は `dry_run=true` でも失敗します。`mastodon` role の
  `docker-compose.override.yml` 配布タスクがこの変数を参照するためです
- `mastodon_compose_project_name` は未投入（プレースホルダーのまま）でも動作します。
  参照するのは稼働中バージョンとの整合性チェック（`failed_when: false` で握りつぶす）だけ
  のため、投入しないとその安全確認だけが機能しなくなります
- Redis / DB サーバーはこのデプロイ機構の対象外です（別リポジトリ `ikatodon-db` /
  `ikatodon-redis`）
