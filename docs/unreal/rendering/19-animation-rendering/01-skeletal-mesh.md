# 스켈레탈 메시 렌더링

스켈레탈 메시의 구조, 본 트랜스폼 계산, GPU 스키닝을 분석합니다.

---

## 스켈레탈 메시 구조

### 메시 데이터 구조

```
┌─────────────────────────────────────────────────────────────────┐
│                  Skeletal Mesh Data Structure                   │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  USkeletalMesh:                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                          │   │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐      │   │
│  │  │  Skeleton   │  │  LOD Data   │  │  Materials  │      │   │
│  │  │  Reference  │  │  Array      │  │  Array      │      │   │
│  │  └──────┬──────┘  └──────┬──────┘  └─────────────┘      │   │
│  │         │                │                               │   │
│  │         ▼                ▼                               │   │
│  │  ┌─────────────┐  ┌─────────────────────────────────┐   │   │
│  │  │ USkeleton   │  │  FSkeletalMeshLODRenderData     │   │   │
│  │  │             │  │  ┌─────────────────────────┐    │   │   │
│  │  │ • BoneTree  │  │  │ RenderSections[]        │    │   │   │
│  │  │ • RefPose   │  │  │ StaticVertexBuffers     │    │   │   │
│  │  │ • Sockets   │  │  │ SkinWeightVertexBuffer  │    │   │   │
│  │  │             │  │  │ MorphTargetVertexInfos  │    │   │   │
│  │  └─────────────┘  │  │ ClothVertexBuffer       │    │   │   │
│  │                   │  └─────────────────────────┘    │   │   │
│  │                   └─────────────────────────────────┘   │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 버텍스 데이터

```cpp
// 스켈레탈 메시 버텍스 구조
struct FSoftSkinVertex
{
    FVector Position;           // 로컬 위치
    FVector TangentX;           // 탄젠트 X
    FVector TangentY;           // 탄젠트 Y (비노말)
    FVector TangentZ;           // 노말
    FVector2D UVs[MAX_TEXCOORDS]; // UV 좌표
    FColor Color;               // 버텍스 컬러

    // 스킨 웨이트 (최대 8개 본 영향)
    uint8 InfluenceBones[MAX_TOTAL_INFLUENCES];
    uint8 InfluenceWeights[MAX_TOTAL_INFLUENCES];
};

// GPU 스키닝용 압축 포맷
struct FGPUSkinVertexBase
{
    // 패킹된 탄젠트 (8바이트)
    FPackedNormal TangentX;
    FPackedNormal TangentZ;
};

struct FSkinWeightInfo
{
    // 본 인덱스와 웨이트 (8바이트)
    uint8 InfluenceBones[4];
    uint8 InfluenceWeights[4];
};
```

---

## 본 트랜스폼 계산

### 본 계층 구조

```
┌─────────────────────────────────────────────────────────────────┐
│                     Bone Hierarchy                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  트랜스폼 계산 순서:                                            │
│                                                                 │
│  Root (0)                                                       │
│  ├── Pelvis (1)                                                 │
│  │   ├── Spine_01 (2)                                          │
│  │   │   ├── Spine_02 (3)                                      │
│  │   │   │   ├── Spine_03 (4)                                  │
│  │   │   │   │   ├── Clavicle_L (5)                            │
│  │   │   │   │   │   └── UpperArm_L (6)                        │
│  │   │   │   │   │       └── LowerArm_L (7)                    │
│  │   │   │   │   │           └── Hand_L (8)                    │
│  │   │   │   │   ├── Clavicle_R (9)                            │
│  │   │   │   │   │   └── ...                                   │
│  │   │   │   │   └── Neck (15)                                 │
│  │   │   │   │       └── Head (16)                             │
│  │   ├── Thigh_L (20)                                          │
│  │   │   └── Calf_L (21)                                       │
│  │   │       └── Foot_L (22)                                   │
│  │   └── Thigh_R (25)                                          │
│  │       └── ...                                               │
│                                                                 │
│  WorldTransform[i] = ParentWorldTransform × LocalTransform[i]  │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 트랜스폼 계산 코드

```cpp
// 본 트랜스폼 계산
void FAnimationRuntime::FillUpComponentSpaceTransforms(
    const FReferenceSkeleton& RefSkeleton,
    const TArray<FTransform>& LocalTransforms,
    TArray<FTransform>& ComponentSpaceTransforms)
{
    const int32 NumBones = RefSkeleton.GetNum();

    for (int32 BoneIndex = 0; BoneIndex < NumBones; ++BoneIndex)
    {
        const int32 ParentIndex = RefSkeleton.GetParentIndex(BoneIndex);

        if (ParentIndex != INDEX_NONE)
        {
            // 부모의 월드 트랜스폼 × 로컬 트랜스폼
            ComponentSpaceTransforms[BoneIndex] =
                LocalTransforms[BoneIndex] *
                ComponentSpaceTransforms[ParentIndex];
        }
        else
        {
            // 루트 본
            ComponentSpaceTransforms[BoneIndex] = LocalTransforms[BoneIndex];
        }
    }
}

// 스키닝 행렬 계산
void ComputeSkinningMatrices(
    const TArray<FTransform>& ComponentSpaceTransforms,
    const TArray<FMatrix>& RefBasesInvMatrix,
    TArray<FMatrix>& SkinningMatrices)
{
    for (int32 BoneIndex = 0; BoneIndex < NumBones; ++BoneIndex)
    {
        // 스키닝 행렬 = 현재 월드 × 레퍼런스 역행렬
        SkinningMatrices[BoneIndex] =
            RefBasesInvMatrix[BoneIndex] *
            ComponentSpaceTransforms[BoneIndex].ToMatrixWithScale();
    }
}
```

---

## GPU 스키닝

### 스키닝 파이프라인

```
┌─────────────────────────────────────────────────────────────────┐
│                     GPU Skinning Pipeline                       │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  CPU 측:                                                        │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  1. Animation Evaluation                                 │   │
│  │     ┌────────────┐    ┌────────────┐    ┌────────────┐  │   │
│  │     │ Bone Local │ →  │ Component  │ →  │ Skinning   │  │   │
│  │     │ Transforms │    │ Space      │    │ Matrices   │  │   │
│  │     └────────────┘    └────────────┘    └────────────┘  │   │
│  └─────────────────────────────────────────────────────────┘   │
│                              │                                  │
│                              ▼ (Bone Buffer Upload)             │
│  GPU 측:                                                        │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  2. Vertex Shader Skinning                               │   │
│  │                                                          │   │
│  │  for each vertex:                                        │   │
│  │    skinnedPos = 0                                        │   │
│  │    for each influence (up to 4/8):                       │   │
│  │      boneMatrix = BoneMatrices[boneIndex]                │   │
│  │      skinnedPos += (boneMatrix × position) × weight      │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 버텍스 셰이더 스키닝

```hlsl
// GPU 스키닝 버텍스 셰이더
float4x4 CalcBoneMatrix(FVertexFactoryInput Input)
{
    float4x4 BoneMatrix = float4x4(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0);

    // 4개 본 영향 (기본)
    UNROLL
    for (int i = 0; i < 4; i++)
    {
        int BoneIndex = Input.BlendIndices[i];
        float Weight = Input.BlendWeights[i];

        BoneMatrix += BoneMatrices[BoneIndex] * Weight;
    }

    // 추가 4개 본 (8본 스키닝)
    #if GPUSKIN_UNLIMITED_BONE_INFLUENCE
    UNROLL
    for (int i = 4; i < 8; i++)
    {
        int BoneIndex = Input.BlendIndicesExtra[i-4];
        float Weight = Input.BlendWeightsExtra[i-4];

        BoneMatrix += BoneMatrices[BoneIndex] * Weight;
    }
    #endif

    return BoneMatrix;
}

void SkinPosition(
    FVertexFactoryInput Input,
    out float3 OutPosition,
    out float3 OutTangentX,
    out float3 OutTangentZ)
{
    float4x4 BoneMatrix = CalcBoneMatrix(Input);

    // 위치 변환
    OutPosition = mul(float4(Input.Position, 1), BoneMatrix).xyz;

    // 노말/탄젠트 변환 (역전치 행렬 사용)
    float3x3 BoneMatrix3x3 = (float3x3)BoneMatrix;
    OutTangentX = mul(Input.TangentX, BoneMatrix3x3);
    OutTangentZ = mul(Input.TangentZ, BoneMatrix3x3);
}
```

### 본 버퍼 관리

```cpp
// 본 행렬 버퍼
class FBoneBufferPool
{
    // 본 행렬 버퍼 (Structured Buffer)
    FStructuredBufferRHIRef BoneMatrixBuffer;

    // 버퍼 업데이트
    void UpdateBoneData(
        const TArray<FMatrix>& SkinningMatrices,
        FRHICommandList& RHICmdList)
    {
        // 3x4 행렬로 압축 (열 기준)
        TArray<FMatrix3x4> PackedMatrices;
        PackedMatrices.SetNum(SkinningMatrices.Num());

        for (int32 i = 0; i < SkinningMatrices.Num(); ++i)
        {
            // 4x4 → 3x4 변환 (마지막 행 생략)
            PackedMatrices[i] = FMatrix3x4(SkinningMatrices[i]);
        }

        // GPU 버퍼 업데이트
        void* Data = RHILockBuffer(
            BoneMatrixBuffer,
            0,
            PackedMatrices.Num() * sizeof(FMatrix3x4),
            RLM_WriteOnly);

        FMemory::Memcpy(Data, PackedMatrices.GetData(),
            PackedMatrices.Num() * sizeof(FMatrix3x4));

        RHIUnlockBuffer(BoneMatrixBuffer);
    }
};

// 3x4 행렬 구조 (48바이트 vs 64바이트)
struct FMatrix3x4
{
    float M[3][4];  // Row 0-2, Column 0-3

    FMatrix3x4(const FMatrix& Mat)
    {
        M[0][0] = Mat.M[0][0]; M[0][1] = Mat.M[0][1];
        M[0][2] = Mat.M[0][2]; M[0][3] = Mat.M[0][3];
        M[1][0] = Mat.M[1][0]; M[1][1] = Mat.M[1][1];
        M[1][2] = Mat.M[1][2]; M[1][3] = Mat.M[1][3];
        M[2][0] = Mat.M[2][0]; M[2][1] = Mat.M[2][1];
        M[2][2] = Mat.M[2][2]; M[2][3] = Mat.M[2][3];
    }
};
```

---

## LOD 시스템

### 스켈레탈 메시 LOD

```
┌─────────────────────────────────────────────────────────────────┐
│                  Skeletal Mesh LOD System                       │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  LOD 레벨:                                                      │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                          │   │
│  │  LOD 0 (Highest)     LOD 1           LOD 2    LOD 3     │   │
│  │  ┌──────────┐       ┌──────────┐   ┌──────┐  ┌────┐     │   │
│  │  │ 50,000   │       │ 20,000   │   │ 5,000│  │1,000│    │   │
│  │  │ vertices │       │ vertices │   │ verts│  │verts│    │   │
│  │  │          │       │          │   │      │  │    │     │   │
│  │  │ 100 bones│       │ 80 bones │   │50bone│  │30bone│   │   │
│  │  └──────────┘       └──────────┘   └──────┘  └────┘     │   │
│  │                                                          │   │
│  │  Distance:  0-10m      10-30m       30-70m    70m+       │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  LOD 선택 기준:                                                 │
│  • Screen Size (화면 차지 비율)                                 │
│  • Distance (카메라 거리)                                       │
│  • Forced LOD (강제 지정)                                       │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### LOD 설정

```cpp
// 스켈레탈 메시 LOD 설정
UPROPERTY(EditAnywhere)
TArray<FSkeletalMeshLODInfo> LODInfo;

struct FSkeletalMeshLODInfo
{
    // 화면 크기 임계값
    FPerPlatformFloat ScreenSize;

    // LOD 히스테리시스
    float LODHysteresis;

    // 본 리덕션 설정
    TArray<FBoneReference> BonesToRemove;

    // 버텍스 리덕션
    float ReductionSettings;

    // 섹션별 설정
    TArray<FSkelMeshMergeSectionMapping> SectionMapping;
};

// LOD 선택 로직
int32 USkeletalMeshComponent::ComputeDesiredLOD() const
{
    // 화면 크기 계산
    float ScreenSize = ComputeBoundsScreenSize(
        Bounds.Origin,
        Bounds.SphereRadius,
        ViewLocation,
        ViewProjectionMatrix);

    // LOD 결정
    const int32 NumLODs = SkeletalMesh->GetLODNum();
    for (int32 LODIndex = 0; LODIndex < NumLODs - 1; ++LODIndex)
    {
        float LODScreenSize = SkeletalMesh->GetLODInfo(LODIndex).ScreenSize;
        if (ScreenSize >= LODScreenSize)
        {
            return LODIndex;
        }
    }

    return NumLODs - 1;
}
```

---

## 스키닝 최적화

### 최적화 기법

```
┌─────────────────────────────────────────────────────────────────┐
│                  Skinning Optimization                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. 본 영향 수 제한:                                            │
│     ┌────────────────────────────────────────────────────┐     │
│     │ 4 Bones/Vertex (기본)  → 저사양 하드웨어            │     │
│     │ 8 Bones/Vertex         → 고품질 캐릭터              │     │
│     │ Unlimited              → 특수 케이스               │     │
│     └────────────────────────────────────────────────────┘     │
│                                                                 │
│  2. 본 행렬 압축:                                               │
│     ┌────────────────────────────────────────────────────┐     │
│     │ 4x4 Matrix (64 bytes) → 3x4 Matrix (48 bytes)      │     │
│     │ 또는 Dual Quaternion (32 bytes)                    │     │
│     └────────────────────────────────────────────────────┘     │
│                                                                 │
│  3. 본 LOD:                                                     │
│     ┌────────────────────────────────────────────────────┐     │
│     │ 거리에 따라 사용하는 본 수 감소                     │     │
│     │ 손가락, 페이셜 본 등 제거                          │     │
│     └────────────────────────────────────────────────────┘     │
│                                                                 │
│  4. 컴퓨트 셰이더 스키닝:                                       │
│     ┌────────────────────────────────────────────────────┐     │
│     │ 버텍스 셰이더 대신 컴퓨트 셰이더로 스키닝           │     │
│     │ → 결과를 버텍스 버퍼에 저장하여 재사용              │     │
│     └────────────────────────────────────────────────────┘     │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 듀얼 쿼터니언 스키닝

```hlsl
// Dual Quaternion Skinning
// 볼륨 보존이 더 좋음 (캔디 래퍼 문제 해결)

struct DualQuaternion
{
    float4 Real;  // 회전
    float4 Dual;  // 이동
};

float4x4 DQToMatrix(DualQuaternion DQ)
{
    float4 r = DQ.Real;
    float4 d = DQ.Dual;

    // 회전 행렬
    float3x3 rotMat = QuatToMatrix(r);

    // 이동 벡터
    float3 trans = 2.0 * (r.w * d.xyz - d.w * r.xyz +
                          cross(r.xyz, d.xyz));

    return float4x4(
        rotMat[0], 0,
        rotMat[1], 0,
        rotMat[2], 0,
        trans, 1);
}

void DualQuaternionSkinning(
    FVertexFactoryInput Input,
    out float3 OutPosition,
    out float3 OutNormal)
{
    DualQuaternion BlendDQ = (DualQuaternion)0;

    // DQ 블렌딩
    for (int i = 0; i < 4; i++)
    {
        int BoneIndex = Input.BlendIndices[i];
        float Weight = Input.BlendWeights[i];

        DualQuaternion BoneDQ = BoneDualQuaternions[BoneIndex];

        // 안티포달 처리 (최단 경로)
        if (dot(BlendDQ.Real, BoneDQ.Real) < 0)
        {
            BoneDQ.Real = -BoneDQ.Real;
            BoneDQ.Dual = -BoneDQ.Dual;
        }

        BlendDQ.Real += BoneDQ.Real * Weight;
        BlendDQ.Dual += BoneDQ.Dual * Weight;
    }

    // 정규화
    float norm = length(BlendDQ.Real);
    BlendDQ.Real /= norm;
    BlendDQ.Dual /= norm;

    // 변환 적용
    float4x4 SkinMatrix = DQToMatrix(BlendDQ);
    OutPosition = mul(float4(Input.Position, 1), SkinMatrix).xyz;
    OutNormal = mul(Input.Normal, (float3x3)SkinMatrix);
}
```

---

## 참고 자료

- [Skeletal Mesh Overview](https://docs.unrealengine.com/skeletal-mesh/)
- [GPU Skinning](https://docs.unrealengine.com/gpu-skinning/)
- [Dual Quaternion Skinning](https://www.cs.utah.edu/~ladislav/kavan08geometric/kavan08geometric.html)
