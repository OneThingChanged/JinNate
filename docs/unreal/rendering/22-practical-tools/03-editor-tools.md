# 에디터 도구

프로파일러, Widget Reflector, Asset Audit 등 에디터 내장 도구를 분석합니다.

---

## 프로파일러

```
┌─────────────────────────────────────────────────────────────────┐
│                      Editor Profilers                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Session Frontend (Window → Developer Tools → Session Frontend):│
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                          │   │
│  │  ┌─────────────────────────────────────────────────┐    │   │
│  │  │ Profiler Tab                                     │    │   │
│  │  ├─────────────────────────────────────────────────┤    │   │
│  │  │ • CPU 프로파일링                                 │    │   │
│  │  │ • 함수별 시간 측정                               │    │   │
│  │  │ • 콜 그래프                                      │    │   │
│  │  │ • 프레임 분석                                    │    │   │
│  │  └─────────────────────────────────────────────────┘    │   │
│  │                                                          │   │
│  │  ┌─────────────────────────────────────────────────┐    │   │
│  │  │ Console Tab                                      │    │   │
│  │  ├─────────────────────────────────────────────────┤    │   │
│  │  │ • 원격 콘솔 명령                                 │    │   │
│  │  │ • 로그 뷰어                                      │    │   │
│  │  └─────────────────────────────────────────────────┘    │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  GPU Visualizer (ProfileGPU):                                   │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ • 렌더링 패스별 GPU 시간                                │   │
│  │ • 계층적 타이밍 표시                                    │   │
│  │ • 병목 지점 식별                                        │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 프로파일러 사용

```cpp
// 세션 프론트엔드 프로파일러 사용
// 1. Window → Developer Tools → Session Frontend
// 2. 프로파일러 탭 선택
// 3. 데이터 캡처 시작

// 프로파일 데이터 캡처 (콘솔)
stat startfile          // 캡처 시작
// ... 게임 플레이 ...
stat stopfile           // 캡처 종료
// Saved/Profiling/*.ue4stats 파일 생성됨

// 프로파일러에서 파일 로드
// Session Frontend → Profiler → Load → 파일 선택

// GPU 프로파일러 사용
ProfileGPU              // 한 프레임 캡처
// 또는 Ctrl+Shift+,

// 커스텀 프로파일 마커
DECLARE_CYCLE_STAT(TEXT("My Custom Stat"), STAT_MyCustomStat, STATGROUP_Game);

void MyFunction()
{
    SCOPE_CYCLE_COUNTER(STAT_MyCustomStat);
    // 측정할 코드
}
```

---

## Widget Reflector

```
┌─────────────────────────────────────────────────────────────────┐
│                    Widget Reflector                             │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  위치: Window → Developer Tools → Widget Reflector              │
│                                                                 │
│  기능:                                                          │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                          │   │
│  │  Live Widget Picker:                                     │   │
│  │  ┌──────────────────────────────────────────────────┐   │   │
│  │  │ 화면에서 위젯 클릭 → 계층 구조에서 하이라이트    │   │   │
│  │  └──────────────────────────────────────────────────┘   │   │
│  │                                                          │   │
│  │  Widget Hierarchy:                                       │   │
│  │  ┌──────────────────────────────────────────────────┐   │   │
│  │  │ SWindow                                           │   │   │
│  │  │ └─ SOverlay                                       │   │   │
│  │  │    └─ SVerticalBox                                │   │   │
│  │  │       ├─ STextBlock                               │   │   │
│  │  │       └─ SButton                                  │   │   │
│  │  │          └─ STextBlock                            │   │   │
│  │  └──────────────────────────────────────────────────┘   │   │
│  │                                                          │   │
│  │  Widget Details:                                         │   │
│  │  ┌──────────────────────────────────────────────────┐   │   │
│  │  │ • 타입: SButton                                   │   │   │
│  │  │ • 가시성: Visible                                 │   │   │
│  │  │ • 크기: 200x50                                    │   │   │
│  │  │ • 클리핑: Yes                                     │   │   │
│  │  │ • 포커스: None                                    │   │   │
│  │  └──────────────────────────────────────────────────┘   │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Widget Reflector 활용

```cpp
// Widget Reflector 열기
// 콘솔: WidgetReflector
// 또는 메뉴: Window → Developer Tools → Widget Reflector

// 기능:
// 1. Pick Widget (Ctrl+Shift+마우스 이동)
//    - 마우스 아래 위젯 하이라이트
//    - 클릭하면 계층에서 선택

// 2. Focus를 따라가기
//    - 키보드 포커스 위젯 추적

// 3. Hit Test 시각화
//    - 히트 테스트 영역 표시

// 4. Clipping 시각화
//    - 클리핑 영역 표시

// 5. Invalidation 디버깅
//    - 위젯 무효화 추적

// Slate 통계 확인
// 콘솔: Slate.Stats 1
// 표시 정보:
// - Num Widgets: 위젯 수
// - Num Batches: 배치 수
// - Vertices: 버텍스 수
```

---

## Asset Audit

```
┌─────────────────────────────────────────────────────────────────┐
│                      Asset Audit                                │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  위치: Window → Developer Tools → Asset Audit                   │
│                                                                 │
│  기능:                                                          │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                          │   │
│  │  Size Map:                                               │   │
│  │  ┌──────────────────────────────────────────────────┐   │   │
│  │  │ 에셋 크기를 트리맵으로 시각화                     │   │   │
│  │  │ ┌────────────────────┬──────────┐               │   │   │
│  │  │ │                    │          │               │   │   │
│  │  │ │   Textures         │  Meshes  │               │   │   │
│  │  │ │   (큰 영역)         │          │               │   │   │
│  │  │ │                    ├──────────┤               │   │   │
│  │  │ │                    │ Sounds   │               │   │   │
│  │  │ └────────────────────┴──────────┘               │   │   │
│  │  └──────────────────────────────────────────────────┘   │   │
│  │                                                          │   │
│  │  Audit 항목:                                             │   │
│  │  • 디스크 크기                                           │   │
│  │  • 메모리 크기                                           │   │
│  │  • 에셋 타입별 분류                                      │   │
│  │  • 참조 수                                               │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Asset Audit 사용

```cpp
// Asset Audit 열기
// Window → Developer Tools → Asset Audit

// 기능:
// 1. 폴더 선택하여 분석
// 2. Size Map 탭에서 크기 시각화
// 3. 큰 에셋 클릭하여 상세 정보 확인

// 콘솔에서 에셋 정보 확인
obj list class=Texture2D      // 모든 텍스처 나열
obj list class=StaticMesh     // 모든 스태틱 메시
obj list class=Material       // 모든 머티리얼

// 에셋 크기 리포트 생성
MemReport                      // 메모리 리포트
MemReport -Full               // 상세 리포트

// 참조 검색
// 콘텐츠 브라우저에서 에셋 우클릭
// → Reference Viewer
// → Size Map
```

---

## Reference Viewer

```
┌─────────────────────────────────────────────────────────────────┐
│                   Reference Viewer                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  에셋 우클릭 → Reference Viewer                                 │
│                                                                 │
│  그래프 표시:                                                   │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                          │   │
│  │  Referencers (이 에셋을 참조하는 것들)                   │   │
│  │       │                                                  │   │
│  │       ▼                                                  │   │
│  │  ┌─────────┐       ┌─────────┐       ┌─────────┐       │   │
│  │  │Level_01 │ ────► │MyActor  │ ────► │ Texture │       │   │
│  │  └─────────┘       └─────────┘       └─────────┘       │   │
│  │                          │                               │   │
│  │                          ▼                               │   │
│  │                    ┌─────────┐                          │   │
│  │                    │Material │                          │   │
│  │                    └─────────┘                          │   │
│  │                                                          │   │
│  │  Dependencies (이 에셋이 참조하는 것들)                  │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  옵션:                                                          │
│  • Search Depth: 검색 깊이                                      │
│  • Show Referencers: 참조자 표시                                │
│  • Show Dependencies: 의존성 표시                               │
│  • Show Soft References: 소프트 레퍼런스 포함                   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## Statistics 창

```
┌─────────────────────────────────────────────────────────────────┐
│                    Statistics Window                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  위치: Window → Statistics                                      │
│                                                                 │
│  표시 정보:                                                     │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                          │   │
│  │  Primitive Stats:                                        │   │
│  │  ├── Static Meshes: 1,234                               │   │
│  │  ├── Static Mesh Triangles: 5,678,901                   │   │
│  │  ├── Skeletal Meshes: 56                                │   │
│  │  └── Skeletal Mesh Triangles: 789,012                   │   │
│  │                                                          │   │
│  │  Lighting Stats:                                         │   │
│  │  ├── Point Lights: 45                                   │   │
│  │  ├── Spot Lights: 12                                    │   │
│  │  ├── Directional Lights: 1                              │   │
│  │  └── Lightmap Memory: 128 MB                            │   │
│  │                                                          │   │
│  │  Texture Stats:                                          │   │
│  │  ├── Textures: 890                                      │   │
│  │  └── Texture Memory: 512 MB                             │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 머티리얼 분석 도구

```
┌─────────────────────────────────────────────────────────────────┐
│                 Material Analysis Tools                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Material Editor Stats:                                         │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Window → Stats (머티리얼 에디터 내)                     │   │
│  │                                                          │   │
│  │  표시 정보:                                              │   │
│  │  • Base Pass Shader: 245 instructions                   │   │
│  │  • Texture Samples: 8                                    │   │
│  │  • Virtual Texture Samples: 2                           │   │
│  │  • Shader Permutations: 32                              │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  Platform Stats (우측 하단 드롭다운):                           │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  플랫폼별 셰이더 통계 확인                               │   │
│  │  • Windows (SM5)                                        │   │
│  │  • Android (ES3.1)                                      │   │
│  │  • iOS (Metal)                                          │   │
│  │  • PS5, XSX, Switch 등                                  │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 머티리얼 분석

```cpp
// 머티리얼 에디터에서 Stats 창 열기
// Window → Stats

// 표시되는 정보:
// - Compile errors/warnings
// - Instruction count (per shader type)
// - Texture samples
// - Shader complexity estimate

// 콘솔에서 머티리얼 정보
ListMaterials                  // 모든 머티리얼 나열
DumpMaterialStats             // 머티리얼 통계 덤프

// 셰이더 복잡도 디버그
r.ShaderComplexity.ShowCost=1
r.ShaderComplexity.Enabled=1

// 특정 머티리얼 인스펙션
// 머티리얼 에디터에서:
// - Live Preview 활성화
// - Stats 창에서 실시간 instruction count 확인
// - Platform Preview로 타겟 플랫폼 통계 확인
```

---

## Output Log 활용

```
┌─────────────────────────────────────────────────────────────────┐
│                     Output Log Tips                             │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  위치: Window → Developer Tools → Output Log                    │
│                                                                 │
│  필터링:                                                        │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Categories: LogTemp, LogShaders, LogRHI, LogRenderer   │   │
│  │  Verbosity: Error, Warning, Log, Verbose                │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  유용한 로그 카테고리:                                          │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  LogRenderer      렌더링 관련                            │   │
│  │  LogShaders       셰이더 컴파일                          │   │
│  │  LogRHI           RHI 레이어                             │   │
│  │  LogStreaming     스트리밍                               │   │
│  │  LogTexture       텍스처                                 │   │
│  │  LogMaterial      머티리얼                               │   │
│  │  LogSlate         UI                                     │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 로그 활용

```cpp
// 특정 카테고리 로그 레벨 설정
Log LogRenderer Verbose        // 상세 로그 활성화
Log LogRenderer Warning        // 경고 이상만

// 로그 파일 위치
// Saved/Logs/*.log

// 커스텀 로그 카테고리 생성
DECLARE_LOG_CATEGORY_EXTERN(LogMyGame, Log, All);
DEFINE_LOG_CATEGORY(LogMyGame);

// 사용
UE_LOG(LogMyGame, Log, TEXT("My message"));
UE_LOG(LogMyGame, Warning, TEXT("Warning: %s"), *WarningText);
UE_LOG(LogMyGame, Error, TEXT("Error occurred!"));

// 조건부 로그
UE_CLOG(bCondition, LogMyGame, Log, TEXT("Conditional log"));

// 화면에 메시지 출력
GEngine->AddOnScreenDebugMessage(-1, 5.0f, FColor::Yellow, TEXT("On screen"));
```

---

## 주요 에디터 도구 요약

| 도구 | 위치 | 용도 |
|------|------|------|
| Session Frontend | Window → Developer Tools | CPU 프로파일링 |
| Widget Reflector | Window → Developer Tools | UI 디버깅 |
| Asset Audit | Window → Developer Tools | 에셋 크기 분석 |
| Reference Viewer | 에셋 우클릭 | 참조 관계 분석 |
| Statistics | Window → Statistics | 레벨 통계 |
| Output Log | Window → Developer Tools | 로그 확인 |

---

## 참고 자료

- [Editor Tools](https://docs.unrealengine.com/editor-tools/)
- [Profiling Tools](https://docs.unrealengine.com/profiling/)
- [Asset Management](https://docs.unrealengine.com/asset-management/)
