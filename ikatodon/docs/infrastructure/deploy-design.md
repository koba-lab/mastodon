---
status: draft
fixed: false
ai-review: disabled
---

> [!WARNING]
> **このファイルの内容は確定していません（Fix ではありません）。**
> 検討途中の草案であり、**誤った記述が含まれています**。ここに書かれた手順・コマンド・
> 設定値をそのまま実行しないでください。実装に着手する時点で、改めて検討・検証します。
>
> **AI による自動レビューの対象外です。** Copilot などの自動レビューによる指摘は、
> このファイルに対しては受け付けません。未確定の草案に対する指摘は際限が無く、
> 判断のコストに見合わないためです。

# デプロイ自動化の詳細仕様（draft）

[`../infrastructure.md`](../infrastructure.md) の要約から遷移してきた場合、まず全体像は
そちらを参照してください。ここには compose ファイルのテンプレート化・構成管理・
ゼロダウンタイムデプロイ・デプロイワークフローの検討中の詳細を置きます。

---

## compose ファイルのテンプレート化

イメージタグの指定は `ikatodon/compose.override.yml.template` に移し、GitHub Actions が
`envsubst` でバージョンを埋め込んで各ホストへ配置する案。`docker-compose.yml` は
**本家のまま**に戻す。これにより毎リリースごとに本家との差分がコンフリクトする問題が消える
（`CLAUDE.md` の「上流に手を入れない」方針にも合致する）。

```yaml
services:
  web:
    image: ghcr.io/koba-lab/ikatodon:${IKATODON_VERSION}
    ports: ['${PRIVATE_IP:?PRIVATE_IP is required}:3000:3000']
    logging: { driver: json-file, options: { max-size: 50m, max-file: '3' } }
  streaming:
    image: ghcr.io/koba-lab/ikatodon-streaming:${IKATODON_VERSION}
    ports: ['${PRIVATE_IP:?PRIVATE_IP is required}:4000:4000']
    logging: { driver: json-file, options: { max-size: 50m, max-file: '3' } }
  sidekiq:
    image: ghcr.io/koba-lab/ikatodon:${IKATODON_VERSION}
    logging: { driver: json-file, options: { max-size: 50m, max-file: '3' } }
```

- `sidekiq` にもログ上限を入れる。Docker の `json-file` ドライバは既定でログサイズが
  無制限。3サービスとも同じ上限を設定する
- `sidekiq` はポートを公開しない。ポート公開先はいずれもプライベート網の中だけで、DB /
  Redis と同じ信頼範囲に収める
- `${PRIVATE_IP}` は fail-closed にする。単純な `${PRIVATE_IP}` という書き方だと、変数が
  未設定のとき Compose は空文字で補間し、`ports: [':3000:3000']` のように全インターフェース
  に公開されてしまうため、Compose の必須変数構文 `${PRIVATE_IP:?PRIVATE_IP is required}` を
  使う
- `envsubst` は置換対象の変数を明示的に絞って呼び出す（`envsubst '$IKATODON_VERSION'` の
  ように）。変数指定なしで実行すると、テンプレート内の `${PRIVATE_IP}` まで GHA 側の環境
  変数（通常は未設定＝空文字）で置換されてしまう

ホストの `.env`（Ansible が配布、秘密は含まない想定）:

```
PRIVATE_IP=<プライベートIP>
COMPOSE_PROJECT_NAME=<既存の project 名>
COMPOSE_FILE=/opt/ikatodon/current/docker-compose.yml:/opt/ikatodon/current/compose.override.yml
```

---

## 構成管理（Ansible）

`ikatodon/ansible/` に、`ikatodon-db` と同じ流儀の Ansible playbook を置く案。エージェント
レスで、サーバー側に必要なのは SSH と Python3 のみ（どちらも既存）。常駐プロセスは増えない。

管理対象候補: nginx 設定（テンプレート化。通常版 / drain 版の include を含む）、ufw、
`.env` の非機密部分。

導入は `--check --diff` の dry run で差分ゼロを確認してから適用する想定。現状の設定を
正確にテンプレートへ起こす必要があるため、`sudo nginx -T` で完全な現状を吸い出してから
作業する。

nginx の Docker 化（`ikatodon-redis` と同じ方式）は Cloudflare 化の判断の後に検討する。

⚠️ **未整理**: Ansible が配布するファイルと GitHub Actions がデプロイ時に配布するファイルの
経路が両方あり、管理がどちらに集約されるべきかは実装時にあらためて検討する。

---

## ゼロダウンタイムデプロイ

コンテナをプライベート IP にも公開し、nginx に「隣のサーバー」をバックアップ登録する案。
既存の `acme-challenge` upstream と同じパターンを踏襲する。転送先は隣の nginx ではなく
隣のアプリのポートを直接指すのでループしない。プライベート網なので平文 HTTP で足りる。

```nginx
upstream mastodon_web {
  server 127.0.0.1:3000 max_fails=2 fail_timeout=5s;
  server <隣のプライベートIP>:3000 backup;
}
```

`proxy_next_upstream` は POST を再送しないため、これだけでは投稿が失敗し得る。対策として
コンテナを止める前に nginx から自分を外す（drain）。Ansible が「通常版」「drain 版」両方の
include を配布し、デプロイ時にシンボリックリンクを張り替えて reload する案。

WebSocket（streaming）は再接続が発生する。ここは構造上ゼロにできない。

**切替可否の判定案**: `docker-compose.yml` の `web` / `streaming` には既にコンテナレベルの
healthcheck（`curl localhost:3000/health`）が定義されているが、`docker compose up -d` は
コンテナを起動して即座に終了し、healthcheck の結果を待たない。実際に切替可否を判定する
のは以下の明示的なポーリングで、次の3つがすべて確認できて初めて nginx を復帰する案。

- `web` の `/health`（`app/controllers/health_controller.rb:3-6`）
- `streaming` の `/api/v1/streaming/health`
- `sidekiq` が起動後も running であること（healthcheck エンドポイントを持たないため、
  コンテナの状態確認で代替する）

⚠️ **未整理（実装時に決める）**: `web` の `/health` は DB / Redis への接続確認を行わない。
新イメージにアプリ側のバグがあり DB/Redis 接続だけが壊れているケースを検知できないが、
これを許容するか、依存確認込みのチェックを別途用意するかは実装時に決める。

---

## デプロイワークフロー

### 現状（聞き取り）

手動デプロイ。Web サーバー上で `git pull`（本体の checkout）を行っている。「本家で必要と
される追加コマンド」がどこにも記録されていない。post deployment migration を「1台目だけ
新しい」状態で実行してしまっている。

### 方向性 — Web サーバー上の git clone を廃止する

clone は compose ファイルの配送手段でしかなかったが、静的ファイルはイメージ内のアプリ
自身が配信できるため、clone を維持する理由が無い、という方向で検討している。

**なぜ nginx 側の変更なしでいけそうか（実測）。** 本家のサンプル設定 `dist/nginx.conf` は
静的ファイルをディスクから優先して探す構成を例示しているが、これは upstream と完全一致
しており実際には使われていない。実際に運用されている
`/etc/nginx/sites-available/ika.queloud.net` は、既に全パスで「ディスクに無ければ常に
アプリへフォールバックする」構成になっている。そのため、clone を廃止してディスク上に
静的ファイルが置かれなくなっても、nginx は常に `@proxy`（アプリ）へフォールバックする
だけで、`RAILS_SERVE_STATIC_FILES=true` によりアプリ側が配信を引き継げる見込み。

```
GHA が envsubst で override（compose.override.yml）を生成
  → 対象バージョンの「タグ」から本家の docker-compose.yml も取得
  → 両方を scp で2台へ配置  （appleboy/scp-action 等）
  → docker compose pull    （appleboy/ssh-action 等）
  → docker compose up -d
```

- ベースの `docker-compose.yml` も override と一緒に配布する案。override（イメージタグ）
  だけを配布するとホスト上の `docker-compose.yml` が固定されてしまい、本家の `command` /
  `healthcheck` / ネットワーク設定の変更が伝播しなくなるため
- `version` 入力は「タグ」に限定する案。`ikatodon-build.yml` はタグ push のときだけ
  イメージをビルドするため、コミット単位のイメージは存在しない
- 整形は `sed` ではなく `envsubst` を使う。ここでも置換対象の変数を `IKATODON_VERSION` だけ
  に絞って呼び出す

### 採用しなかった案（検討記録）

| 案                                                                   | 不採用の理由                                                                                                                                                                                                                                                                                                                        |
| -------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Kamal**                                                            | `deploy.yml` が compose と二重管理になる。本家が `command` や `healthcheck` を変えても伝播せず静かに壊れる。ステージングが無く CI しか使えない環境では反映結果の検証がしにくい（※この制約は自前のロールバック機構にも同様に残っており、本番以外での検証手段が無い点は変わらない）                                                   |
| **Docker Swarm**                                                     | 2台間で `2377/tcp` `7946/tcp+udp` `4789/udp` を開ける必要があり、VPS の制約で開けられない可能性                                                                                                                                                                                                                                     |
| **Ansible をデプロイに使う**                                         | Ansible は構成管理ツールでデプロイツールではない。切替もロールバックも自作になる                                                                                                                                                                                                                                                    |
| **Kubernetes / k3s**                                                 | 2台構成に対して過大                                                                                                                                                                                                                                                                                                                 |
| **git clone を維持する**                                             | 版指定の設計が別途必要になり、`public/` の更新への追従作業も残ってしまう                                                                                                                                                                                                                                                            |
| **nginx の `proxy_cache` 導入**（上流サンプルは `@mastodon` に適用） | 恩恵を受けるのは匿名アクセス（連合クローラ・リンクプレビュー・検索エンジン）だけで負荷が問題という情報が無いこと、`Vary` が付いていない認証依存のエンドポイントが1つでもあれば情報漏洩になり検証が必要になること、デプロイ自動化とは独立した変更であることの3点から見送る。負荷が問題になった時点で計測しながら単独の PR で検討する |

### 検討中の設計 — `releases/<version>/` + `current` シンボリックリンク

以前の案は `*.next.yml` / `*.previous.yml` というファイル命名によるステージ・退避方式
だったが、レビューで見つかった複数のバグ（ステージファイルの接尾辞の不統一、`prepare` の
再実行で退避先を上書きしてしまう、等）は、どちらも「今どの版が有効か」を命名規約という
アプリケーション側の取り決めだけで表現していたことが根本原因だった。そこで Capistrano と
同じ、バージョン番号付きディレクトリ＋ `current` シンボリックリンク方式を検討している。

```
/opt/ikatodon/
  releases/
    v4.6.4/   docker-compose.yml, compose.override.yml, .env.production -> ../../.env.production
    v4.6.5/   docker-compose.yml, compose.override.yml, .env.production -> ../../.env.production
  current -> releases/v4.6.5        ← シンボリックリンク
  .env                              ← PRIVATE_IP, COMPOSE_PROJECT_NAME, COMPOSE_FILE（Ansible が配布）
  .env.production                   ← 秘密ファイル本体はここに1つだけ（Ansible が配布）
```

「今どの版が有効か」を `current` シンボリックリンクの参照先という OS の機能で表現し、
ファイル命名の整合性を人や CI が手作業で守らずに済ませる狙い。

| 担当（案）                   | 内容                                                                                                                                                                                                                                      |
| ---------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Ansible（一度きり・冪等）    | `/opt/ikatodon/releases/` を作る。初回移行（ブートストラップ）を実行し、その完了後に `.env` の `COMPOSE_FILE` を `current` 配下へ向ける。`.env.production` の配置と `COMPOSE_PROJECT_NAME` の設定も Ansible の責務                        |
| GitHub Actions（毎デプロイ） | `releases/.tmp-<version>-<run_id>/` に compose 2ファイルと `.env.production` への symlink を組み立て、内容が完成してから `mv -T` で `releases/<version>/` へアトミックに配置する → drain 後に `ln -sfn releases/<version> current` で切替 |
| 世代管理                     | 直近2世代を保持。切替前に `readlink current` で現在版を記録し、現在版とその直前版を明示的に除外して削除する（バージョン番号のソート順に依存しない）                                                                                       |

いくつか固めた個別ポイント（検討過程のメモ）:

- `.env.production` は releases 配下へコピーせずシンボリックリンクで参照する案。
  `docker-compose.yml` の3サービスすべてが `env_file: .env.production` を相対パスで
  指定しているため、秘密ファイル本体は `/opt/ikatodon/.env.production` の1箇所にだけ置き、
  各 `releases/<version>/` 配下にはシンボリックリンクを作る
- `COMPOSE_PROJECT_NAME` を固定する。compose ファイルの置き場所が変わると Docker Compose
  が自動生成する project 名も変わり得るため、Ansible が同じ project 名を `.env` に設定する
- `prepare` は冪等かつアトミックに書く。一時ディレクトリで release の中身を完成させてから
  `mv -T` で配置し、既存の `releases/<version>/` は上書きせず再利用する
- リモートでの `docker compose` 操作は作業ディレクトリを明示する（`cd /opt/ikatodon` または
  `--project-directory /opt/ikatodon`）

**手動設定は一切不要にする方向。すべて IaC（Ansible + GitHub Actions）で完結させる。**

#### 初回移行（ブートストラップ）の考え方

現在、本番は checkout 上の compose ファイルで稼働しており、`/opt/ikatodon/releases/` も
`current` シンボリックリンクも存在しない。この状態のまま通常のデプロイワークフローを
実行すると `readlink current` が失敗するため、初回だけの移行手順が必要になる。

ブートストラップは Ansible の冪等なタスクとして書く案（一度きりの手動作業にはしない）。

1. `/opt/ikatodon/releases/` ディレクトリを作る
2. 現行の `COMPOSE_PROJECT_NAME` を実機で確認し、`.env` に固定する
3. `COMPOSE_FILE` を `current` 配下へ向ける前に、現在稼働中のバージョンの compose 一式を
   初期 release として `releases/<現行version>/` へ取り込む
4. `.env.production` の本体を `/opt/ikatodon/.env.production` へ移動し、初期 release から
   のシンボリックリンクを張る
5. `current` を初期 release へ向ける
6. ここまで完了してから `.env` の `COMPOSE_FILE` を `current` 配下へ向ける

この順序であれば、切り替えの前後で `docker compose` が参照する実体は常に「今動いている
のと同じ compose ファイル」であり続け、ブートストラップの過程でコンテナが不要に再起動
しないはず、という見立て。

#### ワークフロー構造（案）

```
on: workflow_dispatch
  inputs: version（例 v4.6.5）, pause_before_post（既定 false）
concurrency: 本番デプロイで1本に限定

verify        PR 時の CI で担保済みの内容を再確認
prepare       各ホストで、releases/.tmp-<version>-<run_id>/ に新しい override と対象タグの
                docker-compose.yml を envsubst で生成し、.env.production への symlink を張って
                中身を完成させる → mv -T で releases/<version>/ へアトミックに配置
                → docker compose pull で新イメージのみ事前取得
pre-migrate   releases/<version>/ にステージ済みの新イメージから db:migrate
                （SKIP_POST_DEPLOYMENT_MIGRATIONS=true。exec は使わない）
deploy        単一ジョブ内で host1 → host2 の順に明示的に直列実行する（matrix は使わない）。
                各ホストで: drain → readlink current で切替前の版を記録 →
                current を切替 → docker compose up -d → 3つのヘルスチェックを待つ →
                失敗時は記録した版へ自動ロールバック
gate          if: inputs.pause_before_post → Environments の承認待ち
post-migrate  db:migrate（全台更新後）
```

**matrix をやめた理由**: 以前の案は `matrix: [host1, host2]` + `max-parallel: 1` だったが、
`readlink current` で読み取る「切替前の版（ロールバック先）」を matrix の各 leg（別々の
ジョブ実行）のシェル内にしか保持できず、host2 が失敗したときに host1 を戻すための情報が
matrix の構造上残らない問題があった。単一ジョブ内で2ホストを明示的に直列制御する方式で
検討し直している。

その他のメモ:

- `version` の入力値がそのまま `releases/<version>/` のディレクトリ名・
  `${IKATODON_VERSION}` の両方に使われる
- workflow-level の `concurrency` グループを必須とする
- バックアップのジョブは持たない（PITR 側で対応。[`backup-design.md`](./backup-design.md) 参照）
- post migration が全台更新後に走る（現状の問題の修正）
- migration の有無は GHA 側で `git diff --name-only <稼働中> <対象> -- db/migrate
db/post_migrate` で判定し、空なら pre/post ごとスキップできる案

#### ロールバックの層分け（案）

| いつ                                          | 動作案                                                                                                                                                                                                                            |
| --------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| ヘルスチェックが通らない                      | 自動。`current` を切替直前の版へ戻し、前のイメージ・前の base compose の組で起動し直してから nginx を戻す。host2 で失敗した場合は host1 も逆順に drain して戻す。この逆順の復元自体が失敗した場合は自動リトライせず停止・通知する |
| migration が失敗                              | 自動で中断。`db:migrate` は `disable_ddl_transaction!` を使う migration もあるため DB が部分的に更新されている可能性があり、「影響なし」ではない                                                                                  |
| post migration が失敗                         | 自動では戻さない。両台とも新版で DB が中途半端な状態。デプロイを止めて通知する                                                                                                                                                    |
| 公開後に不具合が判明（post migration 実行前） | 手動。前の `version` を入力して再実行する。DB は戻らない（PITR が保険）                                                                                                                                                           |
| 公開後に不具合が判明（post migration 実行後） | 単純なアプリロールバックは安全ではない。`db/post_migrate` にはスキーマ削除を伴う migration が含まれるため、旧コードに戻すと壊れる可能性がある。forward fix か DB 復元（PITR）を伴う手順が必要になる                               |

#### 検証の分担（案）

| どこ           | 何を                                                                       | 何を確認していないか                                                                                                                                   |
| -------------- | -------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------ |
| PR 時の CI     | 生成した compose の構文検証。イメージが定義どおり起動し `/health` を返すか | ホスト固有値（`PRIVATE_IP` 等）が無いので不完全                                                                                                        |
| prepare ジョブ | `releases/<version>/` に配置した compose ファイルの構文検証                | 構成（構文・変数展開結果）の検証であって、ホスト IP に実際に bind できるか、コンテナが起動して `/health` を返すかは別途 preflight で確認する必要がある |

---

## 未確認事項

- GHA からサーバーへの ssh 経路が実際に通るか（`ufw` が無効なことと、GitHub-hosted runner
  から到達できることは別問題）。セルフホストランナーは採用しない方針（パブリックリポジトリ
  でフォークからの PR が実行され得るため）
