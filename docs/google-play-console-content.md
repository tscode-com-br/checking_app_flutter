# Google Play Console Content (Template)

Use this as a starting point in Play Console fields.

## Short description (up to 80 chars)

```text
Registro rapido de Check-In e Check-Out com historico e operacao em campo.
```

## Full description (up to 4000 chars)

```text
Checking e um aplicativo operacional para registrar Check-In e Check-Out com rapidez.

Recursos principais:
- registro manual de Check-In e Check-Out
- historico do ultimo Check-In e ultimo Check-Out por usuario
- sincronizacao com API segura (HTTPS)
- agendamento local para apoio operacional
- recursos de geolocalizacao para fluxo operacional em campo

O aplicativo foi projetado para uso corporativo em rotinas de presenca e operacao.

Importante:
- o uso de localizacao depende da configuracao e autorizacao do usuario
- alguns recursos podem usar localizacao em segundo plano quando habilitados para automacao operacional
```

## Reviewer notes (for sensitive permissions)

```text
This app is used in operational attendance workflows.

Background location is used only when the feature is enabled by the operator to support operational automation scenarios.

How to test:
1) Open app and enter a valid 4-char user key.
2) Enable geolocation options in the app panel.
3) Grant location permissions requested by Android.
4) Configure reference point and radius.
5) Move in/out of configured area and verify behavior.
```

## Support contact

Fill in Play Console fields:

1. Support email
2. Privacy policy URL
3. Optional support website
