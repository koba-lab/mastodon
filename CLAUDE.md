# イカトドン (ikatodon)

koba-lab が運用する Mastodon フォークです。上流は [mastodon/mastodon](https://github.com/mastodon/mastodon)。

## 最重要方針: 上流コードには手を入れない

**上流由来のコードをイカトドン側で修正してはいけません。** バグや設計上の問題を見つけた場合も、このリポジトリでパッチを当てるのではなく上流に issue / PR として報告してください。

理由は、独自パッチが上流バージョン追随のたびにマージコンフリクトの原因になり、フォークの保守コストが際限なく増えるためです。

これはレビュー指摘（Copilot の自動レビューを含む）に対しても同様です。指摘内容が技術的に正しくても、対象が上流由来のコードであれば**本リポジトリでは修正せず、その理由を返信して見送ります**。判断に迷ったら、そのファイルが上流と一致しているかを確認してください。

```bash
git diff --stat <上流タグ> HEAD -- <ファイル>   # 出力が空なら上流と完全一致 = 触らない
```

`spec/` も例外ではありません。上流のテストファイルに独自のテストを足すと、同じ理由で衝突します。

独自差分を増やしてよいのは、**上流に存在しないファイル**（`.github/workflows/ikatodon-build.yml`、`docs/README.md`、`app/javascript/styles/ikadon/` など）か、イカトドン固有の設定・ブランディングに限られます。

## ブランチ構成

| ブランチ   | 役割                               |
| ---------- | ---------------------------------- |
| `ikatodon` | デフォルトブランチ。本番相当       |
| `master`   | 上流追随用。機能 PR はここへ向ける |

機能 PR は `master` にマージし、その後 `master` → `ikatodon` の PR で本番へ反映します。

この `master` → `ikatodon` の PR は、`.github/workflows/ikatodon-promote-pr.yml` が `master` への push を検知して自動作成します。これまで手で作っていたものを自動化しただけで、マージするかどうかは常に人間の判断です。既に開いている PR があればタイトルと本文が更新されるだけで、重複して作られることはありません。

タイトルは `master → ikatodon (PR #883)` の形になります。番号は運ぶ変更の PR で、辿れば中身が分かります。

### CI のゲートは `master` 側に置く

必須ステータスチェック（ruleset の "Require status checks to pass"）は **`master` にだけ設定し、`ikatodon` には設定しません**。コードが入ってくる入口は `master` であり、`ikatodon` へは master で CI を通した内容しか流れてこないためです。

この配置には実利もあります。既定の `GITHUB_TOKEN` で作成した PR では CI がトリガーされない（ワークフローの再帰実行を防ぐ GitHub の仕様）ため、`ikatodon` に必須チェックを設定すると、自動作成された PR はチェックが永久に報告されずマージ不能になります。ゲートを `master` 側に置けばこの問題が起きず、PAT も不要です。

どうしても `ikatodon` 側にも必須チェックが必要になった場合は、PAT を `secrets.IKATODON_PROMOTE_TOKEN` に登録してください（`contents:read` / `pull-requests:write`）。未登録なら `GITHUB_TOKEN` にフォールバックします。

必須にするチェックを選ぶときの注意:

- **`paths` フィルタ付きのワークフローを必須にしない。** `lint-ruby` / `lint-js` / `lint-css` / `lint-haml` / `test-js` / `test-migrations` などは変更パスによっては丸ごと実行されません。必須にするとドキュメントだけの PR が "Expected — Waiting for status" で永久に止まります
- **`lint` という名前を指定しない。** `format-check` と `lint-*` の 5 本がどれもジョブ名 `lint` で、名前の文字列照合では区別できません
- 常に実行されるのは `test-ruby.yml` と `format-check.yml` の 2 本だけです（`check-i18n` と `codeql` は `branches: [main, stable-*]` 指定のため `master` / `ikatodon` では発火しません）。名前が一意でパスフィルタもない **`test (.ruby-version)`** が第一候補です

### `ikatodon` への直接マージについて

`master` 以外から `ikatodon` へマージすることは、規約として避けます。ただし GitHub には base/head の組み合わせを制限する機能がないため、機械的には強制していません（強制するにはガード用ワークフローを `ikatodon` の必須チェックにする必要があり、上記の PAT 問題が再発します）。

## 上流バージョン追随の手順

1. 上流タグを fetch する

   ```bash
   git fetch --no-tags https://github.com/mastodon/mastodon \
     refs/tags/vX.Y.Z:refs/tags/vX.Y.Z
   ```

2. **作業前の独自差分を記録する**（作業後との比較に使う）

   ```bash
   git diff --name-only <現行タグ> HEAD    # ファイル集合
   git diff --shortstat  <現行タグ> HEAD   # 行数
   ```

3. コンフリクトしうる範囲を事前に把握する。上流の変更ファイルと独自差分ファイルの積集合だけが対象になる

   ```bash
   comm -12 <(git diff --name-only <現行タグ> HEAD | sort) \
            <(git diff --name-only <現行タグ> <新タグ> | sort)
   ```

4. マージし、コンフリクトを解消する。判断基準は「そのファイルにイカトドン独自の変更が入っているか」
   - **独自変更なし** → 上流版をそのまま採用（失われるものはない）
   - **独自変更あり** → 独自部分を保持しつつ上流の変更を取り込む

5. `docker-compose.yml` のイメージタグを新バージョンへ更新する（`ghcr.io/koba-lab/ikatodon` / `ikatodon-streaming` の 3 箇所）

6. **作業後の独自差分が作業前と一致することを確認する**。ファイル集合・行数が変わっていなければ、独自差分の増減はゼロ

## 検証

上流の CI と同じ内容をローカルでも通します。

```bash
bundle exec rubocop --parallel
bundle exec haml-lint
bundle exec rspec spec/models spec/lib spec/services
bundle exec rspec spec/requests spec/controllers
yarn typecheck && yarn lint:js && yarn lint:css && yarn format:check && yarn test:js run
```

### マイグレーション検証

まず `db/` に差分があるかを見ます。差分がなければ新規マイグレーションは 0 本です。

```bash
git diff --stat <現行タグ> <新タグ> -- db/
```

新規マイグレーションの有無にかかわらず、上流 `.github/workflows/test-migrations.yml` と同じ 4 フローを実行してマイグレーション連鎖が壊れていないことを確認します。空 DB ではなく `rails tests:migrations:prepare_database`（v2.0〜v3.3.0 相当の履歴データを段階投入）を使うこと。

1. `db:prepare` → `db:migrate`
2. `SKIP_POST_DEPLOYMENT_MIGRATIONS=true db:prepare` → `db:migrate`
3. one step: 履歴データ投入 → 全 migrate → `check_database`
4. two step: 履歴データ投入 → v4.2.0 breakpoint → pre-deployment → post-deployment → `check_database`

`RAILS_ENV=test` で実行すること。履歴データの OTP secret はテスト環境のレガシー鍵で暗号化されているため、他の環境では `Unable to decrypt OTP secret` で失敗します。

あわせて `db/schema.rb` が上流と完全一致すること（独自スキーマずれがないこと）も確認します。

## デプロイ

1. タグを push すると `.github/workflows/ikatodon-build.yml` が ghcr へイメージをビルドする
2. `docker compose pull`
3. マイグレーションがある場合は先に流す

   ```bash
   docker compose run --rm web \
     env SKIP_POST_DEPLOYMENT_MIGRATIONS=true bundle exec rails db:migrate
   ```

   `docker compose exec` は使わないこと。稼働中の**旧**コンテナの中で実行され、新しいマイグレーションファイルが存在しないまま「何もせず成功」します。`run` は `image:` から新しいコンテナを作るため `pull` 済みなら新コードで動きます（`down` は不要）。`--service-ports` は付けないこと（稼働中の web とポートが衝突します）。

4. `docker compose up -d` で web を入れ替える
5. post-deployment マイグレーション

   ```bash
   docker compose run --rm web bundle exec rails db:migrate
   ```

## 既知の事情

- `db/migrate/20180528141302_create_custom_filters.rb` は上流の `20180628181026_...` をリネームしたもの。内容は同一。上流版が復活していないか追随のたびに確認すること
- `app/javascript/styles/ikadon*` の独自テーマは「塩漬け」方針。4.6 のデザイントークン刷新には追随していないが、`config/themes.yml` でコメントアウトされているため実害はない
- 本番は PostgreSQL 16 (`ikatodon-db`) / Redis 7 (`ikatodon-redis`)。`docker-compose.yml` の db / redis サービスはコメントアウトされている
