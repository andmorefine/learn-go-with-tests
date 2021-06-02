---
description: 'JSON, routing and embedding'
---

# JSON、ルーティング、埋め込み

[**この章のすべてのコードはここにあります**](https://github.com/andmorefine/learn-go-with-tests/tree/master/json)

[前の章](http-server.md) プレイヤーが勝ったゲームの数を保存するWebサーバーを作成しました。

私たちの製品所有者には新しい要件があります。保存されているすべてのプレーヤーのリストを返す「`/league`」という新しいエンドポイントを作成します。彼女はこれがJSONとして返されることを望んでいます。

## ここまでのコードは

```go
// server.go
package main

import (
    "fmt"
    "net/http"
)

type PlayerStore interface {
    GetPlayerScore(name string) int
    RecordWin(name string)
}

type PlayerServer struct {
    store PlayerStore
}

func (p *PlayerServer) ServeHTTP(w http.ResponseWriter, r *http.Request) {
    player := r.URL.Path[len("/players/"):]

    switch r.Method {
    case http.MethodPost:
        p.processWin(w, player)
    case http.MethodGet:
        p.showScore(w, player)
    }
}

func (p *PlayerServer) showScore(w http.ResponseWriter, player string) {
    score := p.store.GetPlayerScore(player)

    if score == 0 {
        w.WriteHeader(http.StatusNotFound)
    }

    fmt.Fprint(w, score)
}

func (p *PlayerServer) processWin(w http.ResponseWriter, player string) {
    p.store.RecordWin(player)
    w.WriteHeader(http.StatusAccepted)
}
```

```go
// InMemoryPlayerStore.go
package main

func NewInMemoryPlayerStore() *InMemoryPlayerStore {
    return &InMemoryPlayerStore{map[string]int{}}
}

type InMemoryPlayerStore struct {
    store map[string]int
}

func (i *InMemoryPlayerStore) RecordWin(name string) {
    i.store[name]++
}

func (i *InMemoryPlayerStore) GetPlayerScore(name string) int {
    return i.store[name]
}
```

```go
// main.go
package main

import (
    "log"
    "net/http"
)

func main() {
    server := &PlayerServer{NewInMemoryPlayerStore()}

    if err := http.ListenAndServe(":5000", server); err != nil {
        log.Fatalf("could not listen on port 5000 %v", err)
    }
}
```

章の上部にあるリンクで対応するテストを見つけることができます。

まず、「`/league`」テーブルのエンドポイントを作成します。

## 最初にテストを書く

いくつかの便利なテスト関数と偽の`PlayerStore`を使用するため、既存のスイートを拡張します。

```go
func TestLeague(t *testing.T) {
    store := StubPlayerStore{}
    server := &PlayerServer{&store}

    t.Run("it returns 200 on /league", func(t *testing.T) {
        request, _ := http.NewRequest(http.MethodGet, "/league", nil)
        response := httptest.NewRecorder()

        server.ServeHTTP(response, request)

        assertStatus(t, response.Code, http.StatusOK)
    })
}
```

実際のスコアとJSONについて心配する前に、目標に向かって反復する計画で変更を小さく保つようにします。最も簡単な開始は、`/league`を押して`OK`が返されることを確認することです。

## テストを実行してみます

```text
=== RUN   TestLeague/it_returns_200_on_/league
panic: runtime error: slice bounds out of range [recovered]
    panic: runtime error: slice bounds out of range

goroutine 6 [running]:
testing.tRunner.func1(0xc42010c3c0)
    /usr/local/Cellar/go/1.10/libexec/src/testing/testing.go:742 +0x29d
panic(0x1274d60, 0x1438240)
    /usr/local/Cellar/go/1.10/libexec/src/runtime/panic.go:505 +0x229
github.com/quii/learn-go-with-tests/json-and-io/v2.(*PlayerServer).ServeHTTP(0xc420048d30, 0x12fc1c0, 0xc420010940, 0xc420116000)
    /Users/quii/go/src/github.com/quii/learn-go-with-tests/json-and-io/v2/server.go:20 +0xec
```

あなたの`PlayerServer`はこのようにパニックになるはずです。`server.go`を指しているスタックトレースのコード行に移動します。

```go
player := r.URL.Path[len("/players/"):]
```

前の章で、これはルーティングを行うためのかなり単純な方法であると述べました。何が起こっているかというと、 `/league`を超えたインデックスから始まるパスの文字列を分割しようとしているため、`範囲外のスライス境界(slice bounds out of range)`になります。

## 成功させるのに十分なコードを書く

Goには[`ServeMux`](https://golang.org/pkg/net/http/#ServeMux) (request multiplexer)と呼ばれるルーティング機構が組み込まれており、`http.Handler`を特定のリクエストパスにアタッチすることができます。

いくつかの罪を犯して、テストをできる限り迅速に通過させましょう。テストに成功したら、安全にリファクタリングできます。

```go
func (p *PlayerServer) ServeHTTP(w http.ResponseWriter, r *http.Request) {

    router := http.NewServeMux()

    router.Handle("/league", http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        w.WriteHeader(http.StatusOK)
    }))

    router.Handle("/players/", http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        player := r.URL.Path[len("/players/"):]

        switch r.Method {
        case http.MethodPost:
            p.processWin(w, player)
        case http.MethodGet:
            p.showScore(w, player)
        }
    }))

    router.ServeHTTP(w, r)
}
```

* リクエストの開始時にはルータを作成し、`x`のパスには`y`ハンドラを使用するように指示します。
* 新しいエンドポイントには`http.HandlerFunc`を使用し、`/league`がリクエストされたときに `w.WriteHeader(http.StatusOK)` を指定する _anonymous function_ を使用して、新しいテストをパスするようにします。
* `/players/`のルートについては、コードを切り取り、別の`http.HandlerFunc`に貼り付けています。
* 最後に、新しいルータの `ServeHTTP` を呼び出して、リクエストを処理します。

これでテストはパスするはずです。

## リファクタリング♪

`ServeHTTP`はかなり大きく見えます。ハンドラを別のメソッドにリファクタリングすることで、物事を少し分離することができます。

```go
func (p *PlayerServer) ServeHTTP(w http.ResponseWriter, r *http.Request) {

    router := http.NewServeMux()
    router.Handle("/league", http.HandlerFunc(p.leagueHandler))
    router.Handle("/players/", http.HandlerFunc(p.playersHandler))

    router.ServeHTTP(w, r)
}

func (p *PlayerServer) leagueHandler(w http.ResponseWriter, r *http.Request) {
    w.WriteHeader(http.StatusOK)
}

func (p *PlayerServer) playersHandler(w http.ResponseWriter, r *http.Request) {
    player := r.URL.Path[len("/players/"):]

    switch r.Method {
    case http.MethodPost:
        p.processWin(w, player)
    case http.MethodGet:
        p.showScore(w, player)
    }
}
```

リクエストが来てからルータの設定をして、それを呼び出すというのは、なんだか変な感じがします。理想的には、ある種の`NewPlayerServer`関数を持っていて、依存関係を取り込んで、 ルータを作成するための一度きりのセットアップを行うことです。それぞれのリクエストはそのルーターのインスタンスを使うだけです。

```go
type PlayerServer struct {
    store  PlayerStore
    router *http.ServeMux
}

func NewPlayerServer(store PlayerStore) *PlayerServer {
    p := &PlayerServer{
        store,
        http.NewServeMux(),
    }

    p.router.Handle("/league", http.HandlerFunc(p.leagueHandler))
    p.router.Handle("/players/", http.HandlerFunc(p.playersHandler))

    return p
}

func (p *PlayerServer) ServeHTTP(w http.ResponseWriter, r *http.Request) {
    p.router.ServeHTTP(w, r)
}
```

* `PlayerServer`はルータを保存する必要があります。
* ルーティングの作成を`ServeHTTP`から`NewPlayerServer`に移動したので、これはリクエストごとではなく一度だけで済みます。
* `NewPlayerServer(&store)`で `PlayerServer{&store}`を実行するために使用していたすべてのテストおよび製品コードを更新する必要があります。

### 最後のリファクタリング

以下のようにコードを変更してみてください。

```go
type PlayerServer struct {
    store PlayerStore
    http.Handler
}

func NewPlayerServer(store PlayerStore) *PlayerServer {
    p := new(PlayerServer)

    p.store = store

    router := http.NewServeMux()
    router.Handle("/league", http.HandlerFunc(p.leagueHandler))
    router.Handle("/players/", http.HandlerFunc(p.playersHandler))

    p.Handler = router

    return p
}
```

最後に、`func (p *PlayerServer) ServeHTTP(w http.ResponseWriter, r *http.Request)`が不要になったので、**delete** が不要になったので、**削除**してください。

## 埋め込み

`PlayerServer`の2番目のプロパティを変更し、名前付きプロパティ`router http.ServeMux`を削除して、`http.Handler`に置き換えました。 これは _埋め込み（embedding）_ と呼ばれます。

> Go は典型的な型駆動型のサブクラス化の概念を提供しませんが、構造体やインターフェイス内に型を埋め込むことで、実装の一部を「借用」する機能があります。

[効果的なGo - Embedding](https://golang.org/doc/effective_go.html#embedding)

これが意味することは、私たちの `PlayerServer`が` http.Handler`が持つすべてのメソッドを持っているということです。これは単なる `ServeHTTP`です。

この`http.Handler`を「埋める」ために、`NewPlayerServer`で作成した`router`に割り当てます。これは`http.ServeMux`が`ServeHTTP`というメソッドを持っているからです。

埋め込み型を介してすでに公開しているため、これにより独自の`ServeHTTP`メソッドを削除できます。

埋め込みは非常に興味深い言語機能です。埋め込みは非常に興味深い言語の機能で、新しいインターフェースを構成するためにインターフェースと一緒に使うことができます。

```go
type Animal interface {
    Eater
    Sleeper
}
```

また、インターフェースだけでなく、具象型でも使用できます。具象型を埋め込むと予想されるように、そのすべてのパブリックメソッドとフィールドにアクセスできます。

### 欠点はありますか？

埋め込む型のすべてのパブリックメソッドとフィールドを公開するため、埋め込み型には注意する必要があります。私たちの場合、\(`http.Handler`\)を公開したい _interface_ だけを埋め込んだので問題ありません。

怠惰で埋め込まれた`http.ServeMux`ではなく具象型でも機能しますが、`Handle(path、handler)`が原因で、`PlayerServer`のユーザーはサーバーに新しいルートを追加できます公開する。

**型を埋め込むときは、公開APIにどのような影響があるかをよく考えてください**

埋め込みを誤用してAPIを汚染し、型の内部を公開することは、よくある間違いです。

これでアプリケーションが再構築され、新しいルートを簡単に追加して、 `/league`エンドポイントの開始を設定できます。ここで、いくつかの有用な情報を返すようにする必要があります。

このようなJSONを返す必要があります。

```javascript
[
   {
      "Name":"Bill",
      "Wins":10
   },
   {
      "Name":"Alice",
      "Wins":15
   }
]
```

## 最初にテストを書く

まず、応答を意味のあるものに解析することから始めます。

```go
func TestLeague(t *testing.T) {
    store := StubPlayerStore{}
    server := NewPlayerServer(&store)

    t.Run("it returns 200 on /league", func(t *testing.T) {
        request, _ := http.NewRequest(http.MethodGet, "/league", nil)
        response := httptest.NewRecorder()

        server.ServeHTTP(response, request)

        var got []Player

        err := json.NewDecoder(response.Body).Decode(&got)

        if err != nil {
            t.Fatalf("Unable to parse response from server %q into slice of Player, '%v'", response.Body, err)
        }

        assertStatus(t, response.Code, http.StatusOK)
    })
}
```

### JSON文字列をテストしないのはなぜですか？

より単純な最初のステップは、応答の本文に特定のJSON文字列があることを表明することだと主張できます。

私の経験では、JSON文字列に対して評価するテストには次の問題があります。

* もろさ。データモデルを変更すると、テストは失敗します。
* デバッグが難しい。 2つのJSON文字列を比較するときに実際の問題が何であるかを理解するのは難しい場合があります。
* 悪い意図。出力はJSONである必要がありますが、本当に重要なのは、データがエンコードされる方法ではなく、データが正確に何であるかです。
* 標準ライブラリの再テスト。標準ライブラリがJSONを出力する方法をテストする必要はありません。すでにテストされています。他の人のコードをテストしないでください。

代わりに、JSONを解析して、テストに関連するデータ構造に変換する必要があります。

### データモデリング

JSONデータモデルを考えると、いくつかのフィールドを持つ`Player`の配列が必要なようですので、これをキャプチャする新しいタイプを作成しました。

```go
type Player struct {
    Name string
    Wins int
}
```

### JSONデコード

```go
var got []Player
err := json.NewDecoder(response.Body).Decode(&got)
```

JSONを解析してデータモデルにするには、 `encoding/json`パッケージから`Decoder`を作成し、その`Decode`メソッドを呼び出します。`Decoder`を作成するには、読み取るための`io.Reader`が必要です。この場合は、応答スパイの`Body`です。

`Decode`は、デコードしようとしているもののアドレスを受け取ります。そのため、前の行で`Player`の空のスライスを宣言します。

JSONの解析が失敗する可能性があるため、`Decode`が`error`を返す可能性があります。それが失敗した場合にテストを続行する意味はないので、エラーを確認し、エラーが発生した場合は `t.Fatalf`でテストを停止します。テストを実行している誰かが解析できない文字列を確認することが重要であるため、エラーとともに応答本文を表示することに注意してください。

## Try to run the test

```text
=== RUN   TestLeague/it_returns_200_on_/league
    --- FAIL: TestLeague/it_returns_200_on_/league (0.00s)
        server_test.go:107: Unable to parse response from server '' into slice of Player, 'unexpected end of JSON input'
```

現在、エンドポイントは本文を返さないため、JSONに解析できません。

## 成功させるのに十分なコードを書く

```go
func (p *PlayerServer) leagueHandler(w http.ResponseWriter, r *http.Request) {
    leagueTable := []Player{
        {"Chris", 20},
    }

    json.NewEncoder(w).Encode(leagueTable)

    w.WriteHeader(http.StatusOK)
}
```

テストに成功しました。

### エンコードとデコード

標準ライブラリの素敵な対称性に注目してください。

* `Encoder`を作成するには、`http.ResponseWriter`が実装する`io.Writer`が必要です。
* `Decoder`を作成するには、レスポンススパイの`Body`フィールドが実装する`io.Reader`が必要です。

この本を通して、`io.Writer`を使用しました。これは、標準ライブラリでの普及と、多くのライブラリが簡単に動作することを示すもう1つのデモです。

## リファクタリング♪

ハンドラーと`leagueTable`を取得することの間に懸念の分離を導入すると、すぐにはハードコードしないことになるので便利です。

```go
func (p *PlayerServer) leagueHandler(w http.ResponseWriter, r *http.Request) {
    json.NewEncoder(w).Encode(p.getLeagueTable())
    w.WriteHeader(http.StatusOK)
}

func (p *PlayerServer) getLeagueTable() []Player {
    return []Player{
        {"Chris", 20},
    }
}
```

次に、テストを拡張して、必要なデータを正確に制御できるようにします。

## 最初にテストを書く

テストを更新して、`League`テーブルにストアでスタブするプレーヤーが含まれていることをアサートできます。

`League`を保存できるように、`StubPlayerStore`を更新します。これは、`Player`のスライスにすぎません。そこに期待されるデータを保存します。

```go
type StubPlayerStore struct {
    scores   map[string]int
    winCalls []string
    league   []Player
}
```

次に、スタブの`League`プロパティに一部のプレーヤーを配置して現在のテストを更新し、サーバーから返されることを評価します。

```go
func TestLeague(t *testing.T) {

    t.Run("it returns the league table as JSON", func(t *testing.T) {
        wantedLeague := []Player{
            {"Cleo", 32},
            {"Chris", 20},
            {"Tiest", 14},
        }

        store := StubPlayerStore{nil, nil, wantedLeague}
        server := NewPlayerServer(&store)

        request, _ := http.NewRequest(http.MethodGet, "/league", nil)
        response := httptest.NewRecorder()

        server.ServeHTTP(response, request)

        var got []Player

        err := json.NewDecoder(response.Body).Decode(&got)

        if err != nil {
            t.Fatalf("Unable to parse response from server %q into slice of Player, '%v'", response.Body, err)
        }

        assertStatus(t, response.Code, http.StatusOK)

        if !reflect.DeepEqual(got, wantedLeague) {
            t.Errorf("got %v want %v", got, wantedLeague)
        }
    })
}
```

## テストを実行してみます

```text
./server_test.go:33:3: too few values in struct initializer
./server_test.go:70:3: too few values in struct initializer
```

## テストを実行するための最小限のコードを記述し、失敗したテスト出力を確認します

`StubPlayerStore`に新しいフィールドがあるので、他のテストを更新する必要があります。他のテストでは`nil`に設定します。

テストをもう一度実行してみてください。

```text
=== RUN   TestLeague/it_returns_the_league_table_as_JSON
    --- FAIL: TestLeague/it_returns_the_league_table_as_JSON (0.00s)
        server_test.go:124: got [{Chris 20}] want [{Cleo 32} {Chris 20} {Tiest 14}]
```

## 成功させるのに十分なコードを書く

データが`StubPlayerStore`にあることを知っており、それをインターフェイス` PlayerStore`に抽象化しました。`PlayerStore`で私たちを渡す誰もがリーグのデータを提供できるように、これを更新する必要があります。

```go
type PlayerStore interface {
    GetPlayerScore(name string) int
    RecordWin(name string)
    GetLeague() []Player
}
```

これで、ハードコードされたリストを返すのではなく、ハンドラーコードを更新してそれを呼び出すことができます。メソッド`getLeagueTable()`を削除してから、`leagueHandler`を更新して`GetLeague()`を呼び出します。

```go
func (p *PlayerServer) leagueHandler(w http.ResponseWriter, r *http.Request) {
    json.NewEncoder(w).Encode(p.store.GetLeague())
    w.WriteHeader(http.StatusOK)
}
```

テストを実行してみてください。

```text
# github.com/quii/learn-go-with-tests/json-and-io/v4
./main.go:9:50: cannot use NewInMemoryPlayerStore() (type *InMemoryPlayerStore) as type PlayerStore in argument to NewPlayerServer:
    *InMemoryPlayerStore does not implement PlayerStore (missing GetLeague method)
./server_integration_test.go:11:27: cannot use store (type *InMemoryPlayerStore) as type PlayerStore in argument to NewPlayerServer:
    *InMemoryPlayerStore does not implement PlayerStore (missing GetLeague method)
./server_test.go:36:28: cannot use &store (type *StubPlayerStore) as type PlayerStore in argument to NewPlayerServer:
    *StubPlayerStore does not implement PlayerStore (missing GetLeague method)
./server_test.go:74:28: cannot use &store (type *StubPlayerStore) as type PlayerStore in argument to NewPlayerServer:
    *StubPlayerStore does not implement PlayerStore (missing GetLeague method)
./server_test.go:106:29: cannot use &store (type *StubPlayerStore) as type PlayerStore in argument to NewPlayerServer:
    *StubPlayerStore does not implement PlayerStore (missing GetLeague method)
```

`InMemoryPlayerStore`と`StubPlayerStore`には、インターフェイスに追加した新しいメソッドがないため、コンパイラーは不平を言っています。

`StubPlayerStore`の場合は非常に簡単です。先ほど追加した`league`フィールドを返すだけです。

```go
func (s *StubPlayerStore) GetLeague() []Player {
    return s.league
}
```

ここでは、`InMemoryStore`の実装方法について説明します。

```go
type InMemoryPlayerStore struct {
    store map[string]int
}
```

`GetLeague`を「適切に」実装することは、マップを反復することでかなり簡単ですが、テストをパスするための最小限のコードを記述しようとしていることを思い出してください。

それでは、コンパイラーを今のところ幸せにして、`InMemoryStore`での実装が不完全であるという不快な気持ちに耐えてみましょう。

```go
func (i *InMemoryPlayerStore) GetLeague() []Player {
    return nil
}
```

これが実際に私たちに伝えていることは、これをテストしたいのですが、とりあえずここに置いておきましょう。

テストを試して実行すると、コンパイラーはパスし、テストはパスするはずです！

## リファクタリング♪

テストコードは意図をうまく伝えておらず、リファクタリングできる定型文がたくさんあります。

```go
t.Run("it returns the league table as JSON", func(t *testing.T) {
    wantedLeague := []Player{
        {"Cleo", 32},
        {"Chris", 20},
        {"Tiest", 14},
    }

    store := StubPlayerStore{nil, nil, wantedLeague}
    server := NewPlayerServer(&store)

    request := newLeagueRequest()
    response := httptest.NewRecorder()

    server.ServeHTTP(response, request)

    got := getLeagueFromResponse(t, response.Body)
    assertStatus(t, response.Code, http.StatusOK)
    assertLeague(t, got, wantedLeague)
})
```

ここに新しいヘルパーがあります

```go
func getLeagueFromResponse(t *testing.T, body io.Reader) (league []Player) {
    t.Helper()
    err := json.NewDecoder(body).Decode(&league)

    if err != nil {
        t.Fatalf("Unable to parse response from server %q into slice of Player, '%v'", body, err)
    }

    return
}

func assertLeague(t *testing.T, got, want []Player) {
    t.Helper()
    if !reflect.DeepEqual(got, want) {
        t.Errorf("got %v want %v", got, want)
    }
}

func newLeagueRequest() *http.Request {
    req, _ := http.NewRequest(http.MethodGet, "/league", nil)
    return req
}
```

サーバーが機能するために必要な最後の1つは、`JSON`を返していることをマシンが認識できるように、応答で`content-type`ヘッダーを返すことを確認することです。

## 最初にテストを書く

このアサーションを既存のテストに追加します

```go
if response.Result().Header.Get("content-type") != "application/json" {
    t.Errorf("response did not have content-type of application/json, got %v", response.Result().Header)
}
```

## テストを実行してみます

```text
=== RUN   TestLeague/it_returns_the_league_table_as_JSON
    --- FAIL: TestLeague/it_returns_the_league_table_as_JSON (0.00s)
        server_test.go:124: response did not have content-type of application/json, got map[Content-Type:[text/plain; charset=utf-8]]
```

## 成功させるのに十分なコードを書く

`leagueHandler`を更新します

```go
func (p *PlayerServer) leagueHandler(w http.ResponseWriter, r *http.Request) {
    w.Header().Set("content-type", "application/json")
    json.NewEncoder(w).Encode(p.store.GetLeague())
}
```

テストは成功するはずです。

## リファクタリング♪

`assertContentType`のヘルパーを追加します。

```go
const jsonContentType = "application/json"

func assertContentType(t *testing.T, response *httptest.ResponseRecorder, want string) {
    t.Helper()
    if response.Result().Header.Get("content-type") != want {
        t.Errorf("response did not have content-type of %s, got %v", want, response.Result().Header)
    }
}
```

テストで使用してください。

```go
assertContentType(t, response, jsonContentType)
```

これで`PlayerServer`を整理したので、`InMemoryPlayerStore`に目を向けることができます。これを製品の所有者にデモしようとした場合、`/league`は機能しないためです。

確信を得るための最も簡単な方法は、統合テストに追加することです。新しいエンドポイントにアクセスして、 `/league`から正しい応答が返されることを確認できます。

## 最初にテストを書く

`t.Run`を使用してこのテストを少し分解し、サーバーテストのヘルパーを再利用できます。これもリファクタリングテストの重要性を示しています。

```go
func TestRecordingWinsAndRetrievingThem(t *testing.T) {
    store := NewInMemoryPlayerStore()
    server := NewPlayerServer(store)
    player := "Pepper"

    server.ServeHTTP(httptest.NewRecorder(), newPostWinRequest(player))
    server.ServeHTTP(httptest.NewRecorder(), newPostWinRequest(player))
    server.ServeHTTP(httptest.NewRecorder(), newPostWinRequest(player))

    t.Run("get score", func(t *testing.T) {
        response := httptest.NewRecorder()
        server.ServeHTTP(response, newGetScoreRequest(player))
        assertStatus(t, response.Code, http.StatusOK)

        assertResponseBody(t, response.Body.String(), "3")
    })

    t.Run("get league", func(t *testing.T) {
        response := httptest.NewRecorder()
        server.ServeHTTP(response, newLeagueRequest())
        assertStatus(t, response.Code, http.StatusOK)

        got := getLeagueFromResponse(t, response.Body)
        want := []Player{
            {"Pepper", 3},
        }
        assertLeague(t, got, want)
    })
}
```

## テストを実行してみます

```text
=== RUN   TestRecordingWinsAndRetrievingThem/get_league
    --- FAIL: TestRecordingWinsAndRetrievingThem/get_league (0.00s)
        server_integration_test.go:35: got [] want [{Pepper 3}]
```

## 成功させるのに十分なコードを書く

`GetLeague()`を呼び出すと、`InMemoryPlayerStore`は`nil`を返すため、修正する必要があります。

```go
func (i *InMemoryPlayerStore) GetLeague() []Player {
    var league []Player
    for name, wins := range i.store {
        league = append(league, Player{name, wins})
    }
    return league
}
```

必要なのは、マップを反復処理して、各キー/値を`Player`に変換することだけです。

これでテストに成功するはずです。

## まとめ

TDDを使用してプログラムを安全に反復し続け、ルーターで保守可能な方法で新しいエンドポイントをサポートし、コンシューマーにJSONを返すことができるようになりました。次の章では、データの永続化とリーグの分類について説明します。

ここで習得したもの

* **ルーティング**. 標準ライブラリには、ルーティングを行うための使いやすい型が用意されています。標準ライブラリは`http.Handler`インターフェースを完全に取り入れており、`Handler`にルートを割り当て、ルータ自身も`Handler`になります。しかし、パス変数のような、あなたが期待するような機能はありません。この情報を自分で簡単に解析することはできますが、それが面倒になったら他のルーティングライブラリを見ることを検討したほうがいいかもしれません。人気のあるもののほとんどは、`http.Handler`も実装するという標準ライブラリの哲学に固執しています。
* **型の埋め込み**. この手法については少し触れましたが、[Effective Goから学ぶ](https://golang.org/doc/effective_go.html#embedding)もあります。ここから一つだけ取っておくべきことがあるとすれば、非常に便利なことがあるということですが、常にパブリックAPIのことを考えて、適切なものだけを公開するということです。
* **JSONのデシリアライズとシリアライズ**. 標準ライブラリは、データのシリアライズとデシリアライズを非常に簡単にしてくれます。また、設定にもオープンで、必要に応じてこれらのデータ変換がどのように動作するかをカスタマイズできます。
