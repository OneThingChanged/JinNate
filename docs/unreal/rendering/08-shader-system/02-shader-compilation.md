# 셰이더 컴파일

UE의 셰이더 컴파일 파이프라인, 순열 시스템, 캐싱을 분석합니다.

---

## GLSL 셰이더 파이프라인

![GLSL 셰이더 파이프라인](../images/ch08/1617944-20210802224313983-501197597.jpg)

*HLSLCC를 통한 GLSL 변환 - HLSL 파싱 → AST → Mesa IR → 최적화 → GLSL 출력 + Parameter Map*

---

## 컴파일 파이프라인

### 전체 흐름

```
┌─────────────────────────────────────────────────────────────────┐
│                    셰이더 컴파일 파이프라인                       │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  HLSL 소스 (.usf)                                               │
│       │                                                         │
│       ▼                                                         │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                    전처리기                              │   │
│  │  - #include 처리                                        │   │
│  │  - #define 매크로 확장                                   │   │
│  │  - 순열 매크로 적용                                      │   │
│  └────────────────────────┬────────────────────────────────┘   │
│                           │                                     │
│                           ▼                                     │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                    HLSL 컴파일러                         │   │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐              │   │
│  │  │   FXC    │  │   DXC    │  │  HLSLCC  │              │   │
│  │  │(DX11 SM5)│  │(DX12 SM6)│  │(크로스)   │              │   │
│  │  └──────────┘  └──────────┘  └──────────┘              │   │
│  └────────────────────────┬────────────────────────────────┘   │
│                           │                                     │
│           ┌───────────────┼───────────────┐                     │
│           ▼               ▼               ▼                     │
│  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐            │
│  │    DXBC      │ │    DXIL      │ │    SPIRV     │            │
│  │  (DX11 BC)   │ │  (DX12 IL)   │ │  (Vulkan)    │            │
│  └──────────────┘ └──────────────┘ └──────────────┘            │
│                           │                                     │
│                           ▼                                     │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                    DDC (Derived Data Cache)              │   │
│  │  키: 소스 해시 + 플랫폼 + 순열                           │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 컴파일 요청

```cpp
// 셰이더 컴파일 작업
class FShaderCompileJob
{
public:
    // 셰이더 타입
    FShaderType* ShaderType;

    // 순열 ID
    int32 PermutationId;

    // 소스 파일
    FString SourceFilename;
    FString EntryPoint;

    // 컴파일 환경
    FShaderCompilerEnvironment Environment;

    // 대상 플랫폼
    EShaderPlatform Platform;

    // 입력 해시 (DDC 키용)
    FSHAHash InputHash;

    // 출력
    FShaderCompilerOutput Output;
    bool bSucceeded;
};

// 컴파일 요청 제출
void SubmitShaderCompileJob(FShaderType* Type, int32 Permutation)
{
    FShaderCompileJob* Job = new FShaderCompileJob();
    Job->ShaderType = Type;
    Job->PermutationId = Permutation;
    Job->SourceFilename = Type->GetSourceFilename();
    Job->EntryPoint = Type->GetFunctionName();
    Job->Platform = GMaxRHIShaderPlatform;

    // 환경 설정
    Type->SetupCompileEnvironment(Job->Environment, Permutation);

    // 입력 해시 계산
    Job->InputHash = CalculateInputHash(Job);

    // DDC에서 캐시된 결과 확인
    if (TryGetCachedShader(Job->InputHash, Job->Output))
    {
        Job->bSucceeded = true;
        OnCompileComplete(Job);
        return;
    }

    // 컴파일 큐에 제출
    GShaderCompilingManager->AddJob(Job);
}
```

---

## 크로스 컴파일

![HLSL 크로스 컴파일 흐름](../images/ch08/1617944-20210802224406321-493419453.png)

*HLSL 크로스 컴파일 파이프라인 - D3DCompiler(DXBC/DXIL)와 SPIR-V 경로로 분기하여 각 플랫폼 지원*

![SPIR-V 에코시스템](../images/ch08/1617944-20210802224300810-1196548340.jpg)

*SPIR-V 기반 셰이더 에코시스템 - GLSL/HLSL에서 SPIR-V로 변환 후 SPIRV-Cross로 Metal/HLSL/GLSL 재생성*

### 플랫폼별 컴파일러

```cpp
// 셰이더 플랫폼
enum class EShaderPlatform
{
    SP_PCD3D_SM5,           // DirectX 11
    SP_PCD3D_SM6,           // DirectX 12
    SP_VULKAN_SM5,          // Vulkan
    SP_METAL_SM5,           // Metal (macOS)
    SP_METAL_MACES3_1,      // Metal (iOS)
    SP_OPENGL_ES3_1,        // OpenGL ES
};

// 플랫폼별 컴파일러 선택
IShaderFormat* GetShaderFormat(EShaderPlatform Platform)
{
    switch (Platform)
    {
        case SP_PCD3D_SM5:
            return new FShaderFormatD3D();  // FXC

        case SP_PCD3D_SM6:
            return new FShaderFormatD3D();  // DXC

        case SP_VULKAN_SM5:
            return new FShaderFormatVulkan();  // DXC → SPIRV

        case SP_METAL_SM5:
            return new FShaderFormatMetal();  // Metal Compiler

        default:
            return nullptr;
    }
}
```

### HLSL 크로스 컴파일

```cpp
// HLSL → SPIRV 크로스 컴파일
class FVulkanShaderCompiler
{
public:
    bool Compile(const FShaderCompilerInput& Input, FShaderCompilerOutput& Output)
    {
        // 1. HLSL → SPIRV (DXC 사용)
        TArray<uint32> SPIRVCode;
        if (!CompileHLSLToSPIRV(Input.SourceCode, Input.EntryPoint, SPIRVCode))
        {
            return false;
        }

        // 2. SPIRV 최적화
        OptimizeSPIRV(SPIRVCode);

        // 3. SPIRV 리플렉션
        ExtractReflection(SPIRVCode, Output.ParameterMap);

        // 4. 출력
        Output.ShaderCode = SPIRVCode;
        return true;
    }

private:
    bool CompileHLSLToSPIRV(const FString& Source, const FString& Entry,
                            TArray<uint32>& OutSPIRV)
    {
        // DXC 컴파일러 호출
        IDxcCompiler* Compiler = GetDXCompiler();

        IDxcBlob* ShaderBlob;
        HRESULT HR = Compiler->Compile(
            SourceBlob,
            L"Shader.hlsl",
            *Entry,
            L"vs_6_0",  // 또는 ps_6_0, cs_6_0 등
            Arguments,
            NumArguments,
            nullptr, 0,
            nullptr,
            &Result);

        // SPIRV 코드 추출
        Result->GetResult(&ShaderBlob);
        // ...

        return SUCCEEDED(HR);
    }
};
```

---

## 순열 시스템

### 순열 정의

```cpp
// 순열 차원 선언
class FMyShader : public FGlobalShader
{
    // 불리언 순열 (0 또는 1)
    class FFeatureADim : SHADER_PERMUTATION_BOOL("FEATURE_A_ENABLED");

    // 정수 순열 (0, 1, 2, ...)
    class FQualityDim : SHADER_PERMUTATION_INT("QUALITY_LEVEL", 4);

    // 열거형 순열
    class FLightTypeDim : SHADER_PERMUTATION_ENUM_CLASS("LIGHT_TYPE", ELightType);

    // 스파스 순열 (특정 값만)
    class FSparseIntDim : SHADER_PERMUTATION_SPARSE_INT("SPARSE_VALUE", 1, 2, 4, 8);

    // 순열 도메인 (모든 차원 조합)
    using FPermutationDomain = TShaderPermutationDomain<
        FFeatureADim,
        FQualityDim,
        FLightTypeDim
    >;

    // 총 순열 수: 2 * 4 * (ELightType 값 수)
};
```

### 순열 필터링

```cpp
// 불필요한 순열 제외
static bool ShouldCompilePermutation(const FGlobalShaderPermutationParameters& Parameters)
{
    FPermutationDomain PermutationVector(Parameters.PermutationId);

    // 고품질에서만 특정 기능 지원
    if (PermutationVector.Get<FQualityDim>() < 2 &&
        PermutationVector.Get<FFeatureADim>())
    {
        return false;  // 이 조합은 컴파일하지 않음
    }

    // 모바일에서는 저품질만
    if (IsMobilePlatform(Parameters.Platform))
    {
        if (PermutationVector.Get<FQualityDim>() > 1)
        {
            return false;
        }
    }

    return true;
}

// 런타임에서 순열 선택
void GetShaderPermutation(const FViewInfo& View, FPermutationDomain& OutPermutation)
{
    OutPermutation.Set<FFeatureADim>(View.bFeatureAEnabled);
    OutPermutation.Set<FQualityDim>(View.QualityLevel);
    OutPermutation.Set<FLightTypeDim>(View.DominantLightType);
}
```

### 순열 폭발 방지

```cpp
// 문제: 너무 많은 순열
// 5개 불리언 차원 = 2^5 = 32개
// 10개 불리언 차원 = 2^10 = 1024개
// 15개 불리언 차원 = 2^15 = 32768개!

// 해결 1: 순열 대신 동적 분기
#if USE_DYNAMIC_BRANCHING
    // 셰이더 내에서 조건문
    if (FeatureEnabled)
    {
        // Feature A 코드
    }
#else
    // 컴파일 타임에 결정
    #if FEATURE_A_ENABLED
        // Feature A 코드
    #endif
#endif

// 해결 2: 순열 그룹화
class FQualityPresetDim : SHADER_PERMUTATION_INT("QUALITY_PRESET", 3);
// Low = 모든 기능 Off
// Medium = 일부 기능 On
// High = 모든 기능 On
// 개별 기능 순열 대신 프리셋으로 압축

// 해결 3: 특수화 상수 (Vulkan)
// 일부 순열을 런타임에 특수화
layout(constant_id = 0) const bool FEATURE_A = false;
```

---

## 셰이더 캐싱

### DDC (Derived Data Cache)

```cpp
// DDC 키 생성
FSHAHash CalculateShaderInputHash(const FShaderCompileJob& Job)
{
    FSHA1 HashState;

    // 소스 코드 해시
    HashState.Update(Job.SourceCode);

    // 인클루드 파일 해시
    for (const FString& Include : Job.Includes)
    {
        HashState.Update(Include);
    }

    // 컴파일 환경
    HashState.Update(Job.Environment);

    // 순열 ID
    HashState.Update(Job.PermutationId);

    // 플랫폼
    HashState.Update(Job.Platform);

    // 컴파일러 버전
    HashState.Update(GetCompilerVersion());

    return HashState.Finalize();
}

// DDC에서 셰이더 조회
bool TryGetCachedShader(const FSHAHash& Key, FShaderCompilerOutput& OutOutput)
{
    TArray<uint8> CachedData;

    // 로컬 DDC 확인
    if (GetDerivedDataCacheRef().GetSynchronous(*Key.ToString(), CachedData))
    {
        // 역직렬화
        FMemoryReader Ar(CachedData);
        OutOutput.Serialize(Ar);
        return true;
    }

    // 공유 DDC 확인 (네트워크)
    if (GetDerivedDataCacheRef().GetAsynchronous(*Key.ToString(), CachedData))
    {
        FMemoryReader Ar(CachedData);
        OutOutput.Serialize(Ar);
        return true;
    }

    return false;
}

// DDC에 셰이더 저장
void CacheShader(const FSHAHash& Key, const FShaderCompilerOutput& Output)
{
    TArray<uint8> CachedData;
    FMemoryWriter Ar(CachedData);
    Output.Serialize(Ar);

    GetDerivedDataCacheRef().Put(*Key.ToString(), CachedData);
}
```

### PSO 캐싱

```cpp
// Pipeline State Object 캐싱
class FPSOCache
{
public:
    // PSO 조회 또는 생성
    FGraphicsPipelineState* GetOrCreatePSO(const FGraphicsPipelineStateInitializer& Initializer)
    {
        // 해시 계산
        uint32 Hash = CalculatePSOHash(Initializer);

        // 캐시 확인
        if (FGraphicsPipelineState** Found = Cache.Find(Hash))
        {
            return *Found;
        }

        // 새 PSO 생성
        FGraphicsPipelineState* NewPSO = RHICreateGraphicsPipelineState(Initializer);

        // 캐시에 저장
        Cache.Add(Hash, NewPSO);

        return NewPSO;
    }

    // 사전 컴파일 (로딩 히치 방지)
    void PrecachePSO(const FGraphicsPipelineStateInitializer& Initializer)
    {
        // 백그라운드에서 PSO 생성
        AsyncTask(ENamedThreads::AnyBackgroundThreadNormalTask, [=]()
        {
            RHICreateGraphicsPipelineState(Initializer);
        });
    }

private:
    TMap<uint32, FGraphicsPipelineState*> Cache;
};
```

---

## 비동기 컴파일

### 셰이더 컴파일 매니저

```cpp
// 비동기 셰이더 컴파일 관리
class FShaderCompilingManager
{
public:
    // 작업 추가
    void AddJob(FShaderCompileJob* Job)
    {
        PendingJobs.Add(Job);

        // 워커 프로세스 깨우기
        WakeUpWorkers();
    }

    // 특정 셰이더 대기
    void FinishCompilation(const TCHAR* MaterialName)
    {
        while (HasPendingJobsForMaterial(MaterialName))
        {
            ProcessCompletedJobs();
            FPlatformProcess::Sleep(0.01f);
        }
    }

    // 모든 컴파일 대기
    void FinishAllCompilation()
    {
        while (HasPendingJobs())
        {
            ProcessCompletedJobs();
            FPlatformProcess::Sleep(0.01f);
        }
    }

    // 진행률
    float GetProgress() const
    {
        int32 Total = TotalJobsSubmitted;
        int32 Completed = TotalJobsCompleted;
        return Total > 0 ? float(Completed) / float(Total) : 1.0f;
    }

private:
    TArray<FShaderCompileJob*> PendingJobs;
    TArray<FShaderCompileJob*> CompletedJobs;
    int32 TotalJobsSubmitted;
    int32 TotalJobsCompleted;
};

// 워커 프로세스 (ShaderCompileWorker.exe)
int main()
{
    while (true)
    {
        // 파이프에서 작업 수신
        FShaderCompileJob Job = ReceiveJob();

        // 컴파일
        CompileShader(Job);

        // 결과 전송
        SendResult(Job);
    }
}
```

### 핫 리로드

```cpp
// 셰이더 핫 리로드 (에디터)
void RecompileChangedShaders()
{
    // 변경된 파일 감지
    TArray<FString> ChangedFiles = DetectChangedShaderFiles();

    if (ChangedFiles.Num() == 0)
        return;

    // 영향받는 셰이더 찾기
    TArray<FShaderType*> AffectedTypes;
    for (const FString& File : ChangedFiles)
    {
        for (FShaderType* Type : AllShaderTypes)
        {
            if (Type->DependsOn(File))
            {
                AffectedTypes.Add(Type);
            }
        }
    }

    // 재컴파일 요청
    for (FShaderType* Type : AffectedTypes)
    {
        for (int32 Perm = 0; Perm < Type->GetPermutationCount(); Perm++)
        {
            if (Type->ShouldCompilePermutation(Perm))
            {
                SubmitShaderCompileJob(Type, Perm);
            }
        }
    }

    // 완료 대기
    GShaderCompilingManager->FinishAllCompilation();

    // 셰이더 맵 업데이트
    UpdateShaderMaps();
}
```

---

## 컴파일 최적화

### 병렬 컴파일

```cpp
// 다중 워커 프로세스
class FShaderCompileThreadRunnable : public FRunnable
{
public:
    virtual uint32 Run() override
    {
        while (!bShouldStop)
        {
            // 작업 가져오기
            FShaderCompileJob* Job = Manager->GetNextJob();

            if (Job)
            {
                // 워커 프로세스로 전달
                SendToWorkerProcess(Job);

                // 결과 대기
                ReceiveFromWorkerProcess(Job);

                // 완료 처리
                Manager->OnJobCompleted(Job);
            }
            else
            {
                FPlatformProcess::Sleep(0.01f);
            }
        }
        return 0;
    }
};

// 워커 프로세스 풀
void InitializeWorkerPool()
{
    int32 NumWorkers = FMath::Max(1, FPlatformMisc::NumberOfCoresIncludingHyperthreads() - 2);

    for (int32 i = 0; i < NumWorkers; i++)
    {
        FProcHandle Process = FPlatformProcess::CreateProc(
            TEXT("ShaderCompileWorker.exe"),
            nullptr,
            true, false, false,
            nullptr, 0, nullptr, nullptr);

        WorkerProcesses.Add(Process);
    }
}
```

---

## 요약

| 단계 | 설명 |
|------|------|
| 전처리 | #include, #define 처리 |
| 크로스 컴파일 | HLSL → DXBC/SPIRV/Metal |
| 순열 생성 | 조건 조합별 변형 생성 |
| DDC 캐싱 | 입력 해시 기반 결과 캐시 |
| PSO 캐싱 | 파이프라인 상태 캐시 |
| 비동기 컴파일 | 워커 프로세스 병렬 처리 |

셰이더 컴파일 시스템은 성능과 호환성의 균형을 맞춥니다.
---

<div style="display: flex; justify-content: space-between; align-items: center; padding: 16px 0;">
  <a href="../01-shader-architecture/" style="text-decoration: none;">← 이전: 01. 셰이더 아키텍처</a>
  <a href="../03-shader-types/" style="text-decoration: none;">다음: 03. 셰이더 타입 →</a>
</div>
