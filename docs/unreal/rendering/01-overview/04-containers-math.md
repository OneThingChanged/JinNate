# 04. 컨테이너 및 수학 라이브러리

> UE의 핵심 자료구조와 수학 타입

---

## 목차

1. [핵심 컨테이너](#1-핵심-컨테이너)
2. [TArray 상세](#2-tarray-상세)
3. [TMap과 TSet](#3-tmap과-tset)
4. [수학 타입](#4-수학-타입)
5. [벡터 압축 기법](#5-벡터-압축-기법)
6. [Bounds와 충돌](#6-bounds와-충돌)

---

## 1. 핵심 컨테이너 {#1-핵심-컨테이너}

### 1.1 UE vs STL 비교

| 컨테이너 | UE | STL | 주요 차이점 |
|----------|-----|-----|------------|
| **배열** | TArray | vector | 성장 전략, 힙 할당자 |
| **연결 리스트** | TDoubleLinkedList | list | 침투적 구조 |
| **해시 맵** | TMap | unordered_map | TSparseArray 기반 |
| **집합** | TSet | set | 해시 기반 버킷팅 |
| **큐** | TQueue | queue | Lock-free 모드 지원 |
| **스택** | TArray | stack | TArray로 구현 |
| **우선순위 큐** | TArray (힙) | priority_queue | 힙 함수 제공 |

### 1.2 왜 STL을 사용하지 않는가?

UE가 자체 컨테이너를 사용하는 이유:

1. **메모리 제어**: 커스텀 할당자 통합
2. **최적화**: 게임 특화 성장 전략
3. **직렬화**: 저장/로드 자동 지원
4. **리플렉션**: UPROPERTY 지원
5. **크로스 플랫폼**: 일관된 동작 보장

```cpp
// STL과의 상호 운용
#include <vector>

std::vector<int32> StdVector = {1, 2, 3};
TArray<int32> UEArray(StdVector.data(), StdVector.size());

// 또는 범위 기반
TArray<int32> FromRange;
FromRange.Reserve(StdVector.size());
for (int32 Value : StdVector)
{
    FromRange.Add(Value);
}
```

---

## 2. TArray 상세 {#2-tarray-상세}

### 2.1 기본 사용

```cpp
// 생성
TArray<int32> Numbers;
TArray<FString> Names = {TEXT("Alice"), TEXT("Bob")};

// 추가
Numbers.Add(10);
Numbers.Add(20);
Numbers.Emplace(30);  // in-place 생성

// 접근
int32 First = Numbers[0];
int32 Last = Numbers.Last();
int32* Ptr = Numbers.GetData();

// 제거
Numbers.RemoveAt(0);
Numbers.RemoveSingle(20);
Numbers.RemoveAll([](int32 N) { return N > 15; });

// 크기
int32 Count = Numbers.Num();
bool bEmpty = Numbers.IsEmpty();
```

### 2.2 성장 전략

```cpp
// TArray의 성장 알고리즘
SizeType DefaultCalculateSlackGrow(
    SizeType NumElements,
    SizeType NumAllocatedElements,
    SIZE_T BytesPerElement)
{
    SizeType Grow;

    if (NumAllocatedElements == 0)
    {
        // 초기 할당: 4개 요소
        Grow = 4;
    }
    else
    {
        // 이후: 현재 + 37.5% + 16
        Grow = NumElements + 3 * NumElements / 8 + 16;
    }

    return Grow;
}
```

성장 패턴 비교:

| 요소 수 | STL vector (2배) | TArray (37.5%+16) |
|--------|-----------------|-------------------|
| 4 | 8 | 7 |
| 8 | 16 | 19 |
| 16 | 32 | 38 |
| 32 | 64 | 60 |
| 64 | 128 | 104 |

### 2.3 고급 기능

```cpp
// 정렬
Numbers.Sort();  // 기본 비교
Numbers.Sort([](int32 A, int32 B) { return A > B; });  // 내림차순
Numbers.StableSort();  // 안정 정렬

// 검색
int32* Found = Numbers.FindByKey(10);
int32 Index = Numbers.Find(10);
int32 IndexByPredicate = Numbers.IndexOfByPredicate(
    [](int32 N) { return N > 15; });

// 필터링
TArray<int32> Filtered = Numbers.FilterByPredicate(
    [](int32 N) { return N % 2 == 0; });

// 힙 연산
Numbers.Heapify();
Numbers.HeapPush(5);
int32 Top;
Numbers.HeapPop(Top);

// 예약 및 축소
Numbers.Reserve(100);  // 미리 공간 확보
Numbers.Shrink();  // 사용하지 않는 공간 해제
Numbers.Empty();  // 비우기 (메모리 유지)
Numbers.Reset();  // 비우기 (메모리 해제)
```

### 2.4 반복

```cpp
// Range-based for
for (int32 Number : Numbers)
{
    UE_LOG(LogTemp, Log, TEXT("%d"), Number);
}

// 인덱스 필요시
for (int32 i = 0; i < Numbers.Num(); ++i)
{
    UE_LOG(LogTemp, Log, TEXT("[%d] = %d"), i, Numbers[i]);
}

// 반복자
for (auto It = Numbers.CreateIterator(); It; ++It)
{
    *It *= 2;  // 수정 가능
}

// 역순 반복
for (int32 i = Numbers.Num() - 1; i >= 0; --i)
{
    if (Numbers[i] < 0)
    {
        Numbers.RemoveAt(i);  // 안전한 제거
    }
}
```

---

## 3. TMap과 TSet {#3-tmap과-tset}

### 3.1 TMap 기본

```cpp
// 생성
TMap<FString, int32> Scores;

// 추가
Scores.Add(TEXT("Alice"), 100);
Scores.Add(TEXT("Bob"), 85);
Scores.Emplace(TEXT("Charlie"), 90);

// 접근
int32* AliceScore = Scores.Find(TEXT("Alice"));
if (AliceScore)
{
    *AliceScore += 10;
}

// FindOrAdd - 없으면 생성
int32& DaveScore = Scores.FindOrAdd(TEXT("Dave"));
DaveScore = 75;

// 제거
Scores.Remove(TEXT("Bob"));

// 반복
for (const auto& Pair : Scores)
{
    UE_LOG(LogTemp, Log, TEXT("%s: %d"), *Pair.Key, Pair.Value);
}
```

### 3.2 TSet 기본

```cpp
// 생성
TSet<int32> UniqueNumbers;

// 추가
UniqueNumbers.Add(10);
UniqueNumbers.Add(20);
UniqueNumbers.Add(10);  // 무시됨 (중복)

// 검사
bool bContains = UniqueNumbers.Contains(10);

// 집합 연산
TSet<int32> SetA = {1, 2, 3, 4};
TSet<int32> SetB = {3, 4, 5, 6};

TSet<int32> Union = SetA.Union(SetB);        // {1,2,3,4,5,6}
TSet<int32> Intersect = SetA.Intersect(SetB); // {3,4}
TSet<int32> Difference = SetA.Difference(SetB); // {1,2}

// 배열로 변환
TArray<int32> Array = UniqueNumbers.Array();
```

### 3.3 커스텀 키 타입

```cpp
// 커스텀 해시/동등 함수 필요
struct FCustomKey
{
    int32 ID;
    FString Name;

    // 동등 비교
    bool operator==(const FCustomKey& Other) const
    {
        return ID == Other.ID && Name == Other.Name;
    }
};

// 해시 함수 정의
uint32 GetTypeHash(const FCustomKey& Key)
{
    return HashCombine(GetTypeHash(Key.ID), GetTypeHash(Key.Name));
}

// 사용
TMap<FCustomKey, FString> CustomMap;
CustomMap.Add({1, TEXT("Key1")}, TEXT("Value1"));
```

---

## 4. 수학 타입 {#4-수학-타입}

### 4.1 핵심 타입

| 타입 | 설명 | 크기 |
|------|------|------|
| **FVector** | 3D 벡터 (X, Y, Z) | 12 bytes |
| **FVector2D** | 2D 벡터 (X, Y) | 8 bytes |
| **FVector4** | 4D 벡터 (X, Y, Z, W) | 16 bytes |
| **FIntVector** | 정수 3D 벡터 | 12 bytes |
| **FRotator** | 오일러 각 (Pitch, Yaw, Roll) | 12 bytes |
| **FQuat** | 쿼터니언 (X, Y, Z, W) | 16 bytes |
| **FMatrix** | 4x4 행렬 | 64 bytes |
| **FTransform** | 위치 + 회전 + 스케일 | 48 bytes |
| **FPlane** | 평면 (X, Y, Z, W) | 16 bytes |
| **FBox** | AABB 바운딩 박스 | 24 bytes |
| **FSphere** | 구체 (Center + Radius) | 16 bytes |

### 4.2 FVector 연산

```cpp
// 생성
FVector A(1.0f, 2.0f, 3.0f);
FVector B = FVector::ZeroVector;
FVector C = FVector::OneVector;
FVector D = FVector::UpVector;  // (0, 0, 1)

// 산술 연산
FVector Sum = A + B;
FVector Diff = A - B;
FVector Scaled = A * 2.0f;
FVector Divided = A / 2.0f;

// 벡터 연산
float DotProduct = FVector::DotProduct(A, B);
FVector CrossProduct = FVector::CrossProduct(A, B);

float Length = A.Size();
float LengthSquared = A.SizeSquared();  // 더 빠름

FVector Normalized = A.GetSafeNormal();  // 영벡터 안전 처리
A.Normalize();  // in-place

// 거리
float Distance = FVector::Dist(A, B);
float DistanceSquared = FVector::DistSquared(A, B);

// 보간
FVector Lerped = FMath::Lerp(A, B, 0.5f);
FVector VInterped = FMath::VInterpTo(A, B, DeltaTime, Speed);

// 투영
FVector Projected = A.ProjectOnTo(B);
FVector ProjectedOnPlane = FVector::VectorPlaneProject(A, PlaneNormal);

// 반사
FVector Reflected = FMath::GetReflectionVector(Direction, SurfaceNormal);
```

### 4.3 FRotator와 FQuat

```cpp
// FRotator (Pitch, Yaw, Roll - 도 단위)
FRotator Rotation(45.0f, 90.0f, 0.0f);

// 방향 벡터 획득
FVector Forward = Rotation.Vector();
FVector Right = FRotationMatrix(Rotation).GetUnitAxis(EAxis::Y);
FVector Up = FRotationMatrix(Rotation).GetUnitAxis(EAxis::Z);

// 쿼터니언 변환
FQuat Quat = Rotation.Quaternion();

// FQuat 연산
FQuat QuatA = FQuat::Identity;
FQuat QuatB = FQuat(FVector::UpVector, FMath::DegreesToRadians(90.0f));

// 쿼터니언 곱 (회전 합성)
FQuat Combined = QuatA * QuatB;

// 보간
FQuat SlerpedQuat = FQuat::Slerp(QuatA, QuatB, 0.5f);

// 벡터 회전
FVector RotatedVector = Quat.RotateVector(OriginalVector);

// 역쿼터니언
FQuat Inverse = Quat.Inverse();
```

### 4.4 FMatrix

```cpp
// 단위 행렬
FMatrix Identity = FMatrix::Identity;

// 변환 행렬 생성
FMatrix Translation = FTranslationMatrix(FVector(100, 0, 0));
FMatrix Rotation = FRotationMatrix(FRotator(0, 90, 0));
FMatrix Scale = FScaleMatrix(FVector(2, 2, 2));

// 행렬 곱 (변환 합성)
FMatrix Transform = Scale * Rotation * Translation;  // SRT 순서

// 역행렬
FMatrix InverseTransform = Transform.Inverse();

// 벡터 변환
FVector TransformedPoint = Transform.TransformPosition(Point);
FVector TransformedDirection = Transform.TransformVector(Direction);

// 뷰 행렬
FMatrix ViewMatrix = FLookAtMatrix(EyePosition, LookAtPosition, UpVector);

// 투영 행렬
FMatrix ProjMatrix = FPerspectiveMatrix(
    FOV,            // 시야각
    AspectRatio,    // 종횡비
    NearPlane,      // 근평면
    FarPlane        // 원평면
);
```

### 4.5 FTransform

```cpp
// 생성
FTransform Transform(
    FQuat::Identity,           // Rotation
    FVector(0, 0, 100),        // Translation
    FVector(1, 1, 1)           // Scale
);

// 개별 접근
FVector Location = Transform.GetLocation();
FQuat Rotation = Transform.GetRotation();
FVector Scale = Transform.GetScale3D();

// 수정
Transform.SetLocation(NewLocation);
Transform.SetRotation(NewRotation);
Transform.SetScale3D(NewScale);

// 변환 적용
FVector TransformedPoint = Transform.TransformPosition(LocalPoint);
FVector InverseTransformedPoint = Transform.InverseTransformPosition(WorldPoint);

// 변환 합성
FTransform Combined = TransformA * TransformB;

// 보간
FTransform BlendedTransform;
BlendedTransform.Blend(TransformA, TransformB, 0.5f);

// 행렬 변환
FMatrix Matrix = Transform.ToMatrixWithScale();
FTransform FromMatrix(Matrix);
```

---

## 5. 벡터 압축 기법 {#5-벡터-압축-기법}

### 5.1 팔면체 인코딩

단위 벡터를 2D로 압축하는 기법 (노말 압축에 사용):

![벡터 압축](../images/ch01/1617944-20201026110807857-1536924981.png)
*단위 구 → 팔면체 → 2D 정사각형 투영*

```cpp
// Engine\Shaders\Private\DeferredShadingCommon.ush

// 3D 단위 벡터 → 2D 팔면체 좌표
float2 UnitVectorToOctahedron(float3 N)
{
    // L1 노름으로 정규화
    N.xy /= dot(1, abs(N));

    // 하반구 처리 (z < 0)
    if (N.z <= 0)
    {
        N.xy = (1 - abs(N.yx)) * sign(N.xy);
    }

    return N.xy;
}

// 2D 팔면체 좌표 → 3D 단위 벡터
float3 OctahedronToUnitVector(float2 Oct)
{
    float3 N = float3(Oct, 1 - dot(1, abs(Oct)));

    // 하반구 복원
    if (N.z < 0)
    {
        N.xy = (1 - abs(N.yx)) * sign(N.xy);
    }

    return normalize(N);
}
```

### 5.2 G-Buffer에서의 활용

```cpp
// G-Buffer 노말 인코딩 (3채널 → 2채널)
float2 EncodeNormal(float3 WorldNormal)
{
    // 월드 노말을 팔면체로 인코딩
    float2 Encoded = UnitVectorToOctahedron(WorldNormal);

    // [−1, 1] → [0, 1]
    return Encoded * 0.5 + 0.5;
}

// G-Buffer 노말 디코딩
float3 DecodeNormal(float2 Encoded)
{
    // [0, 1] → [−1, 1]
    float2 Oct = Encoded * 2.0 - 1.0;

    return OctahedronToUnitVector(Oct);
}
```

### 5.3 쿼터니언 압축

```cpp
// 쿼터니언을 3개 컴포넌트로 압축
// 가장 큰 컴포넌트를 암시적으로 저장
uint32 CompressQuat(const FQuat& Q)
{
    // 가장 큰 컴포넌트 찾기
    int32 LargestIndex = 0;
    float LargestValue = FMath::Abs(Q.X);

    for (int32 i = 1; i < 4; ++i)
    {
        float Value = FMath::Abs(Q[i]);
        if (Value > LargestValue)
        {
            LargestValue = Value;
            LargestIndex = i;
        }
    }

    // 나머지 3개 컴포넌트 양자화
    // ... (10비트씩 패킹)
}
```

---

## 6. Bounds와 충돌 {#6-bounds와-충돌}

### 6.1 FBoxSphereBounds

AABB(축 정렬 경계 상자)와 구체 경계를 함께 저장:

```cpp
struct FBoxSphereBounds
{
    FVector Origin;      // 중심점
    FVector BoxExtent;   // 반 크기
    float SphereRadius;  // 경계 구체 반지름

    // 생성
    FBoxSphereBounds(const FBox& Box);
    FBoxSphereBounds(const FSphere& Sphere);
    FBoxSphereBounds(const FVector& InOrigin, const FVector& InExtent, float InRadius);

    // 변환
    FBoxSphereBounds TransformBy(const FMatrix& M) const;
    FBoxSphereBounds TransformBy(const FTransform& M) const;

    // 합치기
    FBoxSphereBounds operator+(const FBoxSphereBounds& Other) const;

    // 박스 획득
    FBox GetBox() const
    {
        return FBox(Origin - BoxExtent, Origin + BoxExtent);
    }

    // 구체 획득
    FSphere GetSphere() const
    {
        return FSphere(Origin, SphereRadius);
    }
};
```

### 6.2 기본 충돌 검사

```cpp
// AABB vs AABB
bool BoxIntersect(const FBox& A, const FBox& B)
{
    return A.Intersect(B);
}

// 구체 vs 구체
bool SphereIntersect(const FSphere& A, const FSphere& B)
{
    float DistSquared = FVector::DistSquared(A.Center, B.Center);
    float RadiusSum = A.W + B.W;
    return DistSquared <= RadiusSum * RadiusSum;
}

// 레이 vs AABB
bool RayBoxIntersect(const FVector& Origin, const FVector& Direction,
                     const FBox& Box, float& OutHitTime)
{
    FVector InvDir = FVector(1.0f) / Direction;

    FVector T1 = (Box.Min - Origin) * InvDir;
    FVector T2 = (Box.Max - Origin) * InvDir;

    FVector TMin = FVector::Min(T1, T2);
    FVector TMax = FVector::Max(T1, T2);

    float TEntry = FMath::Max3(TMin.X, TMin.Y, TMin.Z);
    float TExit = FMath::Min3(TMax.X, TMax.Y, TMax.Z);

    if (TEntry <= TExit && TExit >= 0)
    {
        OutHitTime = TEntry >= 0 ? TEntry : TExit;
        return true;
    }
    return false;
}
```

### 6.3 프러스텀 컬링

```cpp
// 뷰 프러스텀 평면 (6개)
struct FConvexVolume
{
    TArray<FPlane> Planes;  // Near, Far, Left, Right, Top, Bottom

    // AABB가 프러스텀 내에 있는지 검사
    bool IntersectBox(const FVector& Origin, const FVector& Extent) const
    {
        for (const FPlane& Plane : Planes)
        {
            // 평면까지의 부호 거리 계산
            float Dist = Plane.PlaneDot(Origin);

            // 박스의 투영 반지름
            float ProjRadius =
                Extent.X * FMath::Abs(Plane.X) +
                Extent.Y * FMath::Abs(Plane.Y) +
                Extent.Z * FMath::Abs(Plane.Z);

            // 완전히 바깥이면 컬링
            if (Dist > ProjRadius)
            {
                return false;
            }
        }
        return true;  // 모든 평면 통과 = 가시적
    }
};
```

---

## 요약

| 카테고리 | 핵심 내용 |
|----------|----------|
| **TArray** | 37.5%+16 성장 전략, 힙/정렬/검색 지원 |
| **TMap/TSet** | 해시 기반, 커스텀 키 해시 함수 필요 |
| **수학 타입** | FVector, FRotator, FQuat, FMatrix, FTransform |
| **압축** | 팔면체 인코딩으로 노말 2채널 압축 |
| **Bounds** | FBoxSphereBounds로 컬링 최적화 |

---

## 다음 문서

[05. 좌표 공간 시스템](05-coordinate-system.md)에서 UE의 8가지 좌표 공간과 변환을 살펴봅니다.
