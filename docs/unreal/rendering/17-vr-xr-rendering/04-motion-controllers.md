# 모션 컨트롤러

VR 모션 컨트롤러와 핸드 트래킹의 렌더링 및 인터랙션을 분석합니다.

---

## 모션 컨트롤러 시스템

### 트래킹 구조

```
┌─────────────────────────────────────────────────────────────────┐
│                  Motion Controller 트래킹                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  트래킹 데이터:                                                  │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                          │   │
│  │     Controller                                           │   │
│  │        ╭───╮                                            │   │
│  │        │   │ ← Position (X, Y, Z)                       │   │
│  │        │ ◎ │ ← Orientation (Pitch, Yaw, Roll)           │   │
│  │        │   │                                            │   │
│  │        ╰─┬─╯                                            │   │
│  │          │                                              │   │
│  │          ▼                                              │   │
│  │     ┌─────────────────────────────────────────────┐    │   │
│  │     │  Tracking Data (per frame)                  │    │   │
│  │     │  • Position: FVector                        │    │   │
│  │     │  • Orientation: FQuat                       │    │   │
│  │     │  • Linear Velocity: FVector                 │    │   │
│  │     │  • Angular Velocity: FVector                │    │   │
│  │     │  • Tracking Status: Valid/Lost              │    │   │
│  │     └─────────────────────────────────────────────┘    │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  업데이트 빈도:                                                  │
│  • 컨트롤러 센서: 250-1000 Hz                                  │
│  • 게임 업데이트: 72-120 Hz (디스플레이 동기)                   │
│  • 예측 보간: 필요 시 적용                                      │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### UE 컴포넌트

```cpp
// Motion Controller Component
UPROPERTY(VisibleAnywhere)
UMotionControllerComponent* LeftController;

UPROPERTY(VisibleAnywhere)
UMotionControllerComponent* RightController;

void SetupMotionControllers()
{
    // 왼손 컨트롤러
    LeftController = CreateDefaultSubobject<UMotionControllerComponent>("LeftController");
    LeftController->SetTrackingSource(EControllerHand::Left);
    LeftController->SetTrackingMotionSource(FName("Left"));

    // 오른손 컨트롤러
    RightController = CreateDefaultSubobject<UMotionControllerComponent>("RightController");
    RightController->SetTrackingSource(EControllerHand::Right);
    RightController->SetTrackingMotionSource(FName("Right"));

    // 트래킹 설정
    LeftController->bDisplayDeviceModel = true;  // 컨트롤러 메시 표시
    LeftController->DisplayModelSource = FName("OpenXR");  // 시스템 모델 사용
}

// 컨트롤러 위치 쿼리
FVector GetControllerLocation(EControllerHand Hand)
{
    UMotionControllerComponent* Controller =
        (Hand == EControllerHand::Left) ? LeftController : RightController;

    return Controller->GetComponentLocation();
}
```

---

## 핸드 트래킹

### 손 골격 데이터

```
┌─────────────────────────────────────────────────────────────────┐
│                    Hand Tracking 구조                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  손 골격 (26 조인트):                                            │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                          │   │
│  │         Index    Middle   Ring    Pinky                 │   │
│  │           │        │       │        │                   │   │
│  │          ┌┴┐      ┌┴┐     ┌┴┐      ┌┴┐   ← Tip        │   │
│  │          │ │      │ │     │ │      │ │                  │   │
│  │          ├─┤      ├─┤     ├─┤      ├─┤   ← Distal     │   │
│  │          │ │      │ │     │ │      │ │                  │   │
│  │          ├─┤      ├─┤     ├─┤      ├─┤   ← Intermediate│   │
│  │          │ │      │ │     │ │      │ │                  │   │
│  │          └┬┘      └┬┘     └┬┘      └┬┘   ← Proximal   │   │
│  │    Thumb  │        │       │        │                   │   │
│  │      ┌┐   └────────┴───────┴────────┘   ← Metacarpal  │   │
│  │      ││                                                 │   │
│  │      ├┤        ┌─────┐                                 │   │
│  │      ││        │Wrist│   ← Wrist                       │   │
│  │      └┘        └─────┘                                 │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  조인트 데이터:                                                  │
│  • Position: 월드 또는 로컬 공간                               │
│  • Rotation: 조인트 방향                                       │
│  • Radius: 조인트 크기 (충돌용)                                │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 핸드 트래킹 구현

```cpp
// 손 트래킹 데이터 접근
class UHandTrackingComponent : public UActorComponent
{
    void UpdateHandTracking()
    {
        IHandTracker* HandTracker = GetHandTracker();

        if (HandTracker && HandTracker->IsHandTrackingStateValid())
        {
            // 왼손 데이터
            FXRMotionControllerState LeftHandState;
            HandTracker->GetMotionControllerState(
                EControllerHand::Left,
                LeftHandState);

            // 손가락별 조인트 위치
            TArray<FTransform> LeftHandJoints;
            HandTracker->GetAllHandJointTransforms(
                EControllerHand::Left,
                LeftHandJoints);

            // 손 메시 업데이트
            UpdateHandMesh(LeftHandJoints);
        }
    }

    void UpdateHandMesh(const TArray<FTransform>& Joints)
    {
        // 스키닝된 메시 업데이트
        for (int32 i = 0; i < Joints.Num(); i++)
        {
            FName BoneName = GetBoneNameForJoint(i);
            HandMesh->SetBoneTransformByName(
                BoneName,
                Joints[i],
                EBoneSpaces::WorldSpace);
        }
    }
};

// 제스처 인식
bool DetectPinchGesture(EControllerHand Hand)
{
    FVector ThumbTip = GetJointPosition(Hand, EHandJoint::ThumbTip);
    FVector IndexTip = GetJointPosition(Hand, EHandJoint::IndexTip);

    float Distance = FVector::Dist(ThumbTip, IndexTip);

    return Distance < PinchThreshold;  // 예: 2cm
}
```

---

## 컨트롤러 렌더링

### 컨트롤러 메시

```
┌─────────────────────────────────────────────────────────────────┐
│                  Controller Rendering Options                    │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. 시스템 컨트롤러 모델                                         │
│     ┌─────────────────────────────────────────────────────┐    │
│     │ • 런타임에서 제공하는 실제 컨트롤러 메시              │    │
│     │ • 자동으로 디바이스에 맞는 모델 로드                  │    │
│     │ • DisplayModelSource = "OpenXR" 또는 "OculusXR"      │    │
│     └─────────────────────────────────────────────────────┘    │
│                                                                 │
│  2. 커스텀 컨트롤러 모델                                         │
│     ┌─────────────────────────────────────────────────────┐    │
│     │ • 게임 스타일에 맞는 커스텀 메시                      │    │
│     │ • 예: 손, 무기, 도구                                  │    │
│     │ • CustomDisplayMesh 사용                              │    │
│     └─────────────────────────────────────────────────────┘    │
│                                                                 │
│  3. 손 메시 (핸드 트래킹)                                       │
│     ┌─────────────────────────────────────────────────────┐    │
│     │ • 스키닝된 손 메시                                    │    │
│     │ • 조인트 트래킹 데이터로 애니메이션                   │    │
│     │ • 리얼리즘 또는 스타일라이즈드                        │    │
│     └─────────────────────────────────────────────────────┘    │
│                                                                 │
│  4. 투명 / 없음                                                  │
│     ┌─────────────────────────────────────────────────────┐    │
│     │ • 포인터/커서만 표시                                  │    │
│     │ • 최소 오버헤드                                       │    │
│     │ • 특정 게임 스타일                                    │    │
│     └─────────────────────────────────────────────────────┘    │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 포인터/레이캐스트

```cpp
// VR 포인터 구현
class UVRPointerComponent : public USceneComponent
{
    // 포인터 라인
    UPROPERTY(VisibleAnywhere)
    USplineMeshComponent* PointerMesh;

    // 히트 포인트
    UPROPERTY(VisibleAnywhere)
    UStaticMeshComponent* HitIndicator;

    void UpdatePointer()
    {
        FVector Start = GetComponentLocation();
        FVector Direction = GetForwardVector();

        // 레이캐스트
        FHitResult HitResult;
        bool bHit = GetWorld()->LineTraceSingleByChannel(
            HitResult,
            Start,
            Start + Direction * MaxPointerDistance,
            ECC_Visibility);

        if (bHit)
        {
            // 직선 포인터
            UpdateStraightPointer(Start, HitResult.Location);

            // 히트 인디케이터
            HitIndicator->SetWorldLocation(HitResult.Location);
            HitIndicator->SetWorldRotation(HitResult.Normal.Rotation());
            HitIndicator->SetVisibility(true);
        }
        else
        {
            // 최대 거리까지 포인터
            UpdateStraightPointer(Start, Start + Direction * MaxPointerDistance);
            HitIndicator->SetVisibility(false);
        }
    }

    // 곡선 포인터 (텔레포트용)
    void UpdateCurvedPointer(
        FVector Start,
        FVector Velocity,
        float Gravity)
    {
        TArray<FVector> PathPoints;

        // 포물선 궤적 계산
        FVector CurrentPos = Start;
        FVector CurrentVel = Velocity;
        float TimeStep = 0.02f;

        for (int i = 0; i < MaxPathPoints; i++)
        {
            PathPoints.Add(CurrentPos);

            // 중력 적용
            CurrentVel += FVector(0, 0, -Gravity) * TimeStep;
            CurrentPos += CurrentVel * TimeStep;

            // 충돌 체크
            if (CurrentPos.Z < FloorHeight)
                break;
        }

        // 스플라인 업데이트
        UpdateSplineMesh(PathPoints);
    }
};
```

---

## 햅틱 피드백

### 햅틱 시스템

```cpp
// 햅틱 피드백 구현
class UVRHapticComponent : public UActorComponent
{
    // 단순 햅틱
    void PlayHapticPulse(
        EControllerHand Hand,
        float Intensity,
        float Duration)
    {
        APlayerController* PC = GetPlayerController();
        if (PC)
        {
            PC->PlayHapticEffect(
                HapticEffect,
                Hand,
                Intensity,
                false);
        }
    }

    // 고급 햅틱 (파형)
    void PlayHapticWaveform(
        EControllerHand Hand,
        UCurveFloat* AmplitudeCurve,
        UCurveFloat* FrequencyCurve,
        float Duration)
    {
        // OpenXR 햅틱 API
        XrHapticVibration Vibration = {};
        Vibration.type = XR_TYPE_HAPTIC_VIBRATION;
        Vibration.amplitude = AmplitudeCurve->GetFloatValue(CurrentTime);
        Vibration.frequency = FrequencyCurve->GetFloatValue(CurrentTime);
        Vibration.duration = XR_MIN_HAPTIC_DURATION;

        xrApplyHapticFeedback(
            Session,
            GetHandPath(Hand),
            &Vibration);
    }
};

// 햅틱 패턴 예시
void CreateImpactHaptic()
{
    // 충돌 시 강한 단발
    PlayHapticPulse(EControllerHand::Right, 1.0f, 0.1f);
}

void CreateContinuousHaptic()
{
    // 지속적인 진동 (예: 총 연사)
    FHapticFeedbackEffect_Curve* Effect = NewObject<FHapticFeedbackEffect_Curve>();
    Effect->HapticDetails.Amplitude.ExternalCurve = AmplitudeCurve;
    Effect->HapticDetails.Frequency.ExternalCurve = FrequencyCurve;

    GetPlayerController()->PlayDynamicForceFeedback(
        1.0f,    // Intensity
        0.5f,    // Duration
        true,    // AffectsLeft
        true,    // AffectsRight
        false,   // Looping
        Effect);
}
```

---

## 인터랙션 시스템

### 그랩 시스템

```
┌─────────────────────────────────────────────────────────────────┐
│                    VR Grab System                                │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  그랩 타입:                                                      │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                          │   │
│  │  1. Snap Grab (스냅)                                    │   │
│  │     ┌─────┐        ┌─────┐                              │   │
│  │     │ ╭─╮ │   →    │╭───╮│  오브젝트가 손에 스냅       │   │
│  │     │ │◯│ │        ││ ◯ ││  정해진 그립 포인트         │   │
│  │     │ ╰─╯ │        │╰───╯│                              │   │
│  │     └─────┘        └─────┘                              │   │
│  │                                                          │   │
│  │  2. Physics Grab (물리)                                 │   │
│  │     ┌─────┐        ┌─────┐                              │   │
│  │     │ ╭─╮ │   →    │ ╭◯╮ │  물리 시뮬레이션            │   │
│  │     │ │◯│ │        │ │ │ │  컨스트레인트 기반          │   │
│  │     │ ╰─╯ │        │ ╰─╯ │                              │   │
│  │     └─────┘        └─────┘                              │   │
│  │                                                          │   │
│  │  3. Attach Grab (부착)                                  │   │
│  │     ┌─────┐        ┌─────┐                              │   │
│  │     │ ╭─╮ │   →    │ ╭─╮ │  단순 부착                  │   │
│  │     │ │◯│ │        │ │◯│ │  물리 없음                  │   │
│  │     │ ╰─╯ │        │ ╰─◯╯ │                              │   │
│  │     └─────┘        └─────┘                              │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 그랩 구현

```cpp
// 그랩 인터페이스
class IVRGrabbable
{
    virtual void OnGrabbed(UMotionControllerComponent* Controller) = 0;
    virtual void OnReleased() = 0;
    virtual FTransform GetGrabTransform() = 0;
};

// 그랩 컴포넌트
class UVRGrabComponent : public UActorComponent
{
    // 그랩 검사
    void CheckForGrabbable()
    {
        // 오버랩 검사
        TArray<AActor*> OverlappingActors;
        GrabSphere->GetOverlappingActors(OverlappingActors);

        for (AActor* Actor : OverlappingActors)
        {
            if (Actor->Implements<UVRGrabbable>())
            {
                NearestGrabbable = Actor;
                break;
            }
        }
    }

    // 그랩 실행
    void GrabObject()
    {
        if (NearestGrabbable)
        {
            IVRGrabbable* Grabbable = Cast<IVRGrabbable>(NearestGrabbable);

            // 그랩 트랜스폼 가져오기
            FTransform GrabTransform = Grabbable->GetGrabTransform();

            // 물리 그랩 설정
            FPhysicsConstraintHandle Constraint;
            SetupGrabConstraint(NearestGrabbable, GrabTransform, Constraint);

            // 콜백
            Grabbable->OnGrabbed(MotionController);

            // 햅틱
            PlayHapticPulse(EControllerHand::Right, 0.5f, 0.1f);
        }
    }
};
```

---

## 성능 고려사항

### 컨트롤러 렌더링 최적화

```
┌─────────────────────────────────────────────────────────────────┐
│                  Controller Rendering 최적화                     │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  메시 최적화                                                     │
│  □ 컨트롤러/손 메시 LOD 설정                                    │
│  □ 폴리곤 수 최소화 (손: ~3000 tris)                           │
│  □ 단일 머티리얼 사용                                           │
│                                                                 │
│  업데이트 최적화                                                  │
│  □ 가시성 컬링 (화면 밖 컨트롤러)                               │
│  □ 업데이트 빈도 조절 (먼 거리에서)                             │
│  □ 본 업데이트 최적화 (핸드 트래킹)                             │
│                                                                 │
│  물리 최적화                                                     │
│  □ 단순화된 콜리전 볼륨                                         │
│  □ 스윕 검사 최소화                                             │
│  □ 물리 업데이트 빈도 조절                                      │
│                                                                 │
│  포인터/인터랙션 최적화                                          │
│  □ 레이캐스트 빈도 제한                                         │
│  □ 단순화된 콜리전 채널                                         │
│  □ 공간 분할 활용                                               │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 다음 단계

- [AR/MR 렌더링](05-ar-mr-rendering.md)에서 증강/혼합 현실 렌더링을 학습합니다.
