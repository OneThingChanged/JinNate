# 오프라인 렌더링

배치 렌더링, 컴포지팅 워크플로우, 외부 도구 연동을 분석합니다.

---

## 배치 렌더링

### 커맨드 라인 렌더링

```
┌─────────────────────────────────────────────────────────────────┐
│                  Command Line Rendering                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  기본 명령어:                                                    │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                          │   │
│  │  UnrealEditor.exe [Project] [Map] [Options]             │   │
│  │                                                          │   │
│  │  필수 옵션:                                              │   │
│  │  -game                     게임 모드                    │   │
│  │  -MoviePipelineLocalExecutorClass=...                   │   │
│  │  -LevelSequence="..."      시퀀스 경로                  │   │
│  │  -MoviePipelineConfig="..."  설정 경로                  │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  예시:                                                          │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                          │   │
│  │  UnrealEditor.exe MyProject.uproject                    │   │
│  │    /Game/Maps/MainLevel                                 │   │
│  │    -game                                                │   │
│  │    -MoviePipelineLocalExecutorClass=                    │   │
│  │      /Script/MovieRenderPipelineCore.                   │   │
│  │      MoviePipelineLocalExecutor                         │   │
│  │    -LevelSequence="/Game/Cinematics/Scene01"            │   │
│  │    -MoviePipelineConfig="/Game/Configs/HighQuality"     │   │
│  │    -NoLoadingScreen                                     │   │
│  │    -Unattended                                          │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Python 스크립트 자동화

```python
# MRQ Python 자동화
import unreal

def render_sequence(sequence_path, config_path, output_dir):
    # 서브시스템 가져오기
    subsystem = unreal.get_editor_subsystem(
        unreal.MoviePipelineQueueSubsystem)

    # 큐 생성
    queue = subsystem.get_queue()

    # 잡 추가
    job = queue.allocate_new_job()
    job.sequence = unreal.SoftObjectPath(sequence_path)
    job.map = unreal.SoftObjectPath("/Game/Maps/MainLevel")

    # 설정 로드
    config = unreal.load_asset(config_path)
    job.set_configuration(config)

    # 출력 설정 수정
    output_setting = job.get_configuration().find_or_add_setting_by_class(
        unreal.MoviePipelineOutputSetting)
    output_setting.output_directory.path = output_dir

    # 렌더 시작
    executor = unreal.MoviePipelinePIEExecutor()
    subsystem.render_queue_with_executor(executor)

# 배치 렌더링
sequences = [
    "/Game/Cinematics/Scene01",
    "/Game/Cinematics/Scene02",
    "/Game/Cinematics/Scene03"
]

for seq in sequences:
    render_sequence(
        seq,
        "/Game/Configs/HighQuality",
        f"C:/Renders/{seq.split('/')[-1]}"
    )
```

---

## 출력 파이프라인

### EXR 워크플로우

```
┌─────────────────────────────────────────────────────────────────┐
│                  EXR 컴포지팅 워크플로우                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  UE 출력:                                                        │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                          │   │
│  │  Multi-Layer EXR                                        │   │
│  │  ┌─────────────────────────────────────────────────┐   │   │
│  │  │  Layer: rgba (Beauty)                           │   │   │
│  │  │  Layer: WorldNormal.xyz                         │   │   │
│  │  │  Layer: BaseColor.rgb                           │   │   │
│  │  │  Layer: Metallic.r                              │   │   │
│  │  │  Layer: Roughness.r                             │   │   │
│  │  │  Layer: AmbientOcclusion.r                      │   │   │
│  │  │  Layer: WorldPosition.xyz                       │   │   │
│  │  │  Layer: Depth.z                                 │   │   │
│  │  │  Layer: ObjectId.r                              │   │   │
│  │  │  Layer: Velocity.xy                             │   │   │
│  │  └─────────────────────────────────────────────────┘   │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                              │                                  │
│                              ▼                                  │
│  컴포지팅 (Nuke/Fusion/After Effects):                          │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                          │   │
│  │  • 색 보정 / 그레이딩                                    │   │
│  │  • DOF 재조정                                            │   │
│  │  • 모션 블러 추가                                        │   │
│  │  • 오브젝트 마스킹 (Object ID 활용)                      │   │
│  │  • 리라이팅 (노말/AO 활용)                               │   │
│  │  • Z-Depth 기반 포그                                     │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 파일 네이밍

```cpp
// 파일 네이밍 토큰
UPROPERTY(EditAnywhere)
FString FileNameFormat = TEXT("{sequence_name}_{camera_name}_{frame_number}");

// 사용 가능한 토큰:
// {sequence_name}     - 시퀀스 이름
// {shot_name}         - 샷 이름
// {camera_name}       - 카메라 이름
// {frame_number}      - 프레임 번호 (0001, 0002, ...)
// {frame_number_rel}  - 상대 프레임 번호
// {render_pass}       - 렌더 패스 이름
// {date}              - 날짜
// {time}              - 시간
// {version}           - 버전 번호

// 예시 출력:
// Scene01_MainCamera_Beauty_0001.exr
// Scene01_MainCamera_WorldNormal_0001.exr
// Scene01_MainCamera_Depth_0001.exr
```

---

## 외부 도구 연동

### Nuke 연동

```python
# Nuke에서 UE EXR 임포트
import nuke

def import_ue_render(exr_path, frame_range):
    # 메인 Read 노드
    read = nuke.createNode('Read')
    read['file'].setValue(exr_path)
    read['first'].setValue(frame_range[0])
    read['last'].setValue(frame_range[1])

    # Shuffle 노드로 레이어 분리
    layers = [
        ('rgba', 'Beauty'),
        ('WorldNormal', 'Normal'),
        ('BaseColor', 'Albedo'),
        ('Depth', 'Depth'),
        ('ObjectId', 'Matte')
    ]

    for layer_name, output_name in layers:
        shuffle = nuke.createNode('Shuffle2')
        shuffle['in1'].setValue(layer_name)
        shuffle.setInput(0, read)
        shuffle['label'].setValue(output_name)

# EXR 메타데이터 활용
# UE는 카메라 정보를 EXR 메타데이터에 저장
def read_ue_metadata(exr_path):
    import OpenEXR
    import Imath

    exr = OpenEXR.InputFile(exr_path)
    header = exr.header()

    # 카메라 정보
    focal_length = header.get('FocalLength', None)
    sensor_width = header.get('SensorWidth', None)
    near_clip = header.get('NearClip', None)
    far_clip = header.get('FarClip', None)

    return {
        'focal_length': focal_length,
        'sensor_width': sensor_width,
        'near_clip': near_clip,
        'far_clip': far_clip
    }
```

### DaVinci Resolve 연동

```
┌─────────────────────────────────────────────────────────────────┐
│                  DaVinci Resolve 워크플로우                      │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. 프로젝트 설정:                                               │
│     • Timeline Resolution: 4K UHD                              │
│     • Timeline Frame Rate: 24fps                               │
│     • Color Science: DaVinci YRGB Color Managed                │
│     • Input Color Space: ACEScg (UE 출력과 매칭)               │
│                                                                 │
│  2. 미디어 임포트:                                               │
│     • EXR 시퀀스 임포트                                        │
│     • 프레임 레이트 확인                                        │
│     • Color Space 태그 확인                                    │
│                                                                 │
│  3. 그레이딩:                                                    │
│     • Primary 보정                                              │
│     • 세컨더리 보정 (ObjectID 마스크 활용)                      │
│     • Power Windows                                            │
│     • LUT 적용                                                  │
│                                                                 │
│  4. 출력:                                                        │
│     • ProRes 4444 또는 DNxHR 444                               │
│     • HDR 필요시 HDR10/Dolby Vision                            │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 렌더 팜 통합

### 분산 렌더링

```cpp
// 렌더 팜 잡 생성
struct FRenderFarmJob
{
    // 잡 정보
    FString JobName;
    FString ProjectPath;
    FString SequencePath;
    FString ConfigPath;

    // 프레임 범위
    int32 StartFrame;
    int32 EndFrame;

    // 청크 설정
    int32 FramesPerTask = 10;  // 태스크당 프레임 수

    // 우선순위
    int32 Priority = 50;

    // 의존성
    TArray<FString> DependsOnJobs;
};

// Deadline 플러그인 예시
void SubmitToDeadline(const FRenderFarmJob& Job)
{
    // Deadline 잡 정보 파일 생성
    FString JobInfoFile = GenerateJobInfoFile(Job);
    FString PluginInfoFile = GeneratePluginInfoFile(Job);

    // 제출
    FString Command = FString::Printf(
        TEXT("deadlinecommand %s %s"),
        *JobInfoFile,
        *PluginInfoFile);

    FPlatformProcess::ExecProcess(*Command, nullptr, nullptr);
}
```

### 렌더 팜 설정

```
┌─────────────────────────────────────────────────────────────────┐
│                  렌더 팜 아키텍처                                │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────┐                                               │
│  │  Submitter  │  (아티스트 워크스테이션)                       │
│  │  (UE + MRQ) │                                               │
│  └──────┬──────┘                                               │
│         │                                                       │
│         ▼                                                       │
│  ┌─────────────┐                                               │
│  │  Deadline   │  (렌더 팜 관리자)                              │
│  │  Repository │                                               │
│  └──────┬──────┘                                               │
│         │                                                       │
│    ┌────┴────┬─────────┬─────────┐                            │
│    ▼         ▼         ▼         ▼                            │
│  ┌────┐   ┌────┐   ┌────┐   ┌────┐                            │
│  │Node│   │Node│   │Node│   │Node│  (렌더 노드)               │
│  │ 01 │   │ 02 │   │ 03 │   │ 04 │                            │
│  └────┘   └────┘   └────┘   └────┘                            │
│                                                                 │
│  프레임 분배:                                                    │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ Frame 1-10  → Node 01                                   │   │
│  │ Frame 11-20 → Node 02                                   │   │
│  │ Frame 21-30 → Node 03                                   │   │
│  │ Frame 31-40 → Node 04                                   │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 품질 검증

### 렌더 검증 체크리스트

```
┌─────────────────────────────────────────────────────────────────┐
│                  렌더 품질 검증                                  │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  렌더링 전:                                                      │
│  □ 시퀀서 프리뷰로 타이밍 확인                                  │
│  □ 카메라 컷/전환 확인                                          │
│  □ 오디오 싱크 확인                                             │
│  □ 누락된 에셋 없음 확인                                        │
│                                                                 │
│  렌더링 중:                                                      │
│  □ 프레임 드롭 없음                                             │
│  □ 에러/경고 로그 확인                                          │
│  □ 디스크 공간 충분                                             │
│                                                                 │
│  렌더링 후:                                                      │
│  □ 프레임 수 정확                                               │
│  □ 해상도/비트 깊이 확인                                        │
│  □ 컬러 스페이스 확인                                           │
│  □ 노이즈/아티팩트 확인                                         │
│  □ 알파 채널 확인 (필요시)                                      │
│  □ AOV 패스 확인                                                │
│                                                                 │
│  자동 검증 스크립트:                                             │
│  □ 프레임 연속성 체크                                           │
│  □ 파일 크기 이상치 검출                                        │
│  □ 썸네일 생성 및 검토                                          │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 참고 자료

- [Movie Render Queue 문서](https://docs.unrealengine.com/movie-render-queue/)
- [Sequencer 문서](https://docs.unrealengine.com/sequencer/)
- [Virtual Production 문서](https://docs.unrealengine.com/virtual-production/)
- [ACES 색 관리](https://acescentral.com/)
