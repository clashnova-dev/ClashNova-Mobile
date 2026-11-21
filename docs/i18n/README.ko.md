# ClashNova Mobile

<!-- i18n-nav -->
[English](../../README.md) · [简体中文](README.zh-CN.md) · [Deutsch](README.de.md) · [Français](README.fr.md) · [日本語](README.ja.md) · **한국어** · [Русский](README.ru.md)

> 번역은 영어 기본 문서보다 늦을 수 있습니다.

[sing-box](https://sing-box.sagernet.org/)(libbox) 기반의 iOS / Android 프록시 클라이언트로, Flutter로 작성되었습니다. Clash, sing-box, 범용 구독을 가져오기만 하면 연결됩니다 — 서버에서는 아무것도 실행되지 않습니다. 파싱, 지연 시간 측정, 연결 자체가 모두 기기에서 이루어집니다.

코어는 [`sing_box`](https://pub.dev/packages/sing_box) 플러그인(GPL-3.0)에서 왔으므로, 프로젝트 전체가 **GPL-3.0**으로 배포됩니다.

<p align="center">
  <img src="../screenshots/home-light.png" width="230" alt="홈(라이트)">
  <img src="../screenshots/home-dark.png" width="230" alt="홈(다크)">
  <img src="../screenshots/nodes.png" width="230" alt="노드 및 지연 측정">
</p>

## 기능

**구독.** 세 가지 형식이 기기에서 노드로 파싱됩니다.

- **Clash** YAML(`proxies:`) — 앱 내에서 변환하며 ss / vmess / vless / trojan / hysteria2 / tuic / socks / http, ws·grpc 전송, tls / reality / utls를 지원합니다.
- **sing-box** JSON — 해당 `outbounds`와 `endpoints`를 그대로 사용합니다.
- **범용** — base64 또는 줄 단위 공유 링크(vmess, vless, trojan, ss, hysteria2, tuic 등).

각 구독은 새로고침·복사·삭제할 수 있고, 카드에 노드 수와 마지막 업데이트 시각이 표시됩니다. 인식할 수 없는 노드 유형은 건너뛰며 나머지에는 영향을 주지 않습니다.

**노드.** 이름·지역·프로토콜로 검색하고 지연 시간으로 정렬합니다. *테스트*는 각 노드에 TCP 핸드셰이크를 수행하고 — 중단할 수 있는 진행 표시와 함께 — 결과를 초록(≤100 ms), 노랑(≤300 ms), 빨강으로 분류하며, 도달할 수 없으면 *시간 초과*로 표시합니다. 직접 노드를 고르거나 자동 선택에 맡길 수 있습니다(코어의 urltest 그룹이 가장 빠른 노드를 고릅니다).

**연결과 라우팅.** 시스템 VPN은 iOS에서는 Network Extension(Packet Tunnel), Android에서는 VpnService를 통해 동작합니다. 연결된 상태에서 **규칙**, **전역**, **직접** 라우팅을 전환할 수 있습니다(코어의 clash mode에 연동). 실시간 연결 목록(각 연결을 개별적으로 닫을 수 있음), 코어의 실시간 로그, 업/다운 속도를 모두 제공합니다.

**인터페이스.** 라이트 / 다크 / 시스템 따름 테마와 일곱 가지 언어 — 간체 중국어, English, 日本語, 한국어, Deutsch, Français, Русский — 를 설정에서 전환하며 즉시 적용됩니다.

## 스크린샷

| 노드 | 구독 | 설정 | 도움말 |
| :-: | :-: | :-: | :-: |
| <img src="../screenshots/nodes.png" width="190"> | <img src="../screenshots/subscriptions.png" width="190"> | <img src="../screenshots/settings.png" width="190"> | <img src="../screenshots/help.png" width="190"> |

| 구독 추가 | 언어 | 홈(라이트) | 홈(다크) |
| :-: | :-: | :-: | :-: |
| <img src="../screenshots/add-subscription.png" width="190"> | <img src="../screenshots/language.png" width="190"> | <img src="../screenshots/home-light.png" width="190"> | <img src="../screenshots/home-dark.png" width="190"> |

## 빌드

Flutter(버전은 [pubspec.yaml](../../pubspec.yaml)의 `sdk` 제약을 따름)와 각 대상 플랫폼의 툴체인이 필요합니다.

```sh
cp .env.example .env
flutter pub get
python3 scripts/prepare-libbox.py android
python3 scripts/prepare-libbox.py apple
flutter run --dart-define-from-file=.env                                               # 연결된 기기에서 디버그
flutter build apk --release --dart-define-from-file=.env                               # Android
flutter build ipa --release --dart-define-from-file=.env --export-method development   # iOS
```

### 설정(.env)

빌드 옵션은 `--dart-define-from-file`로 프로젝트 루트의 `.env` 파일(gitignore 처리됨)에서 주입됩니다.

```
ENABLE_LOGIN=false   # false이면 계정 로그인 화면을 숨김
BASE_URL=            # 선택적 백엔드 주소. 비워 두면 독립 구독 클라이언트로 동작
```

기본값 그대로면 앱은 자체 완결적인 구독 클라이언트입니다. 기본값은 [lib/env.dart](../../lib/env.dart)에 있습니다.

### iOS

iOS VPN은 Network Extension이 제공하므로 **실기기에서만 동작합니다**(시뮬레이터는 UI만 실행). 기기에 처음 빌드하려면 다음이 필요합니다.

- 유료 Apple 개발자 계정;
- Xcode의 *Signing & Capabilities*에서 `Runner`와 `PacketTunnel` 두 target에 서명을 설정하고 App Groups와 Network Extensions를 활성화;
- App Group `group.dev.airport.airportMobile`와 확장 bundle id `dev.airport.airportMobile.PacketTunnel`([lib/core/sing_box_core.dart](../../lib/core/sing_box_core.dart) 참고).

처음 연결할 때 iOS가 VPN 구성 추가를 요청하므로 허용하세요.

### Android

`flutter run -d <기기>`를 사용하거나 release APK를 설치합니다. 처음 연결하면 시스템 VPN 권한 요청이 뜨므로 허용하세요.

## 프로젝트 구조

```
lib/
  main.dart            시작, MaterialApp, 테마와 언어, 로그인 게이트
  app_state.dart       상태 허브(구독 / 노드 / 연결 / 지연 / 라우팅 모드 / 영속화)
  env.dart             빌드 시 설정(ENABLE_LOGIN / BASE_URL)
  i18n.dart, i18n/     메시지 카탈로그
  theme.dart           라이트·다크 디자인 토큰
  widgets.dart         재사용 컴포넌트(카드, 다이얼로그, 드롭다운, pill 등)
  core/
    sing_box_core.dart         sing_box 플러그인 래퍼(연결 / 상태 / 로그 / 지연 / clash mode)
    subscription_parser.dart   Clash / sing-box / 범용 파싱
  pages/               각 페이지(홈 / 노드 / 구독 / 연결 / 로그 / 설정 / 도움말 / 로그인)
```

실제 아웃바운드 트래픽은 기기의 sing-box 코어가 전달합니다. 노드 테스트는 직접 TCP 핸드셰이크로 — 서버 도달성과 지연을 반영하며, 프록시를 통한 전체 처리량은 아닙니다.

## 라이선스

GPL-3.0. 이 프로젝트는 GPL-3.0인 sing-box(libbox)를 링크하므로, 배포 시 같은 라이선스를 따르고 해당 소스 코드와 고지를 제공해야 합니다. [LICENSE](../../LICENSE)를 참고하세요.
