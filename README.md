# Checking

Aplicativo Android em Flutter para registro de Check-In e Check-Out do projeto Checking.

## Situacao de repositorio

- Este diretorio continua com `.git` proprio no workspace.
- O procedimento oficial do projeto nao usa mais commit/push deste app.
- Nao usar `git subtree` nem push deste repositorio como parte da rotina operacional.
- O unico fluxo oficial de commit/push do projeto fica no repositorio principal `checkcheck`.

## Versão de publicação

- versão alvo para a Google Play: `1.2.2`
- versão do app no projeto: `1.2.2+9` em `pubspec.yaml`

## Escopo atual

- layout responsivo herdado da versao anterior do app
- persistência local de configuração e histórico básico
- banco local SQLite para catálogo de localizações
- armazenamento seguro da chave compartilhada da API
- sincronização do histórico por `GET /api/mobile/state`
- sincronização do catálogo por `GET /api/mobile/locations`
- envio manual e automático por `POST /api/mobile/events/forms-submit`
- agendamento Android nativo persistido localmente e restaurado após reboot/update
- compartilhamento de localização precisa com monitoramento em segundo plano no Android
- automação de check-in/check-out ao entrar no range de localizações cadastradas no website admin
- configuração de release pronta para assinatura por upload key e geração de AAB

## Comandos úteis

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
flutter build appbundle --release
```

Build de release assistido (versão 1.2.2):

```powershell
pwsh ./scripts/build-play-aab.ps1 -BuildName 1.2.2 -BuildNumber 9
```

Cada build assistido passa a arquivar o `app-release.aab` e o `mapping.txt` do R8 em `build/release-artifacts/<buildName>+<buildNumber>/`.

Preflight de publicacao (valida assinatura, qualidade e gera AAB):

```powershell
pwsh ./scripts/play-release-preflight.ps1 -BuildName 1.2.2 -BuildNumber 9
```

Geracao de upload key (uma unica vez, interativo):

```powershell
pwsh ./scripts/create-upload-keystore.ps1
```

Comando de geração de upload key (uma única vez):

```powershell
keytool -genkeypair -v -storetype JKS -keyalg RSA -keysize 2048 -validity 10000 -alias checking-upload -keystore android/keys/checking-upload-keystore.jks
```

## Estrutura principal

- `lib/src/app` inicialização do app
- `lib/src/core/theme` tema visual
- `lib/src/features/checking/models` modelos de estado e respostas da API
- `lib/src/features/checking/services` persistência local e cliente HTTP
- `lib/src/features/checking/controller` regra de negócio da tela
- `lib/src/features/checking/view` interface principal

## Observações

- o fluxo de envio ao Forms foi movido para a API; o app não executa mais automação local do Microsoft Forms
- o campo `local` enviado pelo app atualiza somente o estado operacional e a auditoria na API; ele não altera o preenchimento do Microsoft Forms
- para release assinado, copie `android/keystore.properties.example` para `android/keystore.properties` e preencha os dados reais do upload key
- o build de release agora exige upload key válida; não há fallback para assinatura de debug
- a publicação final na Google Play ainda depende de política de privacidade, Data Safety e material de loja

Checklist operacional completo para submissao:

- `docs/google-play-submission-checklist.md`
- `docs/google-play-console-content.md`

## Operacao Git atual

O app continua disponivel no workspace para leitura, manutencao local, build e testes, mas nao existe mais procedimento oficial de publicacao por Git para este diretorio.

Regra pratica:

- nao fazer `git commit` neste diretorio como parte da rotina operacional do projeto;
- nao fazer `git push` deste diretorio;
- nao usar `git subtree` a partir do repositorio principal para tentar sincronizar o app.
