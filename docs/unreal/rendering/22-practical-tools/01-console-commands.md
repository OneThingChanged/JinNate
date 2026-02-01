# 콘솔 명령어 모음

렌더링 관련 콘솔 명령어와 CVar를 정리합니다.

---

## 통계 명령어 (stat)

```
┌─────────────────────────────────────────────────────────────────┐
│                      Stat Commands                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  기본 성능:                                                     │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  stat fps              프레임레이트 및 밀리초            │   │
│  │  stat unit             GT/RT/GPU/RHIT 시간              │   │
│  │  stat unitgraph        유닛 그래프 표시                  │   │
│  │  stat raw              Raw 통계                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  렌더링:                                                        │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  stat gpu              GPU 패스별 시간                   │   │
│  │  stat scenerendering   씬 렌더링 상세                    │   │
│  │  stat initviews        가시성 계산                       │   │
│  │  stat lightrendering   라이팅 렌더링                     │   │
│  │  stat shadowrendering  그림자 렌더링                     │   │
│  │  stat rhi              RHI 통계                          │   │
│  │  stat d3d12rhi         D3D12 RHI 통계                    │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  오브젝트:                                                      │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  stat particles        파티클 통계                       │   │
│  │  stat anim             애니메이션                        │   │
│  │  stat component        컴포넌트                          │   │
│  │  stat staticmesh       스태틱 메시                       │   │
│  │  stat skeletalmesh     스켈레탈 메시                     │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  메모리:                                                        │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  stat memory           메모리 개요                       │   │
│  │  stat memoryplatform   플랫폼별 메모리                   │   │
│  │  stat memorystatic     정적 메모리                       │   │
│  │  stat streaming        텍스처 스트리밍                   │   │
│  │  stat streamingdetails 스트리밍 상세                     │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### stat 사용법

```cpp
// 콘솔에서 사용
stat fps               // 활성화
stat fps               // 다시 입력하면 비활성화
stat none              // 모든 stat 비활성화

// 여러 stat 동시 표시
stat unit
stat gpu
stat scenerendering

// 코드에서 stat 제어
void ToggleStatDisplay()
{
    // stat 명령 실행
    GEngine->Exec(GetWorld(), TEXT("stat fps"));
}

// 커스텀 stat 그룹 표시
// stat MyGame (STATGROUP_MyGame으로 정의된 경우)
```

---

## 렌더링 명령어 (r.)

```
┌─────────────────────────────────────────────────────────────────┐
│                   Rendering CVars (r.)                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  해상도/스케일:                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  r.ScreenPercentage=100       렌더링 해상도 %           │   │
│  │  r.DynamicRes.OperationMode=1 동적 해상도 활성화        │   │
│  │  r.MipMapLODBias=0            밉맵 바이어스             │   │
│  │  r.SetRes=1920x1080f          해상도 설정               │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  그림자:                                                        │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  r.Shadow.CSM.MaxCascades=4   CSM 캐스케이드 수         │   │
│  │  r.Shadow.MaxResolution=2048  최대 그림자 해상도        │   │
│  │  r.Shadow.RadiusThreshold=0.01 그림자 반경 임계값       │   │
│  │  r.Shadow.DistanceScale=1.0   그림자 거리 스케일        │   │
│  │  r.ShadowQuality=5            그림자 품질 (0-5)         │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  포스트 프로세스:                                               │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  r.BloomQuality=5             블룸 품질                  │   │
│  │  r.MotionBlurQuality=4        모션 블러 품질            │   │
│  │  r.DepthOfFieldQuality=2      DOF 품질                  │   │
│  │  r.SSR.Quality=3              SSR 품질                  │   │
│  │  r.AmbientOcclusionLevels=3   AO 레벨                   │   │
│  │  r.Tonemapper.Quality=1       톤매퍼 품질               │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  안티앨리어싱:                                                  │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  r.AntiAliasingMethod=2       AA 방식 (0=None,1=FXAA,   │   │
│  │                               2=TAA,3=MSAA,4=TSR)       │   │
│  │  r.TemporalAACurrentFrameWeight=0.04 TAA 가중치         │   │
│  │  r.TemporalAASamples=8        TAA 샘플 수               │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 주요 r. 명령어 상세

```cpp
// 그래픽 피처 토글
r.DefaultFeature.AutoExposure=1     // 자동 노출
r.DefaultFeature.MotionBlur=1       // 모션 블러
r.DefaultFeature.Bloom=1            // 블룸
r.DefaultFeature.AmbientOcclusion=1 // AO
r.DefaultFeature.LensFlare=1        // 렌즈 플레어

// Nanite
r.Nanite=1                          // Nanite 활성화
r.Nanite.MaxPixelsPerEdge=1         // 픽셀당 최대 엣지
r.Nanite.Visualize.Overview=1       // Nanite 오버뷰 시각화

// Lumen
r.Lumen.DiffuseIndirect.Allow=1     // Lumen 간접광
r.Lumen.Reflections.Allow=1         // Lumen 반사
r.Lumen.TraceMeshSDFs=1             // SDF 트레이싱

// Virtual Shadow Maps
r.Shadow.Virtual.Enable=1           // VSM 활성화
r.Shadow.Virtual.ResolutionLodBiasLocal=0 // 로컬 라이트 LOD 바이어스

// 레이트레이싱
r.RayTracing=1                      // 레이트레이싱 활성화
r.RayTracing.GlobalIllumination=1   // RT GI
r.RayTracing.Reflections=1          // RT 반사
r.RayTracing.Shadows=1              // RT 그림자

// 디버그
r.ShaderDevelopmentMode=1           // 셰이더 개발 모드
r.DumpShaderDebugInfo=1             // 셰이더 디버그 정보 덤프
r.GPUCrashDebugging=1               // GPU 크래시 디버깅
```

---

## Show 명령어

```
┌─────────────────────────────────────────────────────────────────┐
│                     Show Commands                               │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  오브젝트 표시:                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Show StaticMeshes         스태틱 메시                   │   │
│  │  Show SkeletalMeshes       스켈레탈 메시                 │   │
│  │  Show Landscape            랜드스케이프                  │   │
│  │  Show Foliage              폴리지                        │   │
│  │  Show InstancedStaticMeshes 인스턴스 메시               │   │
│  │  Show Particles            파티클                        │   │
│  │  Show Decals               데칼                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  디버그 표시:                                                   │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Show Collision            콜리전                        │   │
│  │  Show Bounds               바운드 박스                   │   │
│  │  Show BSP                  BSP 지오메트리                │   │
│  │  Show Navigation           네비게이션 메시               │   │
│  │  Show Volumes              볼륨                          │   │
│  │  Show LightRadius          라이트 반경                   │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  렌더링 피처:                                                   │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Show PostProcessing       포스트 프로세스               │   │
│  │  Show Bloom                블룸                          │   │
│  │  Show MotionBlur           모션 블러                     │   │
│  │  Show DepthOfField         DOF                           │   │
│  │  Show AmbientOcclusion     AO                            │   │
│  │  Show DynamicShadows       동적 그림자                   │   │
│  │  Show GlobalIllumination   GI                            │   │
│  │  Show Fog                  포그                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### ShowFlag 사용

```cpp
// 콘솔에서
Show Collision          // 토글
Show Collision 1        // 켜기
Show Collision 0        // 끄기

// 코드에서 ShowFlag 제어
void ToggleCollisionView(APlayerController* PC)
{
    if (PC && PC->GetLocalPlayer())
    {
        UGameViewportClient* Viewport = PC->GetLocalPlayer()->ViewportClient;
        if (Viewport)
        {
            // 콜리전 표시 토글
            Viewport->EngineShowFlags.Collision =
                !Viewport->EngineShowFlags.Collision;
        }
    }
}

// 에디터에서 EngineShowFlags 설정
FEngineShowFlags ShowFlags = FEngineShowFlags(ESFIM_Editor);
ShowFlags.SetCollision(true);
ShowFlags.SetBounds(true);
ShowFlags.SetPostProcessing(false);
```

---

## 셰이더 명령어

```
┌─────────────────────────────────────────────────────────────────┐
│                    Shader Commands                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  컴파일:                                                        │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  recompileshaders all          모든 셰이더 재컴파일      │   │
│  │  recompileshaders changed      변경된 셰이더만           │   │
│  │  recompileshaders material X   특정 머티리얼             │   │
│  │  recompileshaders global       글로벌 셰이더             │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  디버그:                                                        │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  r.ShaderDevelopmentMode=1     개발 모드                 │   │
│  │  r.DumpShaderDebugInfo=1       디버그 정보 덤프          │   │
│  │  r.DumpShaderDebugShortNames=1 짧은 이름 사용            │   │
│  │  r.Shaders.Optimize=0          최적화 비활성화           │   │
│  │  r.Shaders.KeepDebugInfo=1     디버그 정보 유지          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  캐시:                                                          │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  r.ShaderPipelineCache.Enabled=1 파이프라인 캐시         │   │
│  │  r.ShaderPipelineCache.SaveBinary=1 바이너리 저장        │   │
│  │  r.ShaderCodeLibrary=1          셰이더 라이브러리        │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 프로파일링 명령어

```
┌─────────────────────────────────────────────────────────────────┐
│                  Profiling Commands                             │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  GPU 프로파일링:                                                │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  ProfileGPU                 GPU 프로파일 (한 프레임)     │   │
│  │  ProfileGPU 10              GPU 프로파일 (10 프레임)     │   │
│  │  r.GPUStatsEnabled=1        GPU 통계 활성화              │   │
│  │  r.ProfileGPU.ShowUI=1      GPU 프로파일 UI              │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  CPU 프로파일링:                                                │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  stat startfile             프로파일 녹화 시작           │   │
│  │  stat stopfile              프로파일 녹화 종료           │   │
│  │  DumpFrame                   프레임 덤프                 │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  FPS 차트:                                                      │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  StartFPSChart              FPS 차트 녹화 시작           │   │
│  │  StopFPSChart               FPS 차트 녹화 종료           │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  Unreal Insights:                                               │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Trace.Start                트레이스 시작                │   │
│  │  Trace.Stop                 트레이스 종료                │   │
│  │  Trace.Bookmark X           북마크 추가                  │   │
│  │  -trace=cpu,gpu,frame       실행 인자로 지정            │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 유틸리티 명령어

```cpp
// 화면 캡처
HighResShot 1920x1080           // 고해상도 스크린샷
HighResShot 4                   // 4배 해상도
Shot                            // 일반 스크린샷

// 렌더링 프리즈
FreezeRendering                 // 렌더링 고정/해제
PauseRenderClock               // 렌더 클럭 일시정지

// 카메라
ToggleDebugCamera              // 디버그 카메라 토글
ViewMode [Mode]                // 뷰모드 변경

// 메모리
MemReport                      // 메모리 리포트
MemReport -Full                // 상세 메모리 리포트
obj list class=Texture2D       // 특정 클래스 오브젝트 목록
obj gc                         // 가비지 컬렉션 강제 실행

// 레벨
open [MapName]                 // 맵 열기
travel [MapName]               // 맵 이동
restartlevel                   // 레벨 재시작

// 기타
Quit                           // 에디터/게임 종료
Exit                           // 종료
DisplayAll [Class] [Property]  // 특정 클래스의 속성 표시
```

---

## 유용한 CVar 조합

```cpp
// 성능 디버깅 세트
r.ScreenPercentage=100
r.DynamicRes.OperationMode=0
r.Shadow.MaxResolution=512
r.BloomQuality=0
r.MotionBlurQuality=0

// 최고 품질 세트
r.ScreenPercentage=200
sg.ResolutionQuality=100
sg.ViewDistanceQuality=3
sg.AntiAliasingQuality=3
sg.ShadowQuality=3
sg.PostProcessQuality=3
sg.TextureQuality=3
sg.EffectsQuality=3
sg.FoliageQuality=3

// 셰이더 디버깅 세트
r.ShaderDevelopmentMode=1
r.DumpShaderDebugInfo=1
r.Shaders.Optimize=0
r.Shaders.KeepDebugInfo=1

// 메모리 절약 세트
r.Streaming.PoolSize=500
r.Streaming.MipBias=1
r.Shadow.MaxResolution=512
r.MaxAnisotropy=4
```

---

## 참고 자료

- [Console Variables](https://docs.unrealengine.com/console-variables/)
- [Stat Commands](https://docs.unrealengine.com/stat-commands/)
- [Show Flags](https://docs.unrealengine.com/show-flags/)
