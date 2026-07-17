<h1 align="center">all_box</h1>

<p align="center">
🇺🇸 <a href="https://github.com/CriandoGames/all_box/blob/main/README.md">English</a> | 🇧🇷 Português
</p>

<p align="center">
  <a href="https://pub.dev/packages/all_box"><img src="https://img.shields.io/pub/v/all_box.svg?label=pub.dev" alt="pub version"></a>
  <a href="https://pub.dev/packages/all_box/score"><img src="https://img.shields.io/pub/likes/all_box?label=likes" alt="pub likes"></a>
  <a href="https://pub.dev/packages/all_box/score"><img src="https://img.shields.io/pub/points/all_box?label=pub%20points" alt="pub points"></a>
  <a href="https://github.com/CriandoGames/all_box/blob/main/LICENSE"><img src="https://img.shields.io/github/license/CriandoGames/all_box" alt="license"></a>
  <img src="https://img.shields.io/badge/testes-136-brightgreen" alt="136 testes">
</p>

<p align="center">
💡 Armazenamento chave-valor síncrono e simples para Dart e Flutter, com uma estratégia de escrita crash-safe.
</p>

## Sumário

- [Features](#-features)
- [Instalação](#-instalação)
- [App de Exemplo](#-app-de-exemplo)
- [Exemplos de Uso](#-exemplos-de-uso)
- [Precisa de reatividade?](#-precisa-de-reatividade)
- [Separando dados por usuário ou contexto](#-separando-dados-por-usuário-ou-contexto)
- [API](#-api)
- [Como funciona](#️-como-funciona)
- [Comparação](#-comparação)
- [Quando usar (e quando não usar)](#-quando-usar-e-quando-não-usar)
- [Testes](#-testes)
- [Documentação](#-documentação)
- [Outros pacotes nossos](#-outros-pacotes-nossos)

## 🚀 Features

- 🪶 **Leituras síncronas.** Depois do `init()`, todo `read<T>()` é
  síncrono — sem `Future`, sem `FutureBuilder`.
- 🧱 **Dart puro, zero dependência do Flutter.** Funciona em qualquer
  ambiente Dart — CLI, servidor, ou app Flutter.
- 🛡️ **Estratégia de escrita crash-safe.** Projetado para evitar arquivos
  parcialmente gravados em plataformas IO. Veja
  [Como funciona](#️-como-funciona).
- 📍 **`path` explícito, nunca resolvido internamente.** Você decide onde o
  container vive — sem dependência interna de `path_provider`, sem
  surpresas de resolução de plugin/Activity.
- ⚡ **Escrita otimista + debounced**, com níveis opcionais de durabilidade
  mais forte (`writeAndSave()`, `writeAndFlush()`) quando você precisar.
- 🧭 **Falhas de persistência observáveis.** O `write()` continua síncrono,
  mas você pode usar `onPersistenceError` para registrar/reportar falhas de
  persistência assíncrona.
- 🧹 **APIs explícitas de ciclo de vida.** Use `close()` para liberar um
  container e `destroy()` para remover seus dados persistidos.
- 🧪 **Storage em memória para testes.** `AllBox.memory()` — sem I/O real,
  sem `Timer` real.
- 🌐 **Suporte a Web**, apoiado em `window.localStorage`.
- 🔌 **Sem reatividade embutida.** Traga a sua — veja
  [Precisa de reatividade?](#-precisa-de-reatividade).

## 📦 Instalação

```
dart pub add all_box
```

```yaml
dependencies:
  all_box: ^0.8.0
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

## 📱 App de Exemplo

O diretório `example/` contém um app Flutter interativo (`CounterPage`) que
demonstra a superfície pública usada no dia a dia: `write()` otimista vs.
`writeAndFlush()`, `erase()`, e `flushNow()` disparado em
`AppLifecycleState.paused`.

```bash
cd example
flutter pub get
flutter run
```

## 🧪 Exemplos de Uso

### Inicialização

```dart
import 'package:all_box/all_box.dart';
import 'package:path_provider/path_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final dir = await getApplicationDocumentsDirectory();
  await AllBox.init('my_container', path: dir.path);

  runApp(const MyApp());
}
```

`path` é obrigatório em plataformas IO e ignorado na Web (o `AllBox` nunca
resolve isso por você). Também existe um argumento avançado `storage:`
para conectar sua própria implementação de `AllBoxStorage`, mas o código
do dia a dia nunca precisa dele.

Nomes de container continuam permissivos por padrão por compatibilidade.
Se você quiser validar nomes no IO antes de qualquer acesso a arquivo,
habilite explicitamente:

```dart
await AllBox.init(
  'settings',
  path: dir.path,
  validateContainerName: true,
);
```

A validação estrita aceita apenas letras, números, `.`, `_` e `-`, e rejeita
nomes que parecem caminhos ou nomes reservados do sistema operacional, como
`../data`, `a/b`, `cache:name`, `CON` e `NUL`.

### Semeando dados no primeiro run

```dart
await AllBox.init(
  'settings',
  path: dir.path,
  initialData: const {'darkMode': false, 'onboarded': false},
);
```

`initialData` só se aplica na primeira vez que o container é criado — veja
[Como funciona](#️-como-funciona) para a regra exata.

### Lendo e escrevendo

```dart
final box = AllBox('my_container');

box.write('name', 'Carlos');               // otimista + debounced
String? name = box.read<String>('name');
String safeName = box.readOrDefault<String>('name', 'anonymous');

await box.writeAndSave('name', 'Carlos');  // espera o write do OS
await box.writeAndFlush('name', 'Carlos'); // espera confirmação em disco

box.remove('name');
box.erase(); // limpa tudo

await box.flushNow(); // força um flush agora, ex.: em AppLifecycleState.paused
```

### Erros de persistência

O `write()` continua síncrono de propósito: ele atualiza a memória e agenda
um flush com debounce. Se essa persistência posterior falhar, você pode
observar o erro sem transformar o `all_box` numa biblioteca de estado
reativo:

```dart
final box = await AllBox.init(
  'settings',
  path: dir.path,
  onPersistenceError: (AllBoxPersistenceError error) {
    // registre/reporte error.container, error.operation, error.cause
  },
);

box.write('theme', 'dark');
```

`writeAndSave()`, `writeAndFlush()` e `flushNow()` continuam completando com
erro quando a persistência aguardada falha. A mesma falha também é reportada
via `onPersistenceError`.

### Liberando ou destruindo um container

```dart
await box.close(); // grava pendências, fecha o storage e remove do registro

await box.close(flushPending: false); // descarta writes debounced pendentes

await box.destroy(); // apaga dados persistidos, fecha o storage e remove
```

`destroy()` é uma API de exclusão lógica. Ela remove os arquivos `.db`,
`.tmp` e `.bak` no IO, ou a chave de storage na Web, mas não é um secure
wipe e não promete sobrescrever fisicamente o armazenamento.

### Valor com fallback seguro

```dart
final box = AllBox('settings');
final theme = box.readOrDefault<String>('theme', 'light');
// Retorna 'light' se a chave 'theme' ainda não existir
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

## 🔌 Precisa de reatividade?

O `all_box` não traz uma camada reativa própria de propósito. Ele fica
focado em storage. Se você precisa de estado reativo no Flutter, use o
[`all_observer`](https://pub.dev/packages/all_observer) com
`Observer(...)` e mantenha storage e estado de UI separados — ou conecte o
`all_box` a um `ChangeNotifier`/solução de gerenciamento de estado que
você já use.

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

Qualquer um dos dois padrões mantém o `all_box` fazendo o que ele se propõe
a fazer — preferências, configurações locais, estado simples de app e
micro caches — não um substituto para um banco de dados embarcado completo,
com queries, índices ou relações (veja
[Quando usar](#-quando-usar-e-quando-não-usar)).

## 📚 API

| Member | Descrição |
| --- | --- |
| `AllBox([container])` | Factory constructor; retorna um singleton por nome de container. |
| `static AllBox.init(container, {path, flushDelay, initialData, storage, onPersistenceError, validateContainerName})` | Carrega o `container` para a memória e retorna o `AllBox` inicializado. `path` é obrigatório em plataformas IO, ignorado na Web. Validação de nome é opt-in por compatibilidade. |
| `static AllBox.memory(container, {initialData})` | Forma recomendada de testar código que consome o `all_box`: sem I/O real, sem `Timer` real. Substitui o descontinuado `initWithMemoryBackendForTesting`. |
| `T? read<T>(key)` / `T readOrDefault<T>(key, fallback)` | Leituras síncronas. |
| `void write(key, value)` | Escrita otimista + debounced. |
| `Future<void> writeAndSave(key, value)` | Escreve e espera o write do OS terminar. |
| `Future<void> writeAndFlush(key, value)` | Escreve e espera a garantia de durabilidade mais forte disponível. |
| `void remove(key)` / `void erase()` | Remove uma chave / limpa tudo. |
| `Future<void> flushNow()` | Força um flush imediato, ignorando a janela de debounce. |
| `Future<void> close({flushPending})` | Grava ou descarta writes pendentes, fecha o backend de storage e remove o container do registro interno. |
| `Future<void> destroy()` | Apaga os dados persistidos do container, fecha o storage e remove do registro. Não é secure wipe. |
| `hasData(key)`, `getKeys()`, `getValues()` | Introspecção. |

## 🛠️ Como funciona

O `all_box` segue uma lista curta de decisões de design deliberadas:

- **`path` sempre explícito no IO, automático na Web.** Sem resolução
  interna de diretório, sem dependência de plugin.
- **`initialData` só se aplica num first-run de verdade.**
- **`init()` é determinístico sob concorrência.** Chamadas concorrentes
  equivalentes compartilham uma inicialização; opções conflitantes são
  rejeitadas.
- **Validação de nome de container é opt-in.** Apps existentes mantêm seus
  nomes por padrão; o modo estrito fica disponível via
  `validateContainerName`.
- **Falhas de persistência são observáveis.** `onPersistenceError` reporta
  falhas assíncronas do flush debounced sem tornar `write()` assíncrono.
- **Web atualmente é apenas Window/localStorage.** Web Workers, Service
  Workers, escritas multiaba seguras e ativar IndexedDB como backend são
  trabalho futuro de backend; o testbed interno de IndexedDB ainda não é
  usado por `AllBox.init()`.
- **Sem reatividade embutida** — veja
  [Precisa de reatividade?](#-precisa-de-reatividade).

O pipeline de write-ahead + rename atômico, a coordenação de
flush/debounce, o backend Web via `dart:js_interop`, e a lista completa de
limitações conhecidas (limites do storage Web, isolate-safety,
portabilidade do `File.rename`) estão documentados em
[Arquitetura interna](documentation/pt-BR/architecture.md).

## ⚖️ Comparação

| | `all_box` | GetStorage | Hive | Isar | SharedPreferences |
|---|---|---|---|---|---|
| Leitura | Síncrona, em memória | Síncrona, em memória | Síncrona (box aberta) | Síncrona (simples) / assíncrona (queries) | Assíncrona |
| `path` do storage | Explícito, obrigatório | Resolvido internamente | Resolvido pelo chamador | Resolvido pelo chamador | Resolvido pela plataforma |
| Estratégia de crash-safety | Write-ahead + rename atômico + `.bak`, documentada | Não documentada no mesmo nível | WAL/compaction interno | WAL via engine própria | Depende da plataforma |
| Suporte a Web | Sim (`localStorage`) | Sim | Sim | Sim | Sim |
| Reatividade | Nenhuma (traga a sua) | `GetBuilder`/`Obx` (GetX) | `ValueListenableBuilder` sobre `box.listenable()` | `watchObject`/`watchLazy` (streams) | Nenhuma — precisa de wrapper próprio |
| Escopo | Só storage key-value | Storage + utils de UI (GetX) | Storage orientado a boxes | Banco de dados completo | Wrapper de plataforma |

![Comparativo de desempenho: all_box vs. Hive e SharedPreferences, medido no dispositivo em modo profile](doc/comparison_benchmark_pt-BR.png)

Medido no dispositivo (Android, modo profile) pela tela "Comparativo de
storage" do app example. Metodologia completa, números e ressalvas por
biblioteca em [Comparação](documentation/pt-BR/comparison.md).

`all_box` propositalmente não tenta ser um banco de dados nem resolver seu
próprio `path` — isso é uma escolha de design, não uma lacuna.

## 🤔 Quando usar (e quando não usar)

Use `all_box` quando quiser um storage chave-valor simples — configurações,
flags, pequenos estados de app — com leituras síncronas depois do boot e
escrita otimista com opção de confirmação durável explícita. Traga sua
própria reatividade (veja [acima](#-precisa-de-reatividade)) se precisar
dela.

Escolha outra coisa quando precisar especificamente do que ela faz de
melhor: adapters de tipo customizado para objetos complexos (Hive), um
banco de dados embarcado completo com queries/índices/relações (Isar), o
wrapper de plataforma mais "padrão" do ecossistema Flutter
(SharedPreferences), ou uma lib de storage com reatividade embutida.

## 🧪 Testes

```bash
flutter test
```

Se você está testando seu próprio app/pacote (não o `all_box` em si), use
storage em memória em vez de um diretório real ou navegador:

```dart
final box = await AllBox.memory(
  'my_container',
  initialData: {'darkMode': true},
);
```

Isso não faz I/O real e não agenda nenhum `Timer` real, o que importa
especialmente dentro de `testWidgets` (sua zona `FakeAsync` espera que
todo `Timer` seja resolvido antes do teste terminar).

(O antigo `AllBox.initWithMemoryBackendForTesting()` ainda funciona — agora
é só um wrapper fino e `@Deprecated` em volta do `AllBox.memory()`.)

## 📚 Documentação

- [Comparação](documentation/pt-BR/comparison.md) — comparação detalhada com GetStorage, Hive, Isar, SharedPreferences, incluindo benchmark de desempenho.
- [Arquitetura interna](documentation/pt-BR/architecture.md) — pipeline de write-ahead + rename atômico, coordenação de flush, o backend Web via `dart:js_interop`, e limitações conhecidas.

## 📦 Outros pacotes nossos

`all_box` faz parte de uma pequena família de pacotes Dart & Flutter
publicados sob o publisher verificado
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
