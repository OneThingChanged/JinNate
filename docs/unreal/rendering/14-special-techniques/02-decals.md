# 데칼 시스템

디퍼드 데칼, DBuffer 데칼, 메시 데칼의 구현과 활용 방법을 다룹니다.

---

## 개요

데칼은 기존 표면 위에 텍스처나 머티리얼을 투영하여 다양한 효과를 만드는 기법입니다.

```
┌─────────────────────────────────────────────────────────────────┐
│                      데칼 투영 원리                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│                    ┌─────────────┐                              │
│                    │  Decal Box  │                              │
│                    │  (투영 볼륨) │                              │
│                    └──────┬──────┘                              │
│                           │ 투영 방향                           │
│                           ▼                                     │
│           ════════════════════════════════════                 │
│           ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓  ◀── 표면         │
│           ════════════════════════════════════                 │
│                    │                │                           │
│                    └────────────────┘                           │
│                      투영된 데칼                                │
│                                                                 │
│  장점:                                                          │
│  - 표면 지오메트리 무관                                         │
│  - 동적 추가/제거 가능                                          │
│  - 복잡한 표면에도 적용                                         │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 데칼 타입

### Deferred Decal (기본)

G-Buffer 렌더링 후 적용되며, BasePass 이후에 G-Buffer를 수정합니다.

```cpp
// 기본 데칼 설정
ADecalActor* Decal = World->SpawnActor<ADecalActor>();
Decal->SetDecalMaterial(DecalMaterial);
Decal->GetDecal()->DecalSize = FVector(100, 100, 100);

// 페이드 설정
Decal->GetDecal()->FadeStartDelay = 5.0f;
Decal->GetDecal()->FadeDuration = 2.0f;
```

```
┌─────────────────────────────────────────────────────────────────┐
│                  Deferred Decal 파이프라인                       │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  BasePass ──▶ G-Buffer ──▶ Decal Pass ──▶ Lighting Pass        │
│                               │                                 │
│                               ▼                                 │
│                    G-Buffer 수정:                               │
│                    - GBufferA (Normal)                          │
│                    - GBufferB (Metallic, Specular, Roughness)  │
│                    - GBufferC (BaseColor)                       │
│                                                                 │
│  제한사항:                                                      │
│  - 반투명 오브젝트에 적용 불가                                  │
│  - 섀도우에 영향 없음                                          │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### DBuffer Decal

BasePass 이전에 DBuffer에 렌더링되어 더 정확한 결과를 제공합니다.

```cpp
// 프로젝트 설정에서 DBuffer 활성화
// Project Settings > Rendering > Decals > DBuffer Decals

// DBuffer 데칼 머티리얼 설정
Material->MaterialDomain = MD_DeferredDecal;
Material->DecalBlendMode = DBM_DBuffer_ColorNormalRoughness;
```

```
┌─────────────────────────────────────────────────────────────────┐
│                  DBuffer Decal 파이프라인                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  DBuffer Pass ──▶ BasePass (DBuffer 샘플링) ──▶ G-Buffer       │
│       │                                                         │
│       ▼                                                         │
│  DBuffer:                                                       │
│  - DBufferA: BaseColor                                         │
│  - DBufferB: Normal                                            │
│  - DBufferC: Roughness, Metallic, etc.                         │
│                                                                 │
│  장점:                                                          │
│  - 정확한 라이팅                                                │
│  - 앰비언트 오클루전 적용                                       │
│  - 더 나은 블렌딩                                               │
│                                                                 │
│  단점:                                                          │
│  - 추가 메모리 비용 (DBuffer)                                  │
│  - 약간의 성능 오버헤드                                         │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Decal Blend Mode

```cpp
// 블렌드 모드 옵션
enum EDecalBlendMode
{
    DBM_Translucent,              // 반투명 (라이팅 영향 없음)
    DBM_Stain,                    // 컬러만 변경
    DBM_Normal,                   // 노멀만 변경
    DBM_Emissive,                 // 이미시브 (빛 방출)

    // DBuffer 전용
    DBM_DBuffer_ColorNormalRoughness,  // 전체
    DBM_DBuffer_Color,                 // 컬러만
    DBM_DBuffer_ColorNormal,           // 컬러+노멀
    DBM_DBuffer_ColorRoughness,        // 컬러+러프니스
    DBM_DBuffer_Normal,                // 노멀만
    DBM_DBuffer_NormalRoughness,       // 노멀+러프니스
    DBM_DBuffer_Roughness,             // 러프니스만

    DBM_Volumetric_DistanceFunction,   // 볼류메트릭
    DBM_AlphaComposite,                // 알파 합성
    DBM_AmbientOcclusion              // AO
};
```

---

## 데칼 머티리얼 제작

### 기본 데칼 머티리얼

```
┌─────────────────────────────────────────────────────────────────┐
│                    데칼 머티리얼 노드 구성                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  [Texture Sample]                                               │
│       │                                                         │
│       ├──▶ RGB ──▶ [Base Color]                                │
│       │                                                         │
│       └──▶ A ────▶ [Opacity]                                   │
│                                                                 │
│  [Constant] 0.5 ──▶ [Roughness]                                │
│                                                                 │
│  Material Settings:                                             │
│  - Material Domain: Deferred Decal                             │
│  - Blend Mode: Translucent                                     │
│  - Decal Blend Mode: 원하는 모드                               │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 노멀 맵 데칼

```cpp
// 노멀 맵을 사용하는 데칼
// Material에서:
// 1. Normal 텍스처 샘플링
// 2. Normal 출력에 연결
// 3. Decal Blend Mode = DBM_Normal 또는 DBM_DBuffer_ColorNormal
```

### 마스킹

```hlsl
// 투영 방향 기반 마스킹 (머티리얼 함수)
float3 DecalNormal = GetDecalOrientation();
float3 SurfaceNormal = PixelNormalWS;

float NdotD = dot(SurfaceNormal, DecalNormal);
float Mask = saturate(NdotD * FadeSharpness);

// 급경사면에서 페이드 아웃
Opacity *= Mask;
```

---

## 데칼 배치

### 코드로 스폰

```cpp
// 데칼 스폰
UDecalComponent* Decal = UGameplayStatics::SpawnDecalAtLocation(
    World,
    DecalMaterial,
    FVector(100, 100, 100),  // 크기
    Location,
    Rotation,
    LifeSpan  // 수명 (0 = 영구)
);

// 또는 컴포넌트로 추가
UDecalComponent* DecalComp = NewObject<UDecalComponent>(this);
DecalComp->SetDecalMaterial(Material);
DecalComp->DecalSize = FVector(50, 50, 50);
DecalComp->AttachToComponent(RootComponent, FAttachmentTransformRules::KeepRelativeTransform);
DecalComp->RegisterComponent();
```

### 충돌 지점에 데칼

```cpp
// 히트 결과로부터 데칼 배치
void SpawnDecalAtHit(const FHitResult& Hit)
{
    if (Hit.bBlockingHit)
    {
        // 히트 노멀로 회전 계산
        FRotator Rotation = Hit.ImpactNormal.Rotation();
        Rotation.Pitch -= 90.0f;  // 데칼은 -X 방향으로 투영

        UGameplayStatics::SpawnDecalAtLocation(
            GetWorld(),
            BulletHoleDecal,
            FVector(10, 10, 10),
            Hit.ImpactPoint,
            Rotation,
            10.0f  // 10초 후 삭제
        );
    }
}
```

### 데칼 풀링

```cpp
// 데칼 풀 관리
class FDecalPool
{
public:
    void Initialize(int32 PoolSize, UMaterialInterface* Material);

    UDecalComponent* GetDecal()
    {
        if (AvailableDecals.Num() > 0)
        {
            return AvailableDecals.Pop();
        }
        return CreateNewDecal();
    }

    void ReturnDecal(UDecalComponent* Decal)
    {
        Decal->SetVisibility(false);
        AvailableDecals.Add(Decal);
    }

private:
    TArray<UDecalComponent*> AvailableDecals;
    TArray<UDecalComponent*> ActiveDecals;
};
```

---

## 최적화

### 정렬 순서

```cpp
// 데칼 정렬 우선순위
Decal->SortOrder = 1;  // 높을수록 나중에 렌더링 (위에 표시)

// 정렬 순서 영향:
// - 같은 위치의 데칼 겹침 해결
// - 높은 순서 = 더 위에 렌더링
```

### 수량 제한

```cpp
// 화면당 데칼 수 제한
r.Decal.MaxDrawDistance = 5000   // 최대 거리
r.Decal.SortBySize = 1           // 크기로 정렬

// 동적 데칼 관리
void ManageDecals()
{
    // 오래된 데칼 제거
    while (ActiveDecals.Num() > MaxDecals)
    {
        UDecalComponent* Oldest = ActiveDecals[0];
        ActiveDecals.RemoveAt(0);
        Oldest->DestroyComponent();
    }
}
```

### 거리 페이드

```cpp
// 거리 기반 페이드 아웃
Decal->FadeScreenSize = 0.001f;  // 스크린 크기 기준 페이드

// 또는 머티리얼에서
// CameraDistance 노드 사용하여 페이드
```

---

## 고급 기법

### 프로시저럴 데칼

```hlsl
// 머티리얼에서 프로시저럴 패턴
float2 UV = GetDecalUV();

// 균열 패턴 생성
float Cracks = GenerateCrackPattern(UV, Seed);

// 시간에 따른 확산
float Spread = saturate(Time * SpreadSpeed);
Cracks *= Spread;

BaseColor = lerp(OriginalColor, CrackColor, Cracks);
```

### 상호작용 데칼

```cpp
// 발자국 데칼 시스템
void LeaveFootprint(const FVector& Location, const FRotator& Rotation)
{
    UDecalComponent* Footprint = SpawnDecal(Location, Rotation);

    // 깊이 정보를 바탕으로 변형
    // 또는 발자국 노멀 맵 적용

    // 시간에 따라 페이드 아웃
    Footprint->SetFadeOut(10.0f, 5.0f, true);  // 10초 후 시작, 5초간 페이드
}
```

### 데칼 프로젝터

```cpp
// 런타임 프로젝션 텍스처
USceneCaptureComponent2D* Projector;
Projector->TextureTarget = RenderTarget;

// 프로젝션 머티리얼에서 RenderTarget 사용
// 동적 이미지를 표면에 투영
```

---

## 콘솔 명령

```cpp
// 디버그 시각화
r.Decal.DrawDebugBoxes 1

// 성능 설정
r.Decal.MaxDrawDistance 5000
r.Decal.SortBySize 1
r.Decal.StencilSizeThreshold 0.0

// DBuffer
r.DBuffer 1  // DBuffer 활성화

// 데칼 통계
stat decals
```

---

## 데칼 타입 비교

| 타입 | 라이팅 | AO | 메모리 | 용도 |
|------|--------|-----|--------|------|
| Translucent | 부분 | X | 낮음 | 단순 오버레이 |
| Stain | O | X | 낮음 | 컬러 변경 |
| Normal | O | X | 낮음 | 표면 디테일 |
| DBuffer | O | O | 높음 | 고품질 데칼 |
| Emissive | X | X | 낮음 | 발광 효과 |

---

## 요약

| 설정 | 권장 사용처 |
|------|------------|
| Deferred Decal | 일반적인 데칼 |
| DBuffer Decal | 정확한 라이팅 필요 시 |
| Translucent | 단순 스티커, 로고 |
| Emissive | 빛나는 표시, UI |

---

## 참고 자료

- [Decal Actor](https://docs.unrealengine.com/decal-actor/)
- [DBuffer Decals](https://docs.unrealengine.com/dbuffer-decals/)
- [Decal Materials](https://docs.unrealengine.com/decal-materials/)
