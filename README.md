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
