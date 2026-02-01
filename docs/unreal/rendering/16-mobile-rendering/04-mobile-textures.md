# 모바일 텍스처

모바일 플랫폼의 텍스처 압축 포맷과 최적화 기법을 분석합니다.

---

## 압축 포맷

### 플랫폼별 포맷

```
┌─────────────────────────────────────────────────────────────────┐
│                  모바일 텍스처 압축 포맷                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  플랫폼          권장 포맷            대안 포맷                  │
│  ─────────────────────────────────────────────────────────────  │
│  Android         ASTC               ETC2                        │
│  iOS             ASTC               PVRTC (구형)                │
│  모든 플랫폼     ASTC               -                           │
│                                                                 │
│  ASTC (Adaptive Scalable Texture Compression):                  │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                          │   │
│  │  블록 크기     bpp      품질      사용 사례              │   │
│  │  ──────────────────────────────────────────────────────  │   │
│  │  4×4          8.0      최고      Normal, UI             │   │
│  │  5×5          5.12     높음      Albedo                 │   │
│  │  6×6          3.56     중간      일반 텍스처            │   │
│  │  8×8          2.0      낮음      배경                   │   │
│  │  10×10        1.28     최저      원거리 배경            │   │
│  │  12×12        0.89     -         거의 사용 안 함        │   │
│  │                                                          │   │
│  │  * bpp = bits per pixel                                 │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  ETC2 (Android 대안):                                           │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  RGB:        ETC2 RGB (4 bpp)                           │   │
│  │  RGBA:       ETC2 RGBA (8 bpp)                          │   │
│  │  Normal:     ETC2 RG (8 bpp)                            │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### UE 텍스처 설정

```cpp
// 텍스처 압축 설정
// Texture Editor → Compression Settings

// 일반 텍스처
Compression Settings = Default (DXT1/5, ASTC, ETC2)

// 노말맵
Compression Settings = Normalmap (DXT5, BC5, ASTC 4x4)

// UI 텍스처
Compression Settings = UserInterface2D (RGBA, 높은 품질)

// 마스크 텍스처
Compression Settings = Masks (Grayscale, 채널 패킹)

// HDR 텍스처
Compression Settings = HDR (BC6H, ASTC HDR)

// 프로젝트 설정 (DefaultEngine.ini)
[/Script/AndroidRuntimeSettings.AndroidRuntimeSettings]
TextureFormatPriority_ASTC=1
TextureFormatPriority_ETC2=2

[/Script/IOSRuntimeSettings.IOSRuntimeSettings]
TextureFormatPriority_ASTC=1
TextureFormatPriority_PVRTC=2
```

---

## 텍스처 스트리밍

### 모바일 스트리밍 설정

```
┌─────────────────────────────────────────────────────────────────┐
│                  Mobile Texture Streaming                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  메모리 예산:                                                    │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                          │   │
│  │  총 텍스처 메모리                                        │   │
│  │  ┌─────────────────────────────────────────────────┐    │   │
│  │  │████████████████████░░░░░░░░░░░░░░░░░░░░░░░░░░░░│    │   │
│  │  │   로드됨 (512MB)      스트리밍 풀 (512MB)      │    │   │
│  │  └─────────────────────────────────────────────────┘    │   │
│  │                                                          │   │
│  │  설정:                                                   │   │
│  │  r.Streaming.PoolSize=512        (MB)                   │   │
│  │  r.Streaming.MaxTempMemoryAllowed=50                    │   │
│  │  r.Streaming.Boost=0             (0=off, 1=on)         │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  밉맵 스트리밍:                                                  │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                          │   │
│  │  Mip 0 (Full Res)  ████████████████  2048×2048         │   │
│  │  Mip 1             ████████████      1024×1024         │   │
│  │  Mip 2             ████████           512×512          │   │
│  │  Mip 3             ████               256×256  ← 상주  │   │
│  │  Mip 4             ██                 128×128  ← 상주  │   │
│  │                                                          │   │
│  │  • 작은 밉맵은 항상 메모리에 유지                        │   │
│  │  • 큰 밉맵은 필요시 스트리밍                             │   │
│  │  • 거리/스크린 사이즈 기반 결정                          │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 스트리밍 우선순위

```cpp
// 텍스처 스트리밍 우선순위
// Texture Editor → Level Of Detail

// 텍스처 그룹
enum TextureGroup
{
    TEXTUREGROUP_World,           // 월드 텍스처
    TEXTUREGROUP_Character,       // 캐릭터 (높은 우선순위)
    TEXTUREGROUP_Weapon,          // 무기 (높은 우선순위)
    TEXTUREGROUP_Vehicle,         // 차량
    TEXTUREGROUP_UI,              // UI (항상 풀 해상도)
    TEXTUREGROUP_Effects,         // 이펙트
    TEXTUREGROUP_Skybox,          // 스카이박스
};

// LOD Bias 설정
// Texture → LOD Bias = 1  (한 단계 낮은 밉 사용)

// 최대 해상도 제한
// Texture → Maximum Texture Size = 1024

// 모바일 특화 설정
#if PLATFORM_MOBILE
    MaxTextureSize = 1024;        // 2K 대신 1K
    TextureStreamingPoolSize = 256; // MB
    DropMipMapLevel = 2;          // 2단계 밉 드롭
#endif
```

---

## 텍스처 아틀라스

### 아틀라싱 전략

```
┌─────────────────────────────────────────────────────────────────┐
│                  Texture Atlasing                                │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  개별 텍스처 (비효율)           아틀라스 (효율)                  │
│  ┌─────┐ ┌─────┐ ┌─────┐      ┌─────────────────┐             │
│  │ A   │ │ B   │ │ C   │      │ ┌───┬───┬───┐   │             │
│  └─────┘ └─────┘ └─────┘      │ │ A │ B │ C │   │             │
│  ┌─────┐ ┌─────┐ ┌─────┐  →   │ ├───┼───┼───┤   │             │
│  │ D   │ │ E   │ │ F   │      │ │ D │ E │ F │   │             │
│  └─────┘ └─────┘ └─────┘      │ └───┴───┴───┘   │             │
│                               └─────────────────┘             │
│  6 텍스처 바인딩               1 텍스처 바인딩                  │
│  6 Draw Calls 가능            1 Draw Call 가능                 │
│                                                                 │
│  아틀라스 장점:                                                  │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ • 텍스처 바인딩 감소                                     │   │
│  │ • 배칭 가능성 증가                                       │   │
│  │ • 메모리 효율 (패딩 최소화)                              │   │
│  │ • 드로우 콜 감소                                         │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  주의사항:                                                       │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ • 밉맵 블리딩 (Border 필요)                              │   │
│  │ • UV 재계산 필요                                         │   │
│  │ • 타일링 불가 (Wrap 모드)                                │   │
│  │ • 스트리밍 그래뉼래리티 저하                              │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 채널 패킹

```cpp
// 채널 패킹 예시
// 여러 그레이스케일 텍스처를 하나의 RGBA 텍스처로

// 패킹 구조
struct PackedTexture
{
    // Red:   Metallic
    // Green: Roughness
    // Blue:  AO (Ambient Occlusion)
    // Alpha: Height / Mask
};

// 머티리얼에서 언팩
half4 Packed = PackedTexture.Sample(Sampler, UV);
half Metallic = Packed.r;
half Roughness = Packed.g;
half AO = Packed.b;
half Height = Packed.a;

// 장점:
// - 텍스처 수 1/4로 감소
// - 메모리 절약
// - 샘플링 횟수 감소

// 주의:
// - sRGB 비활성화 필요
// - 압축 품질 고려
// - 각 채널 독립적 밉맵 불가
```

---

## Virtual Texture

### 모바일 Virtual Texture

```
┌─────────────────────────────────────────────────────────────────┐
│                  Mobile Virtual Texture                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Runtime Virtual Texture (RVT):                                  │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                          │   │
│  │  ┌────────────────────────────────────────────────┐     │   │
│  │  │         Virtual Texture (논리적)               │     │   │
│  │  │  ┌────┬────┬────┬────┬────┬────┬────┬────┐    │     │   │
│  │  │  │    │    │    │    │    │    │    │    │    │     │   │
│  │  │  ├────┼────┼────┼────┼────┼────┼────┼────┤    │     │   │
│  │  │  │    │ R  │ R  │    │    │    │    │    │ R  │     │   │
│  │  │  ├────┼────┼────┼────┼────┼────┼────┼────┤ =  │     │   │
│  │  │  │    │ R  │ R  │ R  │    │    │    │    │Resident  │   │
│  │  │  └────┴────┴────┴────┴────┴────┴────┴────┘    │     │   │
│  │  │                                                │     │   │
│  │  └────────────────────────────────────────────────┘     │   │
│  │                         │                                │   │
│  │                         ▼                                │   │
│  │  ┌────────────────────────────────────────────────┐     │   │
│  │  │         Physical Cache (실제 메모리)           │     │   │
│  │  │  ┌────┬────┬────┬────┬────┬────┐              │     │   │
│  │  │  │Page│Page│Page│Page│Page│Page│              │     │   │
│  │  │  │ 0  │ 1  │ 2  │ 3  │ 4  │ 5  │              │     │   │
│  │  │  └────┴────┴────┴────┴────┴────┘              │     │   │
│  │  │                                                │     │   │
│  │  │  고정 크기 캐시 (예: 4096×4096)                │     │   │
│  │  └────────────────────────────────────────────────┘     │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  모바일 설정:                                                    │
│  r.VT.PoolSize=128              (Physical Cache 크기, MB)      │
│  r.VT.Borders=1                 (밉 블리딩 방지)               │
│  r.VT.MaxUploadsPerFrame=4      (프레임당 업로드 제한)         │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 메모리 최적화

### 텍스처 메모리 계산

```cpp
// 텍스처 메모리 계산
size_t CalculateTextureMemory(
    int Width, int Height,
    EPixelFormat Format,
    int MipCount)
{
    size_t TotalSize = 0;

    for (int Mip = 0; Mip < MipCount; Mip++)
    {
        int MipWidth = FMath::Max(1, Width >> Mip);
        int MipHeight = FMath::Max(1, Height >> Mip);

        size_t MipSize = CalculateMipSize(MipWidth, MipHeight, Format);
        TotalSize += MipSize;
    }

    return TotalSize;
}

// 포맷별 크기 (bpp)
// ASTC 4×4:    8.0 bpp
// ASTC 6×6:    3.56 bpp
// ASTC 8×8:    2.0 bpp
// ETC2 RGB:    4.0 bpp
// ETC2 RGBA:   8.0 bpp
// PVRTC 4bpp:  4.0 bpp
// Uncompressed RGBA: 32.0 bpp

// 예시: 1024×1024 ASTC 6×6 (풀 밉체인)
// Mip 0: 1024×1024 × 3.56 / 8 = 466 KB
// Mip 1: 512×512 × 3.56 / 8 = 116 KB
// ...
// 총: ~620 KB
```

### 최적화 전략

```
┌─────────────────────────────────────────────────────────────────┐
│                  텍스처 메모리 최적화                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. 해상도 제한                                                  │
│     ┌─────────────────────────────────────────────────────┐    │
│     │ 최대 텍스처 크기:                                    │    │
│     │ • 캐릭터/무기: 1024×1024                            │    │
│     │ • 환경: 512×512 ~ 1024×1024                         │    │
│     │ • UI: 필요한 만큼                                    │    │
│     │ • 이펙트: 256×256 ~ 512×512                         │    │
│     └─────────────────────────────────────────────────────┘    │
│                                                                 │
│  2. 압축 최적화                                                  │
│     ┌─────────────────────────────────────────────────────┐    │
│     │ • ASTC 6×6 기본 사용                                 │    │
│     │ • 노말맵: ASTC 4×4                                   │    │
│     │ • 배경: ASTC 8×8 이상                                │    │
│     │ • 알파 없으면 RGB 포맷                               │    │
│     └─────────────────────────────────────────────────────┘    │
│                                                                 │
│  3. 밉맵 관리                                                    │
│     ┌─────────────────────────────────────────────────────┐    │
│     │ • LOD Bias로 상위 밉 드롭                            │    │
│     │ • 최소 상주 밉 레벨 설정                              │    │
│     │ • 원거리 텍스처는 낮은 밉만 유지                      │    │
│     └─────────────────────────────────────────────────────┘    │
│                                                                 │
│  4. 공유 및 재사용                                               │
│     ┌─────────────────────────────────────────────────────┐    │
│     │ • 틸링 가능한 텍스처 공유                             │    │
│     │ • 채널 패킹으로 텍스처 수 감소                        │    │
│     │ • 프로시저럴 텍스처 활용                              │    │
│     └─────────────────────────────────────────────────────┘    │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 텍스처 품질 설정

### Scalability 그룹

```cpp
// Engine Scalability Groups
[TextureQuality@0]  // Low
r.Streaming.PoolSize=128
r.Streaming.MipBias=2
r.MaxAnisotropy=0

[TextureQuality@1]  // Medium
r.Streaming.PoolSize=256
r.Streaming.MipBias=1
r.MaxAnisotropy=2

[TextureQuality@2]  // High
r.Streaming.PoolSize=512
r.Streaming.MipBias=0
r.MaxAnisotropy=4

[TextureQuality@3]  // Epic (모바일에서 드물게 사용)
r.Streaming.PoolSize=1024
r.Streaming.MipBias=0
r.MaxAnisotropy=8
```

### 디바이스 프로파일

```cpp
// DeviceProfiles.ini

[Android_Adreno5xx]
+CVars=r.Streaming.PoolSize=256
+CVars=r.MobileContentScaleFactor=0.8

[Android_Mali_G7x]
+CVars=r.Streaming.PoolSize=384
+CVars=r.MobileContentScaleFactor=1.0

[IOS_A12]
+CVars=r.Streaming.PoolSize=512
+CVars=r.MobileContentScaleFactor=1.0

[IOS_A14]
+CVars=r.Streaming.PoolSize=768
+CVars=r.MobileContentScaleFactor=1.0
```

---

## 디버깅

### 텍스처 분석

```cpp
// 콘솔 명령어
stat streaming          // 스트리밍 통계
stat textures           // 텍스처 통계

// 시각화
r.Streaming.Debug=1     // 스트리밍 디버그 표시
ShowFlag.TextureStreamingBudget 1

// 메모리 분석
obj list class=texture2d  // 모든 텍스처 나열
obj refs name=TextureName  // 특정 텍스처 참조

// 모바일 프리뷰
r.Mobile.TextureQuality   // 텍스처 품질 레벨
```

---

## 다음 단계

- [모바일 최적화](05-mobile-optimization.md)에서 전체적인 모바일 최적화 전략을 학습합니다.
