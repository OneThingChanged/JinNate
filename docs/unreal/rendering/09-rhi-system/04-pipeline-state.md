# 04. 파이프라인 스테이트

PSO(Pipeline State Object)의 구조, 생성, 캐싱 메커니즘을 분석합니다.

---

## PSO 개요

### 파이프라인 스테이트란?

```
┌─────────────────────────────────────────────────────────────────┐
│                    Pipeline State Object (PSO)                  │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  PSO = GPU 파이프라인의 전체 상태를 하나의 객체로 패키징         │
│                                                                 │
│  Legacy API (D3D11):                                            │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  개별 상태 설정                                          │   │
│  │  SetVertexShader(VS);                                   │   │
│  │  SetPixelShader(PS);                                    │   │
│  │  SetBlendState(Blend);                                  │   │
│  │  SetRasterizerState(Raster);                            │   │
│  │  SetDepthStencilState(DS);                              │   │
│  │  ...                                                    │   │
│  │  Draw();  ← 여기서 드라이버가 상태 조합/검증/컴파일      │   │
│  │           → 드라이버 오버헤드 발생                       │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  Modern API (D3D12/Vulkan):                                     │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  PSO 미리 생성                                          │   │
│  │  CreateGraphicsPipelineState(Desc);  ← 사전 컴파일       │   │
│  │                                                         │   │
│  │  드로우 시:                                              │   │
│  │  SetPipelineState(PSO);  ← 이미 컴파일된 상태            │   │
│  │  Draw();                 ← 최소 오버헤드                 │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### PSO 구성 요소

```
┌─────────────────────────────────────────────────────────────────┐
│                    Graphics PSO 구성                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                    Shader Stages                        │   │
│  │  ┌──────┐  ┌──────┐  ┌──────┐  ┌──────┐  ┌──────┐      │   │
│  │  │  VS  │→ │  HS  │→ │  DS  │→ │  GS  │→ │  PS  │      │   │
│  │  └──────┘  └──────┘  └──────┘  └──────┘  └──────┘      │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                    Fixed Function States                │   │
│  │                                                         │   │
│  │  Blend State         Rasterizer State   Depth/Stencil   │   │
│  │  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐  │   │
│  │  │ SrcBlend    │    │ FillMode    │    │ DepthEnable │  │   │
│  │  │ DstBlend    │    │ CullMode    │    │ DepthFunc   │  │   │
│  │  │ BlendOp     │    │ FrontCCW    │    │ StencilEnable│ │   │
│  │  │ WriteMask   │    │ DepthBias   │    │ StencilOps  │  │   │
│  │  └─────────────┘    └─────────────┘    └─────────────┘  │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                    Input/Output                         │   │
│  │                                                         │   │
│  │  Input Layout           Render Target Format            │   │
│  │  ┌─────────────┐       ┌─────────────┐                  │   │
│  │  │ Position    │       │ RT0: RGBA8  │                  │   │
│  │  │ Normal      │       │ RT1: RGBA16F│                  │   │
│  │  │ UV          │       │ DS: D24S8   │                  │   │
│  │  └─────────────┘       └─────────────┘                  │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## Graphics PSO

### PSO 초기화 구조체

```cpp
// 그래픽스 PSO 초기화 데이터
struct FGraphicsPipelineStateInitializer
{
    // 셰이더
    FRHIVertexShader* VertexShader;
    FRHIPixelShader* PixelShader;
    FRHIGeometryShader* GeometryShader;      // 선택적
    FRHIHullShader* HullShader;              // 선택적
    FRHIDomainShader* DomainShader;          // 선택적

    // 버텍스 선언
    FRHIVertexDeclaration* VertexDeclaration;

    // 블렌드 상태
    FRHIBlendState* BlendState;

    // 래스터라이저 상태
    FRHIRasterizerState* RasterizerState;

    // 깊이/스텐실 상태
    FRHIDepthStencilState* DepthStencilState;

    // 렌더 타겟 포맷
    TStaticArray<EPixelFormat, MaxSimultaneousRenderTargets> RenderTargetFormats;
    EPixelFormat DepthStencilFormat;
    uint32 NumSamples;  // MSAA

    // 프리미티브 타입
    EPrimitiveType PrimitiveType;

    // 기타 플래그
    uint16 Flags;
};
```

### PSO 생성

```cpp
// 블렌드 상태 생성
FBlendStateRHIRef CreateBlendState()
{
    FBlendStateInitializerRHI Initializer;

    // 불투명
    Initializer.RenderTargets[0].ColorBlendOp = BO_Add;
    Initializer.RenderTargets[0].ColorSrcBlend = BF_One;
    Initializer.RenderTargets[0].ColorDestBlend = BF_Zero;
    Initializer.RenderTargets[0].ColorWriteMask = CW_RGBA;
    Initializer.RenderTargets[0].AlphaBlendOp = BO_Add;
    Initializer.RenderTargets[0].AlphaSrcBlend = BF_One;
    Initializer.RenderTargets[0].AlphaDestBlend = BF_Zero;

    return RHICreateBlendState(Initializer);
}

// 래스터라이저 상태 생성
FRasterizerStateRHIRef CreateRasterizerState()
{
    FRasterizerStateInitializerRHI Initializer;

    Initializer.FillMode = FM_Solid;
    Initializer.CullMode = CM_Back;
    Initializer.DepthBias = 0;
    Initializer.SlopeScaleDepthBias = 0;
    Initializer.bAllowMSAA = true;
    Initializer.bEnableLineAA = false;

    return RHICreateRasterizerState(Initializer);
}

// 깊이/스텐실 상태 생성
FDepthStencilStateRHIRef CreateDepthStencilState()
{
    FDepthStencilStateInitializerRHI Initializer;

    Initializer.bEnableDepthWrite = true;
    Initializer.DepthTest = CF_DepthNearOrEqual;
    Initializer.bEnableFrontFaceStencil = false;
    Initializer.bEnableBackFaceStencil = false;

    return RHICreateDepthStencilState(Initializer);
}

// 전체 PSO 생성
FGraphicsPipelineStateRHIRef CreateGraphicsPSO()
{
    FGraphicsPipelineStateInitializer Initializer;

    // 셰이더 설정
    Initializer.VertexShader = MyVertexShader.GetVertexShader();
    Initializer.PixelShader = MyPixelShader.GetPixelShader();

    // 버텍스 레이아웃
    Initializer.VertexDeclaration = GMyVertexDeclaration.VertexDeclarationRHI;

    // 상태 객체
    Initializer.BlendState = TStaticBlendState<>::GetRHI();
    Initializer.RasterizerState = TStaticRasterizerState<>::GetRHI();
    Initializer.DepthStencilState = TStaticDepthStencilState<true, CF_DepthNearOrEqual>::GetRHI();

    // 렌더 타겟 포맷
    Initializer.RenderTargetFormats[0] = PF_FloatRGBA;
    Initializer.DepthStencilFormat = PF_DepthStencil;
    Initializer.NumSamples = 1;

    Initializer.PrimitiveType = PT_TriangleList;

    return RHICreateGraphicsPipelineState(Initializer);
}
```

---

## Compute PSO

### Compute 파이프라인

```cpp
// 컴퓨트 PSO는 단순 - 셰이더만 필요
struct FComputePipelineStateInitializer
{
    FRHIComputeShader* ComputeShader;
};

// 컴퓨트 PSO 생성
FComputePipelineStateRHIRef CreateComputePSO(FRHIComputeShader* Shader)
{
    return RHICreateComputePipelineState(Shader);
}

// 사용 예시
void DispatchCompute(FRHICommandList& RHICmdList)
{
    // PSO 설정
    RHICmdList.SetComputePipelineState(MyComputePSO);

    // 리소스 바인딩
    RHICmdList.SetShaderTexture(MyComputeShader, 0, InputTexture);
    RHICmdList.SetShaderUAV(MyComputeShader, 0, OutputUAV);

    // 디스패치
    RHICmdList.DispatchComputeShader(
        FMath::DivideAndRoundUp(Width, 8),
        FMath::DivideAndRoundUp(Height, 8),
        1
    );
}
```

---

## 정적 상태 객체

### Static State 매크로

```cpp
// 컴파일 타임에 상태 정의
template<
    bool bEnableDepthWrite = true,
    ECompareFunction DepthTest = CF_DepthNearOrEqual,
    bool bEnableFrontFaceStencil = false,
    // ... 기타 파라미터
>
class TStaticDepthStencilState : public TStaticStateRHI<...>
{
public:
    static FDepthStencilStateRHIRef GetRHI()
    {
        static FDepthStencilStateRHIRef State;
        if (!State.IsValid())
        {
            FDepthStencilStateInitializerRHI Initializer(/* 템플릿 파라미터 사용 */);
            State = RHICreateDepthStencilState(Initializer);
        }
        return State;
    }
};

// 사용 예시
// 불투명 렌더링 (깊이 쓰기 활성화)
TStaticDepthStencilState<true, CF_DepthNearOrEqual>::GetRHI();

// 반투명 렌더링 (깊이 쓰기 비활성화)
TStaticDepthStencilState<false, CF_DepthNearOrEqual>::GetRHI();

// 스카이박스 (깊이 테스트만)
TStaticDepthStencilState<false, CF_LessEqual>::GetRHI();
```

### 블렌드 상태 예시

```cpp
// 불투명 블렌드
TStaticBlendState<>::GetRHI();

// 알파 블렌드 (표준)
TStaticBlendState<
    CW_RGBA,           // ColorWriteMask
    BO_Add,            // ColorBlendOp
    BF_SourceAlpha,    // ColorSrcBlend
    BF_InverseSourceAlpha  // ColorDestBlend
>::GetRHI();

// Additive 블렌드
TStaticBlendState<CW_RGBA, BO_Add, BF_One, BF_One>::GetRHI();

// Multiply 블렌드
TStaticBlendState<CW_RGBA, BO_Add, BF_DestColor, BF_Zero>::GetRHI();
```

---

## PSO 캐싱

### 캐싱 필요성

```
┌─────────────────────────────────────────────────────────────────┐
│                    PSO 컴파일 비용                               │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  PSO 생성 = GPU 드라이버에서 파이프라인 컴파일                   │
│                                                                 │
│  비용:                                                          │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  단순 PSO:    10-50 ms                                  │   │
│  │  복잡한 PSO:  100-500 ms                                │   │
│  │  극단적 경우: 1-2초                                      │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  문제:                                                          │
│  - 런타임 PSO 생성 → 프레임 스터터링                            │
│  - 동일 PSO 반복 생성 → 리소스 낭비                             │
│                                                                 │
│  해결:                                                          │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  1. 메모리 캐시: 세션 중 PSO 재사용                      │   │
│  │  2. 디스크 캐시: 게임 재시작 시에도 유지                  │   │
│  │  3. 사전 컴파일: 로딩 화면에서 미리 생성                  │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### PSO 캐시 구현

```cpp
// PSO 캐시 관리자
class FPipelineStateCache
{
    // 메모리 캐시
    TMap<FPSOCacheKey, FGraphicsPipelineStateRHIRef> GraphicsCache;
    TMap<FRHIComputeShader*, FComputePipelineStateRHIRef> ComputeCache;

    // 동기화
    FCriticalSection CacheLock;

public:
    FGraphicsPipelineStateRHIRef GetOrCreateGraphicsPSO(
        const FGraphicsPipelineStateInitializer& Initializer)
    {
        FPSOCacheKey Key(Initializer);

        {
            FScopeLock Lock(&CacheLock);
            if (FGraphicsPipelineStateRHIRef* Found = GraphicsCache.Find(Key))
            {
                return *Found;  // 캐시 히트
            }
        }

        // 캐시 미스 - 새로 생성
        FGraphicsPipelineStateRHIRef NewPSO = RHICreateGraphicsPipelineState(Initializer);

        {
            FScopeLock Lock(&CacheLock);
            GraphicsCache.Add(Key, NewPSO);
        }

        return NewPSO;
    }
};

// PSO 캐시 키 (해시용)
struct FPSOCacheKey
{
    FSHAHash VertexShaderHash;
    FSHAHash PixelShaderHash;
    uint64 BlendStateHash;
    uint64 RasterizerStateHash;
    uint64 DepthStencilStateHash;
    // ... 기타 상태

    uint32 GetHash() const
    {
        // 모든 필드로 해시 계산
        return HashCombine(GetTypeHash(VertexShaderHash), ...);
    }
};
```

### 디스크 캐시

```
┌─────────────────────────────────────────────────────────────────┐
│                    PSO 디스크 캐시                               │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  저장 위치:                                                      │
│  - [Project]/Saved/PipelineCache/                              │
│  - 플랫폼별 디렉토리                                            │
│                                                                 │
│  파일 포맷:                                                      │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Header                                                 │   │
│  │  ├── Version                                            │   │
│  │  ├── Platform (D3D12/Vulkan/Metal)                      │   │
│  │  ├── GPU Vendor/Model                                   │   │
│  │  └── Driver Version                                     │   │
│  │                                                         │   │
│  │  PSO Entries                                            │   │
│  │  ├── PSO Key Hash                                       │   │
│  │  ├── Initializer Data                                   │   │
│  │  └── Compiled Binary (드라이버 종속)                    │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  주의:                                                          │
│  - 드라이버 업데이트 시 캐시 무효화 가능                        │
│  - GPU 변경 시 캐시 무효화                                      │
│  - 버전 미스매치 시 재컴파일                                    │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## PSO 사전 컴파일

### 사전 컴파일 수집

```cpp
// 게임 플레이 중 PSO 사용 기록
class FPSOCollector
{
    TSet<FPSOCacheKey> UsedPSOs;
    bool bRecording = false;

public:
    void StartRecording()
    {
        bRecording = true;
        UsedPSOs.Empty();
    }

    void OnPSOUsed(const FGraphicsPipelineStateInitializer& Init)
    {
        if (bRecording)
        {
            UsedPSOs.Add(FPSOCacheKey(Init));
        }
    }

    void StopAndSave(const FString& Filename)
    {
        bRecording = false;
        // 파일로 저장
        SerializePSOKeys(Filename, UsedPSOs);
    }
};

// 콘솔 명령어
// r.ShaderPipelineCache.StartLoggingPSORequests  - 기록 시작
// r.ShaderPipelineCache.StopLoggingPSORequests   - 기록 중지
// r.ShaderPipelineCache.SaveBinaryCache          - 캐시 저장
```

### 로딩 시 사전 컴파일

```cpp
// 게임 시작 시 PSO 프리컴파일
class FPSOPrecompiler
{
public:
    void PrecompileFromCache(const FString& CacheFile)
    {
        TArray<FPSOCacheKey> Keys;
        LoadPSOKeys(CacheFile, Keys);

        // 비동기 컴파일 태스크
        for (const FPSOCacheKey& Key : Keys)
        {
            FFunctionGraphTask::CreateAndDispatchWhenReady(
                [Key]()
                {
                    // 백그라운드에서 PSO 생성
                    CreatePSOFromKey(Key);
                },
                TStatId(),
                nullptr,
                ENamedThreads::AnyBackgroundThreadNormalTask
            );
        }

        // 로딩 화면에서 완료 대기
        WaitForCompletion();
    }
};
```

### 번들 (D3D12)

```cpp
// D3D12 Bundle - 작은 커맨드 리스트 재사용
// PSO와 함께 자주 사용되는 명령 세트 캐싱

class FD3D12Bundle
{
    ID3D12GraphicsCommandList* BundleCommandList;

public:
    void Record(ID3D12PipelineState* PSO, /* 기타 상태 */)
    {
        // 번들에 명령 기록
        BundleCommandList->SetPipelineState(PSO);
        BundleCommandList->SetGraphicsRootSignature(RootSig);
        BundleCommandList->IASetPrimitiveTopology(D3D_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
        BundleCommandList->Close();
    }

    void Execute(ID3D12GraphicsCommandList* CmdList)
    {
        // 메인 커맨드 리스트에서 번들 실행
        CmdList->ExecuteBundle(BundleCommandList);
    }
};
```

---

## 상태 변경 최소화

### 상태 정렬

```
┌─────────────────────────────────────────────────────────────────┐
│                    상태 정렬 최적화                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  정렬 전:                                                        │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  SetPSO(A) → Draw → SetPSO(B) → Draw → SetPSO(A) → Draw │   │
│  │  PSO 변경: 3회                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  정렬 후:                                                        │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  SetPSO(A) → Draw → Draw → SetPSO(B) → Draw             │   │
│  │  PSO 변경: 2회                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  UE 정렬 기준 (FMeshDrawCommand):                               │
│  1. PSO (가장 비용 높음)                                        │
│  2. 셰이더 바인딩                                               │
│  3. 버텍스 버퍼                                                  │
│  4. 머티리얼 파라미터                                            │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 더티 상태 추적

```cpp
// 변경된 상태만 설정
class FStateCache
{
    FGraphicsPipelineStateRHIRef CurrentPSO;
    FRHITexture* BoundTextures[MaxTextures];
    FRHIBuffer* BoundBuffers[MaxBuffers];

public:
    void SetPSO(FRHICommandList& CmdList, FGraphicsPipelineStateRHIRef NewPSO)
    {
        if (CurrentPSO != NewPSO)
        {
            CurrentPSO = NewPSO;
            CmdList.SetGraphicsPipelineState(NewPSO);
        }
        // 같으면 스킵
    }

    void SetTexture(FRHICommandList& CmdList, uint32 Slot, FRHITexture* Texture)
    {
        if (BoundTextures[Slot] != Texture)
        {
            BoundTextures[Slot] = Texture;
            CmdList.SetShaderTexture(..., Slot, Texture);
        }
    }
};
```

---

## 요약

PSO 핵심:

1. **개념** - GPU 파이프라인 전체 상태의 사전 컴파일 객체
2. **구성** - 셰이더, 블렌드, 래스터라이저, 깊이/스텐실 상태
3. **캐싱** - 메모리/디스크 캐시로 재컴파일 방지
4. **사전 컴파일** - 로딩 시 미리 생성하여 스터터링 방지
5. **최적화** - 상태 정렬, 더티 추적으로 변경 최소화

PSO는 Modern API에서 필수이며, 적절한 캐싱이 성능의 핵심입니다.

---

## 참고 자료

- [D3D12 PSO](https://docs.microsoft.com/en-us/windows/win32/direct3d12/pipelines-and-shaders-with-directx-12)
- [Vulkan Pipeline](https://www.khronos.org/registry/vulkan/specs/1.3/html/chap10.html)
- [원문 시리즈 (중국어)](https://www.cnblogs.com/timlly/p/13512787.html)
