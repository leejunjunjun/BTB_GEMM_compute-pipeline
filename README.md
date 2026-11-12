# BTB GEMM Compute/Pipeline

Break the Bottleneck 프로젝트의 GEMM MAC array RTL 및 검증 소스입니다.

| 설계 | RTL | |
| --- | --- | --- |
| 기준형 | `rtl/mac_array.v` |-|
| 3가지 idea 합성 | `rtl/mac_array/mac_array_compute.v` | parameter PE_Folding =1, ACC_dup =1 통해 on/off 가능| 
| Accumulator duplication | `rtl/mac_array/mac_array_acc_duplicated.v` | data reuse individual 성능 확인 시 |
| PE folding | `rtl/mac_array/mac_array_PE_folding.v` | PE folding  individual 성능 확인 시 |
| Product module passing | `rtl/mac_array/mac_array_path.v` | mul, special case 반영 |

네 파일 모두 `mac_array` 모듈을 정의합니다. 빌드마다 공통 RTL과 함께 표에서 **한 파일만** 컴파일합니다.

## 각 모듈에 대한 간단 설명

## ACC DUPLICATE(aka. K-outer. Data reuse)

