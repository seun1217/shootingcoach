# 🏀 슈팅코치 (ShootingCoach)

휴대폰을 코트 옆에 세워두고 계속 촬영하면, **슛 하나가 끝날 때마다 애플워치가 진동과 함께 피드백**을 알려주는 iOS + watchOS 앱입니다.

- 📱 **iPhone**: 카메라로 슈터·공의 포물선·골인 여부를 실시간 분석 (온디바이스, 네트워크 불필요)
- ⌚ **Apple Watch**: 슛 결과(성공/실패)와 코칭 팁을 햅틱과 함께 즉시 표시
- 🎯 성공/실패 판정 + 짧음/김 구분, 릴리즈 각도·진입 각도, 팔꿈치·무릎 자세 팁
- 📊 세션 통계(시도/성공/성공률/연속 성공)와 최근 슛 기록
- 🎥 (선택) 세션 전체 영상을 사진 앱에 저장

## 동작 원리

```
iPhone 카메라 (1080p 60fps)
   │  프레임
   ▼
Vision 프레임워크
   ├─ VNDetectTrajectoriesRequest  → 공의 포물선 궤적 (y = ax² + bx + c)
   └─ VNDetectHumanBodyPoseRequest → 슈터 관절 (팔꿈치·무릎 각도)
   ▼
ShotAnalyzer (슛 상태 머신)
   ├─ 궤적이 끝나면: 사용자가 지정한 "림 박스"의 평면을
   │  하강하며 통과한 x 좌표로 성공 / 짧음 / 김 판정
   ├─ 포물선 계수로 릴리즈 각도·진입 각도 계산
   └─ 릴리즈 순간의 자세 스냅샷으로 폼 팁 생성
   ▼
FeedbackEngine → 한 줄 코칭 메시지
   ▼
WatchConnectivity (sendMessage, 백그라운드 시 transferUserInfo 폴백)
   ▼
Apple Watch: 햅틱(성공=success, 실패=failure) + 결과 화면
```

모든 분석은 기기 안에서만 이루어집니다. 영상이 외부로 전송되지 않습니다.

## 요구 사항

| 항목 | 최소 사양 |
|---|---|
| Xcode | 16 이상 (폴더 동기화 프로젝트 형식 사용) |
| iPhone | iOS 17 이상 · **실기기 필요** (카메라/Neural Engine) |
| Apple Watch | watchOS 10 이상, iPhone과 페어링 |

## 설치 & 실행

1. `ShootingCoach.xcodeproj`를 Xcode로 엽니다.
2. **Signing & Capabilities**에서 두 타깃(ShootingCoach, ShootingCoachWatch) 모두 본인 팀을 선택합니다.
   - 번들 ID가 겹치면 `com.seun1217.shootingcoach` 부분을 원하는 접두어로 바꾸세요.
     워치 앱의 번들 ID는 반드시 `<아이폰 번들ID>.watchkitapp` 형태를 유지하고,
     워치 타깃의 `WKCompanionAppBundleIdentifier`도 아이폰 번들 ID와 같게 맞춥니다.
3. `ShootingCoach` 스킴 → 본인 iPhone 선택 → 실행. 워치 앱은 의존성으로 함께 빌드·설치됩니다.
   - 워치에 자동 설치되지 않으면 iPhone의 Watch 앱 → 일반 → 앱 설치에서 수동 설치.

## 사용법

1. **거치**: 삼각대 등으로 iPhone을 가로로 고정하고, 코트 **측면**에서 슈터와 골대가 한 화면에 들어오게 합니다. (분석 중 카메라가 흔들리면 궤적 인식이 어려워집니다)
2. **림 지정**: `림 위치` 버튼을 눌러 노란 박스를 골대 림(고리)에 맞춥니다. 박스 드래그로 이동, 오른쪽 아래 핸들로 크기 조절. 위치는 자동 저장됩니다.
3. **세션 시작**: 초록 버튼을 누르면 분석이 시작됩니다. 슛이 끝날 때마다:
   - iPhone 화면: 궤적 오버레이 + 판정 배너
   - Apple Watch: 진동 + 결과/팁 (예: `짧았어요 — 무릎 반동으로 파워를 더!`)
4. **세션 종료**: 통계 요약이 표시되고, 녹화를 켜두었다면 영상이 사진 앱에 저장됩니다.

> 녹화(⏺ 버튼)는 세션 시작 **전에** 켜야 합니다.

## 판정 로직과 한계

- **성공 판정**은 휴리스틱입니다: 궤적이 하강하며 림 평면을 통과한 지점이 림 박스 안이면 성공으로 봅니다. 림을 한참 맞고 튀어나가는 공(림아웃)은 성공으로 잘못 판정될 수 있습니다.
- 튕긴 공·리바운드가 다시 만드는 포물선은 쿨다운(기본 1초)과 "림 근처에서 시작한 궤적 제외" 규칙으로 걸러냅니다.
- 측면 촬영을 가정하므로 좌/우로 빠진 미스는 구분하지 못하고 짧음/김만 구분합니다.
- 여러 명이 동시에 슛하는 코트, 심한 역광·야간 조명에서는 정확도가 떨어집니다.

## 튜닝 포인트

감지 민감도는 전부 `ShootingCoach/AnalyzerConfig.swift`에 모여 있습니다.

| 상황 | 조정 |
|---|---|
| 슛을 못 잡음 | `trajectoryLength` ↓ (예: 8), `minTrajectoryConfidence` ↓ |
| 오탐(드리블·패스가 잡힘) | `minHorizontalSpan` ↑, `rimApproachMaxDX` ↓ |
| 공이 작게 찍힘 (먼 거리) | `minBallRadius` ↓ |
| 연사 슛 훈련 (빠른 템포) | `attemptCooldown` ↓ |
| 구형 기기 발열 | `frameAnalysisSpacing`을 1/30초로, `poseFrameInterval` ↑ |

## 프로젝트 구조

```
ShootingCoach.xcodeproj      # iOS 앱 + 워치 앱 (Xcode 16 폴더 동기화 형식)
Shared/                      # 두 타깃이 공유하는 모델 (ShotFeedback, 통계, 메시지 인코딩)
ShootingCoach/               # iOS 앱
  CameraService.swift        #   1080p60 캡처 세션
  ShotAnalyzer.swift         #   궤적 추적·슛 판정 상태 머신 (핵심)
  PoseSampler.swift          #   관절 각도 롤링 버퍼
  FeedbackEngine.swift       #   판정+자세 → 코칭 문구
  WatchBridge.swift          #   워치로 전송 (WCSession)
  SessionRecorder.swift      #   세션 녹화 → 사진 앱
  SessionViewModel.swift     #   상태 관리 허브
  Views/                     #   프리뷰·궤적 오버레이·림 편집기·HUD
ShootingCoachWatch/          # watchOS 앱 (피드백 수신 + 햅틱)
```

## 로드맵 아이디어

- Core ML 모델로 림 자동 인식 (수동 박스 제거)
- 골대 뒤 촬영 모드에서 좌/우 미스 구분
- 슛 순간 전후 클립만 잘라 하이라이트 저장
- 세션 히스토리 저장 & 추세 그래프, 워치 단독 요약 화면
