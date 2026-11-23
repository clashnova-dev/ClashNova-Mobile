<div align="center">

<img src="../../assets/icon/icon.png" width="116" alt="ClashNova" />

<h1>ClashNova Mobile</h1>

<p>
  <b>Un client proxy iOS et Android fondé sur <a href="https://sing-box.sagernet.org/">sing-box</a> (libbox), écrit en Flutter.</b><br/>
  Importez un abonnement Clash, sing-box ou universel et vous êtes connecté — rien ne tourne sur un serveur.
</p>

<p>
  <a href="../../LICENSE"><img alt="License" src="https://img.shields.io/badge/License-GPL--3.0-2f6fed?style=flat-square"></a>
  <img alt="Platforms" src="https://img.shields.io/badge/iOS%20·%20Android-5b6472?style=flat-square">
  <img alt="Flutter" src="https://img.shields.io/badge/Flutter-02569B?style=flat-square&logo=flutter&logoColor=white">
  <img alt="sing-box core" src="https://img.shields.io/badge/core-sing--box-7d56f4?style=flat-square">
</p>

<p>
  <a href="../../README.md">English</a> ·
  <a href="README.zh-CN.md">简体中文</a> ·
  <a href="README.de.md">Deutsch</a> ·
  <b>Français</b> ·
  <a href="README.ja.md">日本語</a> ·
  <a href="README.ko.md">한국어</a> ·
  <a href="README.ru.md">Русский</a>
</p>

<img src="../screenshots/home-light.png" width="232" alt="Home (light)" />
<img src="../screenshots/home-dark.png" width="232" alt="Home (dark)" />
<img src="../screenshots/nodes.png" width="232" alt="Nodes" />

<p><a href="https://github.com/clashnova-dev">clashnova-dev</a></p>

</div>

> Les traductions peuvent être en retard sur le document principal en anglais.
## ✨ Fonctionnalités

**Abonnements.** Trois formats sont analysés en nœuds sur l'appareil :

- **Clash** YAML (`proxies:`) — converti dans l'application, couvrant ss / vmess / vless / trojan / hysteria2 / tuic / socks / http, les transports ws et grpc, et tls / reality / utls.
- **sing-box** JSON — ses `outbounds` et `endpoints` sont utilisés directement.
- **Universel** — liens de partage en base64 ou ligne par ligne (vmess, vless, trojan, ss, hysteria2, tuic, etc.).

Chaque abonnement peut être actualisé, copié ou supprimé ; la carte affiche le nombre de nœuds et l'heure de dernière mise à jour, et tout type de nœud non reconnu est ignoré sans affecter les autres.

**Nœuds.** Recherche par nom, région ou protocole et tri par latence. *Test* effectue une poignée de main TCP sur chaque nœud — avec un indicateur de progression interruptible — et classe le résultat en vert (≤100 ms), jaune (≤300 ms) ou rouge, avec *Délai dépassé* pour tout ce qui est injoignable. Choisissez un nœud à la main, ou laissez la sélection automatique (le groupe `urltest` du cœur retient le plus rapide).

**Connexion et routage.** Le VPN système passe par une Network Extension (Packet Tunnel) sur iOS et par `VpnService` sur Android. Basculez le routage entre **règles**, **global** et **direct** une fois connecté (relié au clash mode du cœur). Une liste des connexions en direct (chacune fermable), le journal en direct du cœur et le débit montant/descendant sont disponibles.

**Interface.** Thèmes clair / sombre / selon le système, et sept langues — chinois simplifié, anglais, 日本語, 한국어, Deutsch, Français, Русский — changées dans les paramètres et appliquées immédiatement.

## 📸 Captures d'écran

| Nœuds | Abonnements | Paramètres | Aide |
| :-: | :-: | :-: | :-: |
| <img src="../screenshots/nodes.png" width="190"> | <img src="../screenshots/subscriptions.png" width="190"> | <img src="../screenshots/settings.png" width="190"> | <img src="../screenshots/help.png" width="190"> |

| Ajouter un abonnement | Langue | Accueil (clair) | Accueil (sombre) |
| :-: | :-: | :-: | :-: |
| <img src="../screenshots/add-subscription.png" width="190"> | <img src="../screenshots/language.png" width="190"> | <img src="../screenshots/home-light.png" width="190"> | <img src="../screenshots/home-dark.png" width="190"> |

## 🛠️ Compilation

Il vous faut Flutter (la version est fixée par la contrainte `sdk` dans [pubspec.yaml](../../pubspec.yaml)) et la chaîne d'outils de chaque plateforme cible.

```sh
cp .env.example .env
flutter pub get
python3 scripts/prepare-libbox.py android
python3 scripts/prepare-libbox.py apple
flutter run --dart-define-from-file=.env                                               # débogage sur un appareil connecté
flutter build apk --release --dart-define-from-file=.env                               # Android
flutter build ipa --release --dart-define-from-file=.env --export-method development   # iOS
```

### Configuration (.env)

Les options de compilation sont injectées avec `--dart-define-from-file`, depuis un fichier `.env` à la racine du projet (ignoré par `.gitignore`) :

```
ENABLE_LOGIN=false   # à false, l'écran de connexion au compte est masqué
BASE_URL=            # URL de backend optionnelle ; vide = client d'abonnement autonome
```

Laissée à ces valeurs par défaut, l'application est un client d'abonnement autonome. Les valeurs par défaut se trouvent dans [lib/env.dart](../../lib/env.dart).

### iOS

Le VPN iOS est fourni par une Network Extension, il **ne fonctionne donc que sur un appareil réel** (le simulateur n'exécute que l'interface). Un premier build sur un appareil nécessite :

- un compte développeur Apple payant ;
- la signature configurée pour les deux cibles `Runner` et `PacketTunnel` dans *Signing & Capabilities* de Xcode, avec App Groups et Network Extensions activés ;
- l'App Group `group.dev.airport.airportMobile` et l'identifiant de bundle de l'extension `dev.airport.airportMobile.PacketTunnel` (voir [lib/core/sing_box_core.dart](../../lib/core/sing_box_core.dart)).

À la première connexion, iOS demande d'ajouter la configuration VPN — autorisez-la.

### Android

Utilisez `flutter run -d <appareil>` ou installez l'APK de distribution. La première connexion déclenche l'autorisation VPN du système ; autorisez-la.

## 🗂️ Structure du projet

```
lib/
  main.dart            démarrage, MaterialApp, thème et langue, le verrou de connexion
  app_state.dart       centre d'état (abonnements / nœuds / connexion / latence / mode de routage / persistance)
  env.dart             configuration de compilation (ENABLE_LOGIN / BASE_URL)
  i18n.dart, i18n/     catalogues de messages
  theme.dart           jetons de design clairs et sombres
  widgets.dart         composants réutilisables (cartes, boîtes de dialogue, menus déroulants, pills, etc.)
  core/
    sing_box_core.dart         encapsulation du plugin sing_box (connexion / état / journal / latence / clash mode)
    subscription_parser.dart   analyse Clash / sing-box / universel
  pages/               les différentes pages (accueil / nœuds / abonnements / connexions / journaux / paramètres / aide / connexion)
```

Le trafic sortant est acheminé par le cœur sing-box sur l'appareil. Le test de nœud est une poignée de main TCP directe — il reflète l'accessibilité et la latence du serveur, pas le débit complet à travers le proxy.

## 📄 Licence

GPL-3.0. Le projet lie sing-box (libbox), sous GPL-3.0 ; les distributions doivent donc suivre la même licence et fournir le code source et les mentions correspondants. Voir [LICENSE](../../LICENSE).
