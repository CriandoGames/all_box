<h1 align="center">all_box</h1>

<p align="center">
🇺🇸 <a href="https://github.com/CriandoGames/all_box/blob/main/README.md">English</a> | 🇧🇷 Português
</p>

<p align="center">
  <a href="https://pub.dev/packages/all_box"><img src="https://img.shields.io/pub/v/all_box.svg?label=pub.dev" alt="pub version"></a>
  <a href="https://pub.dev/packages/all_box/score"><img src="https://img.shields.io/pub/likes/all_box?label=likes" alt="pub likes"></a>
  <a href="https://pub.dev/packages/all_box/score"><img src="https://img.shields.io/pub/points/all_box?label=pub%20points" alt="pub points"></a>
  <a href="https://github.com/CriandoGames/all_box/blob/main/LICENSE"><img src="https://img.shields.io/github/license/CriandoGames/all_box" alt="license"></a>
  <img src="https://img.shields.io/badge/testes-77-brightgreen" alt="77 testes">
</p>


<p align="center">
💡 Armazenamento chave-valor síncrono, leve e rápido, Dart puro, com escrita crash-safe.
</p>

## Sumário

- [Features](#-features)
- [Instalação](#-instalação)
- [App de Exemplo](#-app-de-exemplo)
- [Funcionalidades](#️-funcionalidades)
- [Exemplos de Uso](#-exemplos-de-uso)
- [Separando dados por usuário ou contexto](#-separando-dados-por-usuário-ou-contexto)
- [API](#-api)
- [Decisões de Design](#️-decisões-de-design)
- [Limitações conhecidas](#️-limitações-conhecidas-documentadas-não-escondidas)
- [Comparação](#-comparação)
- [Quando usar (e quando não usar)](#-quando-usar-e-quando-não-usar)
- [Testes](#-testes)
- [Documentação](#-documentação)
- [Outros pacotes nossos](#-outros-pacotes-nossos)

## 🚀 Features

- 🪶 **Leituras 100% síncronas.** Depois do `init()`, todo `read<T>()` é síncrono — sem `Future`, sem `FutureBuilder`, sem espera de I/O no caminho de leitura.
- 🧱 **Dart puro, zero dependência do Flutter.** `package:all_box/all_box.dart` não tem nenhum import de Flutter — o `all_box` funciona em qualquer ambiente Dart (CLI, servidor, app Flutter), e não tem nenhuma API reativa/de listener própria.
- 🛡️ **Crash-safety de verdade.** Toda escrita passa por um arquivo `.tmp` e só então um rename atômico substitui o arquivo principal (`.db`); um `.bak` do último estado bom é mantido à parte, com fallback automático em dois estágios (erro de decodificação UTF-8 e erro de `jsonDecode`).
- 📍 **`path` explícito, nunca resolvido internamente.** `AllBox` nunca importa `path_provider` nem resolve diretório algum — quem chama `init()` decide onde o container vive. Isso evita, por construção, os bugs de resolução de plugin/Activity que afetam bibliotecas que resolvem o path por padrão.
- ⚡ **Escrita otimista + debounced**, com `writeAndSave()` (espera o write do OS) e `writeAndFlush()`/`flushNow()` (espera o `fsync`) para os momentos em que você precisa de uma confirmação mais forte e imediata em disco.
- 🧪 **Storage em memória para testes.** `AllBox.memory()` roda sem I/O real e sem `Timer` real, seguro para `testWidgets`.
- 🌐 **Suporte a Web.** `AllBox.init('settings')` (sem `path`) usa automaticamente o `window.localStorage` na Web, via `dart:js_interop` — nunca `dart:html` (que impede a compilação para `dart2wasm`).

## 📦 Instalação

```
dart pub add all_box
```

```yaml
dependencies:
  all_box: ^0.3.0
```

O `all_box` é Dart puro e tem um único ponto de entrada:

```dart
import 'package:all_box/all_box.dart';

// Web: sem `path` — o AllBox usa window.localStorage automaticamente.
final box = await AllBox.init('settings');

// IO (VM/AOT nativa, incl. Flutter mobile/desktop): informe um diretório.
final box = await AllBox.init('settings', path: dir.path);

box.write('name', 'Carlos');
final name = box.read<String>('name');
```

Testando seu próprio app/pacote contra uma instância real de `AllBox`, sem
I/O real nenhum:

```dart
final box = await AllBox.memory('settings', initialData: {'darkMode': true});
```

O `all_box` não tem nenhuma API reativa/de listener própria: num app
Flutter, atualize sua UI chamando `setState` (ou a solução de
gerenciamento de estado que você já usa) logo após
`write()`/`writeAndFlush()`/`erase()`, do mesmo jeito que você faria com
qualquer outro storage síncrono e não-reativo.

## 📱 App de Exemplo

O diretório `example/` contém um app Flutter interativo (`CounterPage`) que
demonstra toda a superfície pública usada no dia a dia: `write()` otimista
vs. `writeAndFlush()`, `erase()`, e `flushNow()` disparado em
`AppLifecycleState.paused`.

Para rodar:

```bash
cd example
flutter pub get
flutter run
```

## ⚙️ Funcionalidades

### Inicialização

```dart
import 'package:all_box/all_box.dart';
import 'package:path_provider/path_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // AllBox nunca resolve o próprio diretório — quem resolve é você, depois
  // que o binding estiver pronto. Qualquer estratégia de path funciona. Não
  // é necessário na Web: `path` é ignorado lá, já que o AllBox usa
  // automaticamente o `window.localStorage`.
  final dir = await getApplicationDocumentsDirectory();
  await AllBox.init('my_container', path: dir.path);

  runApp(const MyApp());
}
```

Qual storage é usado é resolvido automaticamente a partir do alvo de
compilação: a Web sempre usa `window.localStorage`; qualquer outro alvo
(IO) usa o `path` que você fornecer. Também existe um argumento avançado
`storage:` para conectar sua própria implementação de `AllBoxStorage`, mas
o código do dia a dia nunca precisa dele.

### Seed de dados no primeiro run (`initialData`)

```dart
await AllBox.init(
  'settings',
  path: dir.path,
  initialData: const {
    'darkMode': false,
    'onboarded': false,
  },
);
```

`initialData` só é aplicado em um first-run de verdade — quando o container
ainda não tem `<container>.db`/`<container>.bak` no disco. É persistido
imediatamente (não espera o debounce), então sobrevive a um crash logo após
o primeiro lançamento do app. Se o container já existia antes — mesmo que
como um `{}` vazio deixado por um `erase()` anterior — `initialData` é
ignorado e o que está em disco prevalece.

### Leitura e escrita (toda leitura é síncrona)

```dart
final box = AllBox('my_container');

box.write('name', 'Carlos');           // otimista: memória atualiza na
                                        // hora, o disco segue ~100ms
                                        // depois (debounced)

String? name = box.read<String>('name');
String safeName = box.readOrDefault<String>('name', 'anonymous');

await box.writeAndSave('name', 'Carlos');  // espera o write do OS (sem fsync)
await box.writeAndFlush('name', 'Carlos'); // espera o fsync (disco confirmado)

box.remove('name');
box.erase(); // limpa tudo

await box.flushNow(); // força um flush agora, ex.: em AppLifecycleState.paused
```

## 🧪 Exemplos de Uso

### Valor com fallback seguro

```dart
final box = AllBox('settings');
final theme = box.readOrDefault<String>('theme', 'light');
// Retorna 'light' se a chave 'theme' ainda não existir
```

### Escrita otimista vs. escrita confirmada

```dart
box.write('score', 100);              // memória atualizada na hora
await box.writeAndFlush('score', 100); // só retorna após confirmar no disco
```

### Atualizando um widget depois de uma escrita

O `all_box` não tem reatividade embutida, então um widget que exibe um
valor armazenado relê o valor e chama `setState` logo após escrever:

```dart
class DarkModeSwitch extends StatefulWidget {
  const DarkModeSwitch({super.key});

  @override
  State<DarkModeSwitch> createState() => _DarkModeSwitchState();
}

class _DarkModeSwitchState extends State<DarkModeSwitch> {
  late bool _darkMode = AllBox().readOrDefault<bool>('darkMode', false);

  void _toggle(bool value) {
    AllBox().write('darkMode', value);
    setState(() => _darkMode = value);
  }

  @override
  Widget build(BuildContext context) {
    return Switch(value: _darkMode, onChanged: _toggle);
  }
}
```

### Introspecção do container

```dart
box.hasData('theme');   // true / false
box.getKeys();          // todas as chaves gravadas
box.getValues();        // todos os valores gravados
```

### Persistindo o estado do app ao ser pausado

```dart
class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      AllBox('my_container').flushNow();
    }
  }
}
```

## 🧩 Separando dados por usuário ou contexto

O `all_box` não tem uma API dedicada de "escopo", "namespace" ou
"collection" — isso é proposital, para manter a superfície pequena. Em apps
reais você ainda precisa separar dados locais por quem eles pertencem: o
usuário logado, uma conta, uma academia, uma empresa, uma sessão, ou só o
estado global do app. Dois padrões cobrem bem isso com a API que já existe.

**Um container diferente por contexto.** `AllBox.init(container, ...)`
aceita um nome de container arbitrário, e cada nome é um storage totalmente
isolado — seu próprio arquivo no IO, sua própria chave de `localStorage` na
Web:

```dart
final appBox = await AllBox.init('app_settings', path: dir.path);
final userBox = await AllBox.init('user_$userId', path: dir.path);
```

Apagar ou limpar um container nunca afeta o outro. Isso funciona bem quando
o número de contextos é pequeno e conhecido de antemão — ex.: um container
por usuário logado, mais um para configurações globais do app.

**Prefixo de chaves dentro de um único container.** Quando os contextos são
mais dinâmicos, ou você prefere manter tudo num lugar só, prefixar as
chaves funciona igualmente bem:

```dart
final userId = 'user_123';

box.write('user:$userId:theme', 'dark');
box.write('user:$userId:profile', profile);

final theme = box.read<String>('user:$userId:theme');
```

```dart
box.write('app:last_logged_user', userId);
box.write('app:language', 'pt-BR');

final language = box.read<String>('app:language');
```

Uma boa prática é separar as chaves por contexto. Isso ajuda a evitar
conflito de dados e torna mais simples remover informações de um usuário
específico sem apagar configurações globais do app.

Essa separação é útil para:

- apps com múltiplos usuários logados no mesmo dispositivo;
- apps SaaS multi-tenant (empresa, academia, organização);
- cache de respostas de API por conta;
- preferências locais por perfil de usuário;
- limpeza segura no logout, sem afetar configurações globais;
- manter dados temporários de sessão separados do estado persistente do app.

Para projetos maiores, recomendamos padronizar os prefixos das chaves em
uma classe própria, evitando strings espalhadas pelo app:

```dart
class StorageKeys {
  static String userTheme(String userId) => 'user:$userId:theme';
  static String userProfile(String userId) => 'user:$userId:profile';

  static const appLanguage = 'app:language';
  static const lastLoggedUser = 'app:last_logged_user';
}
```

```dart
box.write(StorageKeys.userTheme(userId), 'dark');

final theme = box.read<String>(
  StorageKeys.userTheme(userId),
);
```

Qualquer um dos dois padrões mantém o `all_box` fazendo o que ele se propõe
a fazer — preferências, configurações locais, estado simples de app e
micro caches — não um substituto para um banco de dados embarcado completo,
com queries, índices ou relações (veja
[Quando usar](#-quando-usar-e-quando-não-usar)).

## 📚 API

| Member | Descrição |
| --- | --- |
| `AllBox([container])` | Factory constructor; retorna um singleton por nome de container. |
| `static AllBox.init(container, {path, flushDelay, initialData, storage})` | Carrega o `container` para a memória e retorna o `AllBox` inicializado. `path` é obrigatório em plataformas IO, ignorado na Web. `initialData` semeia valores default, mas só num first-run de verdade. `storage` é um override avançado — veja abaixo. |
| `static AllBox.memory(container, {initialData})` | Forma recomendada de testar código que consome o `all_box`: sem I/O real, sem `Timer` real. Substitui o descontinuado `initWithMemoryBackendForTesting`. |
| `T? read<T>(key)` / `T readOrDefault<T>(key, fallback)` | Leituras síncronas. |
| `void write(key, value)` | Escrita otimista + debounced. Em debug, avisa (via `debugPrint` em vermelho) se `value` não for JSON-encodável, mas nunca lança exceção. |
| `Future<void> writeAndSave(key, value)` | Escreve e espera o write do OS terminar (sem `fsync` forçado) — sobrevive a um crash do app, mais barato que `writeAndFlush()`. Mesmo aviso de serialização de `write()`. |
| `Future<void> writeAndFlush(key, value)` | Escreve e espera a garantia de durabilidade mais forte (`fsync` no IO). Mesmo aviso de serialização de `write()`. |
| `void remove(key)` / `void erase()` | Remove uma chave / limpa tudo. |
| `Future<void> flushNow()` | Força um flush imediato, ignorando a janela de debounce. |
| `hasData(key)`, `getKeys()`, `getValues()` | Introspecção. |

### Por que `path` é obrigatório no IO, mas não na Web?

`AllBox` **nunca** importa `path_provider` (nem resolve diretório algum)
internamente. Em plataformas IO, quem chama sempre decide onde o container
vive — é uma escolha de design deliberada, não um descuido (veja a seção
abaixo). Na Web não há nada para resolver: o `window.localStorage` está
sempre num local fixo e conhecido, então `path` simplesmente não se aplica
ali e é silenciosamente ignorado se você passar um mesmo assim (útil para
código compartilhado entre IO e Web).

## 🛠️ Decisões de Design

- **`path` explícito no IO, storage automático na Web.** O `all_box` nunca
  resolve diretório algum internamente no IO — quem chama `init()` sempre
  informa o `path` ali, evitando qualquer resolução de plugin dentro da
  lib. Na Web, o storage é resolvido automaticamente para
  `window.localStorage`, já que não há um "path" significativo para pedir
  a quem chama.
- **`initialData` só se aplica em first-run de verdade.** A checagem é feita
  pela existência de `<container>.db`/`<container>.bak` em disco, não pelo
  conteúdo em memória — um container esvaziado por `erase()` ainda tem um
  `{}` persistido, então não é considerado "primeiro run" e o seed não é
  reaplicado por cima dele.
- **Crash-safety com write-ahead + rename atômico**, com uma fila de flush
  serializada compartilhada por todo storage (IO, Web, memória, ou o seu
  próprio). Detalhes completos do pipeline em
  [Arquitetura interna](documentation/pt-BR/architecture.md).
- **Sem reatividade embutida.** O `all_box` não tem nenhuma API de
  listener/reatividade própria — `write()`, `remove()` e `erase()` só
  atualizam a memória e agendam a persistência. Isso mantém a superfície do
  core pequena e evita acoplamento a qualquer abordagem específica de
  gerenciamento de estado; conecte a um `setState`, a um `ChangeNotifier`
  seu, ao `all_observer`, ou ao que seu app já usar.
- **Benchmark reproduzível.** Números de performance medidos no
  dispositivo e mantidos neste repositório — veja a seção
  [Comparação](#-comparação); reproduza você mesmo pelo app example
  (`cd example && flutter run --profile`, depois toque no ícone ⚡) ou rode
  o micro-benchmark do pacote com
  `flutter test benchmark/benchmark_test.dart`.
- **Aviso de serialização em debug, não exceção.** `write()`/`writeAndFlush()`
  chamam `jsonEncode` no valor na hora, só em debug, e emitem um
  `debugPrint` em vermelho se ele não for serializável — mas nunca lançam
  exceção nem bloqueiam a escrita. O valor segue gravado em memória
  normalmente; se realmente não puder ser codificado, a falha só volta a
  aparecer, calada, lá dentro do flush.
- **Suporte a Web via `dart:js_interop`, nunca `dart:html`** (veja
  [Arquitetura interna](documentation/pt-BR/architecture.md) para o motivo,
  e as limitações abaixo para o que esse backend pode e não pode fazer).

## ⚠️ Limitações conhecidas (documentadas, não escondidas)

- **O storage Web (`localStorage`) tem limites reais.** Não há um
  equivalente a `fsync` — `save` e `flush` se comportam de forma idêntica
  na Web, já que uma chamada `localStorage.setItem` já é síncrona. O
  storage é isolado por *origem* do navegador (esquema + host + porta), então
  `http://localhost:3000` e `http://localhost:4000` enxergam storages
  completamente diferentes durante o desenvolvimento local. Os limites de
  tamanho variam por navegador (geralmente alguns MB por origem) e não são
  impostos nem informados antecipadamente pelo `AllBox` — uma escrita além
  do limite lança uma `AllBoxStorageException`. Os dados não são
  criptografados: não guarde segredos ou dados sensíveis num container Web
  sem criptografá-los você mesmo antes. Não recomendado para grandes
  volumes de dados.
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
- **Sem reatividade embutida.** `write()`, `remove()` e `erase()` não
  notificam nada — veja [Decisões de Design](#️-decisões-de-design) acima.

## ⚖️ Comparação

| | `all_box` | GetStorage | Hive | Isar | SharedPreferences |
|---|---|---|---|---|---|
| Leitura | Síncrona, em memória | Síncrona, em memória | Síncrona (box aberta) | Síncrona (simples) / assíncrona (queries) | Assíncrona |
| `path` do storage | Explícito, obrigatório | Resolvido internamente | Resolvido pelo chamador | Resolvido pelo chamador | Resolvido pela plataforma |
| Crash-safety documentada | Write-ahead + rename atômico + `.bak` | Não documentada no mesmo nível | WAL/compaction interno | WAL via engine própria | Depende da plataforma |
| Suporte a Web | Sim (`localStorage`) | Sim | Sim | Sim | Sim |
| Reatividade | Nenhuma (traga a sua) | `GetBuilder`/`Obx` (GetX) | `ValueListenableBuilder` sobre `box.listenable()` | `watchObject`/`watchLazy` (streams) | Nenhuma — precisa de wrapper próprio |
| Escopo | Só storage key-value | Storage + utils de UI (GetX) | Storage orientado a boxes | Banco de dados completo | Wrapper de plataforma |

![Comparativo de desempenho: all_box vs. Hive e SharedPreferences, medido no dispositivo em modo profile](doc/comparison_benchmark_pt-BR.png)

Medido no dispositivo (Android, modo profile) pela tela "Comparativo de
storage" do app `example/` — mediana de várias rodadas, mesma sessão e
mesmos loops para todas as libs. A linha de fsync só tem uma barra porque
só o `all_box` oferece essa garantia (`writeAndFlush()`).

`all_box` propositalmente não tenta ser um banco de dados nem resolver seu
próprio `path` — isso é uma escolha de design, não uma lacuna.
[Comparação completa e detalhada, com benchmark de desempenho, aqui](documentation/pt-BR/comparison.md).

## 🤔 Quando usar (e quando não usar)

Use `all_box` quando quiser um storage chave-valor simples — configurações,
flags, pequenos estados de app — com leituras síncronas depois do boot e
escrita otimista com opção de confirmação durável explícita, e você não se
importa em conectar você mesmo as atualizações da UI (sem reatividade
embutida).

Escolha outra coisa quando precisar especificamente do que ela faz de
melhor: adapters de tipo customizado para objetos complexos (Hive), um
banco de dados embarcado completo com queries/índices/relações (Isar), o
wrapper de plataforma mais "padrão" do ecossistema Flutter
(SharedPreferences), ou uma lib de storage com reatividade embutida.

## 🧪 Testes

```bash
flutter test
```

Os testes cobrem especificamente os cenários de bug mapeados acima: arquivo
corrompido com bytes binários aleatórios, JSON inválido, fallback para
`.bak`, múltiplos `write()` gerando um único flush, e isolamento entre
containers.

### Testando código que consome o `all_box`

Se você está testando seu próprio app/pacote (não o `all_box` em si), não
precisa de um diretório real em disco (nem de navegador) — use storage em
memória:

```dart
final box = await AllBox.memory(
  'my_container',
  initialData: {'darkMode': true},
);
```

Isso não faz I/O real e não agenda nenhum `Timer` real (todo `write()`
"flusha" de forma síncrona) — é especialmente importante dentro de
`testWidgets`: sua zona `FakeAsync` espera que todo `Timer` seja resolvido
antes do teste terminar, e um container disk/Web-backed real deixaria um
`Timer` de debounce pendente ali.

(O antigo `AllBox.initWithMemoryBackendForTesting()` ainda funciona — agora
é só um wrapper fino e `@Deprecated` em volta do `AllBox.memory()`.)

## 📚 Documentação

- [Comparação](documentation/pt-BR/comparison.md) — comparação detalhada com GetStorage, Hive, Isar, SharedPreferences, incluindo benchmark de desempenho.
- [Arquitetura interna](documentation/pt-BR/architecture.md) — pipeline de write-ahead + rename atômico, coordenação de flush, e o backend Web via `dart:js_interop`.

## 📦 Outros pacotes nossos

`all_box` faz parte de uma pequena família de pacotes Dart & Flutter com
zero/poucas dependências, publicados sob o publisher verificado
[`opensource.tatamemaster.com.br`](https://pub.dev/publishers/opensource.tatamemaster.com.br/packages):

| Pacote | Versão | Descrição |
|---|---|---|
| [`all_observer`](https://pub.dev/packages/all_observer) | [![pub](https://img.shields.io/pub/v/all_observer.svg)](https://pub.dev/packages/all_observer) | Estado reativo para Flutter sem dependências — `final count = 0.obs;` + `Observer(...)`. |
| [`all_validations_br`](https://pub.dev/packages/all_validations_br) | [![pub](https://img.shields.io/pub/v/all_validations_br.svg)](https://pub.dev/packages/all_validations_br) | Validação de documentos brasileiros (CPF, CNPJ, CNH, PIX), formatadores/máscaras de input, utilitários de JWT/UUID/moeda/criptografia. |
| [`all_image_compress`](https://pub.dev/packages/all_image_compress) | [![pub](https://img.shields.io/pub/v/all_image_compress.svg)](https://pub.dev/packages/all_image_compress) | Compressão de imagem em Dart puro (JPEG, PNG, GIF, BMP, TIFF, WebP), rodando em isolates. |

## 👥 Contribuidores

[![Contributors](https://contrib.rocks/image?repo=CriandoGames/all_box)](https://github.com/CriandoGames/all_box/graphs/contributors)

Made with [contrib.rocks](https://contrib.rocks).

Contribuições são bem-vindas! Leia o [CONTRIBUTING.md](CONTRIBUTING.md) para
começar.

---

Issues e pull requests são bem-vindos no
[repositório do GitHub](https://github.com/CriandoGames/all_box). Distribuído sob a licença [MIT](LICENSE).
