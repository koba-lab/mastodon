# デプロイ自動化の設計

[`../infrastructure.md`](../infrastructure.md) 5節の要約から遷移してきた場合、まず全体像は
そちらを参照してください。ここには issue #876 の検討過程と、実装した設計の詳細を置きます。
運用手順・必要な GitHub Secrets は
[`deploy-runbook.md`](deploy-runbook.md) を参照してください。

---

## 実装した設計

### バージョン識別子

git タグ名が、チェックアウト対象・イメージタグ・ロールバック対象を兼ねます。識別子は
1個です。上流追随は `v4.6.5` のようなタグ、イカトドン独自リリースはその末尾へ `.N` を
足した `v4.6.5.1` のようなタグを使います（PEP440 として妥当なため `ikatodon-build.yml`
は変更不要）。

### サーバー上の git clone を版管理の主役として使い続ける

`docker-compose.yml` が上流追随のたびにコンフリクトすることは、問題ではなく意図した
設計です（オーナー合意済み。「採用しなかった案」参照）。したがって clone を廃止せず、
`git fetch --tags && git checkout <tag>` をデプロイ機構の中心に据えました。

- タグをチェックアウトすれば、そのバージョンの `docker-compose.yml` がそのまま揃います。
  タグ `v4.6.5` の compose は `ghcr.io/koba-lab/ikatodon:v4.6.5` を参照済みです。
  テンプレートも `envsubst` もバージョン変数も不要です
- `public/` を同時に正しいバージョンへ更新できます。nginx の
  `location ~ ^/(emoji|packs|system/accounts/avatars|system/media_attachments/files)` は
  `try_files $uri @proxy` でディスクを先に見るため、clone を止めると古い絵文字が
  ディスクから配られ続けます

### 実装

- `ikatodon/ansible/roles/mastodon/` — checkout（作業ツリー clean 検証・タグと稼働中
  イメージの一致確認込み）、`docker-compose.override.yml`（プライベート IP への publish
  のみ）と `.env.production`（2世代バックアップ）の配布、`docker compose pull`
- `ikatodon/ansible/roles/nginx/` — vhost・upstream snippet のテンプレート、drain / undrain
- `ikatodon/ansible/playbooks/deploy.yml` — 上記2つの role を束ね、drain → `up -d` →
  ヘルスチェック → undrain → migration を1台ずつ実行する
- `.github/workflows/ikatodon-deploy.yml` — `workflow_dispatch` で対象タグを受け取り、
  存在確認・ssh 到達性確認・migration 要否判定をしたうえで上記 playbook を呼ぶ薄い層

### ゼロダウンタイム

nginx に `upstream ikatodon_web` / `upstream ikatodon_streaming` を導入し、隣サーバーの
プライベート IP を `backup` として登録しました（既存の `acme-challenge` upstream と
同じパターン）。プライベート網なので平文 HTTP で足ります。

```nginx
upstream ikatodon_web {
  server 127.0.0.1:3000 max_fails=2 fail_timeout=5s;
  server <peer の private IP>:3000 backup;
}
```

`proxy_next_upstream` は POST を再送しないため、これだけでは投稿が失敗し得ます。対策として
コンテナを止める前に nginx から自分を外します（drain）。「通常版」「drain 版」2種類の
upstream snippet を Ansible が配布し、デプロイのたびにシンボリックリンクを張り替えて
reload します。

```
/etc/nginx/sites-available/ika.queloud.net           # Ansible の template（実体）
/etc/nginx/sites-enabled/ika.queloud.net             # symlink（既存のまま）
/etc/nginx/snippets/ikatodon-upstream-normal.conf    # Ansible の template
/etc/nginx/snippets/ikatodon-upstream-drain.conf     # 自ホストを down にしたもの
/etc/nginx/snippets/ikatodon-upstream.conf           # symlink。drain 切替はこれを張り替える
```

WebSocket（streaming）は再接続が発生します。ここは構造上ゼロにできません。

### 切替可否の判定

`docker compose up -d` は healthcheck の完了を待たずに戻るため、Ansible の `uri` モジュール
で明示的にポーリングします。3つすべてが確認できて初めて nginx を戻します。

- `web` の `/health`（DB / Redis 接続は見ません）
- `streaming` の `/api/v1/streaming/health`
- `sidekiq` がコンテナとして running であること

`web` の `/health` が DB / Redis 接続を確認しないため、新イメージにアプリ側のバグがあり
DB/Redis 接続だけが壊れているケースは検知できません。この範囲は許容しています
（依存確認込みのチェックへの拡張は別途の課題とします）。

### migration

pre（`SKIP_POST_DEPLOYMENT_MIGRATIONS=true`）→ 全台入替 → post の順で実行します。
実行は `docker compose run --rm web`（`exec` は使いません。CLAUDE.md）。1台目でのみ
実行します。

要否は GitHub Actions 側で判定します。稼働中バージョンと対象バージョンの間で
`git diff --name-only <稼働中> <対象> -- db/migrate db/post_migrate` が空なら、pre / post を
丸ごとスキップします。

### 切り戻し

**ロールバック = 前バージョンのデプロイ**です。専用の経路は持ちません。

- デプロイ開始前に全ホストの稼働バージョンを取得します（ssh 越しに `git describe --tags`）。
  2台の間で食い違う場合は中断します。前回のデプロイが中途半端に終わった証拠であり、
  その上に重ねないためです
- 各ホストでも、作業ツリーのタグと稼働中コンテナのイメージタグが一致しない場合は
  中断します（`mastodon` role 内で確認）
- コンテナの入替またはヘルスチェックに失敗した場合、そのホストは **drain されたまま**
  playbook を終了します。自動で undrain しません。壊れた可能性のあるコンテナへ
  トラフィックを戻す方が、drain されたまま隣ホストが全量を受けてサービス継続する
  より悪化し得るためです。復旧するまで隣ホストが全量を受けます

pre-deployment migration の後にアプリだけ戻すのは安全です。Mastodon の2段階 migration は
「pre は旧コードが動いたまま適用できる」ことを前提とした設計だからです。post 実行後は逆で、
アプリだけ戻すと壊れる可能性があるため、自動では戻しません。

`git checkout` は作業ツリーが汚れていると失敗します。`git status --porcelain` が空である
ことを先に検証し、汚れていれば強制的な上書きはせず中断します（手で編集した内容を黙って
捨てないため）。

### dry run

`workflow_dispatch` の `dry_run` 入力を `true` にすると、checkout・override 配布・
`.env.production` 配布・`docker compose pull` までで打ち切ります。本番への影響がない
範囲（コンテナの起動・nginx の切替を行わない）なので、staging を建てずに本番で
検証できます。

---

## 採用しなかった案（検討記録）

| 案                                                            | 不採用の理由                                                                                                                                                                                                                                                                                                            |
| --------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Kamal**                                                       | `deploy.yml` が compose と二重管理になる。本家が `command` や `healthcheck` を変えても伝播せず静かに壊れる。ステージングが無く CI しか使えない環境では反映結果の検証がしにくい                                                                                                                                         |
| **Docker Swarm**                                                | 2台間で `2377/tcp` `7946/tcp+udp` `4789/udp` を開ける必要があり、VPS の制約で開けられない可能性                                                                                                                                                                                                                        |
| **Kubernetes / k3s**                                            | 2台構成に対して過大                                                                                                                                                                                                                                                                                                    |
| **サーバー上の git clone を廃止する**                           | 検討当初は「静的ファイルはイメージ内のアプリ自身が配信できるため clone を維持する理由が無い」という方向で進めていたが、`public/` が更新されたときに反映されない問題（絵文字・アバター等がディスクから古いまま配られ続ける）を見落としていた。指摘を受けて撤回し、clone を維持する現在の設計に戻した                    |
| **compose ファイルのテンプレート化（envsubst）**                | イメージタグを `compose.override.yml.template` に切り出し `envsubst` で埋め込む案を検討したが、`docker-compose.yml` のコンフリクトは意図した設計であり解決すべき問題ではないと判明したため、そもそもの動機が無くなった                                                                                                 |
| **`releases/<version>/` + `current` シンボリックリンク方式**    | Capistrano 同様の世代管理方式を検討したが、「ロールバック = 前バージョンのデプロイ」という設計にしたことで、世代ディレクトリ・`current` シンボリックリンク・世代の保持数管理・ホスト間の状態受け渡しがすべて不要になった。前バージョンの compose は git の当該タグから常に再現できるため、ホスト上に保管する必要がない |
| **nginx の `proxy_cache` 導入**（上流サンプルは `@mastodon` に適用） | 恩恵を受けるのは匿名アクセス（連合クローラ・リンクプレビュー・検索エンジン）だけで負荷が問題という情報が無いこと、`Vary` が付いていない認証依存のエンドポイントが1つでもあれば情報漏洩になり検証が必要になること、デプロイ自動化とは独立した変更であることの3点から見送る。負荷が問題になった時点で計測しながら単独の PR で検討する |

---

## 実機で未確認の事項

- GHA からサーバーへの ssh 経路が実際に通るか（`ufw` が無効なことと、GitHub-hosted runner
  から到達できることは別問題）。`ikatodon-deploy.yml` の疎通確認ステップで検証する
- `COMPOSE_PROJECT_NAME` の実機値（`ikatodon/ansible/roles/mastodon/defaults/main.yml`
  参照）
- 2台のプライベート IP（`ikatodon/ansible/host_vars/web1.yml` / `web2.yml` 参照）
