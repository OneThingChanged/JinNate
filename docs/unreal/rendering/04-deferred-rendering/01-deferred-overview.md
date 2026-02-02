# 01. 디퍼드 렌더링 개요

> 디퍼드 셰이딩의 기본 개념과 Forward와의 비교

---

## 목차

1. [핵심 개념](#1-핵심-개념)
2. [2-패스 구조](#2-2-패스-구조)
3. [Forward vs Deferred](#3-forward-vs-deferred)
4. [UE에서의 구현](#4-ue에서의-구현)

---

## 1. 핵심 개념 {#1-핵심-개념}

### 1.1 디퍼드 렌더링이란?

![디퍼드 렌더링 개요](../images/ch04/1617944-20210505184316256-1193511203.png)
*디퍼드 렌더링의 두 패스 구조*

디퍼드 렌더링은 라이팅 계산을 "지연"하는 렌더링 기법입니다:

1. **Geometry Pass**: 씬 오브젝트 정보를 G-Buffer에 기록
2. **Lighting Pass**: G-Buffer 데이터로 라이팅 계산

### 1.2 왜 "디퍼드"인가?

```
Forward Rendering:
┌──────────────────────────────────────────────────────────┐
│ for each object:                                         │
│     for each light:                                      │
│         shade(object, light)  ← 모든 픽셀에서 라이팅      │
└──────────────────────────────────────────────────────────┘

Deferred Rendering:
┌──────────────────────────────────────────────────────────┐
│ for each object:                                         │
│     writeGBuffer(object)  ← 라이팅 없이 기하 정보만       │
│                                                          │
│ for each pixel in screen:                                │
│     for each light:                                      │
│         shade(pixel, light)  ← 가시 픽셀만 라이팅         │
└──────────────────────────────────────────────────────────┘
```

---

## 2. 2-패스 구조 {#2-2-패스-구조}

### 2.1 Geometry Pass (Base Pass)

| 단계 | 설명 |
|------|------|
| **입력** | 씬 오브젝트 (메시, 머티리얼) |
| **출력** | G-Buffer (여러 렌더 타겟) |
| **라이팅** | 없음 |

### 2.2 Lighting Pass

| 단계 | 설명 |
|------|------|
| **입력** | G-Buffer, 라이트 데이터 |
| **출력** | 최종 Scene Color |
| **처리** | 픽셀당 라이팅 계산 |

```cpp
// 의사 코드
for each pixel in RenderTarget:
    pixelData = sample GBuffer at UV
    color = 0

    for each light:
        color += CalculateLighting(light, pixelData)

    WriteSceneColor(color)
```

---

## 3. Forward vs Deferred {#3-forward-vs-deferred}

### 3.1 비교표

| 측면 | Deferred | Forward |
|------|----------|---------|
| **복잡도** | O(Lights × Pixels) | O(Objects × Lights) |
| **라이트 지원** | 100+ | <10 실용적 |
| **MSAA** | 어려움; TAA 대안 | 네이티브 HW |
| **머티리얼** | GBuffer 슬롯 제약 | 무제한 |
| **반투명** | 미지원 (별도 패스) | 지원 |
| **메모리** | 높음 | 낮음 |
| **오버드로우** | 최소 | 심각 |

### 3.2 장단점

**Deferred 장점:**

- 많은 수의 동적 광원 지원
- 오버드로우 영향 최소화
- 스크린 스페이스 효과에 유리 (SSAO, SSR)

**Deferred 단점:**

- G-Buffer 메모리/대역폭 비용
- MSAA 지원 어려움
- 반투명 처리 별도 필요
- 다양한 셰이딩 모델 제한

---

## 4. UE에서의 구현 {#4-ue에서의-구현}

### 4.1 FDeferredShadingSceneRenderer

```cpp
class FDeferredShadingSceneRenderer : public FSceneRenderer
{
public:
    virtual void Render(FRHICommandListImmediate& RHICmdList) override
    {
        // 1. 가시성 계산
        InitViews(RHICmdList);

        // 2. PrePass (Z-PrePass)
        RenderPrePass(RHICmdList);

        // 3. Base Pass (G-Buffer 생성)
        RenderBasePass(RHICmdList);

        // 4. Lighting Pass
        RenderLights(RHICmdList);

        // 5. 반투명 (Forward)
        RenderTranslucency(RHICmdList);

        // 6. Post Process
        RenderPostProcess(RHICmdList);
    }
};
```

---

## 다음 문서

[02. G-Buffer 구조](02-gbuffer.md)에서 G-Buffer 레이아웃을 살펴봅니다.
---

<div style="display: flex; justify-content: space-between; align-items: center; padding: 16px 0;">
  <a href="../" style="text-decoration: none;">← 이전: Ch.04 개요</a>
  <a href="../02-gbuffer/" style="text-decoration: none;">다음: 02. G-Buffer 구조 →</a>
</div>
