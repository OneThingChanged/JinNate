# RT 기초

레이 트레이싱의 기초 이론과 수학을 설명합니다.

---

## 광선 방정식

```
┌─────────────────────────────────────────────────────────────────┐
│                    광선 (Ray) 정의                               │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  p(t) = o + t·d    (t ≥ 0)                                     │
│                                                                 │
│  o: 원점 (Origin)                                              │
│  d: 방향 (Direction, 정규화)                                   │
│  t: 파라미터 (거리)                                            │
│                                                                 │
│       o                                                         │
│       ●─────────────────────▶ d                                │
│       │                                                         │
│       │ t = 0                                                   │
│       │                                                         │
│       │         ● p(t) = o + t·d                               │
│       │         │                                               │
│       │         │ t > 0                                         │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 광선-삼각형 교차

Möller-Trumbore 알고리즘을 사용합니다.

```cpp
bool RayTriangleIntersect(
    vec3 orig, vec3 dir,
    vec3 v0, vec3 v1, vec3 v2,
    float& t, float& u, float& v)
{
    vec3 edge1 = v1 - v0;
    vec3 edge2 = v2 - v0;
    vec3 pvec = cross(dir, edge2);
    float det = dot(edge1, pvec);

    if (abs(det) < EPSILON) return false;

    float invDet = 1.0 / det;
    vec3 tvec = orig - v0;
    u = dot(tvec, pvec) * invDet;
    if (u < 0 || u > 1) return false;

    vec3 qvec = cross(tvec, edge1);
    v = dot(dir, qvec) * invDet;
    if (v < 0 || u + v > 1) return false;

    t = dot(edge2, qvec) * invDet;
    return t > 0;
}
```

---

## 광선-구 교차

```
┌─────────────────────────────────────────────────────────────────┐
│                    광선-구 교차                                  │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  구: |p - c|² = r²                                             │
│  광선: p = o + td                                              │
│                                                                 │
│  대입:                                                          │
│  |o + td - c|² = r²                                            │
│  t²(d·d) + 2t(d·(o-c)) + (o-c)·(o-c) - r² = 0                 │
│                                                                 │
│  판별식:                                                        │
│  a = d·d (= 1 if normalized)                                   │
│  b = 2·d·(o-c)                                                 │
│  c = (o-c)·(o-c) - r²                                          │
│                                                                 │
│  Δ = b² - 4ac                                                  │
│  Δ < 0: 교차 없음                                              │
│  Δ = 0: 접선                                                   │
│  Δ > 0: 두 점에서 교차                                         │
│                                                                 │
│  t = (-b ± √Δ) / 2a                                            │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 다음 단계

[RT 기법](02-rt-techniques.md)에서 BVH와 가속 구조를 알아봅니다.
