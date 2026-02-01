# 모프 타겟

블렌드 셰이프 구조, GPU 모프 타겟, 페이셜 애니메이션을 분석합니다.

---

## 모프 타겟 개요

### 블렌드 셰이프 구조

```
┌─────────────────────────────────────────────────────────────────┐
│                   Morph Target Structure                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Base Mesh + Delta Offsets:                                     │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                          │   │
│  │  Base Mesh        Morph Target        Result             │   │
│  │  (Neutral)        (Smile)             (Blended)          │   │
│  │                                                          │   │
│  │    ┌───┐            ┌───┐              ┌───┐            │   │
│  │    │   │     +      │ ↗ │    ×0.5 =    │  ↗│            │   │
│  │    │ ● │            │   │              │ ● │            │   │
│  │    │   │            │   │              │   │            │   │
│  │    └───┘            └───┘              └───┘            │   │
│  │                                                          │   │
│  │  수식: FinalPosition = BasePosition + Σ(Delta × Weight) │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  저장 데이터:                                                   │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  • 영향받는 버텍스 인덱스 (Sparse)                       │   │
│  │  • Position Delta (FVector)                              │   │
│  │  • Normal Delta (FVector) - 선택적                       │   │
│  │  • Tangent Delta (FVector) - 선택적                      │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 모프 타겟 데이터

```cpp
// 모프 타겟 데이터 구조
struct FMorphTargetDelta
{
    FVector PositionDelta;    // 위치 오프셋
    FVector TangentZDelta;    // 노말 오프셋
    uint32 SourceIdx;         // 버텍스 인덱스
};

// 모프 타겟 에셋
UCLASS()
class UMorphTarget : public UObject
{
    GENERATED_BODY()

public:
    // LOD별 델타 데이터
    TArray<FMorphTargetLODModel> MorphLODModels;

    // 기본 스켈레탈 메시 참조
    UPROPERTY()
    USkeletalMesh* BaseSkelMesh;
};

struct FMorphTargetLODModel
{
    // 영향받는 버텍스들
    TArray<FMorphTargetDelta> Vertices;

    // 섹션별 버텍스 수
    TArray<int32> SectionIndices;

    // 압축된 버텍스 수
    int32 NumBaseMeshVerts;
};
```

---

## GPU 모프 타겟

### GPU 파이프라인

```
┌─────────────────────────────────────────────────────────────────┐
│                   GPU Morph Target Pipeline                     │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  CPU 측:                                                        │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  1. 활성 모프 타겟 및 가중치 수집                        │   │
│  │     ┌────────────┐  ┌────────────┐  ┌────────────┐      │   │
│  │     │ Smile: 0.8 │  │ Blink: 1.0 │  │ Angry: 0.3 │      │   │
│  │     └────────────┘  └────────────┘  └────────────┘      │   │
│  └─────────────────────────────────────────────────────────┘   │
│                              │                                  │
│                              ▼ (Weight Buffer)                  │
│  GPU 측:                                                        │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  2. Compute Shader로 델타 누적                           │   │
│  │                                                          │   │
│  │  for each active morph target:                           │   │
│  │      for each affected vertex:                           │   │
│  │          accumulatedDelta += delta × weight              │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                              │                                  │
│                              ▼                                  │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  3. Vertex Shader에서 스키닝과 함께 적용                 │   │
│  │                                                          │   │
│  │  skinnedPos = skin(basePos + morphDelta, boneMatrices)   │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 컴퓨트 셰이더 모프

```hlsl
// Morph Target Compute Shader
[numthreads(64, 1, 1)]
void MorphTargetCS(
    uint3 DispatchThreadId : SV_DispatchThreadID)
{
    uint VertexIndex = DispatchThreadId.x;
    if (VertexIndex >= NumVertices)
        return;

    // 델타 누적
    float3 PositionDelta = float3(0, 0, 0);
    float3 NormalDelta = float3(0, 0, 0);

    // 각 활성 모프 타겟에 대해
    for (uint MorphIdx = 0; MorphIdx < NumActiveMorphs; ++MorphIdx)
    {
        float Weight = MorphWeights[MorphIdx];
        if (Weight == 0)
            continue;

        // 이 버텍스에 대한 델타 찾기
        uint DeltaOffset = MorphOffsets[MorphIdx];
        uint DeltaCount = MorphCounts[MorphIdx];

        for (uint i = 0; i < DeltaCount; ++i)
        {
            FMorphDelta Delta = MorphDeltas[DeltaOffset + i];
            if (Delta.VertexIndex == VertexIndex)
            {
                PositionDelta += Delta.PositionDelta * Weight;
                NormalDelta += Delta.TangentZDelta * Weight;
                break;
            }
        }
    }

    // 결과 저장
    MorphedPositions[VertexIndex] = BasePositions[VertexIndex] + PositionDelta;
    MorphedNormals[VertexIndex] = normalize(BaseNormals[VertexIndex] + NormalDelta);
}
```

### 버텍스 셰이더 통합

```hlsl
// GPU Morph + Skinning Vertex Shader
void MainVS(
    FVertexFactoryInput Input,
    out float4 OutPosition : SV_POSITION,
    out FVertexFactoryInterpolants Interpolants)
{
    // 1. 모프 델타 가져오기
    float3 MorphDelta = float3(0, 0, 0);
    float3 MorphNormalDelta = float3(0, 0, 0);

    #if USE_MORPH_TARGETS
    {
        uint VertexIndex = Input.VertexId;
        MorphDelta = MorphPositionBuffer[VertexIndex];
        MorphNormalDelta = MorphNormalBuffer[VertexIndex];
    }
    #endif

    // 2. 모프 적용
    float3 LocalPosition = Input.Position + MorphDelta;
    float3 LocalNormal = Input.Normal + MorphNormalDelta;

    // 3. 스키닝 적용
    float4x4 SkinMatrix = CalcBoneMatrix(Input);
    float3 WorldPosition = mul(float4(LocalPosition, 1), SkinMatrix).xyz;
    float3 WorldNormal = mul(LocalNormal, (float3x3)SkinMatrix);

    // 4. 변환
    OutPosition = mul(float4(WorldPosition, 1), ViewProjectionMatrix);
    Interpolants.WorldNormal = normalize(WorldNormal);
}
```

---

## 페이셜 애니메이션

### 페이셜 리그 구조

```
┌─────────────────────────────────────────────────────────────────┐
│                   Facial Animation System                       │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  FACS (Facial Action Coding System) 기반:                       │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                          │   │
│  │  AU (Action Unit)               표정                     │   │
│  │  ─────────────────────────────────────────────           │   │
│  │  AU01: Inner Brow Raiser        눈썹 안쪽 올리기         │   │
│  │  AU02: Outer Brow Raiser        눈썹 바깥 올리기         │   │
│  │  AU04: Brow Lowerer             눈썹 내리기              │   │
│  │  AU05: Upper Lid Raiser         위 눈꺼풀 올리기         │   │
│  │  AU06: Cheek Raiser             볼 올리기                │   │
│  │  AU07: Lid Tightener            눈꺼풀 조이기            │   │
│  │  AU09: Nose Wrinkler            코 찡그리기              │   │
│  │  AU10: Upper Lip Raiser         윗입술 올리기            │   │
│  │  AU12: Lip Corner Puller        입꼬리 당기기 (미소)     │   │
│  │  AU15: Lip Corner Depressor     입꼬리 내리기            │   │
│  │  AU17: Chin Raiser              턱 올리기                │   │
│  │  AU20: Lip Stretcher            입 벌리기                │   │
│  │  AU25: Lips Part                입술 떼기                │   │
│  │  AU26: Jaw Drop                 턱 내리기                │   │
│  │  ...                                                     │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  조합 예시:                                                     │
│  • 미소 = AU06 + AU12                                          │
│  • 놀람 = AU01 + AU02 + AU05 + AU26                            │
│  • 분노 = AU04 + AU05 + AU07 + AU23                            │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### MetaHuman 페이셜 시스템

```cpp
// MetaHuman Face Rig
UCLASS()
class UMetaHumanFaceAnimInstance : public UAnimInstance
{
    GENERATED_BODY()

public:
    // 페이셜 컨트롤 값 (0-1)
    UPROPERTY(BlueprintReadWrite, Category = "Face")
    TMap<FName, float> FaceControlValues;

    // 립싱크 데이터
    UPROPERTY(BlueprintReadWrite, Category = "Face")
    TArray<float> VisemeWeights;

    // 페이셜 모프 적용
    virtual void NativeUpdateAnimation(float DeltaSeconds) override
    {
        Super::NativeUpdateAnimation(DeltaSeconds);

        // 컨트롤 값을 모프 타겟에 매핑
        for (const auto& Pair : FaceControlValues)
        {
            ApplyMorphTarget(Pair.Key, Pair.Value);
        }

        // 립싱크 적용
        ApplyVisemes(VisemeWeights);
    }

private:
    void ApplyMorphTarget(FName MorphName, float Weight)
    {
        if (USkeletalMeshComponent* Mesh = GetSkelMeshComponent())
        {
            Mesh->SetMorphTarget(MorphName, Weight);
        }
    }

    void ApplyVisemes(const TArray<float>& Weights)
    {
        static const TArray<FName> VisemeNames = {
            TEXT("viseme_sil"),
            TEXT("viseme_PP"),
            TEXT("viseme_FF"),
            TEXT("viseme_TH"),
            TEXT("viseme_DD"),
            TEXT("viseme_kk"),
            TEXT("viseme_CH"),
            TEXT("viseme_SS"),
            TEXT("viseme_nn"),
            TEXT("viseme_RR"),
            TEXT("viseme_aa"),
            TEXT("viseme_E"),
            TEXT("viseme_I"),
            TEXT("viseme_O"),
            TEXT("viseme_U")
        };

        for (int32 i = 0; i < VisemeNames.Num() && i < Weights.Num(); ++i)
        {
            ApplyMorphTarget(VisemeNames[i], Weights[i]);
        }
    }
};
```

---

## 립싱크

### 립싱크 시스템

```
┌─────────────────────────────────────────────────────────────────┐
│                      Lip Sync System                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  오디오 → 비짐 변환:                                            │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                          │   │
│  │   Audio        Phoneme         Viseme        Morph      │   │
│  │   Waveform  →  Detection   →   Mapping  →   Targets    │   │
│  │                                                          │   │
│  │   ┌─────┐     ┌─────┐        ┌─────┐      ┌─────┐       │   │
│  │   │~~~~~│  →  │ "AH" │   →   │ aa  │  →   │ 0.8 │       │   │
│  │   │~~~~~│     │ "EE" │       │ E   │      │ 0.6 │       │   │
│  │   │~~~~~│     │ "OH" │       │ O   │      │ 0.9 │       │   │
│  │   └─────┘     └─────┘        └─────┘      └─────┘       │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  비짐 목록:                                                     │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  sil: 무음          PP: P, B, M       FF: F, V          │   │
│  │  TH: TH             DD: T, D          kk: K, G          │   │
│  │  CH: CH, J, SH      SS: S, Z          nn: N, L          │   │
│  │  RR: R              aa: A             E: E              │   │
│  │  I: I               O: O              U: U, W           │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### OVRLipSync 연동

```cpp
// OVR LipSync 통합
UCLASS()
class ULipSyncComponent : public UActorComponent
{
    GENERATED_BODY()

public:
    // 오디오 소스
    UPROPERTY(EditAnywhere)
    UAudioComponent* AudioSource;

    // 타겟 메시
    UPROPERTY(EditAnywhere)
    USkeletalMeshComponent* TargetMesh;

    virtual void TickComponent(float DeltaTime,
        ELevelTick TickType,
        FActorComponentTickFunction* ThisTickFunction) override
    {
        Super::TickComponent(DeltaTime, TickType, ThisTickFunction);

        if (!AudioSource || !TargetMesh)
            return;

        // 오디오 데이터 가져오기
        TArray<float> AudioData;
        GetAudioData(AudioSource, AudioData);

        // OVR LipSync 처리
        TArray<float> VisemeWeights;
        ProcessLipSync(AudioData, VisemeWeights);

        // 모프 타겟 적용
        ApplyVisemeWeights(TargetMesh, VisemeWeights);
    }

private:
    void ProcessLipSync(const TArray<float>& AudioData,
                       TArray<float>& OutVisemes)
    {
        // OVR LipSync API 호출
        ovrLipSyncFrame Frame;
        ovrLipSync_ProcessFrame(
            LipSyncContext,
            AudioData.GetData(),
            AudioData.Num(),
            &Frame);

        // 비짐 가중치 추출
        OutVisemes.SetNum(ovrLipSyncViseme_Count);
        for (int32 i = 0; i < ovrLipSyncViseme_Count; ++i)
        {
            OutVisemes[i] = Frame.visemes[i];
        }
    }
};
```

---

## 성능 최적화

### 모프 타겟 최적화

```
┌─────────────────────────────────────────────────────────────────┐
│                Morph Target Optimization                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. 희소 저장 (Sparse Storage):                                 │
│     ┌────────────────────────────────────────────────────┐     │
│     │ 모든 버텍스 저장 ✗ → 변경된 버텍스만 저장 ✓        │     │
│     │                                                     │     │
│     │ 50,000 vertices × 100 morphs = 500만 개 ✗          │     │
│     │ 평균 500 affected × 100 morphs = 5만 개 ✓          │     │
│     └────────────────────────────────────────────────────┘     │
│                                                                 │
│  2. GPU 배치 처리:                                              │
│     ┌────────────────────────────────────────────────────┐     │
│     │ 모든 활성 모프를 단일 컴퓨트 패스로 처리            │     │
│     │ Indirect Dispatch로 실제 영향받는 버텍스만 처리     │     │
│     └────────────────────────────────────────────────────┘     │
│                                                                 │
│  3. LOD 기반 최적화:                                            │
│     ┌────────────────────────────────────────────────────┐     │
│     │ 거리에 따라 페이셜 모프 타겟 비활성화               │     │
│     │ LOD 2+: 표정 단순화 (주요 AU만 사용)               │     │
│     └────────────────────────────────────────────────────┘     │
│                                                                 │
│  4. 델타 압축:                                                  │
│     ┌────────────────────────────────────────────────────┐     │
│     │ Float32 → Half (16bit)                             │     │
│     │ 작은 델타 제거 (threshold < 0.001)                 │     │
│     └────────────────────────────────────────────────────┘     │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 최적화 코드

```cpp
// 모프 타겟 LOD 설정
void ConfigureMorphTargetLOD(USkeletalMeshComponent* Mesh)
{
    // LOD별 모프 타겟 활성화
    struct FMorphLODConfig
    {
        int32 LODLevel;
        TArray<FName> ActiveMorphs;
    };

    TArray<FMorphLODConfig> LODConfigs = {
        { 0, { /* 모든 모프 */ } },
        { 1, { TEXT("browInnerUp"), TEXT("eyeBlinkLeft"),
               TEXT("eyeBlinkRight"), TEXT("mouthSmile") } },
        { 2, { TEXT("eyeBlinkLeft"), TEXT("eyeBlinkRight") } },
        { 3, { /* 모프 없음 */ } }
    };

    int32 CurrentLOD = Mesh->GetPredictedLODLevel();

    // 현재 LOD에 맞는 모프만 활성화
    for (const FMorphLODConfig& Config : LODConfigs)
    {
        if (CurrentLOD == Config.LODLevel)
        {
            SetActiveMorphTargets(Mesh, Config.ActiveMorphs);
            break;
        }
    }
}

// 델타 임계값 적용
void CompressMorphTargetDeltas(
    TArray<FMorphTargetDelta>& Deltas,
    float Threshold = 0.001f)
{
    Deltas.RemoveAll([Threshold](const FMorphTargetDelta& Delta)
    {
        return Delta.PositionDelta.Size() < Threshold &&
               Delta.TangentZDelta.Size() < Threshold;
    });
}
```

---

## 참고 자료

- [Morph Target Documentation](https://docs.unrealengine.com/morph-targets/)
- [MetaHuman Documentation](https://docs.metahuman.unrealengine.com/)
- [FACS - Facial Action Coding System](https://en.wikipedia.org/wiki/Facial_Action_Coding_System)
- [OVR LipSync](https://developer.oculus.com/documentation/native/audio-ovrlipsync-native/)
