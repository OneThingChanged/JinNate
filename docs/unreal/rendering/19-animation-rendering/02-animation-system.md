# 애니메이션 시스템

Animation Blueprint, Blend Space, State Machine, 애니메이션 압축을 분석합니다.

---

## Animation Blueprint

### 아키텍처 개요

```
┌─────────────────────────────────────────────────────────────────┐
│                  Animation Blueprint Architecture               │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                   UAnimInstance                          │   │
│  ├─────────────────────────────────────────────────────────┤   │
│  │                                                          │   │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐      │   │
│  │  │  EventGraph │  │  AnimGraph  │  │  Variables  │      │   │
│  │  │             │  │             │  │             │      │   │
│  │  │ • BlueprintI│  │ • StateMach │  │ • Speed     │      │   │
│  │  │   nitialize │  │ • BlendSpace│  │ • Direction │      │   │
│  │  │ • BlueprintU│  │ • Montages  │  │ • IsJumping │      │   │
│  │  │   pdate     │  │ • IK Nodes  │  │ • IsFalling │      │   │
│  │  └─────────────┘  └─────────────┘  └─────────────┘      │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                              │                                  │
│                              ▼                                  │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                   Evaluation Flow                        │   │
│  │                                                          │   │
│  │  Update Phase:                                           │   │
│  │  Character → AnimInstance → Variables → AnimGraph        │   │
│  │                                                          │   │
│  │  Evaluate Phase:                                         │   │
│  │  AnimGraph → Pose Blending → Final Pose → Component      │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### AnimInstance 코드

```cpp
// 커스텀 AnimInstance
UCLASS()
class UMyAnimInstance : public UAnimInstance
{
    GENERATED_BODY()

public:
    // 매 프레임 업데이트
    virtual void NativeUpdateAnimation(float DeltaSeconds) override
    {
        Super::NativeUpdateAnimation(DeltaSeconds);

        // 캐릭터 레퍼런스
        APawn* Owner = TryGetPawnOwner();
        if (!Owner) return;

        // 속도 계산
        FVector Velocity = Owner->GetVelocity();
        Speed = Velocity.Size2D();

        // 방향 계산 (캐릭터 기준)
        if (Speed > 0.1f)
        {
            Direction = CalculateDirection(Velocity, Owner->GetActorRotation());
        }

        // 점프/낙하 상태
        if (ACharacter* Character = Cast<ACharacter>(Owner))
        {
            bIsJumping = Character->GetCharacterMovement()->IsFalling();
        }
    }

protected:
    UPROPERTY(BlueprintReadOnly, Category = "Animation")
    float Speed;

    UPROPERTY(BlueprintReadOnly, Category = "Animation")
    float Direction;

    UPROPERTY(BlueprintReadOnly, Category = "Animation")
    bool bIsJumping;
};
```

---

## Blend Space

### 1D/2D Blend Space

```
┌─────────────────────────────────────────────────────────────────┐
│                     Blend Space Types                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1D Blend Space (속도 기반):                                    │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                          │   │
│  │  Idle      Walk       Jog        Run        Sprint      │   │
│  │   ●─────────●──────────●──────────●──────────●          │   │
│  │   0        150        300        450        600         │   │
│  │                     Speed                                │   │
│  │                                                          │   │
│  │  현재 Speed = 250 → Walk와 Jog 블렌딩                    │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  2D Blend Space (속도 + 방향):                                  │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                          │   │
│  │           Forward (0°)                                   │   │
│  │               ●                                          │   │
│  │              /│\                                         │   │
│  │  Left      / │ \      Right                             │   │
│  │  (-90°) ●───●───● (90°)                                 │   │
│  │              │                                           │   │
│  │              ●                                           │   │
│  │         Backward (180°)                                  │   │
│  │                                                          │   │
│  │  X축: Direction (-180 ~ 180)                             │   │
│  │  Y축: Speed (0 ~ 600)                                    │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Blend Space 평가

```cpp
// Blend Space 평가 로직
void UBlendSpace::EvaluateBlendSpace(
    FVector BlendInput,        // (X, Y, Z) 입력 값
    TArray<FBlendSampleData>& OutSamples)
{
    // 입력 값 클램핑
    FVector ClampedInput = ClampBlendInput(BlendInput);

    // 샘플 가중치 계산
    TArray<FGridBlendSample> GridSamples;
    GetRawSamplesFromBlendInput(ClampedInput, GridSamples);

    // 삼각형 보간
    for (const FGridBlendSample& GridSample : GridSamples)
    {
        // Barycentric 좌표 계산
        FVector BarycentricCoords = CalculateBarycentricCoords(
            ClampedInput,
            GridSample.Triangle);

        // 각 샘플의 가중치
        for (int32 i = 0; i < 3; ++i)
        {
            FBlendSampleData SampleData;
            SampleData.Animation = GridSample.Samples[i].Animation;
            SampleData.Weight = BarycentricCoords[i];
            SampleData.Time = GetSampleTime(GridSample.Samples[i]);

            OutSamples.Add(SampleData);
        }
    }

    // 가중치 정규화
    NormalizeWeights(OutSamples);
}
```

---

## State Machine

### 상태 전이 그래프

```
┌─────────────────────────────────────────────────────────────────┐
│                    State Machine Graph                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                          │   │
│  │        ┌───────────────────────────────────┐            │   │
│  │        │            Locomotion              │            │   │
│  │        │         (Blend Space)              │            │   │
│  │        └───────────────┬───────────────────┘            │   │
│  │                        │                                 │   │
│  │         ┌──────────────┼──────────────┐                 │   │
│  │         │              │              │                 │   │
│  │   bIsJumping    Speed < 10    Attack Input              │   │
│  │         │              │              │                 │   │
│  │         ▼              ▼              ▼                 │   │
│  │  ┌───────────┐  ┌───────────┐  ┌───────────┐           │   │
│  │  │   Jump    │  │   Idle    │  │  Attack   │           │   │
│  │  │ (Montage) │  │ (Sequence)│  │ (Montage) │           │   │
│  │  └───────────┘  └───────────┘  └───────────┘           │   │
│  │         │              │              │                 │   │
│  │         └──────────────┴──────────────┘                 │   │
│  │                        │                                 │   │
│  │                   On Complete                            │   │
│  │                        │                                 │   │
│  │                        ▼                                 │   │
│  │                  Back to Locomotion                      │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 전이 규칙

```cpp
// State Machine 전이 규칙
USTRUCT()
struct FAnimationTransitionRule
{
    GENERATED_BODY()

    // 전이 조건
    UPROPERTY()
    FName SourceState;

    UPROPERTY()
    FName TargetState;

    // 블렌드 설정
    UPROPERTY()
    float BlendTime = 0.2f;

    UPROPERTY()
    EAlphaBlendOption BlendMode = EAlphaBlendOption::Linear;

    // 조건 체크
    bool CanTransition(const UAnimInstance* AnimInstance) const
    {
        // 블루프린트 조건 평가
        return EvaluateCondition(AnimInstance);
    }
};

// 상태 평가
void FAnimNode_StateMachine::Update_AnyThread(
    const FAnimationUpdateContext& Context)
{
    // 현재 상태 업데이트
    CurrentState->Update_AnyThread(Context);

    // 전이 체크
    for (const FAnimationTransitionRule& Rule : TransitionRules)
    {
        if (Rule.SourceState == CurrentStateName &&
            Rule.CanTransition(Context.AnimInstance))
        {
            // 전이 시작
            StartTransition(Rule);
            break;
        }
    }

    // 활성 전이 업데이트
    if (ActiveTransition.IsValid())
    {
        UpdateActiveTransition(Context.GetDeltaTime());
    }
}
```

---

## 애니메이션 압축

### 압축 알고리즘

```
┌─────────────────────────────────────────────────────────────────┐
│                  Animation Compression                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  원본 데이터:                                                   │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  각 본 × 각 프레임 × (Position + Rotation + Scale)      │   │
│  │  = 100 bones × 300 frames × (12 + 16 + 12) bytes       │   │
│  │  = 1,200,000 bytes (1.2 MB)                             │   │
│  └─────────────────────────────────────────────────────────┘   │
│                              │                                  │
│                              ▼                                  │
│  압축 기법:                                                     │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                          │   │
│  │  1. 키 제거 (Key Removal)                                │   │
│  │     • 변화가 없는 키 제거                                │   │
│  │     • 오차 임계값 기반                                   │   │
│  │                                                          │   │
│  │  2. 양자화 (Quantization)                                │   │
│  │     • Float32 → Fixed Point                             │   │
│  │     • 16bit, 8bit 정밀도                                 │   │
│  │                                                          │   │
│  │  3. 커브 피팅 (Curve Fitting)                            │   │
│  │     • 베지어 커브로 근사                                 │   │
│  │     • ACL (Animation Compression Library)               │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                              │                                  │
│                              ▼                                  │
│  압축 결과:                                                     │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  ~50-200 KB (압축률 85-95%)                              │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### ACL (Animation Compression Library)

```cpp
// ACL 압축 설정
UPROPERTY(EditAnywhere)
UAnimationCompressionSettings* CompressionSettings;

// ACL 설정 옵션
struct FACLCompressionSettings
{
    // 오차 임계값
    float TranslationErrorThreshold = 0.01f;  // cm
    float RotationErrorThreshold = 0.01f;     // degrees
    float ScaleErrorThreshold = 0.0001f;

    // 키프레임 샘플링
    float SampleRate = 30.0f;  // FPS

    // 양자화 비트 수
    int32 RotationBits = 16;
    int32 TranslationBits = 16;
    int32 ScaleBits = 16;
};

// 디코딩 (런타임)
void DecompressAnimation(
    const FCompressedAnimSequence& CompressedData,
    float Time,
    TArray<FTransform>& OutBonePoses)
{
    // ACL 디코더 사용
    acl::decompression_context<acl::default_transform_decompression_settings> Context;
    Context.initialize(CompressedData.ACLData, CompressedData.ACLDataSize);

    // 시간 설정
    Context.seek(Time, acl::sample_rounding_policy::none);

    // 각 본의 포즈 디코딩
    for (int32 BoneIndex = 0; BoneIndex < NumBones; ++BoneIndex)
    {
        acl::rtm::qvvf Pose;
        Context.decompress_bone(BoneIndex, &Pose);

        OutBonePoses[BoneIndex] = FTransform(
            FQuat(Pose.rotation),
            FVector(Pose.translation),
            FVector(Pose.scale));
    }
}
```

---

## 포즈 블렌딩

### 블렌딩 방식

```
┌─────────────────────────────────────────────────────────────────┐
│                     Pose Blending Methods                       │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. Linear Blend (선형 보간):                                   │
│     ┌────────────────────────────────────────────────────┐     │
│     │  Result = Pose_A × (1-α) + Pose_B × α              │     │
│     │                                                     │     │
│     │  Position: Lerp                                     │     │
│     │  Rotation: Slerp (Quaternion)                       │     │
│     │  Scale: Lerp                                        │     │
│     └────────────────────────────────────────────────────┘     │
│                                                                 │
│  2. Additive Blend (가산 블렌딩):                               │
│     ┌────────────────────────────────────────────────────┐     │
│     │  Result = Base_Pose + Additive_Pose × α            │     │
│     │                                                     │     │
│     │  사용: 호흡, 히트 리액션, 표정 등                   │     │
│     └────────────────────────────────────────────────────┘     │
│                                                                 │
│  3. Layered Blend (레이어 블렌딩):                              │
│     ┌────────────────────────────────────────────────────┐     │
│     │  하체: Locomotion                                   │     │
│     │  상체: Aiming/Attack                                │     │
│     │                                                     │     │
│     │  Blend by Bone: 특정 본 기준으로 분리               │     │
│     └────────────────────────────────────────────────────┘     │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 블렌딩 코드

```cpp
// 포즈 블렌딩
void BlendPoses(
    const FCompactPose& PoseA,
    const FCompactPose& PoseB,
    float BlendWeight,
    FCompactPose& OutPose)
{
    const FBoneContainer& BoneContainer = OutPose.GetBoneContainer();

    for (FCompactPoseBoneIndex BoneIndex : BoneContainer)
    {
        FTransform& OutTransform = OutPose[BoneIndex];
        const FTransform& TransformA = PoseA[BoneIndex];
        const FTransform& TransformB = PoseB[BoneIndex];

        // 위치 보간
        OutTransform.SetTranslation(
            FMath::Lerp(TransformA.GetTranslation(),
                        TransformB.GetTranslation(),
                        BlendWeight));

        // 회전 보간 (Slerp)
        OutTransform.SetRotation(
            FQuat::Slerp(TransformA.GetRotation(),
                         TransformB.GetRotation(),
                         BlendWeight));

        // 스케일 보간
        OutTransform.SetScale3D(
            FMath::Lerp(TransformA.GetScale3D(),
                        TransformB.GetScale3D(),
                        BlendWeight));
    }
}

// Additive 블렌딩
void ApplyAdditiveAnimation(
    FCompactPose& BasePose,
    const FCompactPose& AdditivePose,
    float AdditiveWeight)
{
    for (FCompactPoseBoneIndex BoneIndex : BasePose.GetBoneContainer())
    {
        FTransform& BaseTransform = BasePose[BoneIndex];
        const FTransform& AdditiveTransform = AdditivePose[BoneIndex];

        // Additive 적용
        FTransform BlendedAdditive = AdditiveTransform;
        BlendedAdditive.SetTranslation(
            AdditiveTransform.GetTranslation() * AdditiveWeight);
        BlendedAdditive.SetRotation(
            FQuat::FastLerp(FQuat::Identity,
                            AdditiveTransform.GetRotation(),
                            AdditiveWeight));

        // Base에 누적
        BaseTransform.AccumulateWithAdditiveScale(
            BlendedAdditive,
            AdditiveWeight);
    }
}
```

---

## 참고 자료

- [Animation Blueprint](https://docs.unrealengine.com/animation-blueprints/)
- [Blend Spaces](https://docs.unrealengine.com/blend-spaces/)
- [Animation Compression](https://docs.unrealengine.com/animation-compression/)
- [ACL Plugin](https://github.com/nfrechette/acl-ue4-plugin)
