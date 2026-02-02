# 05. UE 프레임 분석

> GPU Visualizer와 RenderDoc을 통한 프레임 분석

---

## 목차

1. [GPU Visualizer](#1-gpu-visualizer)
2. [RenderDoc 캡처](#2-renderdoc-캡처)
3. [프레임 렌더링 단계](#3-프레임-렌더링-단계)
4. [성능 최적화 팁](#4-성능-최적화-팁)

---

## 1. GPU Visualizer {#1-gpu-visualizer}

### 1.1 사용법

![GPU Visualizer](../images/ch04/1617944-20210505185140547-1216273573.jpg)
*콘솔 명령 `profilegpu` 실행 후 GPU Visualizer 창*

```cpp
// 콘솔 명령
profilegpu    // GPU 프로파일러 실행
stat gpu      // GPU 통계 표시
```

### 1.2 주요 항목

| 항목 | 설명 |
|------|------|
| **PrePass** | Z-PrePass 시간 |
| **BasePass** | G-Buffer 생성 시간 |
| **Lighting** | 라이팅 패스 시간 |
| **Translucency** | 반투명 렌더링 시간 |
| **PostProcess** | 후처리 시간 |

---

## 2. RenderDoc 캡처 {#2-renderdoc-캡처}

### 2.1 캡처

![RenderDoc](../images/ch04/1617944-20210505185153758-185516829.jpg)
*RenderDoc으로 캡처한 UE의 한 프레임*

1. RenderDoc에서 UE 실행
2. F12 또는 PrintScreen으로 캡처
3. 이벤트 브라우저에서 드로우 콜 분석

### 2.2 분석 항목

- 렌더 타겟 내용
- 셰이더 바인딩
- 드로우 콜 수
- 상태 변경

---

## 3. 프레임 렌더링 단계 {#3-프레임-렌더링-단계}

### 3.1 단계별 시각화

![프레임 단계 1](../images/ch04/1617944-20210505185242764-1968557601.jpg)

![프레임 단계 2](../images/ch04/1617944-20210505185315935-1204060267.jpg)

![프레임 단계 3](../images/ch04/1617944-20210505185326242-1305974724.jpg)

![프레임 단계 4](../images/ch04/1617944-20210505185343871-1695859747.jpg)

### 3.2 요약

```
┌─────────────────────────────────────────────────────────────────┐
│                    전체 프레임 타임라인                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  [PrePass] [BasePass] [SSAO] [Lighting] [Trans] [PostProcess]   │
│     5%        20%       5%      30%        10%       30%        │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 4. 성능 최적화 팁 {#4-성능-최적화-팁}

### 4.1 병목 진단

| 병목 | 증상 | 해결책 |
|------|------|--------|
| **드로우 콜** | BasePass 오래 걸림 | 배칭, 인스턴싱 |
| **셰이더 복잡도** | 픽셀 시간 높음 | LOD, 머티리얼 단순화 |
| **오버드로우** | 투명 오브젝트 많음 | 정렬, 뎁스 프리패스 |
| **대역폭** | G-Buffer 큼 | 해상도 조절, 압축 |

### 4.2 콘솔 명령

```cpp
stat gpu              // GPU 시간
stat scenerendering   // 씬 렌더링 통계
stat rhi              // RHI 통계
r.ScreenPercentage    // 해상도 스케일
r.ViewDistanceScale   // 뷰 거리 스케일
```

---

## 참고 자료

- [원문 시리즈 (중국어)](https://www.cnblogs.com/timlly/p/14732412.html)
- [RenderDoc 공식 문서](https://renderdoc.org/docs/)
- [UE4 프로파일링 가이드](https://docs.unrealengine.com/en-US/TestingAndOptimization/)

---

## 다음 챕터

[Ch.05 광원과 그림자](../05-light-and-shadow/index.md)에서 라이팅 시스템을 살펴봅니다.
---

<div style="display: flex; justify-content: space-between; align-items: center; padding: 16px 0;">
  <a href="../04-deferred-variants/" style="text-decoration: none;">← 이전: 04. 디퍼드 렌더링 변형</a>
  <a href="../../05-light-and-shadow/" style="text-decoration: none;">다음: Ch.05 광원과 그림자 →</a>
</div>
