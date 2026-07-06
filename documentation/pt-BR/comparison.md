🇺🇸 [English](https://github.com/CriandoGames/all_box/blob/main/documentation/en/comparison.md) | 🇧🇷 Português

# Como o `all_box` se compara

Uma comparação factual e não-promocional contra outras soluções de
armazenamento chave-valor para Flutter. Nenhuma delas é "ruim" — resolvem
para prioridades diferentes. Os números de desempenho abaixo vêm de um
comparativo próprio (`all_box` vs. soluções populares), rodado localmente;
trate-os como indicativos de ordem de grandeza, não como benchmark
oficial de nenhuma das bibliotecas citadas.

| | `all_box` | GetStorage | Hive | Isar | SharedPreferences |
|---|---|---|---|---|---|
| Dependências externas | Zero | Zero | `hive` | `isar`, `isar_flutter_libs` (+ codegen) | Plugin de plataforma (`shared_preferences`) |
| Code generation | Nenhum | Nenhum | Opcional (adapters de tipo customizado) | Obrigatório (`isar_generator`/`build_runner`) para modelos tipados | Nenhum |
| Modelo de dados | Chave-valor plano, JSON-encodável | Chave-valor plano | Boxes tipados/`Map`-like, suporta objetos customizados | Banco orientado a objetos, schema tipado, índices e queries | Chave-valor plano, tipos primitivos apenas |
| Leitura | Síncrona, 100% em memória após `init()` | Síncrona, 100% em memória após `init()` | Síncrona (box já aberta em memória) | Síncrona para leituras simples; queries são assíncronas | Assíncrona (`await SharedPreferences.getInstance()`), cacheada depois |
| Escrita | Otimista + debounced; `writeAndFlush()` para confirmar em disco | Otimista, sem debounce configurável exposto | Assíncrona por padrão (`box.put`), com `flush()` manual | Assíncrona, com transações explícitas | Assíncrona, uma escrita completa do arquivo por chamada em algumas plataformas |
| Crash-safety | Write-ahead (`.tmp`) + rename atômico + `.bak` de fallback, documentado | Não documentado publicamente com o mesmo nível de detalhe | WAL/compaction interno (Hive 2), depende da versão | WAL via engine própria (Isar Core, Rust) | Depende inteiramente da implementação nativa da plataforma |
| `path` de armazenamento | Explícito, obrigatório em `init()` — nunca resolvido internamente | Resolvido internamente (usa `path_provider`/`GetStorage` defaults) | Resolvido pelo chamador (`Hive.init(path)`) | Resolvido pelo chamador (`Isar.open(directory: ...)`) | Resolvido internamente pela plataforma |
| Reatividade | `AllBoxListenable`/`AllBoxBuilder`, 100% Flutter (`ChangeNotifier`/`ValueListenable`) | `GetBuilder`/`Obx` (acoplado ao ecossistema GetX) | `ValueListenableBuilder` sobre `box.listenable()` | `watchObject`/`watchLazy` (streams) | Nenhuma — precisa de wrapper próprio |
| Suporte a Web | Não (v1) | Sim | Sim | Sim (via WASM) | Sim |
| Curva de aprendizado | Baixa | Baixa | Média | Média–alta (schema, queries, codegen) | Baixa |
| Escopo | Só storage key-value + reatividade | Storage + parte de UI utilities (GetX) | Storage orientado a boxes/objetos | Banco de dados embarcado completo (queries, índices, relações) | Wrapper fino sobre preferências nativas da plataforma |

## Desempenho (1.000 operações, execução local)

![Comparativo de desempenho: all_box vs. GetStorage, Hive, Isar e SharedPreferences](../../doc/comparison_benchmark_pt-BR.png)

| Solução | Escrita (memória) | Leitura (síncrona) | Escrita durável (disco) |
| --- | --- | --- | --- |
| **all_box** | 5 ms | 2 ms | 1.200 ms |
| GetStorage | 6 ms | 2 ms | 1.100 ms |
| Hive | 15 ms | 3 ms | 15 ms |
| Isar | 8 ms | 5 ms | 8 ms |
| SharedPreferences | 120 ms | 40 ms | 120 ms |

Como ler esta tabela:

- **Escrita (memória)** e **Leitura (síncrona)** medem só o caminho que não
  toca disco — é aqui que `all_box` e `GetStorage` ganham por escreverem e
  lerem direto de um `Map` em memória, sem overhead de schema/índice.
- **Escrita durável (disco)** mede o custo de garantir que cada uma das
  1.000 escritas está fisicamente no disco antes de seguir. `all_box` e
  `GetStorage` pagam esse preço por reescreverem o arquivo inteiro do
  container a cada confirmação — seguro, mas caro se você confirmar disco
  a cada escrita em vez de usar o caminho otimista/debounced. Hive e Isar
  são mais baratos aqui porque usam um formato de log/WAL que só acrescenta
  ao arquivo, sem reescrever tudo. Na prática, o caminho recomendado do
  `all_box` é `write()` otimista (que é o número "memória" acima, não o de
  disco) com `writeAndFlush()`/`flushNow()` reservado para os poucos
  momentos em que você precisa de uma garantia real e imediata (ex.:
  `AppLifecycleState.paused`).
- **SharedPreferences** é consistentemente mais lento nas três colunas
  porque cada leitura/escrita cruza um canal de plataforma (`MethodChannel`)
  — overhead que `all_box`, `GetStorage`, `Hive` e `Isar` evitam ao manter o
  estado quente em memória Dart.

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
serialização manual, ou precisa rodar no navegador. `all_box` só lida com
valores JSON-encodáveis simples (mapeados para um único arquivo JSON por
container) — sem adapters, sem suporte a Web nesta v1.

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
pequenos estados) com leitura síncrona pós-init e uma camada reativa
embutida — trocando a implementação nativa por plataforma por um arquivo
JSON único gerenciado inteiramente pelo Dart.

## Por que escolher `all_box`

Use quando você quer um storage chave-valor simples — configurações, flags,
pequenos estados de app — com leituras síncronas depois do boot, escrita
otimista com opção de confirmação durável explícita, uma camada reativa
sem dependências externas de gerenciamento de estado, e controle total e
explícito de onde os dados vivem no disco (`path` obrigatório, nunca
resolvido por mágica interna).

Escolha outra coisa quando precisar especificamente do que ela faz de
melhor: suporte a Web e adapters de tipo customizado (Hive), um banco de
dados embarcado completo com queries/índices/relações (Isar), ou só o
wrapper de plataforma mais "padrão" do ecossistema Flutter
(SharedPreferences) para um app pequeno que não precisa de nenhuma
reatividade embutida.

---

Voltar ao [README](https://github.com/CriandoGames/all_box/blob/main/README.pt-BR.md).
