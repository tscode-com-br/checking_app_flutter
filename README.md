# Checking

Aplicativo Android em Flutter para registro de Check-In e Check-Out do projeto Checking.

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

## Publicação do código no repositório dedicado do app

Este app está dentro de um monorepo. Para publicar somente a pasta `checking_android_new` no repositório dedicado do app Flutter, use `git subtree`:

```bash
# na raiz do monorepo
git subtree split --prefix checking_android_new -b checking-app-release

# HTTPS
git push https://github.com/tscode-com-br/checking_app_flutter.git checking-app-release:main

# ou SSH
git push git@github.com:tscode-com-br/checking_app_flutter.git checking-app-release:main
```

Opcionalmente, depois do push:

```bash
git branch -D checking-app-release
```
