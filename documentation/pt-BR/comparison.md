🇺🇸 [English](https://github.com/CriandoGames/all_box/blob/main/documentation/en/comparison.md) | 🇧🇷 Português

# Como o `all_box` se compara

Uma comparação factual e não-promocional contra outras soluções de
armazenamento chave-valor para Flutter. Nenhuma delas é "ruim" — resolvem
para prioridades diferentes. Os números de desempenho abaixo foram medidos
**no dispositivo**, pela tela "Comparativo de storage" do app `example/`
deste repositório (Android, modo profile, mesma sessão e mesmos loops para
todas as libs) — qualquer pessoa pode reproduzir rodando
`cd example && flutter run --profile`. Trate-os como indicativos de ordem
de grandeza, não como benchmark oficial de nenhuma das bibliotecas citadas.

| | `all_box` | GetStorage | Hive | Isar | SharedPreferences |
|---|---|---|---|---|---|
| Dependências externas | Zero | Zero | `hive` | `isar`, `isar_flutter_libs` (+ codegen) | Plugin de plataforma (`shared_preferences`) |
| Code generation | Nenhum | Nenhum | Opcional (adapters de tipo customizado) | Obrigatório (`isar_generator`/`build_runner`) para modelos tipados | Nenhum |
| Modelo de dados | Chave-valor plano, JSON-encodável | Chave-valor plano | Boxes tipados/`Map`-like, suporta objetos customizados | Banco orientado a objetos, schema tipado, índices e queries | Chave-valor plano, tipos primitivos apenas |
| Leitura | Síncrona, 100% em memória após `init()` | Síncrona, 100% em memória após `init()` | Síncrona (box já aberta em memória) | Síncrona para leituras simples; queries são assíncronas | Assíncrona (`await SharedPreferences.getInstance()`), cacheada depois |
| Escrita | Otimista + debounced; `writeAndSave()` (aguarda o OS) e `writeAndFlush()` (fsync) para confirmar em disco | Otimista, sem debounce configurável exposto; nenhuma API espera o disco | Assíncrona por padrão (`box.put`), com `flush()` manual | Assíncrona, com transações explícitas | Assíncrona, uma escrita completa do arquivo por chamada em algumas plataformas |
| Crash-safety | Write-ahead (`.tmp`) + rename atômico + `.bak` de fallback, documentado | Não documentado publicamente com o mesmo nível de detalhe | WAL/compaction interno (Hive 2), depende da versão | WAL via engine própria (Isar Core, Rust) | Depende inteiramente da implementação nativa da plataforma |
| `path` de armazenamento | Explícito, obrigatório em `init()` — nunca resolvido internamente | Resolvido internamente (usa `path_provider`/`GetStorage` defaults) | Resolvido pelo chamador (`Hive.init(path)`) | Resolvido pelo chamador (`Isar.open(directory: ...)`) | Resolvido internamente pela plataforma |
| Reatividade | Nenhuma — traga a sua (`setState`, um `ChangeNotifier` seu, `all_observer`, ...) | `GetBuilder`/`Obx` (acoplado ao ecossistema GetX) | `ValueListenableBuilder` sobre `box.listenable()` | `watchObject`/`watchLazy` (streams) | Nenhuma — precisa de wrapper próprio |
| Suporte a Web | Sim (`window.localStorage` via `dart:js_interop`) | Sim | Sim | Sim (via WASM) | Sim |
| Curva de aprendizado | Baixa | Baixa | Média | Média–alta (schema, queries, codegen) | Baixa |
| Escopo | Só storage key-value | Storage + parte de UI utilities (GetX) | Storage orientado a boxes/objetos | Banco de dados embarcado completo (queries, índices, relações) | Wrapper fino sobre preferências nativas da plataforma |

## Desempenho (medido no dispositivo, modo profile)

![Comparativo de desempenho: all_box vs. Hive e SharedPreferences](../../doc/comparison_benchmark_pt-BR.png)

Android (build AE3A.240806.036), modo profile, tela "Comparativo de
storage" do app `example/`, mediana de 5 rodadas (memória) / 3 (disco).
Custo médio por operação (menor é melhor):

| Cenário | all_box | Hive | SharedPreferences |
| --- | --- | --- | --- |
| Escrita otimista (memória), 10.000 ops | **0,3 µs** | 5,3 µs | 87,2 µs |
| Leitura síncrona, 10.000 ops | **0,2 µs** | 0,9 µs | 0,2 µs |
| Escrita confirmada (sem fsync), 200 ops | 28,9 ms | **5,6 ms** | 30,1 ms |
| Escrita durável com fsync, 200 ops | 52,6 ms | — sem API | — sem API |
| Burst de 200 `write()` + 1 flush | **323,7 µs** | 4.532,5 µs | 25.199,0 µs |

Como ler esta tabela:

- **Escrita otimista e leitura** são os pontos fortes do `all_box`: lookup
  e escrita diretos em um `HashMap` em memória — ~17× mais rápido que o
  Hive na escrita, empate técnico com SharedPreferences na leitura.
- **Burst + 1 flush** é o cenário do uso real do `all_box` (escrita
  otimista com debounce, um único flush no fim): 200 escritas persistidas
  em 64 ms no total, ~14× mais rápido que Hive e ~78× que
  SharedPreferences no mesmo loop.
- **Escrita confirmada** usa o contrato de "persistido" de cada lib, sem
  fsync em nenhuma (`writeAndSave()` no `all_box`, `put()` no Hive,
  `setInt()` no SharedPreferences). O Hive vence esta linha, e o motivo é
  estrutural: ele *anexa* alguns bytes num log, enquanto o `all_box`
  regrava o arquivo do container com write-ahead + rename atômico —
  mais operações de arquivo por confirmação, em troca de um arquivo que
  nunca fica meio-escrito. Se você confirma disco a cada escrita em um
  loop, o Hive é melhor; o caminho recomendado do `all_box` é o
  otimista/debounced (linhas 1 e 5).
- **Escrita durável com fsync** só tem uma barra porque só o `all_box`
  oferece essa garantia (`writeAndFlush()`): quando o `Future` completa, o
  dado sobrevive a queda de energia, não só a crash do app. Nenhuma das
  outras tem API equivalente.
- **GetStorage** não está na tabela medida por um motivo técnico: o
  `Future` do `write()` dele resolve após agendar um microtask, sem
  esperar nem o write bufferizado do OS — não existe API no GetStorage que
  espere o dado chegar ao disco, então não há nada comparável a medir nas
  linhas de confirmação/durabilidade. A comparação qualitativa abaixo
  continua cobrindo ele.
- **Isar** ficou fora da medição on-device (exige engine nativa + codegen,
  que complicariam o app example); a comparação qualitativa abaixo segue
  valendo.
- Números de debug mode não servem para comparação — o `all_box`, em
  particular, paga em debug um guard de `jsonEncode` por `write()` que não
  existe em release/profile.

## GetStorage

Um storage chave-valor sync/JSON muito próximo em filosofia ao `all_box` —
mesma ideia de leitura síncrona pós-init e escrita otimista. A diferença
principal de design é o `path`: `GetStorage` resolve o diretório de
armazenamento internamente, enquanto `all_box` exige que você passe `path`
explicitamente em `init()`, evitando por construção os bugs de resolução
de plugin/Activity relatados contra bibliotecas que resolvem o path
sozinhas. `all_box` também documenta explicitamente sua estratégia de
crash-safety (write-ahead + rename atômico + `.bak`); trate isso como uma
diferença de documentação/transparência, não necessariamente como uma
alegação sobre a robustez interna do `GetStorage`.

## Hive

Um banco de dados key-value baseado em boxes com um formato de arquivo
próprio, suporte nativo a Web, e adapters para tipos customizados. Melhor
escolha quando você precisa guardar objetos Dart complexos com um mínimo de
serialização manual. `all_box` só lida com valores JSON-encodáveis simples
(mapeados para um único arquivo JSON por container no IO, ou uma chave
`localStorage` na Web) — sem adapters.

## Isar

Um banco de dados embarcado completo: schema tipado, índices, queries
compostas e relações, construído sobre uma engine própria em Rust. Melhor
escolha quando seu app precisa de fato de um banco de dados — queries
complexas, grandes volumes de registros, relações entre entidades — e não
só de um punhado de preferências/flags. `all_box` propositalmente não tenta
ser um banco de dados; é um key-value plano para configurações, flags e
pequenos estados de app.

## SharedPreferences

O wrapper de plataforma "oficial" do Flutter sobre `UserDefaults`
(iOS/macOS)/`SharedPreferences` (Android) e equivalentes em outras
plataformas. Onipresente e simples, mas assíncrono do início ao fim e
limitado a tipos primitivos (sem listas/mapas aninhados sem serialização
manual). `all_box` cobre o mesmo caso de uso central (configurações, flags,
pequenos estados) com leitura síncrona pós-init — trocando a implementação
nativa por plataforma por um arquivo JSON único gerenciado inteiramente
pelo Dart.

## Por que escolher `all_box`

Use quando você quer um storage chave-valor simples — configurações, flags,
pequenos estados de app — com leituras síncronas depois do boot, escrita
otimista com opção de confirmação durável explícita, e controle total e
explícito de onde os dados vivem no disco (`path` obrigatório, nunca
resolvido por mágica interna). O `all_box` não tem nenhuma API
reativa/de listener própria — conecte as atualizações a um `setState`, um
`ChangeNotifier` seu, ao `all_observer`, ou ao que seu app já usar.

Escolha outra coisa quando precisar especificamente do que ela faz de
melhor: adapters de tipo customizado para objetos complexos (Hive), um
banco de dados embarcado completo com queries/índices/relações (Isar), o
wrapper de plataforma mais "padrão" do ecossistema Flutter
(SharedPreferences), ou uma lib de storage com reatividade embutida.

---

Voltar ao [README](https://github.com/CriandoGames/all_box/blob/main/README.pt-BR.md).
