# Movie Render Queue

UE의 고품질 오프라인 렌더링 시스템인 Movie Render Queue를 분석합니다.

---

## MRQ 개요

### 아키텍처

```
┌─────────────────────────────────────────────────────────────────┐
│                  Movie Render Queue 구조                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                    MRQ Pipeline                          │   │
│  │                                                          │   │
│  │  ┌───────────┐    ┌───────────┐    ┌───────────┐        │   │
│  │  │  Sequence │ -> │   Jobs    │ -> │  Output   │        │   │
│  │  │  (입력)   │    │  (설정)   │    │  (결과)   │        │   │
│  │  └───────────┘    └───────────┘    └───────────┘        │   │
│  │                                                          │   │
│  │  Jobs 구성:                                              │   │
│  │  ┌─────────────────────────────────────────────────┐    │   │
│  │  │                                                  │    │   │
│  │  │  ┌──────────────┐                               │    │   │
│  │  │  │ Output       │  • Resolution                 │    │   │
│  │  │  │ Settings     │  • Frame Rate                 │    │   │
│  │  │  │              │  • File Format                │    │   │
│  │  │  └──────────────┘                               │    │   │
│  │  │                                                  │    │   │
│  │  │  ┌──────────────┐                               │    │   │
│  │  │  │ Render       │  • Anti-Aliasing              │    │   │
│  │  │  │ Settings     │  • Motion Blur                │    │   │
│  │  │  │              │  • Path Tracing               │    │   │
│  │  │  └──────────────┘                               │    │   │
│  │  │                                                  │    │   │
│  │  │  ┌──────────────┐                               │    │   │
│  │  │  │ Export       │  • Image Sequence             │    │   │
│  │  │  │ Settings     │  • Video Codec                │    │   │
│  │  │  │              │  • AOV Passes                 │    │   │
│  │  │  └──────────────┘                               │    │   │
│  │  │                                                  │    │   │
│  │  └─────────────────────────────────────────────────┘    │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 기본 설정

### MRQ 잡 생성

```cpp
// MRQ 접근
// Window → Cinematics → Movie Render Queue

// 블루프린트/C++ 접근
#include "MovieRenderPipelineCore.h"
#include "MoviePipelineQueue.h"

void CreateMRQJob()
{
    // 큐 생성
    UMoviePipelineQueue* Queue = NewObject<UMoviePipelineQueue>();

    // 잡 추가
    UMoviePipelineExecutorJob* Job = Queue->AllocateNewJob();

    // 시퀀스 할당
    Job->Sequence = LevelSequence;
    Job->Map = MapToRender;

    // 설정 할당
    Job->SetConfiguration(MasterConfig);
}

// 설정 옵션
UPROPERTY(EditAnywhere, Category = "Output")
FMoviePipelineOutputSetting OutputSetting
{
    FIntPoint OutputResolution = FIntPoint(3840, 2160);  // 4K
    FFrameRate OutputFrameRate = FFrameRate(24, 1);      // 24fps
    FString OutputDirectory = TEXT("{project}/Saved/MovieRenders/");
    FString FileNameFormat = TEXT("{sequence}_{frame}");
};
```

### 해상도 설정

```
┌─────────────────────────────────────────────────────────────────┐
│                    출력 해상도 옵션                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  표준 해상도:                                                    │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                          │   │
│  │  해상도         픽셀           용도                      │   │
│  │  ─────────────────────────────────────────────────────  │   │
│  │  HD (1080p)    1920×1080      웹, 스트리밍              │   │
│  │  2K            2048×1080      DCI 시네마                │   │
│  │  UHD (4K)      3840×2160      TV, 유튜브               │   │
│  │  4K DCI        4096×2160      시네마                    │   │
│  │  8K UHD        7680×4320      미래 대비                 │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  타일 렌더링 (고해상도):                                         │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                          │   │
│  │  ┌─────┬─────┬─────┐                                    │   │
│  │  │ T1  │ T2  │ T3  │                                    │   │
│  │  ├─────┼─────┼─────┤   8K 이상 렌더링 시               │   │
│  │  │ T4  │ T5  │ T6  │   GPU 메모리 제한 우회            │   │
│  │  ├─────┼─────┼─────┤                                    │   │
│  │  │ T7  │ T8  │ T9  │   r.ScreenPercentage 조합        │   │
│  │  └─────┴─────┴─────┘                                    │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 렌더 패스

### AOV (Arbitrary Output Variables)

```
┌─────────────────────────────────────────────────────────────────┐
│                    렌더 패스 / AOV                               │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  기본 패스:                                                      │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                          │   │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐      │   │
│  │  │   Beauty    │  │   Alpha     │  │   Depth     │      │   │
│  │  │  (Final)    │  │             │  │   (Z)       │      │   │
│  │  │  ████████   │  │  ░░████░░   │  │  ▒▓▓▓▓▓▒   │      │   │
│  │  └─────────────┘  └─────────────┘  └─────────────┘      │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  지오메트리 패스:                                                │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                          │   │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐      │   │
│  │  │  World      │  │   Normal    │  │  Object ID  │      │   │
│  │  │  Position   │  │             │  │             │      │   │
│  │  │  RGB=XYZ    │  │  RGB=NxNyNz │  │  색상=ID    │      │   │
│  │  └─────────────┘  └─────────────┘  └─────────────┘      │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  머티리얼 패스:                                                  │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                          │   │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐      │   │
│  │  │   Albedo    │  │  Roughness  │  │  Metallic   │      │   │
│  │  │  (Diffuse)  │  │             │  │             │      │   │
│  │  │  베이스컬러 │  │  러프니스   │  │  메탈릭     │      │   │
│  │  └─────────────┘  └─────────────┘  └─────────────┘      │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  라이팅 패스:                                                    │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                          │   │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐      │   │
│  │  │  Diffuse    │  │  Specular   │  │    AO       │      │   │
│  │  │  Lighting   │  │  Lighting   │  │             │      │   │
│  │  │  확산 조명  │  │  스페큘러   │  │  앰비언트   │      │   │
│  │  └─────────────┘  └─────────────┘  └─────────────┘      │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 패스 설정

```cpp
// Deferred Rendering 패스 설정
UPROPERTY(EditAnywhere)
class UMoviePipelineDeferredPassBase
{
    // 출력할 패스 선택
    bool bAccumulatorIncludesAlpha = true;

    // G-Buffer 패스
    TArray<FString> AdditionalPasses = {
        TEXT("WorldNormal"),
        TEXT("BaseColor"),
        TEXT("Roughness"),
        TEXT("Metallic"),
        TEXT("AmbientOcclusion"),
        TEXT("ObjectId"),
        TEXT("MaterialId")
    };
};

// 커스텀 스텐실 패스
UPROPERTY(EditAnywhere)
struct FMoviePipelineStencilPass
{
    // 스텐실 레이어 이름
    FString LayerName;

    // 포함할 액터 태그
    TArray<FName> IncludeTags;

    // 제외할 액터 태그
    TArray<FName> ExcludeTags;
};
```

---

## 안티앨리어싱

### 고품질 AA

```
┌─────────────────────────────────────────────────────────────────┐
│                  MRQ Anti-Aliasing 옵션                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Spatial Sample Count:                                          │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                          │   │
│  │  1 Sample        4 Samples       16 Samples             │   │
│  │    ●               ●●              ●●●●                 │   │
│  │                    ●●              ●●●●                 │   │
│  │                                    ●●●●                 │   │
│  │                                    ●●●●                 │   │
│  │                                                          │   │
│  │  앨리어싱        약간 개선        거의 완벽             │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  Temporal Sample Count:                                         │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                          │   │
│  │  프레임 간 누적 (TAA 강화)                               │   │
│  │                                                          │   │
│  │  Frame N:    ○──────────────────○                       │   │
│  │              ↓ 누적             ↓                       │   │
│  │  Frame N+1:  ●──────────────────●                       │   │
│  │                                                          │   │
│  │  더 많은 샘플 = 더 높은 품질 + 더 긴 렌더 시간          │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  권장 설정:                                                      │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                          │   │
│  │  용도              Spatial    Temporal    총 샘플       │   │
│  │  ─────────────────────────────────────────────────────  │   │
│  │  프리뷰            1          1           1             │   │
│  │  중간 품질         4          4           16            │   │
│  │  고품질            8          8           64            │   │
│  │  최고 품질         16         16          256           │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 출력 포맷

### 이미지 시퀀스

```cpp
// 이미지 출력 설정
UPROPERTY(EditAnywhere)
struct FMoviePipelineImageOutputSettings
{
    // 파일 포맷
    EImageFormat Format = EImageFormat::EXR;  // PNG, JPEG, EXR, BMP

    // EXR 설정
    EOpenEXRCompressionFormat Compression = EOpenEXRCompressionFormat::PIZ;
    bool bMultiLayerEXR = true;  // 모든 패스를 하나의 EXR로

    // 비트 깊이
    EImageBitDepth BitDepth = EImageBitDepth::Float16;  // 8, 16, Float16, Float32

    // 색공간
    EColorSpace ColorSpace = EColorSpace::Linear;  // sRGB, Linear, ACEScg
};
```

### 비디오 출력

```cpp
// 비디오 코덱 설정
UPROPERTY(EditAnywhere)
struct FMoviePipelineVideoOutputSettings
{
    // 코덱 선택
    EVideoCodec Codec = EVideoCodec::ProRes;

    // ProRes 변형
    EProResVariant ProResVariant = EProResVariant::ProRes4444;
    // ProRes422, ProRes422HQ, ProRes4444, ProRes4444XQ

    // H.264/H.265
    int32 VideoBitrate = 50000000;  // 50 Mbps
    EH264Profile H264Profile = EH264Profile::High;

    // 오디오
    bool bIncludeAudio = true;
    EAudioCodec AudioCodec = EAudioCodec::AAC;
};
```

---

## 고급 설정

### 콘솔 변수 오버라이드

```cpp
// MRQ용 콘솔 변수 설정
UPROPERTY(EditAnywhere)
struct FMoviePipelineConsoleVariables
{
    // 렌더링 품질
    TMap<FString, FString> CVars = {
        {TEXT("r.ScreenPercentage"), TEXT("200")},
        {TEXT("r.MotionBlurQuality"), TEXT("4")},
        {TEXT("r.DOF.Gather.AccumulatorQuality"), TEXT("1")},
        {TEXT("r.Shadow.MaxCSMResolution"), TEXT("4096")},
        {TEXT("r.AmbientOcclusion.Levels"), TEXT("3")},
        {TEXT("r.SSR.Quality"), TEXT("4")},
        {TEXT("r.SSS.Quality"), TEXT("1")}
    };
};

// 게임 오버라이드
UPROPERTY(EditAnywhere)
struct FMoviePipelineGameOverrides
{
    // 시네마틱 품질 프리셋
    bool bCinematicMode = true;

    // 텍스처 스트리밍 완료 대기
    bool bFlushStreamingOnStartFrame = true;

    // LOD 고정
    int32 ForceLOD = 0;  // 최고 LOD

    // 컬링 비활성화
    bool bDisableDistanceCulling = true;
};
```

---

## 배치 렌더링

### 다중 잡 처리

```cpp
// 큐에 여러 잡 추가
void SetupBatchRender()
{
    UMoviePipelineQueue* Queue = GetQueue();

    // 여러 시퀀스/설정 조합
    for (const FRenderSetup& Setup : RenderSetups)
    {
        UMoviePipelineExecutorJob* Job = Queue->AllocateNewJob();
        Job->Sequence = Setup.Sequence;
        Job->Map = Setup.Map;
        Job->SetConfiguration(Setup.Config);
    }

    // 렌더 실행 (순차)
    UMoviePipelineLocalExecutor* Executor = NewObject<UMoviePipelineLocalExecutor>();
    Executor->Execute(Queue);
}

// 커맨드 라인 배치 렌더링
// UE5Editor.exe Project.uproject -game
//   -MoviePipelineConfig="/Game/Cinematics/RenderConfig.RenderConfig"
//   -LevelSequence="/Game/Cinematics/Sequence.Sequence"
//   -Map="/Game/Maps/MainLevel"
//   -MoviePipelineLocalExecutorClass=/Script/MovieRenderPipelineCore.MoviePipelineLocalExecutor
```

---

## 다음 단계

- [고품질 렌더링](03-high-quality-rendering.md)에서 세부 품질 설정을 학습합니다.
