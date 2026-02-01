# 메모리 최적화

렌더링 메모리 관리와 최적화 기법을 다룹니다. 텍스처 스트리밍, 메모리 풀링, LOD, 압축 전략을 포함합니다.

---

## 개요

GPU 메모리는 제한된 자원이며, 효율적인 관리가 성능과 안정성의 핵심입니다.

```
┌─────────────────────────────────────────────────────────────────┐
│                     GPU 메모리 구성                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │                    GPU 메모리 (VRAM)                       │  │
│  ├───────────────────────────────────────────────────────────┤  │
│  │                                                           │  │
│  │  ┌─────────────────────────────────────────────────────┐  │  │
│  │  │              텍스처 (40-60%)                         │  │  │
│  │  │  Albedo, Normal, Roughness, Lightmaps, UI          │  │  │
│  │  └─────────────────────────────────────────────────────┘  │  │
│  │                                                           │  │
│  │  ┌───────────────────────────────┐                       │  │
│  │  │    Render Targets (15-25%)    │                       │  │
│  │  │  G-Buffer, Shadow, PostFX    │                       │  │
│  │  └───────────────────────────────┘                       │  │
│  │                                                           │  │
│  │  ┌─────────────────────┐ ┌───────────────────────────┐   │  │
│  │  │  Buffers (10-20%)   │ │   기타 (5-10%)            │   │  │
│  │  │  Vertex, Index,     │ │   PSO, 쿼리, 기타        │   │  │
│  │  │  Constant, UAV      │ │                           │   │  │
│  │  └─────────────────────┘ └───────────────────────────┘   │  │
│  │                                                           │  │
│  └───────────────────────────────────────────────────────────┘  │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 메모리 분석

### LLM (Low-Level Memory) 추적

```cpp
// LLM 활성화
-LLM
-LLMCSV  // CSV 출력

// 런타임 확인
stat llm
stat llmfull
stat llmplatform

// 특정 태그 추적
LLM_SCOPE(ELLMTag::Textures);
LLM_SCOPE(ELLMTag::Meshes);
LLM_SCOPE(ELLMTag::Audio);
```

### 메모리 리포트

```cpp
// 메모리 리포트 생성
memreport -full

// 출력 예시:
// ----------------------------------------
// Obj List: class=Texture2D
// ----------------------------------------
// 1. T_Character_D (2048x2048, DXT5): 5.33 MB
// 2. T_Environment_N (4096x4096, BC5): 21.33 MB
// ...
// Total: 847 objects, 1.2 GB
```

### RHI 메모리 통계

```cpp
stat rhi

// 출력:
// Render target memory: 256 MB
// Texture memory: 1024 MB
// Buffer memory: 128 MB
// PSO memory: 32 MB
```

---

## 텍스처 최적화

### 텍스처 압축

```
┌─────────────────────────────────────────────────────────────────┐
│                    플랫폼별 압축 포맷                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  용도          │ PC/Console    │ Mobile (iOS)  │ Mobile (And) │
│  ──────────────┼───────────────┼───────────────┼────────────  │
│  Diffuse      │ BC1 (DXT1)    │ ASTC 6x6      │ ETC2          │
│  Diffuse+Alpha│ BC3 (DXT5)    │ ASTC 4x4      │ ETC2 RGBA     │
│  Normal       │ BC5           │ ASTC 4x4      │ ETC2 RG       │
│  Mask         │ BC4           │ ASTC 8x8      │ ETC2 R        │
│  HDR          │ BC6H          │ ASTC HDR      │ RGB9E5        │
│  High Quality │ BC7           │ ASTC 4x4      │ ETC2          │
│                                                                 │
│  ※ 압축률: BC1 = 8:1, BC3 = 4:1, BC7 = 4:1                    │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 텍스처 크기 관리

```cpp
// 텍스처 그룹별 최대 크기 설정
// DefaultEngine.ini

[SystemSettings]
; World 텍스처
TEXTUREGROUP_World=(MinLODSize=1,MaxLODSize=2048,LODBias=0)

; Character 텍스처
TEXTUREGROUP_Character=(MinLODSize=1,MaxLODSize=2048,LODBias=0)

; UI 텍스처 (압축 없음)
TEXTUREGROUP_UI=(MinLODSize=1,MaxLODSize=4096,LODBias=0)
```

### Never Stream 텍스처 관리

```cpp
// 항상 메모리에 로드되는 텍스처 확인
// Asset Audit로 NeverStream 텍스처 검색

// 필요한 경우만 NeverStream 설정
Texture->NeverStream = false;  // 스트리밍 허용

// NeverStream 필요한 경우:
// - UI 텍스처
// - 매우 작은 텍스처 (< 256)
// - 즉시 로드 필요한 텍스처
```

---

## 텍스처 스트리밍

### 스트리밍 시스템 설정

```cpp
// 스트리밍 풀 크기
r.Streaming.PoolSize 1000  // MB (GPU 메모리의 50-70% 권장)

// 스트리밍 우선순위
r.Streaming.DropMips 0      // MIP 드롭 허용
r.Streaming.LimitPoolSizeToVRAM 1  // VRAM 제한 준수

// 스트리밍 속도
r.Streaming.MaxNumTexturesToStreamPerFrame 4
r.Streaming.NumStaticComponentsProcessedPerFrame 50
```

### 스트리밍 전략

```
┌─────────────────────────────────────────────────────────────────┐
│                   텍스처 스트리밍 시스템                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │                    Streaming Pool                        │    │
│  │  ┌─────────────────────────────────────────────────┐    │    │
│  │  │ Resident Textures (현재 필요)                    │    │    │
│  │  │  - 카메라 근처 텍스처 (고해상도 MIP)            │    │    │
│  │  │  - 현재 보이는 오브젝트                          │    │    │
│  │  └─────────────────────────────────────────────────┘    │    │
│  │                                                          │    │
│  │  ┌─────────────────────────────────────────────────┐    │    │
│  │  │ Pending Stream-In (로드 대기)                    │    │    │
│  │  │  - 곧 필요할 텍스처                              │    │    │
│  │  │  - 우선순위 기반 로드                            │    │    │
│  │  └─────────────────────────────────────────────────┘    │    │
│  │                                                          │    │
│  │  ┌─────────────────────────────────────────────────┐    │    │
│  │  │ Stream-Out Candidates (제거 후보)                │    │    │
│  │  │  - 오래 사용 안 된 텍스처                        │    │    │
│  │  │  - 멀리 있는 오브젝트 텍스처                    │    │    │
│  │  └─────────────────────────────────────────────────┘    │    │
│  └─────────────────────────────────────────────────────────┘    │
│                                                                 │
│  우선순위 = 화면 크기 × 중요도 ÷ 거리²                         │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 스트리밍 디버깅

```cpp
// 스트리밍 시각화
r.Streaming.DropMips 1  // MIP 드롭 강제로 테스트

// 스트리밍 통계
stat streaming
stat streamingdetails

// 텍스처별 스트리밍 상태
ListStreamingTextures
```

---

## 버퍼 메모리 최적화

### 버텍스 버퍼 압축

```cpp
// 버텍스 포맷 최적화
// Position: float3 → half3 (가능한 경우)
// Normal: float3 → 10:10:10:2
// UV: float2 → half2

// UE의 자동 압축 사용
StaticMesh->bAllowCPUAccess = false;  // GPU 전용
StaticMesh->LODGroup = TEXT("LargeWorld");
```

### 인덱스 버퍼 최적화

```cpp
// 16비트 vs 32비트 인덱스
// 버텍스 < 65536 → 16비트 사용 (자동)

// 메시 설정에서 확인
StaticMesh->RenderData->LODResources[0].bHas32BitIndices;
```

### 인스턴스 버퍼 관리

```cpp
// 인스턴스 데이터 최소화
// 필수 데이터만 포함

// 기본: Transform (64 bytes) + Custom Data
struct FInstanceData
{
    FMatrix Transform;           // 64 bytes
    float CustomData[4];         // 16 bytes (필요시)
};

// 최적화: PerInstance Custom Data 최소화
HISM->NumCustomDataFloats = 0;  // 불필요시 0
```

---

## Render Target 관리

### Render Target Pool

```cpp
// 렌더 타겟 풀 사용
FPooledRenderTargetDesc Desc;
Desc.Extent = FIntPoint(1920, 1080);
Desc.Format = PF_FloatRGBA;
Desc.Flags = TexCreate_RenderTargetable | TexCreate_ShaderResource;
Desc.TargetableFlags = TexCreate_RenderTargetable;
Desc.ClearValue = FClearValueBinding::Black;

TRefCountPtr<IPooledRenderTarget> PooledRT;
GRenderTargetPool.FindFreeElement(
    RHICmdList, Desc, PooledRT, TEXT("MyTempRT"));

// 사용 후 자동 반환
```

### Transient 리소스 활용

```cpp
// 임시 리소스 (프레임 내에서만 유효)
// ESRAM/Tile Memory 활용 가능

FRDGTextureDesc Desc = FRDGTextureDesc::Create2D(
    Extent,
    PF_FloatRGBA,
    FClearValueBinding::Black,
    TexCreate_RenderTargetable | TexCreate_ShaderResource
);

// Transient 플래그로 메모리 절약
Desc.Flags |= TexCreate_Transient;

FRDGTextureRef Texture = GraphBuilder.CreateTexture(Desc, TEXT("TransientRT"));
```

```
┌─────────────────────────────────────────────────────────────────┐
│                   Render Target 생명주기                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Frame N:                                                       │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │ Pass A ────▶ RT1 ────▶ Pass B ────▶ RT2 ────▶ Pass C     │  │
│  │              │                      │                     │  │
│  │              ▼                      ▼                     │  │
│  │         [RT1 재사용 가능]      [RT2 재사용 가능]          │  │
│  └───────────────────────────────────────────────────────────┘  │
│                                                                 │
│  RDG가 자동으로:                                                │
│  - 수명 분석                                                    │
│  - 메모리 앨리어싱                                              │
│  - 최적의 타이밍에 할당/해제                                    │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### G-Buffer 메모리

```cpp
// G-Buffer 포맷 분석 (1080p 기준)
// SceneColor:  RGBA16F = 16 MB
// GBufferA:    RGBA8   =  8 MB (Normal)
// GBufferB:    RGBA8   =  8 MB (Metallic, Specular, Roughness)
// GBufferC:    RGBA8   =  8 MB (BaseColor)
// Depth:       D24S8   =  8 MB
// Velocity:    RG16F   =  8 MB (선택적)
// ─────────────────────────────
// 총합:                 56 MB+ (1080p)
//                      224 MB+ (4K)

// 최적화 옵션
r.GBufferFormat 0  // 기본 포맷 (가장 작음)
r.BasePassOutputsVelocity 0  // Velocity 비활성화
```

---

## LOD와 메모리

### 메시 LOD 메모리

```
┌─────────────────────────────────────────────────────────────────┐
│                      LOD 메모리 구조                             │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  메시: SM_Character                                             │
│                                                                 │
│  LOD   │ 삼각형  │ 버텍스  │ 메모리    │ 로드 조건             │
│  ──────┼─────────┼─────────┼───────────┼─────────────────────  │
│  LOD0  │ 50,000  │ 30,000  │ 2.4 MB    │ 항상 로드             │
│  LOD1  │ 20,000  │ 12,000  │ 0.96 MB   │ Screen < 0.5         │
│  LOD2  │  5,000  │  3,000  │ 0.24 MB   │ Screen < 0.25        │
│  LOD3  │  1,000  │    600  │ 0.05 MB   │ Screen < 0.1         │
│  ──────┴─────────┴─────────┴───────────┴─────────────────────  │
│  총합                        3.65 MB                            │
│                                                                 │
│  ※ 모든 LOD가 메모리에 로드됨 (LOD 스트리밍 미사용 시)         │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Proxy LOD / HLOD

```cpp
// HLOD로 원거리 메모리 절약
// 여러 메시 → 하나의 단순화된 메시

// HLOD 설정
// World Settings > World Partition > HLOD

// HLOD 레벨
// HLOD0: 중거리 (여러 액터 병합)
// HLOD1: 원거리 (더 단순화)
```

---

## 메모리 예산 관리

### 플랫폼별 예산

```
┌─────────────────────────────────────────────────────────────────┐
│                   플랫폼별 메모리 예산 예시                       │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  영역              │ PC High │ Console │ Mobile │              │
│  ──────────────────┼─────────┼─────────┼────────│              │
│  텍스처 스트리밍   │ 2 GB    │ 1.5 GB  │ 512 MB │              │
│  Render Targets    │ 512 MB  │ 400 MB  │ 128 MB │              │
│  메시 데이터       │ 512 MB  │ 400 MB  │ 128 MB │              │
│  셰이더/PSO        │ 256 MB  │ 200 MB  │  64 MB │              │
│  기타              │ 256 MB  │ 200 MB  │  64 MB │              │
│  ──────────────────┼─────────┼─────────┼────────│              │
│  총합              │ 3.5 GB  │ 2.7 GB  │ 896 MB │              │
│                                                                 │
│  ※ 실제 값은 프로젝트 요구사항에 따라 조정                     │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 메모리 경고 시스템

```cpp
// 메모리 워터마크 설정
FMemory::SetupTLSCachesOnCurrentThread();

// 커스텀 메모리 모니터링
void CheckMemoryBudget()
{
    FPlatformMemoryStats Stats = FPlatformMemory::GetStats();

    if (Stats.UsedVirtual > WarningThreshold)
    {
        UE_LOG(LogMemory, Warning,
            TEXT("Memory usage high: %lld MB"),
            Stats.UsedVirtual / (1024*1024));

        // 텍스처 품질 낮추기
        GEngine->Exec(nullptr, TEXT("r.Streaming.PoolSize 500"));
    }
}
```

---

## 메모리 누수 방지

### 일반적인 누수 패턴

```cpp
// 1. 텍스처 참조 누수
// BAD: 텍스처 로드 후 해제 안 함
UTexture2D* Texture = LoadObject<UTexture2D>(...);
// 사용 후 참조 유지됨

// GOOD: 명시적 해제 또는 약한 참조
TWeakObjectPtr<UTexture2D> WeakTexture = LoadObject<UTexture2D>(...);

// 2. Render Target 누수
// BAD: 매 프레임 생성
UTextureRenderTarget2D* RT = NewObject<UTextureRenderTarget2D>();

// GOOD: 재사용 또는 풀링
if (!CachedRT)
{
    CachedRT = NewObject<UTextureRenderTarget2D>();
}
```

### 메모리 누수 탐지

```cpp
// 메모리 리포트로 누수 확인
memreport -full

// 오브젝트 카운트 비교
obj list class=Texture2D

// GC 강제 실행 후 확인
obj gc
memreport -full
```

---

## 콘솔 명령 요약

```cpp
// 메모리 분석
stat memory
stat llm
stat rhi
memreport -full

// 텍스처 스트리밍
stat streaming
r.Streaming.PoolSize 1000
ListStreamingTextures

// 텍스처 그룹
r.TextureQuality 0  // 품질 낮춤
r.MipMapLODBias 1   // MIP 바이어스

// GC
obj gc
obj list class=Texture2D

// 메모리 덤프
dumpticks
dumpallocs
```

---

## 요약

| 영역 | 최적화 방법 | 예상 절감 |
|------|-------------|----------|
| 텍스처 | 압축 포맷 사용 | 4-8배 |
| 텍스처 | 스트리밍 활성화 | 동적 관리 |
| 텍스처 | 적절한 해상도 | 2-4배 |
| Render Target | 풀링/재사용 | 30-50% |
| 버퍼 | 압축 버텍스 포맷 | 20-40% |
| LOD | HLOD 활용 | 원거리 50%+ |

---

## 참고 자료

- [Memory Management](https://docs.unrealengine.com/memory-management/)
- [Texture Streaming](https://docs.unrealengine.com/texture-streaming/)
- [Low Level Memory Tracker](https://docs.unrealengine.com/low-level-memory-tracker/)
