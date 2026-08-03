[The documentation has moved to its own repository](https://github.com/tootsuite/documentation/blob/master/README.md)

###ikatodon開発環境のすすめ
postgres と redis は docker で、rails は foreman で動きます。
開発環境の立ち上げはイカのコマンドから

```
$ docker-compose -f docker-compose.dev.yml up -d
$ foreman start
```

ただし初回のみ `docker-compose` のあと、下記コマンドの実行が必要になります。

```
$ bundle install --with development --path vendor/bundle
$ yarn install --pure-lockfile
$ bundle exec rails db:create
$ bundle exec rails db:schema:load
$ bundle exec rails db:seed
```
