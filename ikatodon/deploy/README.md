# ikatodon デプロイ自動化

タグを push するとコンテナイメージのビルドから Web サーバーへの反映までが自動で行われます。

## インフラ構成

| 役割    | 台数 | 備考                                                                       |
| ------- | ---- | -------------------------------------------------------------------------- |
| Web     | 2    | ConoHa VPS。`docker compose` で `web` / `streaming` / `sidekiq` を起動     |
| db      | 1    | ConoHa VPS（[ikatodon-db](https://github.com/koba-lab/ikatodon-db)）       |
| redis   | 1    | ConoHa VPS（[ikatodon-redis](https://github.com/koba-lab/ikatodon-redis)） |
| storage | -    | Backblaze のブロックストレージ                                             |

ロードバランサーは置かず、DNS ラウンドロビンで 2 台の Web サーバーにリクエストを振り分けています。

## デプロイの流れ

1. `.github/workflows/ikatodon-build.yml` がタグ push で `ghcr.io/koba-lab/ikatodon` と
   `ghcr.io/koba-lab/ikatodon-streaming` のイメージをビルドして push する
2. ビルド成功後に `.github/workflows/ikatodon-deploy.yml` が呼び出される
   1. **pre deployment migration**: 1 台目の Web サーバーで
      `SKIP_POST_DEPLOYMENT_MIGRATIONS=true rails db:migrate` を実行する。
      旧コードと新コードが同時に動いても壊れないマイグレーションだけが適用されるため、
      ローリングデプロイ中もサービスを止めずに済む
   2. **rolling deploy**: Web サーバーを 1 台ずつ（`max-parallel: 1`）更新する。
      イメージを pull し、`docker compose up -d --wait` で healthy になるまで待ち、
      さらに `/health` と `/api/v1/streaming/health` を叩いて確認してから次の 1 台へ進む。
      更新中のサーバーはもう 1 台が引き続きリクエストを処理する
   3. **post deployment migration**: 全台が新コードになってから残りのマイグレーションを実行する
3. いずれかの手順で失敗した場合はそこで停止し、まとめが Job Summary に出力される

失敗時（コンテナが healthy にならない・ヘルスチェックが通らない）は、そのサーバーだけ
直前のバージョンへ自動でロールバックし、`docker compose ps` と直近 200 行のログを
Actions のログへ出力します。マイグレーションが失敗した場合は `rails db:migrate` の
出力がそのまま Actions のログに残るため、サーバーへ入らずに原因を確認できます。

手動でデプロイしたいときは Actions から **Deploy ikatodon** を `workflow_dispatch` で
実行し、デプロイしたいタグ（例: `v4.6.4`）を入力してください。

## 必要な設定

### Repository variables

| 名前                    | 例                                        | 説明                                       |
| ----------------------- | ----------------------------------------- | ------------------------------------------ |
| `IKATODON_WEB_HOSTS`    | `["web1.example.com","web2.example.com"]` | 更新する Web サーバー（JSON 配列、更新順） |
| `IKATODON_DEPLOY_USER`  | `mastodon`                                | SSH ユーザー                               |
| `IKATODON_MASTODON_DIR` | `/home/mastodon/live`                     | `docker-compose.yml` があるディレクトリ    |

### Secrets

| 名前                       | 説明                                                             |
| -------------------------- | ---------------------------------------------------------------- |
| `IKATODON_SSH_PRIVATE_KEY` | 各 Web サーバーの deploy ユーザーに登録した秘密鍵                |
| `IKATODON_SSH_KNOWN_HOSTS` | 各 Web サーバーの `known_hosts` エントリ（`ssh-keyscan` の出力） |

デプロイジョブは `production` environment を使うため、GitHub 側で承認者や
デプロイ可能なタグの制限を設定できます。

### サーバー側の前提

- `docker` と `docker compose`（v2）が入っていること
- deploy ユーザーが sudo なしで `docker` を実行できること
- `${IKATODON_MASTODON_DIR}` にこのリポジトリの `docker-compose.yml` と `.env.production` があること
- 同ディレクトリの `.env` に `IKATODON_VERSION` が書き込まれます（`docker-compose.yml` の
  イメージタグはこの値で解決されます）。手動で `docker compose up -d` してもデプロイ済みの
  バージョンが起動します

## スクリプト

サーバー上で実行されるスクリプトは `ikatodon/deploy` にあります。SSH 経由でサーバーへ
コピーされてから実行されるため、単体で実行することもできます。

```console
# 1 台だけ手動で更新する
$ MASTODON_DIR=/home/mastodon/live ./deploy.sh v4.6.4

# マイグレーションだけ実行する
$ MASTODON_DIR=/home/mastodon/live ./migrate.sh v4.6.4 pre
$ MASTODON_DIR=/home/mastodon/live ./migrate.sh v4.6.4 post
```

ロールバックしたいときは、戻したいタグを指定して `deploy.sh` を実行するか、
**Deploy ikatodon** を旧タグで `workflow_dispatch` してください（マイグレーションの
巻き戻しは自動では行われません）。

## ダウンタイムについて

コンテナの入れ替え中はそのサーバーの `web` が数十秒応答しません。DNS ラウンドロビンの
ままだとその間は該当サーバーに割り振られたリクエストが失敗するため、各サーバーの
リバースプロキシ（nginx）で自ホストの `web` が落ちている間はもう 1 台へ流すよう
`upstream` に相手ホストを `backup` として登録し、`proxy_next_upstream error timeout
http_502 http_503 http_504;` を設定しておくとダウンタイムをゼロにできます。
