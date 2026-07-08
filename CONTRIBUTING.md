# Contribuindo com o all_box

Obrigado por considerar contribuir com o `all_box`! Este pacote faz parte da
família `all_*` de projetos open-source da **CriandoGames**, ao lado de
[`all_validations_br`](https://github.com/CriandoGames/all_validations_br) e
`all_compress`. As regras abaixo seguem o mesmo padrão dos demais pacotes da
família.

## Como começar

1. Faça um fork do repositório e clone-o localmente.
2. Instale as dependências:

   ```bash
   dart pub get
   ```

3. Crie uma branch a partir da `main`:

   ```bash
   git checkout -b minha-contribuicao
   ```

## Rodando os testes

```bash
dart test
```

Toda mudança em `lib/` deve vir acompanhada de teste(s) correspondente(s) em
`test/`. Os testes existentes cobrem cenários específicos de crash-safety
(arquivo corrompido, JSON inválido, fallback para `.bak`) e debounce de
escrita — mantenha esse padrão de cobertura ao adicionar funcionalidades
novas.

## Rodando o app de exemplo

```bash
cd example
flutter pub get
flutter run
```

Se sua mudança afeta a API pública, atualize também o `example/lib/main.dart`
para demonstrá-la.

## Estilo de código

```bash
dart format .
dart analyze
```

Nenhum PR deve introduzir warnings do `dart analyze` nem quebrar a
formatação padrão do `dart format`.

## Escopo do pacote

Alguns princípios de design são inegociáveis e qualquer mudança que os
contrarie provavelmente será recusada:

- **Sem reatividade embutida.** `all_box` é Dart puro e não deve ganhar de
  volta nenhuma API de listener/reatividade (nem `AllBoxListenable`/
  `AllBoxBuilder`, nem `listenKey`/`listenAll`) nem voltar a depender do
  Flutter SDK no `pubspec.yaml`. Se você precisa de reatividade no seu app,
  conecte `all_box` a um `setState`, a um `ChangeNotifier` seu, ao
  `all_observer`, ou ao que já usar.
- **`path` continua explícito.** `AllBox` não deve importar `path_provider`
  nem resolver diretório algum internamente.
- **Crash-safety não é opcional.** Qualquer mudança na camada de persistência
  deve manter o padrão write-ahead (`.tmp` → rename atômico) e o fallback
  para `.bak`.

## Enviando o Pull Request

1. Garanta que `dart test` e `dart analyze` passam localmente.
2. Descreva o que mudou e por quê — inclua o cenário de bug ou a
   funcionalidade motivadora, se aplicável.
3. Referencie issues relacionadas, quando existirem.
4. Adicione uma entrada em `CHANGELOG.md` seguindo o formato já usado.

## Reportando bugs

Abra uma issue com:

- Versão do `all_box` e do Flutter/Dart.
- Passos para reproduzir.
- Comportamento esperado vs. observado.
- Se possível, um teste que reproduz a falha — acelera muito a correção.

Toda contribuição, seja código, documentação ou relato de bug, é bem-vinda.
