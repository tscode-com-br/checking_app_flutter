# Google Play Readiness

## Release alvo

- Versão funcional: `1.0.0`
- Build inicial: `1` (`pubspec.yaml` com `1.0.0+1`)

## O que já foi implementado no código

- app Android nativo em Flutter dentro de `checking_android_new`
- `applicationId` e namespace definidos como `com.br.checking`
- tráfego HTTP inseguro desabilitado no Android Manifest
- chave compartilhada da API armazenada com `flutter_secure_storage`
- cliente HTTP bloqueando URL de API sem HTTPS
- permissões Android alinhadas ao escopo operacional atual:
  - `INTERNET`
  - `ACCESS_NETWORK_STATE`
  - `ACCESS_COARSE_LOCATION`
  - `ACCESS_FINE_LOCATION`
- `ACCESS_BACKGROUND_LOCATION`
- `FOREGROUND_SERVICE`
- `FOREGROUND_SERVICE_LOCATION`
- `POST_NOTIFICATIONS`
- `RECEIVE_BOOT_COMPLETED`
- agendamento nativo restaurado após reboot e update do app
- geolocalização automática em background ligada a serviço nativo Android
- build Android validado com sucesso em debug
- configuração de release Android com assinatura obrigatória por upload key (sem fallback debug)
- análise estática e testes básicos validados

## O que ainda depende de material e configuração manual

1. Gerar keystore de produção e preencher `android/keystore.properties` a partir de `android/keystore.properties.example`.
2. Definir versão oficial de publicação e política de versionamento.
3. Publicar política de privacidade acessível por URL pública.
4. Preencher a ficha de Data Safety no Google Play Console.
5. Definir classificação indicativa do app.
6. Produzir ícone final, screenshots e texto definitivo da ficha da loja.
7. Declarar e justificar `background location` com bastante precisão na Play Console, porque o app usa geolocalização operacional em segundo plano.
8. Validar em aparelho real Android 13+ e 14+ o fluxo de permissão de notificação e localização em background.
9. Gerar o `appbundle` final com upload key definitivo para upload na Play Store.

## Passo a passo operacional para o envio da versão 1.0.0

1. Criar `android/keystore.properties` com os dados reais de upload key.
2. Confirmar versão em `pubspec.yaml`: `version: 1.0.0+1`.
3. Executar qualidade mínima:
  - `flutter analyze`
  - `flutter test`
4. Gerar o AAB assinado:
  - `flutter build appbundle --release --build-name 1.0.0 --build-number 1`
  - ou `pwsh ./scripts/build-play-aab.ps1 -BuildName 1.0.0 -BuildNumber 1`
5. Subir o arquivo gerado em `build/app/outputs/bundle/release/app-release.aab` no Google Play Console.
6. Preencher Data Safety, classificação indicativa, política de privacidade e declarações de localização em background.
7. Enviar para teste interno e validar em dispositivo real Android 13+ e 14+.

## O que ainda falta no produto

1. Refinar textos e estados de erro para operação em campo.
2. Validar o fluxo completo contra a API em ambiente real com chave móvel de produção.
3. Executar um build release assinado com upload key definitivo.

## Comandos já validados

```bash
flutter analyze
flutter test
flutter build apk --debug
flutter build appbundle --release --build-name 1.0.0 --build-number 1
```

## Observação importante

O projeto está pronto para gerar o AAB assinado da versão 1.0.0, mas a submissão final ainda depende de pendências de Play Console (política de privacidade, Data Safety, classificação indicativa e materiais de loja), que são externas ao código.