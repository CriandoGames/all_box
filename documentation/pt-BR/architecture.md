🇺🇸 [English](https://github.com/CriandoGames/all_box/blob/main/documentation/en/architecture.md) | 🇧🇷 Português

# Arquitetura interna

Detalhes de implementação por trás das garantias do `all_box`. O uso do
dia a dia do pacote nunca exige ler isto — este documento existe para
contribuidores e para quem quiser auditar as alegações de crash-safety e
de storage Web feitas no
[README](https://github.com/CriandoGames/all_box/blob/main/README.pt-BR.md).

## Crash-safety: write-ahead + rename atômico

Em plataformas IO, toda escrita em disco segue o mesmo pipeline:

1. O novo conteúdo é escrito primeiro num arquivo `.tmp` (write-ahead).
2. Depois que essa escrita termina, um rename atômico substitui o arquivo
   principal (`<container>.db`) pelo conteúdo do `.tmp`.
3. Uma cópia `.bak` do último estado bom conhecido é mantida à parte.

Como o rename é atômico (em filesystems POSIX), o arquivo principal nunca é
observado num estado parcialmente escrito — um crash no meio de uma escrita
deixa o `.db` antigo intacto ou o novo totalmente escrito, nunca uma mistura
dos dois.

### Tratamento de erro de leitura em dois estágios

Na leitura, erros de decodificação UTF-8 e erros de `jsonDecode` são
tratados como estágios de falha distintos. Cada estágio cai para o `.bak`
antes de desistir e começar com um container vazio.

### Portabilidade do `File.rename`

A troca atômica depende da semântica de `File.rename`. Em POSIX
(Linux/macOS/Android/iOS), renomear por cima de um arquivo existente é
atômico. No Windows, o comportamento pode variar entre versões do SDK Dart
— veja
[Limitações conhecidas](https://github.com/CriandoGames/all_box/blob/main/README.pt-BR.md#️-limitações-conhecidas-documentadas-não-escondidas)
no README.

## Coordenação de flush

A lógica de debounce/coalescing/fila de flush serializada vive uma única
vez, dentro do próprio `AllBox`, e funciona contra qualquer implementação
de `AllBoxStorage` (IO, Web, memória, ou uma customizada passada via
`storage:`) — não é duplicada por backend. Isso garante que nunca há duas
escritas concorrentes em andamento contra o mesmo container, mesmo se
`flushNow()` ou `writeAndFlush()` for chamado enquanto um flush debounced
ainda está pendente.

## Backend de storage Web

O backend Web é construído sobre static interop do `dart:js_interop`,
nunca `dart:html`. O `dart:html` impede a compilação para `dart2wasm`,
então depender dele descartaria builds WASM; os extension types do
`dart:js_interop` (estabilizados no Dart 3.3) evitam essa restrição
enquanto ainda chamam `window.localStorage` diretamente, sem dependência
extra (`package:web` não é necessário).

A seleção de plataforma entre os backends IO e Web acontece via imports
condicionais do Dart (`dart.library.io` / `dart.library.js_interop`) em
`lib/src/core/storage/platform/`. Quem consome o pacote nunca vê isso — o
entrypoint público (`package:all_box/all_box.dart`) é o mesmo import em
qualquer plataforma.

`save` e `flush` se comportam de forma idêntica na Web: não há um
equivalente a `fsync`, já que uma chamada `localStorage.setItem` já é
síncrona.

---

Voltar ao [README](https://github.com/CriandoGames/all_box/blob/main/README.pt-BR.md).
