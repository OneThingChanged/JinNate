# 05. FMeshDrawCommand와 최적화

> 드로우 명령 생성, 정렬, 캐싱

---

## 목차

1. [FMeshDrawCommand 구조](#1-fmeshdrawcommand-구조)
2. [명령 정렬](#2-명령-정렬)
3. [정적 메시 캐싱](#3-정적-메시-캐싱)
4. [동적 인스턴싱](#4-동적-인스턴싱)
5. [GPU Scene](#5-gpu-scene)

---

## 1. FMeshDrawCommand 구조 {#1-fmeshdrawcommand-구조}

### 1.1 개요

![FMeshDrawCommand](../images/ch03/1617944-20210319204138477-1053404240.png)
*FMeshDrawCommand 구조*

```cpp
class FMeshDrawCommand
{
public:
    // 셰이더 바인딩
    FMeshDrawShaderBindings ShaderBindings;

    // 버텍스 스트림
    FVertexInputStreamArray VertexStreams;

    // 인덱스 버퍼
    FRHIIndexBuffer* IndexBuffer;

    // PSO 캐시 ID
    FGraphicsMinimalPipelineStateId CachedPipelineId;

    // 드로우 파라미터
    uint32 FirstIndex;
    uint32 NumPrimitives;
    uint32 NumInstances;

    // 상태 비교 (동적 인스턴싱용)
    bool MatchesForDynamicInstancing(const FMeshDrawCommand& Rhs) const;

    // RHI 명령 제출
    void SubmitDraw(FRHICommandList& RHICmdList) const;
};
```

---

## 2. 명령 정렬 {#2-명령-정렬}

### 2.1 정렬 키

![정렬 키](../images/ch03/1617944-20210319204117391-930676450.png)
*FMeshDrawCommandSortKey 구조*

```cpp
class FMeshDrawCommandSortKey
{
    union {
        uint64 PackedData;

        // BasePass 정렬: 상태 변경 최소화
        struct {
            uint64 VertexShaderHash : 16;
            uint64 PixelShaderHash : 32;
            uint64 Masked : 16;
        } BasePass;

        // 반투명 정렬: 뒤에서 앞으로
        struct {
            uint64 MeshIdInPrimitive : 16;
            uint64 Distance : 32;
            uint64 Priority : 16;
        } Translucent;
    };
};
```

### 2.2 정렬 우선순위

| 패스 | 정렬 순서 | 이유 |
|------|-----------|------|
| **BasePass** | Masked > Pixel Shader > Vertex Shader | 상태 변경 최소화 |
| **Translucent** | Priority > Distance > Mesh ID | 올바른 블렌딩 순서 |

---

## 3. 정적 메시 캐싱 {#3-정적-메시-캐싱}

### 3.1 캐싱 조건

- Mobility가 Static 또는 Stationary
- 머티리얼이 정적
- 트랜스폼 변경 없음

### 3.2 구현

```cpp
void FScene::CacheMeshDrawCommands(FPrimitiveSceneInfo* SceneInfo)
{
    if (SceneInfo->Proxy->IsStaticPathAvailable())
    {
        // 각 패스에 대해 명령 사전 생성
        for (int32 PassIndex = 0; PassIndex < EMeshPass::Num; ++PassIndex)
        {
            FMeshPassProcessor* Processor = CreateMeshPassProcessor(PassIndex);

            // 정적 메시 요소 수집
            TArray<FMeshBatch> StaticBatches;
            SceneInfo->Proxy->DrawStaticElements(StaticBatches);

            // 명령 생성 및 캐싱
            for (const FMeshBatch& Batch : StaticBatches)
            {
                Processor->AddMeshBatch(Batch, ...);
            }

            // 캐시에 저장
            SceneInfo->StaticMeshDrawCommands[PassIndex] = MoveTemp(Commands);
        }
    }
}
```

---

## 4. 동적 인스턴싱 {#4-동적-인스턴싱}

### 4.1 State Bucket 해싱

```
┌─────────────────────────────────────────────┐
│           State Bucket Hashing              │
├─────────────────────────────────────────────┤
│                                             │
│  Command A ─┐                               │
│             ├─→ Same PSO/Bindings ─→ Merge  │
│  Command B ─┘                               │
│                                             │
│  Command C ─────→ Different ─→ Separate     │
│                                             │
└─────────────────────────────────────────────┘
```

### 4.2 구현

```cpp
void MergeCompatibleCommands(TArray<FMeshDrawCommand>& Commands)
{
    // 호환 가능한 명령 그룹화
    TMap<uint64, TArray<FMeshDrawCommand*>> Buckets;

    for (FMeshDrawCommand& Cmd : Commands)
    {
        uint64 StateHash = Cmd.ComputeStateHash();
        Buckets.FindOrAdd(StateHash).Add(&Cmd);
    }

    // 각 버킷 내에서 인스턴싱
    for (auto& Pair : Buckets)
    {
        if (Pair.Value.Num() > 1)
        {
            // 첫 번째 명령에 인스턴스 수 누적
            Pair.Value[0]->NumInstances = Pair.Value.Num();
        }
    }
}
```

---

## 5. GPU Scene {#5-gpu-scene}

### 5.1 개념

GPU Scene은 프리미티브 데이터를 GPU 측에 저장합니다:

```cpp
class FGPUScene
{
    // 프리미티브 데이터 버퍼
    FRWBufferStructured PrimitiveBuffer;

    // Primitive ID → 버퍼 인덱스 매핑
    TArray<uint32> PrimitiveIdToIndex;

public:
    void AddPrimitive(FPrimitiveSceneInfo* Primitive)
    {
        // GPU 버퍼에 프리미티브 데이터 업로드
        FPrimitiveSceneShaderData Data;
        Data.LocalToWorld = Primitive->Proxy->GetLocalToWorld();
        Data.Bounds = Primitive->Proxy->GetBounds();
        // ...

        UploadToGPU(Data);
    }
};
```

### 5.2 장점

| 장점 | 설명 |
|------|------|
| **CPU 부담 감소** | 유니폼 버퍼 업데이트 감소 |
| **GPU 드리븐 렌더링** | GPU에서 컬링/선택 가능 |
| **인스턴싱 효율** | Primitive ID로 데이터 페치 |

---

## 프레임 렌더링 전체 흐름

![렌더링 흐름](../images/ch03/1617944-20210319204156161-1637874484.png)
*프레임 렌더링 전체 흐름*

```
1. InitViews() ─→ 가시성 컬링, 동적 요소 수집
        │
        ▼
2. SetupMeshPass() ─→ 각 패스에 대해 프로세서 생성
        │
        ▼
3. Parallel Task ─→ 드로우 명령 생성, 정렬, 캐싱
        │
        ▼
4. State Bucket ─→ 동일한 PSO/바인딩 명령 병합
        │
        ▼
5. Submission ─→ GPU 실행을 위한 RHI 명령 큐잉
```

---

## 참고 자료

- [원문 시리즈 (중국어)](https://www.cnblogs.com/timlly/p/14588598.html)
- [UE4 Source: Engine/Source/Runtime/Renderer/](https://github.com/EpicGames/UnrealEngine)

---

## 다음 챕터

[Ch.04 디퍼드 렌더링](../04-deferred-rendering/index.md)에서 G-Buffer와 Lighting Pass를 살펴봅니다.
---

<div style="display: flex; justify-content: space-between; align-items: center; padding: 16px 0;">
  <a href="../04-mesh-batch-processor/" style="text-decoration: none;">← 이전: 04. FMeshBatch와 FMeshPas</a>
  <a href="../../04-deferred-rendering/" style="text-decoration: none;">다음: Ch.04 디퍼드 렌더링 →</a>
</div>
