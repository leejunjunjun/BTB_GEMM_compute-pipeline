# BTB GEMM Compute/Pipeline

Break the Bottleneck 프로젝트의 GEMM MAC array RTL 및 검증 소스입니다.

| 설계 | RTL | 용도 |
| --- | --- | --- |
| Compute v1 | [mac_array_compute.v](rtl/mac_array/mac_array_compute.v) | ACC duplication, PE folding, product 경로 통합 |
| Compute v2 | [mac_array_compute_v2.v](rtl/mac_array/mac_array_compute_v2.v) | Sparsity 팀의 nonzero 정보와 B tag 연결 |
| Accumulator duplication | [mac_array_acc_duplicated.v](rtl/mac_array/mac_array_acc_duplicated.v) | ACC duplication 단독 비교 |
| PE folding | [mac_array_PE_folding.v](rtl/mac_array/mac_array_PE_folding.v) | PE folding 단독 비교 |
| Product module passing | [mac_array_path.v](rtl/mac_array/mac_array_path.v) | multiplier와 B 특수값 경로 단독 비교 |
## Accmulator duplication(Data_reuse) [target : buffer size가 모든 input을 커버하지 못할때 memory access의 횟수를 줄인다 ]
결정해야할 변수 : REUSE 횟수, 어떤 data (A,B)

진행할simulation option 정리 / 사용한 testbench file, other module file 명


## PE folding [target : cycle pipelining /Area reduce]
timing diagram 
(관련 설명 추가)
(timing diagram 이미지 추가)

진행할 시뮬레이션 option 정리

## Product module passing [targete : power]
단순 simulation 상에서 확인 불가능

-> sparsity team의 module처럼 is_{specialcase} event 신호를 추가하면 특수 case에 대한 빈번함? 체크 가능 

## mac_array_compute.v

ACC duplication, PE folding, passing module을 합친 모듈입니다. 아래 parameter를 조정하여 on/off 가능
| Global parameter | 기본값 | `0` (OFF) | `1` (ON) |
| --- | --- | --- | --- |
| `PE_Folding` | `0` | 16개 product 유닛으로 4×4 타일을 한 phase에 처리 | 8개 product 유닛을 재사용해 위쪽 2행과 아래쪽 2행을 두 phase로 처리 |
| `ACC_dup` | `0` | ACC bank 0만 사용 | 타일별 부분합을 별도 ACC bank에 저장. K-outer 순서로 입력을 공급하며, 한 그룹에서 최대 8개 타일 처리 |

###local param : REUSE 
| 설정 | 기본값 | 동작 |
| --- | --- | --- |
| `REUSE` | `8` | `ACC_dup=1`일 때 한 그룹에서 ACC bank 0~7에 최대 8개 타일의 부분합을 따로 저장한다. `ACC_dup=0`이면 bank 0만 사용한다. |
A data, B data reuse 설정이 불가능함.

## mac_array_compute_v2.v — sparsity 출력 연결
compute team의 idea 구현은 version 1과 동일 sparsity team의 output을 받아 처리하는 부분을 추가하였습니다.

1. **입력 포트** — `op_a_nz[r]`와 `op_b_nz[c]`를 추가했다. 현재 B 열의 활성 여부는 `op_b_tag[4*c +: 4] != 0`으로 판단한다. `op_b_nz`는 선언만 되어 있다.
2. **PE별 연산 마스크** — `FACTORED_MASK=0`이면 기존 `work_mask[r*PE_COLS+c]`를 쓴다. `1`이면 `op_a_nz[r] && (op_b_tag[4*c +: 4] != 0)`으로 `work_enable`을 만든다. 타일 가장자리의 유효 행·열은 `op_rows`와 `op_cols`로 확인한다.
3. **MAC 이벤트와 multiplier enable** — `event_mac`에는 `work_enable`과 현재 phase를 반영한다. v2의 `event_nonzero_mac`은 여기에 A와 B 데이터가 모두 0이 아닌 조건을 더한다. 이 신호와 일반 곱셈 tag(`4'b0001`)가 함께 들어올 때 Booth multiplier 입력을 활성화한다. ±A와 시프트는 tag로 선택한다.
4. **ACC 갱신** — 유효 PE에서 `op_first=1`이면 기존 부분합을 0부터 시작한다. 이후 `work_enable=0`이면 ACC 값을 유지한다. 유효 범위 밖의 PE는 0으로 처리한다. Folded/Unfolded 경로 모두 같은 조건을 쓴다.

## 시뮬레이션 옵션

아래 값은 testbench나 상위 모듈에서 `mac_array_compute #(...)` 인스턴스를 만들 때 지정한다. 두 파일 모두 `mac_array_compute`, `product`, `mul`을 정의하므로 한 빌드에 v1 또는 v2 중 하나만 넣는다. 이 저장소의 `main`에는 RTL만 있으므로, GEMM 통합 시뮬레이션에는 프로젝트의 top과 testbench를 함께 사용한다. 기존 top에서 `mac_array`를 인스턴스화하고 있다면 모듈 이름과 compute 포트 연결을 맞춘다.

| 파라미터 | 적용 | 기본값 | 변경하면 |
| --- | --- | --- | --- |
| `ACC_dup` | v1, v2 | `0` | `0`은 ACC bank 0 사용. `1`은 여러 타일의 부분합을 bank별로 보관. 입력은 K-outer 순서로 공급하고, 새 그룹의 첫 K에서 타일별 `op_first`를 설정한다. 그룹당 최대 8타일. |
| `PE_Folding` | v1, v2 | `0` | `0`은 4×4 타일을 한 번에 처리. `1`은 8개 product 유닛을 두 phase에 걸쳐 재사용. 입력 데이터, tag, mask, 제어 신호를 `op_valid && op_ready`까지 유지한다. |
| `FACTORED_MASK` | v2 | `0` | `0`은 `work_mask` 사용. `1`은 sparsity 쪽의 A nonzero 비트와 B tag 사용. |
| `PE_ROWS`, `PE_COLS` | v1, v2 | `4`, `4` | 포트와 결과 패킹 일부가 4행 고정이므로 이 버전의 비교는 4×4 기준으로 진행한다. |

`REUSE=8`과 folding 시 `PHASE_ROWS=PE_ROWS/2`는 RTL의 `localparam`이다. 시뮬레이션 파라미터로 바로 덮어쓸 수 없다. Folding 제어는 두 phase를 기준으로 짜여 있다.
