<h1 align="center">All Box</h1>

<p align="center">
  💡 Armazenamento chave-valor síncrono, leve e rápido para Flutter — com escrita crash-safe e camada reativa 100% Flutter.
</p>

<p align="center">
  <a href="https://pub.dev/packages/all_box"><img src="https://img.shields.io/pub/v/all_box.svg?label=pub.dev" alt="pub version"></a>
  <a href="https://pub.dev/packages/all_box/score"><img src="https://img.shields.io/pub/likes/all_box?label=likes" alt="pub likes"></a>
  <a href="https://pub.dev/packages/all_box/score"><img src="https://img.shields.io/pub/points/all_box?label=pub%20points" alt="pub points"></a>
  <a href="https://github.com/CriandoGames/all_box/blob/main/LICENSE"><img src="https://img.shields.io/github/license/CriandoGames/all_box" alt="license"></a>
  <img src="https://img.shields.io/badge/testes-12-brightgreen" alt="12 testes">
</p>

---

## 🚀 Descrição do Projeto

**AllBox** é um armazenamento chave-valor para Flutter, construído em torno
de quatro pilares:

- **Camada reativa 100% Flutter.** `AllBoxListenable` e `AllBoxBuilder` são
  construídos diretamente sobre `ChangeNotifier` e `ValueListenable` — sem
  nenhuma dependência externa de gerenciamento de estado.
- **Leituras síncronas.** Depois do `init()`, todo `read<T>()` é síncrono —
  sem `Future`, sem `FutureBuilder`, sem espera de I/O no caminho de leitura.
- **Crash-safety de verdade.** Toda escrita passa por um arquivo `.tmp` e só
  então um rename atômico substitui o arquivo principal (`.db`); um `.bak` do
  último estado bom é mantido à parte, com fallback automático em dois
  estágios (erro de decodificação UTF-8 e erro de `jsonDecode`).
- **`path` explícito, nunca resolvido internamente.** `AllBox` nunca importa
  `path_provider` nem resolve diretório algum — quem chama `init()` decide
  onde o container vive. Isso evita, por construção, os bugs de resolução de
  plugin/Activity que afetam bibliotecas que resolvem o path por padrão.

Parte da família de pacotes open-source `all_*` ao lado
de [`all_validations_br`](https://pub.dev/packages/all_validations_br)
(validações brasileiras, utilitários e criptografia) e `all_image_compress`
(compressão de imagem).

---

## 📦 Instalação

Adicione ao seu `pubspec.yaml`:

```yaml
dependencies:
  all_box: ^0.1.0
```

Em seguida:

```bash
flutter pub get
```

E importe no seu código:

```dart
import 'package:all_box/all_box.dart';
```

---

## 📱 App de Exemplo

O diretório `example/` contém um app Flutter interativo (`CounterPage`) que
demonstra toda a superfície pública usada no dia a dia: `write()` otimista
vs. `writeAndFlush()`, `AllBoxBuilder<T>` reativo, `listenAll` para efeitos
colaterais globais (um `SnackBar`) e `flushNow()` disparado em
`AppLifecycleState.paused`.

Para rodar:

```bash
cd example
flutter pub get
flutter run
```

---

## ⚙️ Funcionalidades

### Inicialização

```dart
import 'package:all_box/all_box.dart';
import 'package:path_provider/path_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // AllBox nunca resolve o próprio diretório — quem resolve é você, depois
  // que o binding estiver pronto. Qualquer estratégia de path funciona.
  final dir = await getApplicationDocumentsDirectory();
  await AllBox.init('my_container', path: dir.path);

  runApp(const MyApp());
}
```

### Leitura e escrita (toda leitura é síncrona)

```dart
final box = AllBox('my_container');

box.write('name', 'Carlos');           // otimista: memória + listeners
                                        // atualizam na hora, o disco segue
                                        // ~100ms depois (debounced)

String? name = box.read<String>('name');
String safeName = box.readOrDefault<String>('name', 'anonymous');

await box.writeAndFlush('name', 'Carlos'); // espera o disco confirmar

box.remove('name');
box.erase(); // limpa tudo e notifica todos os listeners que existiam

await box.flushNow(); // força um flush agora, ex.: em AppLifecycleState.paused
```

### Escutando mudanças

```dart
box.listenKey('name', () => print('name mudou'));
box.removeListenKey('name', callback);

final dispose = box.listenAll(() => print('container mudou'));
// depois
dispose();
```

### Widgets reativos, sem dependências externas de gerenciamento de estado

```dart
AllBoxBuilder<int>(
  keyName: 'counter',
  builder: (context, value) => Text('${value ?? 0}'),
)
```

Ou construa seu próprio `ValueListenable` com `AllBoxListenable<T>`:

```dart
final counter = AllBoxListenable<int>('counter');
ValueListenableBuilder<int?>(
  valueListenable: counter,
  builder: (context, value, _) => Text('${value ?? 0}'),
);
```

### Helper `.val()` sem DI (opcional)

Um mini state-manager opt-in, sem qualquer acoplamento de injeção de
dependência:

```dart
final darkMode = 'darkMode'.val(false);
print(darkMode.value);
darkMode.value = true;
```

---

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

### Reagindo a uma única chave dentro de um widget

```dart
class DarkModeSwitch extends StatelessWidget {
  const DarkModeSwitch({super.key});

  @override
  Widget build(BuildContext context) {
    return AllBoxBuilder<bool>(
      keyName: 'darkMode',
      builder: (context, value) => Switch(
        value: value ?? false,
        onChanged: (v) => AllBox().write('darkMode', v),
      ),
    );
  }
}
```

### Limpando um container e reagindo globalmente

```dart
final dispose = box.listenAll(() => print('algo mudou em "settings"'));

box.erase(); // dispara o listener acima uma única vez

dispose();
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

---

## 📚 API

| Member | Descrição |
| --- | --- |
| `AllBox([container])` | Factory constructor; retorna um singleton por nome de container. |
| `static AllBox.init(container, {required path, flushDelay})` | Carrega o `container` do disco para a memória. `path` é obrigatório — veja abaixo. |
| `T? read<T>(key)` / `T readOrDefault<T>(key, fallback)` | Leituras síncronas. |
| `void write(key, value)` | Escrita otimista + debounced. |
| `Future<void> writeAndFlush(key, value)` | Escreve e espera a confirmação em disco. |
| `void remove(key)` / `void erase()` | Remove uma chave / limpa tudo (`erase()` notifica os listeners de todas as chaves que existiam). |
| `Future<void> flushNow()` | Força um flush imediato, ignorando a janela de debounce. |
| `listenKey(key, cb)` / `removeListenKey(key, cb)` | Listeners por chave. |
| `VoidCallback listenAll(cb)` | Listener global; retorna uma função de dispose. |
| `hasData(key)`, `getKeys()`, `getValues()` | Introspecção. |
| `AllBoxListenable<T>` | `ChangeNotifier` + `ValueListenable<T?>` para uma chave. |
| `AllBoxBuilder<T>` | Widget que reconstrói quando `keyName` muda. |
| `'key'.val<T>(default)` | Handle opcional de mini state-manager sem DI. |

### Por que `path` é um parâmetro obrigatório de `init()`?

`AllBox` **nunca** importa `path_provider` (nem resolve diretório algum)
internamente. Quem chama sempre decide onde o container vive. É uma escolha
de design deliberada, não um descuido — veja a seção abaixo.

---

## 🛠️ Decisões de Design

- **`path` explícito e obrigatório em `init()`.** O `all_box` nunca resolve
  diretório algum internamente — quem chama `init()` sempre informa o
  `path`, evitando qualquer resolução de plugin dentro da lib.
- **Crash-safety com write-ahead + rename atômico.** Toda escrita em disco
  passa por um arquivo `.tmp` e só então um rename atômico substitui o
  arquivo principal (`.db`); um `.bak` do último estado bom é mantido à
  parte.
- **Tratamento de leitura em dois estágios.** Erros de decodificação UTF-8 e
  erros de `jsonDecode` são tratados como estágios/pontos de falha
  distintos, cada um com fallback para o `.bak` antes de desistir e começar
  vazio.
- **Fila de flush serializada.** Nunca há duas escritas concorrentes no
  mesmo arquivo, mesmo se `flushNow()`/`writeAndFlush()` for chamado com um
  flush debounced ainda em andamento.
- **Benchmark próprio.** Números de performance medidos e mantidos neste
  repositório; veja `benchmark/`.
- **Sem suporte a Web nesta v1** (ver limitações abaixo).

---

## 🔄 Diferenças em relação ao GetStorage

- **Sem `package:get`.** Nenhuma classe deste pacote importa ou depende de
  `package:get`; a camada reativa (`AllBoxListenable`/`AllBoxBuilder`) é
  Flutter puro (`ChangeNotifier`/`ValueListenable`).
- **`path` obrigatório em `init()`.** O GetStorage resolve o diretório
  internamente por padrão; o `all_box` exige que quem chama `init()` informe
  o `path`, evitando qualquer resolução de plugin dentro da lib.
- **Crash-safety com write-ahead + rename atômico.** Toda escrita em disco
  passa por um arquivo `.tmp` e só então um rename atômico substitui o
  arquivo principal (`.db`); um `.bak` do último estado bom é mantido à
  parte. O GetStorage original não faz isso (ver PR #175 abaixo).
- **Tratamento de leitura em dois estágios.** Erros de decodificação UTF-8 e
  erros de `jsonDecode` são tratados como estágios/pontos de falha
  distintos, cada um com fallback para o `.bak` antes de desistir e começar
  vazio.
- **Fila de flush serializada.** Nunca há duas escritas concorrentes no
  mesmo arquivo, mesmo se `flushNow()`/`writeAndFlush()` for chamado com um
  flush debounced ainda em andamento.
- **Benchmark próprio.** Não reaproveitamos os números de benchmark do
  get_storage original (contestados na PR #154); veja `benchmark/`.
- **Sem suporte a Web nesta v1** (ver limitações abaixo).

---

## 🐛 Bugs conhecidos do get_storage original que evitamos aqui

Estes são pontos mapeados no repositório
[`jonataslaw/get_storage`](https://github.com/jonataslaw/get_storage) (issues
e PRs abertas, não mergeadas, no momento em que este pacote foi escrito):

- **PR #175** — padrão write-ahead ainda não implementado no original:
  escrita direta no arquivo principal pode corromper o container se o
  processo morrer no meio da gravação. Aqui: gravação sempre passa por
  `.tmp` + rename atômico + `.bak` (ver "Crash-safety" acima).
- **Issues #35, #90, #33, #56 / PR #149** — `MissingPluginException`
  causada por resolver `path_provider` (ou canais de plataforma
  equivalentes) antes do binding do Flutter estar pronto, ou dentro de uma
  `Activity` customizada (ex.: `FlutterFragmentActivity`). Aqui: `path` é
  sempre parâmetro explícito de `init()`; a lib nunca importa
  `path_provider`.
- **Issue #157 / PR #167** — suporte a Web via `dart:html`, que quebra a
  compilação para WASM (`dart2wasm`). Aqui: Web fica de fora do MVP; se um
  dia for implementado, será via `package:web` com conditional imports,
  nunca `dart:html` (ver limitações abaixo).
- **PR #154** — números de benchmark do get_storage original foram
  contestados como incorretos. Aqui: benchmark próprio, com metodologia
  descrita, em `benchmark/benchmark.dart`.

---

## ⚠️ Limitações conhecidas (documentadas, não escondidas)

- **Sem suporte a Web nesta v1.** Se um dia for adicionado, deve usar
  `package:web` via conditional imports — **nunca** `dart:html`, pois
  `dart:html` impede a compilação para WASM (`dart2wasm`). Este é um
  problema real, ainda não resolvido no get_storage original (issue #157,
  PR #167 aberta).
- **Não é isolate-safe.** Cada `AllBox` mantém seu estado em memória no
  isolate onde foi inicializado; não há sincronização entre isolates
  (mesma limitação documentada pelo get_storage original). Se você usa
  múltiplos isolates (ex.: `compute()`, isolates de background), cada um
  precisa do seu próprio `init()` e eles não verão as escritas uns dos
  outros até reler do disco.
- **`File.rename` para o swap atômico depende do sistema operacional.** Em
  POSIX (Linux/macOS/Android/iOS) o rename sobre um arquivo existente é
  atômico. Em Windows o comportamento pode variar entre versões do SDK do
  Dart; teste esse cenário especificamente se seu app roda em Windows
  desktop.

---

## 🧪 Testes

```bash
flutter test
```

Os testes cobrem especificamente os cenários de bug mapeados acima: arquivo
corrompido com bytes binários aleatórios, JSON inválido, fallback para
`.bak`, múltiplos `write()` gerando um único flush, isolamento entre
containers, notificação correta de listeners em `erase()`, e
`listenKey`/`listenAll` sendo corretamente removidos.

---

## 👥 Contribuidores

[![Contributors](https://contrib.rocks/image?repo=CriandoGames/all_box)](https://github.com/CriandoGames/all_box/graphs/contributors)

Made with [contrib.rocks](https://contrib.rocks).

Contribuições são bem-vindas! Leia o [CONTRIBUTING.md](CONTRIBUTING.md) para
começar.

---

## 📄 Licença

Distribuído sob a licença MIT. Veja [LICENSE](LICENSE) para mais detalhes.

---

<p align="center">💻 Desenvolvido com ❤️ para facilitar o desenvolvimento no Flutter.</p>
