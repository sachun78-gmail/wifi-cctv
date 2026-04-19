# CLAUDE.md

## 프로젝트 성격

- 이 프로젝트는 **Flutter 학습 목적**의 스터디 프로젝트다.
- 따라서 "동작하는 코드"뿐만 아니라 **왜 그렇게 작성했는지**를 이해할 수 있어야 한다.

## 모델별 작업 범위

- **Opus**: 직접 코딩하지 않는다. 설계 및 문서 업데이트만 수행한다.
- **Sonnet 4.6**: 분석 내용을 바탕으로 코딩하되, 코딩 진행 전에 반드시 사용자 확인을 받는다.

## 주석 작성 규칙 (학습 목적 전용)

일반적인 프로덕션 코드에서는 "주석은 최소화, WHY만 남긴다"가 원칙이지만,
**이 프로젝트는 학습이 우선 목표**이므로 아래 규칙을 따른다.

### 반드시 주석을 달아야 하는 경우
1. **Flutter/Dart 생소 개념**: `ConsumerStatefulWidget`, `StateNotifier`, `autoDispose`,
   `sealed class`, `switch expression`, `record`, pattern matching 등
   → 한두 줄로 "무엇이고 왜 쓰는지" 설명
2. **생명주기 메서드**: `initState`, `dispose`, `didChangeDependencies` 등
   → 언제 호출되고 왜 이 위치에 코드를 두는지
3. **비동기 처리**: `await` 이후 `mounted` / `context.mounted` 체크
   → 왜 필요한지 (위젯이 dispose 됐을 가능성)
4. **네이티브 리소스 관리**: `RTCVideoRenderer.initialize()`/`dispose()`,
   `MediaStream` 해제, `StreamSubscription.cancel()` 등
   → 누수가 나는 이유와 해제 시점
5. **Riverpod API 선택 이유**: `ref.watch` vs `ref.read` vs `ref.listen`
   → 각 호출 지점에서 왜 그것을 골랐는지
6. **플랫폼/라이브러리 제약**: `flutter_webrtc` 특이 사항, 권한 처리 타이밍 등

### 주석 스타일
- **한국어**로 작성한다 (학습자 모국어).
- **공식 문서 링크**는 불필요. 개념 설명 위주.
- 섹션 구분은 `// ── 섹션 이름 ──────────` 또는 `// ══ 큰 섹션 ══` 형태로 가독성 확보.
- dartdoc(`///`)은 public API와 클래스 선언부에 사용, 내부 구현은 `//`.
- Phase 4 `lib/views/camera_view.dart`의 주석 스타일을 기준으로 삼는다.

### 주의 사항
- 주석이 코드를 **반복 설명하는 것(WHAT)**은 지양한다. 학습자가 모를 만한 개념/이유(WHY)를 설명한다.
- 구현이 바뀌면 주석도 함께 업데이트한다 (stale 주석 금지).
- 테스트 코드에도 동일 규칙 적용: Fake 패턴 이유, `autoDispose` 유지 트릭 등은 주석으로 남긴다.
