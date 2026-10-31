# ikadon テーマ

イカトドン独自のテーマ。グレーのギザギザ地に、角丸のカラムとギザギザのヘッダーが乗る見た目。

## 経緯

Mastodon v2.9 の頃に作られたが、バージョンアップに追随できず `config/themes.yml` で
コメントアウトされたまま約8年放置された。2020年に
[PR #19](https://github.com/koba-lab/mastodon/pull/19) で v3.1.5 対応が試みられ、
マルチカラムはほぼ移植されたがシングルカラム／SP 対応を残して停止した。

v4.6.4 で復活させたのが現行の実装。デザインの一次ソースは PR #19 の
`app/javascript/styles/ikadon/{variables,diff,ika-style}.scss` と、
同 PR のコメントに残っているスクリーンショットおよびデザイン指示。

PR #19 のブランチは削除済みだが、内容は次のコマンドで復元できる。

```bash
git fetch origin 'refs/pull/19/head:refs/remotes/pr/19'
git show refs/remotes/pr/19:app/javascript/styles/ikadon/diff.scss
```

## なぜ腐ったのか

2つ理由がある。どちらも構造的な問題だった。

1. 旧 `ikadon.scss` は上流のパーシャルを手書きで列挙していた。上流が削除した
   `compact_header` / `footer` / `stream_entries` を参照したまま化石化し、ビルド不能になった
2. `config/themes.yml` でコメントアウトされていたため、**CI がこのテーマを一度もコンパイルしなかった**。
   壊れていることに誰も気付けなかった

2 は `themes.yml` を有効化した時点で解消している（下記「CI が守っている範囲」を参照）。
1 は残っているため、アップグレード時の手順として明文化してある。

## 構成

公式の手順（<https://docs.joinmastodon.org/dev/frontend/theming/>）に従っている。

```
app/javascript/styles/
├── application.scss        上流。default テーマのエントリポイント（触らない）
├── ikadon.scss             ikadon のエントリポイント。application.scss の複製
├── mastodon/theme/         上流のトークン定義（触らない）
└── ikadon/
    ├── _base.scss          パレット。mastodon/theme/_base.scss の複製にイカ配色を当てたもの
    ├── _dark.scss          トークン。mastodon/theme/_dark.scss の複製そのまま
    ├── _light.scss         単一固定配色のため _dark.scss へ委譲する
    ├── _utils.scss         上流の複製そのまま
    ├── index.scss          上流の複製そのまま
    ├── _vars.scss          ストライプのグラデーションと一点物の色
    ├── _image.scss         ギザギザ模様とアイコンの base64 画像
    └── _layer.scss         トークンで表現できない構造的な上書き
```

テーマは**丸ごと差し替えのバンドル**である。`ThemeHelper#current_theme` が選んだテーマの
バンドルが `themes/default` の代わりに読み込まれるため、`ikadon.scss` は
「application.scss の全部 ＋ イカ味」でなければならない。上書きレイヤーではない。

### 配色の当て方

**トークン先行**。`_base.scss` のパレット（`--color-grey-*` / `--color-indigo-*` など）を
イカ配色に差し替えることで、UI 全体の地の色が一括で変わる。上流が新しいコンポーネントを
追加しても、トークンを使っている限り自動的にイカ色になる。

| 上流のパレット | ikadon での意味                                                         |
| -------------- | ----------------------------------------------------------------------- |
| `grey`         | 青みを抜いた無彩色のグレー。`950` (#1f1f1f) と `900` (#272727) が地の色 |
| `indigo`       | オレンジ #fd751d。アクセントカラー                                      |
| `yellow`       | ライム #c9f21b。お気に入りの星                                          |
| `green`        | ミントグリーン #21ea80。ブースト                                        |
| `red`          | 上流のまま（ikadon では色指定が無かった）                               |

`_layer.scss` に書くのはトークンでは表現できないものだけに限る。
ギザギザのストライプ（`repeating-linear-gradient`）、角丸、ギザギザの背景画像がそれ。
個別セレクタでの色の直書きは、上流の UI 変更で浮くので避ける。

### ライト／ダークについて

ikadon は**単一固定配色**。当時この概念が無く、グレーのギザギザ地に暗いコンテンツ領域という
見た目だけが存在した。そのため設定 > 外観 の「ライト／ダーク／自動」を切り替えても
同じ絵になるよう、`_light.scss` は `_dark.scss` へ委譲している。

### 角丸の比率

PR #19 のデザインレビューで確定した規則。`_vars.scss` の `$radius-outer` / `$radius-inner`。

- 外側は 15px
- 角丸を重ねる場合、内側は 5px（外側と同じにするとバランスが崩れる）
- コードスニペット（`.hljs`）は 5px 以下。角が丸いほどクリック領域と認識されるため
- アバターは 50% か 5px

## 公式の手順と違う点

1つだけある。

公式ドキュメントは `my_theme.scss` の中で `@use 'my_theme'` と書けとしているが、
そのとおりに `@use 'ikadon'` と書くと Sass がエントリポイント自身を解決してしまい
`Error: Module loop: this module is already being loaded.` で失敗する。
テーマ名とフォルダ名が同じである以上、公式ドキュメントの例でも同じことが起きる。
そのため `@use 'ikadon/index'` とインデックスを明示している。

## アップグレード時の必須工程

`ikadon.scss` は `application.scss` の複製である。上流がパーシャルを追加・削除しても
自動では追随しない。`application.scss` は過去2年で7回変更されており、年3〜4回発生する。

Mastodon を上げたら必ず次を実行し、差分が無いことを確認する。

```bash
diff <(grep '^@use' app/javascript/styles/application.scss) \
     <(grep '^@use' app/javascript/styles/ikadon.scss)
```

期待される差分は次の2点だけ。それ以外が出たら `ikadon.scss` を追随させる。

- `@use 'mastodon/theme'` が `@use 'ikadon/index'` になっている
- 末尾に `@use 'ikadon/layer'` がある

上流が `mastodon/theme/` のトークンを増やした場合は、`ikadon/_dark.scss` にも
同じ差分を取り込む必要がある。`_dark.scss` は上流の複製なので、次で比較できる。

```bash
diff app/javascript/styles/mastodon/theme/_dark.scss \
     app/javascript/styles/ikadon/_dark.scss
```

## CI が守っている範囲

`test-ruby.yml` の `build` ジョブが `bin/rails assets:precompile` を実行する。
`vite_rails` 経由で Vite ビルドが走り、`config/themes.yml` に載っている**全テーマ**が
コンパイルされる。このワークフローは paths フィルタを持たず、すべての pull request で発火する。

つまり `ikadon.scss` がビルド不能になれば CI が赤くなる。**新しい CI は不要**。
ikadon 専用のワークフローを追加しないこと（上流ファイルを増やさないという方針にも合う）。

ただし CI が検知できるのは「ビルドが壊れた」場合だけである。
上流が追加したパーシャルを `ikadon.scss` が読み落としている場合はビルドが通ってしまい、
その画面だけスタイルが当たらない状態になる。上の必須工程が必要なのはこのため。

## 動作確認

```bash
# SCSS 単体（速い）
node_modules/.bin/sass --load-path=app/javascript --quiet-deps \
  app/javascript/styles/ikadon.scss /dev/null

# lint
yarn lint:css
```

実画面は devcontainer で Mastodon を起動し、設定 > 外観 でテーマを `ikadon` に変更して確認する。
テーマの表示ラベルは `I18n.t("themes.#{theme}", default: theme)`
（`app/views/settings/preferences/appearance/show.html.haml`）により、翻訳が無ければ
テーマ名がそのまま出る。そのため i18n ファイルへの追加は不要。

## 未実装

PR #19 でも未完だった領域。

- `layout-single-column`（PC のシンプル UI）
- SP 幅（600px 未満で強制的に `layout-single-column` になる）

なお、アイコンをイカの形に切り出す `mask-image` は
[PR #19 で「ただ見づらいのでやめた」と結論が出ている](https://github.com/koba-lab/mastodon/pull/19#issuecomment-696283987)ので、
復活させない。
