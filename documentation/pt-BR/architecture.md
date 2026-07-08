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
— veja [Limitações conhecidas](#limitações-conhecidas) abaixo.

## Níveis de durabilidade

`write()`, `writeAndSave()` e `writeAndFlush()` atualizam a memória de
forma síncrona em todos os casos; eles diferem só no que o `Future`
retornado (ou a ausência dele) espera antes da persistência ser
considerada concluída:

- **`write()`** é fire-and-forget: a mudança é agendada na fila de flush
  com debounce (veja abaixo) e a chamada retorna imediatamente.
- **`writeAndSave()`** espera o write do OS terminar, sem forçar `fsync` —
  sobrevive a um crash do app, mas não necessariamente a uma queda de
  energia (o OS ainda pode estar segurando o write no page cache).
- **`writeAndFlush()`** espera o `fsync` no IO — a garantia mais forte que
  a plataforma pode oferecer, sobrevivendo tanto a queda de energia quanto
  a crash do app.

Na Web, `writeAndSave()` e `writeAndFlush()` se comportam de forma
idêntica: uma chamada `localStorage.setItem` já é síncrona, então não há
distinção significativa a fazer sobre ela.

## Coordenação de flush

A lógica de debounce/coalescing/fila de flush serializada vive uma única
vez, dentro do próprio `AllBox`, e funciona contra qualquer implementação
de `AllBoxStorage` (IO, Web, memória, ou uma customizada passada via
`storage:`) — não é duplicada por backend. Isso garante que nunca há duas
escritas concorrentes em andamento contra o mesmo container, mesmo se
`flushNow()` ou `writeAndFlush()` for chamado enquanto um flush debounced
ainda está pendente.

A primeira escrita de um burst arma um único `Timer` de debounce
(`flushDelay`, 100ms por padrão); cada escrita seguinte dentro dessa
janela só marca o container como sujo e pega carona no timer já armado —
um burst continua produzindo exatamente um flush.

## Semântica do `initialData`

O `initialData` passado para `AllBox.init()` só é aplicado em um first-run
de verdade. A checagem é baseada na existência de
`<container>.db`/`<container>.bak` em disco — não no estado em memória —
então um container esvaziado por um `erase()` anterior ainda conta como
"já persistido" e o seed nunca é reaplicado por cima dele. Quando se
aplica, o seed é persistido imediatamente (ignorando a janela de
debounce), então sobrevive a um crash logo após o primeiro lançamento do
app.

## Aviso de serialização em debug

`write()`/`writeAndSave()`/`writeAndFlush()` chamam `jsonEncode` no valor
na hora, só em builds de debug, e registram um aviso se ele não for
serializável — mas nunca lançam exceção nem bloqueiam a escrita. O valor
continua sendo escrito em memória normalmente; se realmente não puder ser
codificado, a falha volta a aparecer depois, silenciosamente, dentro do
flush. Isso é intencional: um app em produção não deveria quebrar porque
alguém gravou um `DateTime` ou um `enum` sem `toJson()` — ele deveria só
ser avisado disso, bem alto, durante o desenvolvimento.

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

## Limitações conhecidas

- **O storage Web (`localStorage`) tem limites reais.** Não há um
  equivalente a `fsync` (veja acima). O storage é isolado por *origem* do
  navegador (esquema + host + porta), então `http://localhost:3000` e
  `http://localhost:4000` enxergam storages completamente diferentes
  durante o desenvolvimento local. Os limites de tamanho variam por
  navegador (geralmente alguns MB por origem) e não são impostos nem
  informados antecipadamente pelo `AllBox` — uma escrita além do limite
  lança uma `AllBoxStorageException`. Os dados não são criptografados: não
  guarde segredos ou dados sensíveis num container Web sem criptografá-los
  você mesmo antes. Não recomendado para grandes volumes de dados.
- **Não é isolate-safe.** Cada `AllBox` mantém seu estado em memória no
  isolate onde foi inicializado; não há sincronização entre isolates. Se
  você usa múltiplos isolates (ex.: `compute()`, isolates de background),
  cada um precisa do seu próprio `init()` e eles não verão as escritas uns
  dos outros até reler do disco.
- **`File.rename` para o swap atômico depende do sistema operacional.** Em
  POSIX (Linux/macOS/Android/iOS) o rename sobre um arquivo existente é
  atômico. Em Windows o comportamento pode variar entre versões do SDK do
  Dart; teste esse cenário especificamente se seu app roda em Windows
  desktop.

---

Voltar ao [README](https://github.com/CriandoGames/all_box/blob/main/README.pt-BR.md).
