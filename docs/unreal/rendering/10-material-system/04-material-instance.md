# 04. 머티리얼 인스턴스

머티리얼 인스턴스의 종류, 파라미터 시스템, 런타임 동작을 분석합니다.

---

## 인스턴스 개요

### 머티리얼 인스턴스란?

```
┌─────────────────────────────────────────────────────────────────┐
│                    머티리얼 인스턴스 개념                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  마스터 머티리얼:                                               │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  UMaterial "M_Character"                                │   │
│  │  ├── BaseColor = [TextureSample] × [VectorParam: Tint]  │   │
│  │  ├── Roughness = [ScalarParam: Roughness]               │   │
│  │  └── Normal = [TextureSample]                           │   │
│  │                                                         │   │
│  │  셰이더 컴파일 포함                                      │   │
│  └─────────────────────────────────────────────────────────┘   │
│                           │                                     │
│                           │ 인스턴스화                          │
│                           ▼                                     │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  UMaterialInstanceConstant "MI_Character_Red"          │   │
│  │  ├── Parent = M_Character                               │   │
│  │  ├── Tint = (1, 0, 0, 1)  ← 오버라이드                   │   │
│  │  └── Roughness = 0.3      ← 오버라이드                   │   │
│  │                                                         │   │
│  │  셰이더 재사용 (컴파일 없음!)                            │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  장점:                                                          │
│  - 메모리 절약 (셰이더 공유)                                   │
│  - 컴파일 시간 절약                                            │
│  - 배치 렌더링 최적화                                          │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 인스턴스 클래스 계층

```cpp
// 머티리얼 인터페이스 (추상)
class UMaterialInterface : public UObject
{
    // 공통 인터페이스
};

// 마스터 머티리얼
class UMaterial : public UMaterialInterface
{
    // 노드 그래프, 셰이더 컴파일
};

// 머티리얼 인스턴스 (추상)
class UMaterialInstance : public UMaterialInterface
{
    UPROPERTY()
    UMaterialInterface* Parent;  // 부모 머티리얼

    // 파라미터 오버라이드
    UPROPERTY()
    TArray<FScalarParameterValue> ScalarParameterValues;
    UPROPERTY()
    TArray<FVectorParameterValue> VectorParameterValues;
    UPROPERTY()
    TArray<FTextureParameterValue> TextureParameterValues;
    UPROPERTY()
    TArray<FStaticSwitchParameter> StaticParameters;
};

// 정적 머티리얼 인스턴스 (에디터 편집)
class UMaterialInstanceConstant : public UMaterialInstance
{
    // 에디터에서 생성, 에셋으로 저장
    // 정적 파라미터 변경 시 셰이더 재컴파일
};

// 동적 머티리얼 인스턴스 (런타임)
class UMaterialInstanceDynamic : public UMaterialInstance
{
    // 런타임 생성
    // 동적 파라미터만 변경 가능 (재컴파일 없음)

    void SetScalarParameterValue(FName Name, float Value);
    void SetVectorParameterValue(FName Name, FLinearColor Value);
    void SetTextureParameterValue(FName Name, UTexture* Value);
};
```

---

## 정적 머티리얼 인스턴스

### UMaterialInstanceConstant

```cpp
// 정적 인스턴스 (MIC)
class UMaterialInstanceConstant : public UMaterialInstance
{
public:
    // 에디터에서 파라미터 설정
    void SetScalarParameterValueEditorOnly(FName ParameterName, float Value);
    void SetVectorParameterValueEditorOnly(FName ParameterName, FLinearColor Value);
    void SetTextureParameterValueEditorOnly(FName ParameterName, UTexture* Value);

    // 정적 스위치 파라미터 (재컴파일 필요)
    void SetStaticSwitchParameterValueEditorOnly(FName ParameterName, bool Value);
};

// 에디터에서 MIC 생성
UMaterialInstanceConstant* CreateMIC(UMaterial* Parent)
{
    UMaterialInstanceConstant* MIC = NewObject<UMaterialInstanceConstant>();
    MIC->Parent = Parent;

    // 기본값 오버라이드
    MIC->SetScalarParameterValueEditorOnly(TEXT("Roughness"), 0.3f);
    MIC->SetVectorParameterValueEditorOnly(TEXT("Tint"), FLinearColor::Red);

    return MIC;
}
```

### 정적 파라미터

```
┌─────────────────────────────────────────────────────────────────┐
│                    정적 파라미터 종류                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Static Switch Parameter:                                       │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  bool 값으로 코드 분기                                   │   │
│  │  true/false에 따라 다른 셰이더 생성                      │   │
│  │                                                         │   │
│  │  예: UseNormalMap = true → 노멀맵 샘플링 코드 포함       │   │
│  │      UseNormalMap = false → 버텍스 노멀 사용            │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  Static Component Mask Parameter:                               │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  float4에서 어떤 채널을 사용할지 결정                    │   │
│  │  R/G/B/A 중 선택                                         │   │
│  │                                                         │   │
│  │  예: UseChannel = R → 빨간 채널만 사용                   │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  주의: 정적 파라미터 변경 = 새 셰이더 순열                      │
│  - 셰이더 캐시에 없으면 재컴파일                               │
│  - 과도한 사용은 순열 폭발 유발                                │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 동적 머티리얼 인스턴스

### UMaterialInstanceDynamic

```cpp
// 동적 인스턴스 (MID) 생성
UMaterialInstanceDynamic* CreateMID(UMaterialInterface* Parent)
{
    UMaterialInstanceDynamic* MID = UMaterialInstanceDynamic::Create(Parent, nullptr);
    return MID;
}

// 블루프린트/C++에서 사용
void AMyActor::BeginPlay()
{
    Super::BeginPlay();

    // 머티리얼 가져오기
    UMaterialInterface* BaseMaterial = MeshComponent->GetMaterial(0);

    // 동적 인스턴스 생성
    UMaterialInstanceDynamic* DynMaterial = UMaterialInstanceDynamic::Create(
        BaseMaterial, this);

    // 메시에 적용
    MeshComponent->SetMaterial(0, DynMaterial);

    // 파라미터 변경 (런타임에 언제든)
    DynMaterial->SetScalarParameterValue(TEXT("Emissive"), 2.0f);
    DynMaterial->SetVectorParameterValue(TEXT("Color"), FLinearColor::Green);
}

// Tick에서 애니메이션
void AMyActor::Tick(float DeltaTime)
{
    Super::Tick(DeltaTime);

    // 시간에 따른 파라미터 변화
    float PulseValue = (FMath::Sin(GetWorld()->GetTimeSeconds() * 3.0f) + 1.0f) * 0.5f;
    DynMaterial->SetScalarParameterValue(TEXT("Pulse"), PulseValue);
}
```

### MID 성능 고려

```
┌─────────────────────────────────────────────────────────────────┐
│                    MID 성능 영향                                │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  장점:                                                          │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  - 런타임 머티리얼 커스터마이징                          │   │
│  │  - 재컴파일 없음                                         │   │
│  │  - 애니메이션, 상호작용에 적합                           │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  비용:                                                          │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  - 각 MID는 별도 유니폼 버퍼 필요                        │   │
│  │  - 배칭 불가 (동일 MID끼리만 가능)                       │   │
│  │  - 많은 MID = 많은 드로우 콜                            │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  최적화 전략:                                                   │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  1. 필요할 때만 MID 생성                                │   │
│  │  2. 파라미터 변경 빈도 최소화                            │   │
│  │  3. Per-Instance Custom Data 활용 (인스턴싱)            │   │
│  │  4. 머티리얼 파라미터 컬렉션 사용 (전역 파라미터)        │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 파라미터 컬렉션

### Material Parameter Collection

```cpp
// 머티리얼 파라미터 컬렉션 (MPC)
class UMaterialParameterCollection : public UObject
{
    UPROPERTY()
    TArray<FCollectionScalarParameter> ScalarParameters;

    UPROPERTY()
    TArray<FCollectionVectorParameter> VectorParameters;
};

// MPC 사용 - 여러 머티리얼에서 공유
void SetGlobalParameters()
{
    UMaterialParameterCollection* MPC = LoadObject<UMaterialParameterCollection>(
        nullptr, TEXT("/Game/MPC_GlobalParams"));

    UWorld* World = GetWorld();

    // 전역 파라미터 설정 (모든 사용 머티리얼에 영향)
    UKismetMaterialLibrary::SetScalarParameterValue(
        World, MPC, TEXT("TimeOfDay"), 12.5f);

    UKismetMaterialLibrary::SetVectorParameterValue(
        World, MPC, TEXT("SunColor"), FLinearColor(1.0f, 0.9f, 0.7f));
}
```

### MPC 활용 예시

```
┌─────────────────────────────────────────────────────────────────┐
│                    MPC 활용 패턴                                 │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  글로벌 환경 파라미터:                                          │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  MPC_Environment                                        │   │
│  │  ├── TimeOfDay (0-24)                                   │   │
│  │  ├── WeatherIntensity (0-1)                             │   │
│  │  ├── FogDensity                                         │   │
│  │  └── WindDirection (Vector)                             │   │
│  │                                                         │   │
│  │  모든 식물, 물, 하늘 머티리얼에서 참조                   │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  게임플레이 상태:                                               │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  MPC_GameState                                          │   │
│  │  ├── DamageFlashIntensity                               │   │
│  │  ├── HealthPercentage                                   │   │
│  │  └── AlertLevel                                         │   │
│  │                                                         │   │
│  │  UI, 포스트 프로세스, 캐릭터 머티리얼에서 참조           │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  장점:                                                          │
│  - 단일 업데이트로 모든 머티리얼 영향                          │
│  - MID 없이 파라미터 변경                                      │
│  - 배칭 유지                                                    │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## Per-Instance Custom Data

### 인스턴싱과 커스텀 데이터

```cpp
// 인스턴스별 커스텀 데이터 (ISM/HISM)
class UInstancedStaticMeshComponent
{
    // 인스턴스별 4개 float 값 설정 가능
    void SetCustomDataValue(int32 InstanceIndex, int32 CustomDataIndex, float Value);
};

// 사용 예시
void SetInstanceColors(UInstancedStaticMeshComponent* ISM)
{
    int32 NumInstances = ISM->GetInstanceCount();

    for (int32 i = 0; i < NumInstances; ++i)
    {
        // 각 인스턴스에 다른 색상
        float Hue = (float)i / NumInstances;
        ISM->SetCustomDataValue(i, 0, Hue);        // CustomData0.r
        ISM->SetCustomDataValue(i, 1, 1.0f);       // CustomData0.g
        ISM->SetCustomDataValue(i, 2, 1.0f);       // CustomData0.b

        // 랜덤 스케일
        ISM->SetCustomDataValue(i, 3, FMath::RandRange(0.8f, 1.2f));
    }
}
```

### 머티리얼에서 사용

```
┌─────────────────────────────────────────────────────────────────┐
│                    Per-Instance Data 접근                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  머티리얼 노드:                                                  │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  [PerInstanceCustomData]                                │   │
│  │      │                                                  │   │
│  │      ├── Index 0 ──→ Hue ──→ [HSVToRGB] ──→ BaseColor  │   │
│  │      ├── Index 1 ──→ Saturation                        │   │
│  │      ├── Index 2 ──→ Value                             │   │
│  │      └── Index 3 ──→ Scale ──→ WPO                     │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  장점:                                                          │
│  - 인스턴싱 유지 (단일 드로우 콜)                               │
│  - 인스턴스별 다른 외형                                         │
│  - MID 대비 훨씬 효율적                                         │
│                                                                 │
│  제한:                                                          │
│  - 최대 8개 float 값 (NumCustomDataFloats 설정)                │
│  - ISM/HISM에서만 사용                                         │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 인스턴스 계층

### 인스턴스 체인

```
┌─────────────────────────────────────────────────────────────────┐
│                    머티리얼 인스턴스 계층                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  UMaterial (M_Character)                                │   │
│  │  ├── BaseColor = [Texture] × [Param: Tint]              │   │
│  │  ├── Roughness = [Param: Roughness]                     │   │
│  │  └── 모든 파라미터의 기본값 정의                         │   │
│  └────────────────────────┬────────────────────────────────┘   │
│                           │                                     │
│                           ▼                                     │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  UMaterialInstanceConstant (MI_Character_Soldier)       │   │
│  │  ├── Parent = M_Character                               │   │
│  │  ├── Tint = Brown (오버라이드)                          │   │
│  │  └── Roughness = (기본값 사용)                          │   │
│  └────────────────────────┬────────────────────────────────┘   │
│                           │                                     │
│                           ▼                                     │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  UMaterialInstanceConstant (MI_Character_Soldier_Red)   │   │
│  │  ├── Parent = MI_Character_Soldier                      │   │
│  │  ├── Tint = Red (오버라이드)                            │   │
│  │  └── 나머지는 부모 체인에서 상속                         │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  파라미터 조회 순서:                                            │
│  1. 현재 인스턴스에서 찾기                                      │
│  2. 없으면 부모에서 찾기 (재귀)                                 │
│  3. 마스터 머티리얼까지 올라감                                  │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 파라미터 조회

```cpp
// 파라미터 값 조회 (체인 순회)
bool UMaterialInstance::GetScalarParameterValue(
    FName ParameterName, float& OutValue) const
{
    // 1. 현재 인스턴스에서 찾기
    for (const FScalarParameterValue& Param : ScalarParameterValues)
    {
        if (Param.ParameterInfo.Name == ParameterName)
        {
            OutValue = Param.ParameterValue;
            return true;
        }
    }

    // 2. 부모에서 찾기
    if (Parent)
    {
        return Parent->GetScalarParameterValue(ParameterName, OutValue);
    }

    return false;  // 찾지 못함
}
```

---

## 요약

머티리얼 인스턴스 핵심:

1. **MIC** - 정적 인스턴스, 에디터에서 생성, 에셋으로 저장
2. **MID** - 동적 인스턴스, 런타임 생성, 파라미터 변경 가능
3. **정적 파라미터** - 변경 시 셰이더 재컴파일 필요
4. **동적 파라미터** - 재컴파일 없이 유니폼 버퍼로 변경
5. **MPC** - 여러 머티리얼에서 공유하는 전역 파라미터

적절한 인스턴스 전략으로 메모리와 성능을 최적화할 수 있습니다.

---

## 참고 자료

- [UE Material Instances](https://docs.unrealengine.com/5.0/en-US/instanced-materials-in-unreal-engine/)
- [원문 시리즈 (중국어)](https://www.cnblogs.com/timlly/p/13512787.html)
