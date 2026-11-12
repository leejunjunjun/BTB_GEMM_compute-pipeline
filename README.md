# BTB GEMM Compute/Pipeline

Break the Bottleneck 프로젝트의 GEMM MAC array RTL 및 검증 소스입니다.
기준 설계는 4×4 PE, signed INT8 입력, INT32 누산으로 C=A×B를 계산합니다.
세 후보 설계를 기준형과 비교해 면적, 전력, 실행 사이클을 평가합니다.

| 설계 | RTL |
| --- | --- |
| 기준형 | `rtl/mac_array.v` |
| Accumulator duplication | `rtl/variants/mac_array_acc_duplicated.v` |
| PE folding | `rtl/variants/mac_array_PE_folding.v` |
| Product module passing / pipelining 검토 | `rtl/variants/mac_array_path.v` |

네 파일 모두 `mac_array` 모듈을 정의합니다. 빌드마다 공통 RTL과 함께 표에서 **한 파일만** 컴파일합니다.

- [인터페이스 계약](docs/INTERFACES.md)
- [측정 정의](docs/METRICS.md)
- [원본 회원 배포 안내](docs/MEMBER_DISTRIBUTION.md)
- 테스트벤치와 ready/valid 검증 모듈은 `tb/`에 있습니다.

원본 배포 안내의 `scripts/` 실행 도구는 제공된 파일에 포함되어 있지 않습니다.
테스트벤치는 `DATA_DIR`에서 `config.hex`, `a.hex`, `b.hex`, `c.hex`를 읽습니다.
후보별 기능 검증과 합성 결과는 이 저장소에 아직 기록되지 않았습니다.

## ACC 복제 검토

### 목적

외부 메모리에서 읽은 B 데이터를 여러 A 행 타일에 재사용합니다. 출력 타일별 부분합을 별도 ACC 세트에 유지해, B 버퍼를 줄였을 때 늘어나는 외부 읽기와 실행 사이클을 줄이는 방식입니다.

### 시뮬레이터 비교

A 버퍼 4 KB, M=64, N=128 조건의 추정 사이클입니다. 각 행은 같은 K에서 B 버퍼 16 KB·ACC 복제 미적용 구성을 1.00×로 둡니다. B 버퍼 16 KB에서는 두 구성의 사이클이 같았습니다.

| K | B 4 KB · 복제 미적용 | B 0.25 KB · 복제 미적용 | B 0.25 KB · ACC 최대 8세트 |
| ---: | ---: | ---: | ---: |
| 128 | 1.27× | 5.64× | 1.31× |
| 256 | 1.68× | 5.03× | 1.72× |
| 512 | 2.23× | 3.95× | 2.21× |
| 1024 | 2.65× | 2.72× | 2.72× |

K=128~512에서는 ACC 복제로 B 버퍼 0.25 KB에서 B 버퍼 4 KB 구성과 비슷한 사이클을 얻었습니다. K=1024에서는 A 버퍼에 행 타일 하나만 들어가므로 활성 ACC는 한 세트입니다.

### 활성 ACC 세트와 비용

- INT8 입력과 4행 타일 기준으로 A 행 타일 하나는 `4 × K` 바이트입니다.
- A 버퍼에 행 타일이 하나 이상 들어가는 경우, 활성 ACC 세트 수는 `min(하드웨어 세트 수, floor(A 버퍼 바이트 / (4 × K)), ceil(M / 4))`로 정합니다.
- 작은 B 버퍼에서 절감한 메모리와 추가 ACC 레지스터의 면적·전력을 비교하고, ACC 분리의 파이프라이닝 활용 가능성도 검토합니다.

[GEMM Reuse 시뮬레이터](docs/gemm-reuse19.html)를 다운로드해 브라우저에서 열 수 있습니다.
