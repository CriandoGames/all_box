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

Se arquivos `.db`/`.bak` existem mas nenhum deles pode ser decodificado, o
backend IO emite um diagnóstico somente em debug e começa com um container
vazio em memória. Os arquivos corrompidos não são apagados durante o
`init()`; eles continuam disponíveis para inspeção manual até que uma
persistência posterior bem-sucedida os substitua pelo pipeline normal de
write-ahead. Isso mantém a corrupção visível em builds debug sem adicionar
outra API pública de recuperação.

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

Falhas de flush são reportadas por `onPersistenceError` quando o usuário
fornece esse callback em `AllBox.init()`. Isso importa principalmente para
`write()` com debounce, porque não existe um `Future` retornado onde o erro
possa aparecer. APIs aguardadas (`writeAndSave()`, `writeAndFlush()`,
`flushNow()`) continuam relançando a falha do storage pelo `Future`
retornado; o callback é um gancho adicional de reporte, não um substituto
para erros normais de `Future`.

## Semântica do `initialData`

O `initialData` passado para `AllBox.init()` só é aplicado em um first-run
de verdade. A checagem é baseada na existência de
`<container>.db`/`<container>.bak` em disco — não no estado em memória —
então um container esvaziado por um `erase()` anterior ainda conta como
"já persistido" e o seed nunca é reaplicado por cima dele. Quando se
aplica, o seed é persistido imediatamente (ignorando a janela de
debounce), então sobrevive a um crash logo após o primeiro lançamento do
app.

A inicialização é serializada por container. Chamadas concorrentes com
opções equivalentes compartilham o mesmo `Future` de inicialização em
andamento. Chamadas concorrentes com `path`, `storage`, `initialData`,
`flushDelay`, `onPersistenceError`, `validateContainerName` ou
`experimentalIndexedDbBackend` conflitantes são rejeitadas com `StateError`,
em vez de deixar uma configuração vencer de forma não determinística.

Quando o seed de first-run falha ao persistir, a inicialização faz rollback:
o container fica não inicializado, os dados em memória são limpos e uma
chamada posterior de `init()` pode tentar novamente a partir de um estado
limpo.

## Ciclo de vida e exclusão

`close({flushPending})` fecha um container e remove seu singleton do
registro interno. Com o padrão `flushPending: true`, dados pendentes em
memória são persistidos antes de fechar o backend de storage. Com
`flushPending: false`, writes debounced pendentes são descartados.

`destroy()` cancela trabalho pendente de debounce, apaga os dados
persistidos pelo backend, fecha o backend de storage e remove o singleton
do registro. No IO, o backend apaga `.db`, `.tmp` e `.bak`; na Web, remove a
chave do browser storage. Isso é exclusão lógica, não sobrescrita física
segura.

## Nomes de container no IO

Por compatibilidade, nomes de container continuam permissivos por padrão.
Apps existentes que usam nomes como `user/cache` continuam funcionando.

Quando `validateContainerName: true` é passado para `AllBox.init()` no IO, o
storage IO embutido valida o nome antes de qualquer acesso a arquivo. O
modo estrito aceita apenas letras, números, `.`, `_` e `-`, e rejeita nomes
vazios, `.`/`..`, separadores de caminho, separadores de drive, pontos ou
espaços finais, e nomes reservados do Windows como `CON`, `NUL`, `COM1` e
`LPT1`. Esse modo opt-in é útil para apps que querem uma política única de
filename entre plataformas e nenhum nome de container com aparência de
caminho.

## Snapshots do inspector

`AllBoxInspector.snapshot()` e `snapshotOf()` retornam retratos de um ponto
no tempo. As entradas do snapshot são copiadas profundamente e ficam
imutáveis para maps e listas, então mutar um valor depois que o snapshot foi
criado não altera o retrato já entregue para ferramentas.

O reporte de backend do inspector prioriza compatibilidade. O valor público
`AllBoxBackendKind.web` continua sendo a categoria estável para storage de
navegador, incluindo o testbed interno de IndexedDB e o wrapper de migração.
Ferramentas que precisam da implementação concreta podem ler o campo
opcional `backendDetail` (`localStorage`, `indexedDB` ou
`indexedDBMigration`) no objeto/JSON do snapshot em vez de depender de novos
valores no enum. Os eventos de extensão de mutação mantêm o mesmo tipo e
payload.

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

O backend Web embutido atual é um backend **somente para Window**. Ele é
ligado a `window.localStorage`, que a MDN documenta como uma propriedade de
`Window`, e a Web Storage API é exposta por `Window.localStorage`/
`Window.sessionStorage`. Ele não é anunciado como backend para Web Worker ou
Service Worker. Um backend futuro compatível com workers deve usar outro
contrato de storage, provavelmente IndexedDB, em vez de fingir que
`localStorage` funciona em todos os contextos.

Como o backend Web grava um snapshot JSON completo por container, ele não
sincroniza escritores concorrentes entre múltiplas abas do navegador. O
registro singleton protege apenas uma janela/isolate Dart. Duas abas
escrevendo a partir de snapshots antigos ainda podem perder dados. Esta é
uma limitação arquitetural documentada até existir um protocolo de
revisão/conflito e um backend adequado para coordenação entre contextos.

Existe um backend interno de storage IndexedDB por trás de
`AllBoxIndexedDbStorage` e `AllBoxBrowserIndexedDbDriver`, coberto por
testes regressivos VM/fake e Chrome real. Ele não é o backend Web padrão:
`AllBox.init()` continua resolvendo para `window.localStorage` salvo quando
quem chama opta explicitamente pelo backend beta com migração usando
`experimentalIndexedDbBackend: true`. A compatibilidade do inspector para a
família de backends Web é coberta abaixo.

O caminho de migração de localStorage -> IndexedDB está implementado como
`AllBoxIndexedDbMigrationStorage` e é selecionado apenas pelo opt-in beta
explícito. Os testes cobrem leitura de dados legados no localStorage,
precedência do IndexedDB, migração que remove a cópia legada somente depois
de uma gravação IndexedDB bem-sucedida, fallback para localStorage quando
IndexedDB falha, e delete atravessando os dois stores.
A compatibilidade do inspector é coberta separadamente: todos os backends da
família Web continuam reportando `backend: web`, com `backendDetail`
identificando o backend concreto.

Escritas IndexedDB usam merge por delta por instância em vez de sobrescrever
cegamente o snapshot persistido inteiro. Cada instância de storage lembra o
snapshot que carregou ou salvou localmente por último. No save, ela calcula
as chaves alteradas ou removidas por essa instância, abre uma única
transação IndexedDB `readwrite`, lê o JSON persistido atual dentro dessa
transação, aplica apenas o delta local e grava o JSON mesclado de volta.
Isso mitiga o caso comum de lost update multiaba em que duas abas escrevem
chaves diferentes a partir de snapshots antigos. Se duas abas escrevem ou
removem a mesma chave, a escrita persistida por último vence; o AllBox não
expõe documentos de conflito no estilo PouchDB.

O driver IndexedDB interno de navegador usa schema version 1 com um único
object store `containers`. Depois de abrir um banco, ele verifica se esse
store existe, então um banco incompatível é reportado com um diagnóstico
claro de schema em vez de falhar depois durante uma transação. Testes
regressivos em navegador também cobrem auto-close em `versionchange` e erro
explícito quando uma exclusão fica bloqueada. Esse hardening ainda não torna
IndexedDB o backend Web padrão.

O opt-in beta também é reversível por desenho: remover
`experimentalIndexedDbBackend: true` faz `AllBox.init()` voltar para o
backend localStorage e não ler dados existentes no IndexedDB. Testes
regressivos em navegador cobrem esse comportamento de rollback e cobrem
isolamento de múltiplos containers através do wrapper de migração.

## Benchmarks

`tool/web_storage_benchmark.dart` fornece um relatório leve de benchmark
para o caminho puro em Dart do `AllBoxWebStorage`, usando um browser storage
síncrono falso. Ele cobre 100/1.000/5.000 chaves, valores de 100 KB/500 KB/1
MB, burst de escritas e múltiplos containers:

```bash
dart run tool/web_storage_benchmark.dart
```

`test/web/all_box_web_storage_browser_benchmark_test.dart` complementa isso
com um relatório opcional em navegador real contra `window.localStorage`:

```bash
dart test -p chrome test/web/all_box_web_storage_browser_benchmark_test.dart --reporter expanded
```

Os dois comandos imprimem medições como relatórios comparativos locais, sem
impor limites dependentes da máquina. Use execuções repetidas no mesmo
ambiente/navegador antes de fazer afirmações de desempenho sobre bloqueio de
`window.localStorage`.

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
- **O backend Web default é somente Window e não é seguro para multiaba.**
  Ele usa `window.localStorage` e mantém sincronização apenas dentro da
  janela/isolate Dart atual. Web Workers, Service Workers e escritas
  multiaba seguras exigem outro backend/contrato. O backend IndexedDB beta
  mitiga sobrescrita por snapshot antigo para chaves diferentes, mas
  conflitos na mesma chave continuam last-write-wins e não há API de
  notificação reativa cross-tab.
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
