# nginx 設定棚卸し

[`../infrastructure.md`](../infrastructure.md) 4節の詳細です。issue #876（デプロイ自動化）の
一環として、本番 Web 2台の `sudo nginx -T` 出力を実機で取得し、上流の推奨設定
（`dist/nginx.conf`）と突き合わせて棚卸ししました。

**このドキュメントは実測結果の記録であり、設定変更は含みません。** ここで洗い出した項目への
対応は、後続の PR（Ansible `nginx` role によるゼロダウンタイムデプロイ導入）でまとめて
行います。

⚠️ プライベート IP・退役サーバーの IP・証明書パス・内部構成の詳細はパブリックリポジトリの
制約上、意図的に記載していません（[`../infrastructure.md`](../infrastructure.md) 冒頭の
方針を参照）。2台の Web サーバーは以下「host1」「host2」と呼びます。現役2台のグローバル IP
自体は `ika.queloud.net` の A レコードで引けるため、[`../ansible/inventory/hosts.yml`](../../ansible/inventory/hosts.yml)
に平文で記載しています。

---

## 1. 2台の設定は実質同一

`sudo nginx -T` の出力を diff した結果、差分は次の1点のみでした。

| 差分                           | host1                         | host2    |
| ------------------------------ | ----------------------------- | -------- |
| `geo $allow_ip` の許可 IP 一覧 | 1件がコメントアウトされている | 全件有効 |

この1点を除き、`nginx.conf` 本体・`sites-enabled/default`・`sites-enabled/ika.queloud.net`・
`sites-enabled/test.ika.queloud.net` はバイト単位で一致しています。したがって「2台の設定が
ドリフトしている」という既知の問題は、**この `geo $allow_ip` の1件に限定される**ことが
実測で確定しました。

## 2. 発見事項

### 2.1 HTTP が HTTPS へリダイレクトされない

`sites-enabled/ika.queloud.net` の80番ポート用 server ブロックは次のように書かれています。

```nginx
server {
  listen 80;
  listen [::]:80;
  server_name default_server;
  ...
}
```

`server_name` に指定した `default_server` は特別な意味を持たず、ただの文字列として扱われます。
`default_server` は `listen` 側の属性であり、`sites-enabled/default` の Debian 既定 vhost が
既に `listen 80 default_server;` を持っています。したがってこの誤指定は「`listen` の書き間違い」
ではなく、「`server_name` に実ホスト名を書き忘れた」ことが原因です。

この結果、`Host: ika.queloud.net` を含むリクエストはどの `server_name` にも一致せず、
`sites-enabled/default` の default_server ブロックへ落ちます。**HTTP でのアクセスは
Debian の初期セットアップページが返り、HTTPS へのリダイレクトが機能していません**
（`curl -I -H 'Host: ika.queloud.net' http://<host>/` で実測確認）。

`nginx -T` の実行時に出る次の警告も、この誤指定が原因です。`ika.queloud.net` と
`test.ika.queloud.net` の両 vhost がどちらも `server_name` に文字列 `default_server` を
掲げているため、同一 listen ソケット上での重複としてはじかれています。

```text
nginx: [warn] conflicting server name "default_server" on 0.0.0.0:80, ignored
nginx: [warn] conflicting server name "default_server" on [::]:80, ignored
```

### 2.2 `/.well-known/acme-challenge/` が ika.queloud.net vhost に到達しない

2.1 と同じ原因です。`location ^~ /.well-known/acme-challenge/` は `ika.queloud.net` の80番
server ブロック内に定義されていますが、`Host: ika.queloud.net` のリクエストがそのブロックに
届かないため、`acme-challenge` upstream 経由の兄弟サーバーへのフォールバックの仕組みは
**機能していません**（実測で404を確認）。

証明書の更新自体は別経路で動作しています（2026-07-21発行・2026-10-19まで有効、
`openssl s_client` で確認済み）。これは certbot が `authenticator = nginx` で稼働しており、
更新のたびに nginx プラグインが一時的な server ブロックを自前で注入して、上記の誤指定を
迂回しているためです。`authenticator = nginx` を維持する方針の詳細は
[`deploy-runbook.md`](deploy-runbook.md) の nginx 設定の節を参照してください。

### 2.3 `acme-challenge` upstream の退役 IP（既知の問題 #7・実測で確定）

```nginx
upstream acme-challenge {
  server <host1 のグローバル IP>:80;
  server <retired-1 のグローバル IP>:80;
  server <retired-2 のグローバル IP>:80;
  server <host2 のグローバル IP>:80;
}
```

4件のうち2件（host1・host2 自身。[`../../ansible/inventory/hosts.yml`](../../ansible/inventory/hosts.yml)
に平文記載済み）は生きていますが、残り2件（retired-1・retired-2）は接続してもタイムアウトし
応答がありません。過去に存在したサーバーの IP が残ったままになっています。実 IP は非公開の
運用記録で管理します。

### 2.4 `geo $allow_ip` のドリフト（1節の差分）

メンテナンスモード中のアクセス許可 IP 一覧が2台で食い違っています。メンテナンス中に
どちらのサーバーへ振られるかでアクセス可否が変わる状態です。

### 2.5 HSTS ヘッダの重複

nginx 側で `add_header Strict-Transport-Security "max-age=31536000";` を設定しており、
アプリ側からも同ヘッダが送られているため、レスポンスに `Strict-Transport-Security` が
2本含まれます（`curl -I` で実測確認）。

### 2.6 `error_page` の二重連結（既知の問題 #12・実測で再確認）

```nginx
error_page 500 501 502 504 /home/mastodon/live/public/500.html;
```

最後の引数は URI として解釈され、`root` ディレクティブと連結されます。絶対パスを書いても
`root` の値の後ろに継ぎ足されるだけなので、実際には存在しないパスになり到達できません
（オーナーによる実機確認済み）。上流サンプルは相対 URI `/500.html` を使っています。

なお `test.ika.queloud.net` vhost の同じ設定は `error_page 500 501 502 504 /500.html;` と
相対 URI になっており、こちらは正しく動作します。2つの vhost 間でも記述が食い違っています。

### 2.7 `nginx.conf` の `ssl_protocols`（既知の問題 #14・実測で確定、実害は限定的）

`http` ブロック直下に次の設定が残っています。

```nginx
ssl_protocols TLSv1 TLSv1.1 TLSv1.2; # Dropping SSLv3, ref: POODLE
```

ただし各 vhost の `server` ブロックで `ssl_protocols TLSv1.2;` に上書きされているため、
実際に TLS 1.0 / 1.1 でネゴシエーションできるわけではありません（プロトコル別に接続して
実測確認）。`http` ブロック側の記述は死んでいるだけで、影響は限定的です。TLS 1.3 も
どこにも設定されておらず有効になっていません。

### 2.8 `test.ika.queloud.net` vhost

サーバー移行時の名残で、現在は不要です（オーナー確認済み）。

- DNS の A レコードが存在せず、外部から到達できません
- 証明書は 2019-09-11 に失効済みで、以後の `certbot renew` は毎回この証明書の更新に
  失敗しています。本物の失敗が起きても、この既知の失敗に紛れて気づけない状態です
- vhost 定義には `test-ikatodon-media/` 宛の `proxy_cache` を使ったバックエンド
  （`s3.us-west-1.wasabisys.com`）が設定されていますが、**本番 `ika.queloud.net` vhost には
  `proxy_cache` を使う location が存在しません**。`proxy_cache_path` のディレクティブ自体は
  両 vhost の先頭で定義されていますが、実際に `proxy_cache` を使っているのは
  `test.ika.queloud.net` 側だけです

### 2.9 `upstream` ブロックを使っていない

現行設定は `proxy_pass http://127.0.0.1:3000;` のように直書きしています。上流サンプル
`dist/nginx.conf` は `upstream backend` / `upstream streaming` を定義してそこへ `proxy_pass`
する構成です。ゼロダウンタイムデプロイ（隣サーバーへの `backup` フォールバック）を導入する
には `upstream` 化が前提になります。詳細は
[`../infrastructure.md`](../infrastructure.md) 4節・[`deploy-design.md`](deploy-design.md)
を参照してください。

## 3. 上流サンプルとの差分まとめ

| 項目                   | 現行                                                         | 上流サンプル（`dist/nginx.conf`）                                                               |
| ---------------------- | ------------------------------------------------------------ | ----------------------------------------------------------------------------------------------- |
| upstream 定義          | 無し（直書き）                                               | `upstream backend` / `upstream streaming`                                                       |
| `ssl_protocols`        | `TLSv1.2` のみ                                               | `TLSv1.2 TLSv1.3`                                                                               |
| cipher                 | `HIGH:!MEDIUM:!LOW:!aNULL:!NULL:!SHA`                        | Mozilla Intermediate 相当                                                                       |
| `ssl_session_tickets`  | 未設定                                                       | `off`                                                                                           |
| `client_max_body_size` | `80m`                                                        | `99m`                                                                                           |
| `proxy_read_timeout`   | 未設定（既定 60s）                                           | `120`                                                                                           |
| 静的パスの location    | `emoji` / `packs` / `system/*` を1つの正規表現でまとめて定義 | `/assets/` `/avatars/` `/emoji/` `/headers/` `/ocr/` `/packs/` `/sounds/` `/system/` を個別定義 |
| `error_page`           | 絶対パスで二重連結（2.6）                                    | 相対 URI `/500.html`                                                                            |
| `proxy_cache`          | 未使用（本番 vhost）                                         | `@mastodon` に `CACHE` ゾーンを適用                                                             |

`proxy_cache` を今回導入しない理由は [`deploy-design.md`](deploy-design.md) の
「採用しなかった案」を参照してください。

## 4. まとめ

後続 PR（Ansible `nginx` role）での対応候補は以下です。優先度・詳細は着手時に確定します。

- `server_name default_server;` を実ホスト名 `ika.queloud.net` に修正（`default_server` は
  `sites-enabled/default` 側にのみ残す。2.1・2.2）
- `acme-challenge` upstream から応答のない2 IP を削除（2.3）
- `geo $allow_ip` をテンプレート化し2台のドリフトを解消（2.4）
- HSTS の重複解消（2.5、nginx 側かアプリ側かは着手時に判断）
- `error_page` を相対 URI へ統一（2.6）
- `ssl_protocols TLSv1.2 TLSv1.3` + Mozilla Intermediate cipher + `ssl_session_tickets off`（2.7）
- `test.ika.queloud.net` vhost の削除、期限切れ証明書の削除（2.8）
- `upstream backend` / `upstream streaming` の導入（2.9、ゼロダウンタイムデプロイの前提）

`sites-enabled/default`（Debian 既定 vhost）自体は今回のスコープ外とし、削除しません。
