# 프로파일링 실전

Unreal Insights, GPU 프로파일러, 벤치마킹 방법론을 분석합니다.

---

## 프로파일링 개요

```
┌─────────────────────────────────────────────────────────────────┐
│                   Profiling Overview                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  프로파일링 워크플로우:                                         │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                          │   │
│  │  1. 재현 가능한 시나리오 설정                            │   │
│  │     └─► 벤치마크 레벨, 고정 카메라 경로                  │   │
│  │                                                          │   │
│  │  2. 베이스라인 측정                                      │   │
│  │     └─► 최적화 전 성능 기록                              │   │
│  │                                                          │   │
│  │  3. 병목 식별                                            │   │
│  │     └─► CPU? GPU? Memory? I/O?                          │   │
│  │                                                          │   │
│  │  4. 상세 분석                                            │   │
│  │     └─► 어떤 시스템/패스가 문제인가?                    │   │
│  │                                                          │   │
│  │  5. 최적화 적용                                          │   │
│  │     └─► 한 번에 하나씩 변경                              │   │
│  │                                                          │   │
│  │  6. 결과 검증                                            │   │
│  │     └─► 개선 확인, 회귀 테스트                          │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## Unreal Insights

```
┌─────────────────────────────────────────────────────────────────┐
│                    Unreal Insights                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Unreal Insights = 통합 프로파일링 도구                         │
│                                                                 │
│  실행 방법:                                                     │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  1. 게임 실행 시 트레이스 활성화:                        │   │
│  │     -trace=cpu,gpu,frame,bookmark,log                    │   │
│  │                                                          │   │
│  │  2. .utrace 파일 생성됨                                  │   │
│  │     Saved/Profiling/                                     │   │
│  │                                                          │   │
│  │  3. UnrealInsights.exe로 분석                            │   │
│  │     Engine/Binaries/Win64/UnrealInsights.exe             │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  채널:                                                          │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  cpu       - CPU 타이밍                                  │   │
│  │  gpu       - GPU 타이밍                                  │   │
│  │  frame     - 프레임 타이밍                               │   │
│  │  bookmark  - 사용자 마커                                 │   │
│  │  log       - 로그 메시지                                 │   │
│  │  memory    - 메모리 할당                                 │   │
│  │  loadtime  - 로딩 시간                                   │   │
│  │  file      - 파일 I/O                                    │   │
│  │  net       - 네트워크                                    │   │
│  │  asset     - 에셋 로딩                                   │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Insights 사용법

```cpp
// 커스텀 트레이스 이벤트 추가
TRACE_CPUPROFILER_EVENT_SCOPE(MyCustomEvent);

// 또는 매크로 사용
{
    QUICK_SCOPE_CYCLE_COUNTER(STAT_MyFunction);
    // 측정할 코드
}

// 북마크 추가 (타임라인에 마커)
TRACE_BOOKMARK(TEXT("Level Loaded"));

// 카운터 트레이스
TRACE_COUNTER(MyCategory, MyCounter, Value);

// 실행 예시
// UnrealEditor.exe MyProject -game -trace=default,memory -statnamedevents

// 라이브 연결 (실시간 분석)
// UnrealEditor.exe MyProject -game -tracehost=localhost
// 그 후 UnrealInsights.exe에서 Live Connection
```

---

## GPU 프로파일러

```
┌─────────────────────────────────────────────────────────────────┐
│                    GPU Profiler                                 │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  내장 GPU 프로파일러:                                           │
│  콘솔 명령: ProfileGPU 또는 Ctrl+Shift+,                        │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  GPU Profile Results:                                    │   │
│  │  ─────────────────────────────────────────────────────  │   │
│  │  Frame               14.2 ms                             │   │
│  │  ├─ PrePass          1.2 ms                              │   │
│  │  ├─ BasePass         3.4 ms                              │   │
│  │  │  ├─ Opaque        2.8 ms                              │   │
│  │  │  └─ Masked        0.6 ms                              │   │
│  │  ├─ ShadowDepths     2.1 ms                              │   │
│  │  ├─ Lighting         4.2 ms                              │   │
│  │  │  ├─ DirectLighting 2.4 ms                             │   │
│  │  │  └─ IndirectLighting 1.8 ms                           │   │
│  │  ├─ PostProcessing   2.5 ms                              │   │
│  │  └─ Translucency     0.8 ms                              │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  분석 포인트:                                                   │
│  • 가장 오래 걸리는 패스 식별                                   │
│  • 예상보다 오래 걸리는 패스 확인                               │
│  • 불필요한 패스 제거 가능 여부 검토                            │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### GPU 프로파일링 상세

```cpp
// GPU 프로파일러 활성화
IConsoleManager::Get().FindConsoleVariable(TEXT("r.GPUStatsEnabled"))->Set(1);

// 프로파일 캡처
void CaptureGPUProfile()
{
    // 한 프레임 캡처
    GEngine->Exec(GetWorld(), TEXT("ProfileGPU"));

    // 또는 여러 프레임 캡처
    GEngine->Exec(GetWorld(), TEXT("ProfileGPU 10"));  // 10 프레임
}

// stat 명령어
// stat gpu         - GPU 타이밍 개요
// stat gpustats    - 상세 GPU 통계
// stat drawcount   - 드로우콜 수

// RenderDoc 통합 (상세 GPU 분석)
// 플러그인 활성화: Edit → Plugins → RenderDoc
// 캡처: RenderDoc.CaptureFrame 또는 단축키
#if WITH_EDITOR
void CaptureRenderDoc()
{
    IRenderDocPlugin* RenderDocPlugin =
        FModuleManager::GetModulePtr<IRenderDocPlugin>("RenderDoc");
    if (RenderDocPlugin)
    {
        RenderDocPlugin->CaptureFrame();
    }
}
#endif
```

---

## Stat 명령어 시스템

```
┌─────────────────────────────────────────────────────────────────┐
│                    Stat Commands                                │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  핵심 Stat 명령어:                                              │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  기본 성능:                                              │   │
│  │  stat fps              프레임레이트                      │   │
│  │  stat unit             GT/RT/GPU 시간                    │   │
│  │  stat unitgraph        그래프로 표시                     │   │
│  │                                                          │   │
│  │  렌더링:                                                 │   │
│  │  stat gpu              GPU 패스별 시간                   │   │
│  │  stat scenerendering   씬 렌더링 상세                    │   │
│  │  stat initviews        가시성 계산                       │   │
│  │  stat lightrendering   라이팅 렌더링                     │   │
│  │                                                          │   │
│  │  게임플레이:                                             │   │
│  │  stat game             게임 스레드 상세                  │   │
│  │  stat anim             애니메이션                        │   │
│  │  stat physics          물리                              │   │
│  │  stat ai               AI                                │   │
│  │                                                          │   │
│  │  메모리:                                                 │   │
│  │  stat memory           메모리 개요                       │   │
│  │  stat memoryplatform   플랫폼별 메모리                   │   │
│  │  stat streaming        스트리밍 메모리                   │   │
│  │                                                          │   │
│  │  기타:                                                   │   │
│  │  stat rhi              RHI 통계                          │   │
│  │  stat threading        스레드 사용량                     │   │
│  │  stat particles        파티클 통계                       │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 커스텀 Stat 추가

```cpp
// 커스텀 Stat 그룹 정의
DECLARE_STATS_GROUP(TEXT("MyGame"), STATGROUP_MyGame, STATCAT_Advanced);

// Cycle Counter (시간 측정)
DECLARE_CYCLE_STAT(TEXT("MyExpensiveFunction"), STAT_MyExpensiveFunction, STATGROUP_MyGame);

void MyExpensiveFunction()
{
    SCOPE_CYCLE_COUNTER(STAT_MyExpensiveFunction);

    // 측정할 코드
    DoExpensiveWork();
}

// Memory Counter
DECLARE_MEMORY_STAT(TEXT("MySystem Memory"), STAT_MySystemMemory, STATGROUP_MyGame);

void AllocateMemory(int32 Size)
{
    INC_MEMORY_STAT_BY(STAT_MySystemMemory, Size);
    // 할당
}

void FreeMemory(int32 Size)
{
    DEC_MEMORY_STAT_BY(STAT_MySystemMemory, Size);
    // 해제
}

// Counter (횟수 측정)
DECLARE_DWORD_COUNTER_STAT(TEXT("Enemies Spawned"), STAT_EnemiesSpawned, STATGROUP_MyGame);

void SpawnEnemy()
{
    INC_DWORD_STAT(STAT_EnemiesSpawned);
    // 스폰
}
```

---

## 벤치마킹 방법론

```
┌─────────────────────────────────────────────────────────────────┐
│                  Benchmarking Methodology                       │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  재현 가능한 벤치마크 설정:                                     │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  1. 벤치마크 레벨 생성                                   │   │
│  │     • 대표적인 게임플레이 시나리오                       │   │
│  │     • 최악의 경우 (worst case) 시나리오                  │   │
│  │                                                          │   │
│  │  2. 카메라 경로 녹화                                     │   │
│  │     • Matinee/Sequencer로 고정 경로                     │   │
│  │     • 동일한 뷰 조건 보장                               │   │
│  │                                                          │   │
│  │  3. 일관된 테스트 환경                                   │   │
│  │     • 동일 하드웨어                                      │   │
│  │     • 동일 빌드 구성 (Development/Shipping)             │   │
│  │     • 동일 해상도/설정                                   │   │
│  │                                                          │   │
│  │  4. 여러 번 실행                                         │   │
│  │     • 최소 3회 실행 후 평균                             │   │
│  │     • 워밍업 실행 무시                                   │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 자동화된 벤치마크

```cpp
// 벤치마크 시스템
class FBenchmarkRunner
{
public:
    void RunBenchmark(const FString& BenchmarkName)
    {
        // 워밍업
        RunWarmup();

        // 측정
        TArray<FBenchmarkResult> Results;
        for (int32 i = 0; i < NumRuns; ++i)
        {
            FBenchmarkResult Result = RunSingleBenchmark();
            Results.Add(Result);
        }

        // 결과 분석
        AnalyzeResults(Results);

        // 리포트 생성
        GenerateReport(BenchmarkName, Results);
    }

private:
    FBenchmarkResult RunSingleBenchmark()
    {
        FBenchmarkResult Result;

        // 프레임 타임 수집
        TArray<float> FrameTimes;

        float StartTime = FPlatformTime::Seconds();

        while (FPlatformTime::Seconds() - StartTime < BenchmarkDuration)
        {
            float FrameTime = FApp::GetDeltaTime() * 1000.0f;
            FrameTimes.Add(FrameTime);
        }

        // 통계 계산
        Result.AverageFrameTime = CalculateAverage(FrameTimes);
        Result.MedianFrameTime = CalculateMedian(FrameTimes);
        Result.P99FrameTime = CalculatePercentile(FrameTimes, 99);
        Result.MinFrameTime = FrameTimes.Min();
        Result.MaxFrameTime = FrameTimes.Max();

        return Result;
    }

    float BenchmarkDuration = 30.0f;
    int32 NumRuns = 3;
};

// 콘솔 명령으로 벤치마크 실행
// FPS 차트 캡처
// StartFPSChart / StopFPSChart
void CaptureFPSChart()
{
    GEngine->Exec(GetWorld(), TEXT("StartFPSChart"));

    // 일정 시간 후
    FTimerHandle Handle;
    GetWorld()->GetTimerManager().SetTimer(Handle, []()
    {
        GEngine->Exec(GWorld, TEXT("StopFPSChart"));
    }, 30.0f, false);
}
```

---

## 성능 회귀 방지

```
┌─────────────────────────────────────────────────────────────────┐
│               Performance Regression Prevention                 │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  CI/CD 파이프라인 통합:                                         │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                          │   │
│  │  Code Commit                                             │   │
│  │       │                                                  │   │
│  │       ▼                                                  │   │
│  │  Automated Build                                         │   │
│  │       │                                                  │   │
│  │       ▼                                                  │   │
│  │  Performance Tests                                       │   │
│  │       │                                                  │   │
│  │       ├── Pass → Merge                                   │   │
│  │       │                                                  │   │
│  │       └── Fail → Alert → Review                          │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  성능 예산 설정:                                                │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Metric              Budget        Alert Threshold       │   │
│  │  ───────────────────────────────────────────────────    │   │
│  │  Frame Time          16.67ms       18ms (+10%)           │   │
│  │  Draw Calls          2000          2200 (+10%)           │   │
│  │  Triangle Count      2M            2.5M (+25%)           │   │
│  │  Texture Memory      2GB           2.2GB (+10%)          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 성능 모니터링 시스템

```cpp
// 성능 모니터 클래스
class FPerformanceMonitor
{
public:
    void CheckPerformanceBudgets()
    {
        // 프레임 타임 체크
        float CurrentFrameTime = FApp::GetDeltaTime() * 1000.0f;
        if (CurrentFrameTime > FrameTimeBudget * AlertThreshold)
        {
            OnBudgetExceeded(TEXT("FrameTime"), CurrentFrameTime, FrameTimeBudget);
        }

        // 드로우콜 체크
        int32 DrawCalls = GNumDrawCallsRHI;
        if (DrawCalls > DrawCallBudget * AlertThreshold)
        {
            OnBudgetExceeded(TEXT("DrawCalls"), DrawCalls, DrawCallBudget);
        }

        // 트라이앵글 체크
        int64 Triangles = GNumPrimitivesDrawnRHI;
        if (Triangles > TriangleBudget * AlertThreshold)
        {
            OnBudgetExceeded(TEXT("Triangles"), Triangles, TriangleBudget);
        }
    }

private:
    void OnBudgetExceeded(const TCHAR* MetricName, double Current, double Budget)
    {
        UE_LOG(LogPerf, Warning,
            TEXT("Performance budget exceeded: %s = %.2f (Budget: %.2f)"),
            MetricName, Current, Budget);

        // 알림 시스템 (Slack, Email 등)
        SendAlert(MetricName, Current, Budget);
    }

    float FrameTimeBudget = 16.67f;
    int32 DrawCallBudget = 2000;
    int64 TriangleBudget = 2000000;
    float AlertThreshold = 1.1f;  // +10%
};
```

---

## 주요 도구 요약

| 도구 | 용도 | 실행 방법 |
|------|------|----------|
| Unreal Insights | 종합 프로파일링 | -trace=default |
| ProfileGPU | GPU 패스 분석 | Ctrl+Shift+, |
| stat unit | 스레드 시간 | 콘솔 명령 |
| stat gpu | GPU 시간 | 콘솔 명령 |
| RenderDoc | GPU 디버깅 | 플러그인 |
| FPS Chart | 프레임레이트 기록 | StartFPSChart |

---

## 참고 자료

- [Unreal Insights](https://docs.unrealengine.com/unreal-insights/)
- [GPU Profiling](https://docs.unrealengine.com/gpu-profiling/)
- [Performance Guidelines](https://docs.unrealengine.com/performance-guidelines/)
