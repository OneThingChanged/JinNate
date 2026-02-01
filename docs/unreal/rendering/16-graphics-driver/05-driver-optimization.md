# 게임 엔진 통합

UE의 드라이버 통합과 최적화를 설명합니다.

---

## UE 드라이버 정보 접근

### FGPUDriverInfo

```cpp
// 드라이버 정보 조회
FGPUDriverInfo DriverInfo = FPlatformMisc::GetGPUDriverInfo(GRHIDeviceDescription);

// 사용 가능한 정보
FString VendorId = DriverInfo.VendorId;          // "10DE" (NVIDIA)
FString DeviceDescription = DriverInfo.DeviceDescription;  // "NVIDIA GeForce RTX 3080"
FString DriverVersion = DriverInfo.UserDriverVersion;      // "512.95"
FString DriverDate = DriverInfo.DriverDate;     // "2022-05-15"
```

### 벤더 ID

| 벤더 | ID |
|------|-----|
| NVIDIA | 0x10DE |
| AMD | 0x1002 |
| Intel | 0x8086 |
| Qualcomm | 0x5143 |

---

## 드라이버 워크어라운드

특정 드라이버 버그에 대한 우회 코드를 구현합니다.

```cpp
// 드라이버별 워크어라운드 예시
void ApplyDriverWorkarounds()
{
    FGPUDriverInfo DriverInfo = GetDriverInfo();

    // NVIDIA 특정 버전 버그 우회
    if (DriverInfo.IsNVIDIA())
    {
        int32 DriverVersion = ParseDriverVersion(DriverInfo.UserDriverVersion);

        if (DriverVersion >= 51200 && DriverVersion < 51295)
        {
            // 텍스처 좌표 오프셋 버그 우회
            bUseCustomTexCoordOffset = true;
        }
    }

    // AMD 특정 버그 우회
    if (DriverInfo.IsAMD())
    {
        // 특정 셰이더 컴파일러 버그 우회
        bDisableAsyncShaderCompilation = true;
    }
}
```

---

## 성능 최적화 통합

### 드라이버 힌트

```cpp
// NVIDIA 전용 힌트
#if WITH_NVAPI
    NvAPI_D3D11_BeginUAVOverlapEx(Context, true);  // UAV 오버랩 허용
    // ... 렌더링 ...
    NvAPI_D3D11_EndUAVOverlap(Context);
#endif

// AMD 전용 힌트
#if WITH_AGS
    agsDriverExtensionsDX12_SetDepthBounds(
        AgsContext, CommandList,
        MinDepth, MaxDepth
    );
#endif
```

### 프로파일 연동

```
┌─────────────────────────────────────────────────────────────────┐
│                    UE 프로파일링 도구 연동                       │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  NVIDIA NSight:                                                 │
│  • Aftermath SDK 통합 (크래시 덤프)                            │
│  • NSight Graphics 프레임 캡처                                  │
│  • NVTX 마커 삽입                                              │
│                                                                 │
│  AMD:                                                           │
│  • RGP (Radeon GPU Profiler) 연동                              │
│  • PIX 지원                                                    │
│                                                                 │
│  공통:                                                          │
│  • RenderDoc 호환                                              │
│  • GPU 프로파일러 (stat GPU)                                   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 드라이버 업데이트 권장

### 최소 드라이버 버전 체크

```cpp
// 시작 시 드라이버 버전 확인
void CheckMinimumDriverVersion()
{
    FGPUDriverInfo DriverInfo = GetDriverInfo();

    if (DriverInfo.IsNVIDIA())
    {
        const int32 MinVersion = 47200;  // 472.00
        if (ParseVersion(DriverInfo) < MinVersion)
        {
            ShowWarning("드라이버 업데이트를 권장합니다.");
        }
    }
}
```

---

## 문제 해결

```
┌─────────────────────────────────────────────────────────────────┐
│                    일반적인 드라이버 문제                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  문제: 그래픽 아티팩트                                          │
│  해결: 드라이버 업데이트, VRAM 안정성 확인                      │
│                                                                 │
│  문제: TDR 발생                                                 │
│  해결: 셰이더 복잡도 감소, 타임아웃 늘리기 (개발용)            │
│                                                                 │
│  문제: 성능 저하                                                │
│  해결: 드라이버 프로파일 설정, 전원 관리 모드 확인             │
│                                                                 │
│  문제: 크래시                                                   │
│  해결: 이전 안정 버전 드라이버, 디버그 레이어 확인             │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 참고 자료

- [NVIDIA Developer](https://developer.nvidia.com/)
- [AMD GPUOpen](https://gpuopen.com/)
- [Intel Graphics Developer](https://www.intel.com/content/www/us/en/developer/tools/graphics/overview.html)
- [원본 문서 (timlly)](https://www.cnblogs.com/timlly/p/16404963.html)
