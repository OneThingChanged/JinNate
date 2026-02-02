# 04. 디퍼드 렌더링 변형

> TBDR, Clustered, Visibility Buffer 등 고급 기법

---

## 목차

1. [Tiled Deferred (TBDR)](#1-tiled-deferred-tbdr)
2. [Clustered Deferred](#2-clustered-deferred)
3. [Visibility Buffer](#3-visibility-buffer)
4. [기타 변형](#4-기타-변형)

---

## 1. Tiled Deferred (TBDR) {#1-tiled-deferred-tbdr}

### 1.1 개념

![TBDR 뎁스](../images/ch04/1617944-20210505184450431-1525923419.jpg)
*TBDR의 타일별 뎁스 범위*

스크린을 타일(예: 16x16 픽셀)로 분할하고, 타일별로 영향을 미치는 라이트만 계산:

```
1. 스크린을 타일로 분할
2. 타일별 Min/Max 뎁스 계산
3. 각 타일과 교차하는 라이트 목록 생성
4. 타일별로 해당 라이트만 라이팅 계산
```

### 1.2 장점

- 라이트당 픽셀 순회 감소
- GPU 워크그룹 활용

---

## 2. Clustered Deferred {#2-clustered-deferred}

### 2.1 개념

![Clustered 개념](../images/ch04/1617944-20210505184543959-1768447878.jpg)
*Clustered Deferred: 뎁스를 여러 조각으로 세분화*

TBDR을 뎁스 방향으로도 확장:

```
┌─────────────────────────────────────────┐
│  Tiled: 2D 타일 (XY)                     │
│                                         │
│  Clustered: 3D 클러스터 (XYZ)            │
│  - 더 정밀한 라이트 컬링                  │
│  - 뎁스 범위가 큰 씬에 유리               │
└─────────────────────────────────────────┘
```

### 2.2 비교

![비교](../images/ch04/1617944-20210505184605861-1136735194.jpg)
*빨간색: Tiled, 녹색: Implicit Clustered, 파란색: Explicit Clustered*

---

## 3. Visibility Buffer {#3-visibility-buffer}

### 3.1 개념

![Visibility Buffer](../images/ch04/1617944-20210505184726143-882156015.jpg)
*G-Buffer vs Visibility Buffer 비교*

G-Buffer 대신 삼각형 ID + 인스턴스 ID만 저장 (4 bytes):

| 장점 | 단점 |
|------|------|
| 대역폭 대폭 감소 | Bindless 텍스처 필요 |
| 작은 삼각형에 유리 | 픽셀당 속성 페치 필요 |

---

## 4. 기타 변형 {#4-기타-변형}

### 4.1 Decoupled Deferred Shading

![Decoupled](../images/ch04/1617944-20210505184643677-1430840819.jpg)
*이전 셰이딩 결과를 재사용하는 메모이제이션 캐시*

- MSAA 지원 향상
- 스토캐스틱 샘플링과 결합

### 4.2 Deferred Coarse Pixel Shading

![Coarse Shading](../images/ch04/1617944-20210505184818850-1769555354.jpg)
*변화가 적은 영역은 낮은 빈도로 셰이딩*

- ddx/ddy로 변화율 감지
- 셰이딩 빈도 동적 조절

---

## 다음 문서

[05. 프레임 분석](05-frame-analysis.md)에서 실제 프레임 캡처 분석을 살펴봅니다.
---

<div style="display: flex; justify-content: space-between; align-items: center; padding: 16px 0;">
  <a href="../03-pipeline-stages/" style="text-decoration: none;">← 이전: 03. 렌더링 파이프라인 단계</a>
  <a href="../05-frame-analysis/" style="text-decoration: none;">다음: 05. UE 프레임 분석 →</a>
</div>
