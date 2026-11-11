# 공통 인터페이스 계약

## 공통 규칙

- `clk` 상승 에지에서만 전송합니다. `valid && ready`가 동시에 1이면 정확히 1개 전송입니다.
- `valid=1, ready=0` 동안 valid와 **모든 payload/metadata**를 유지합니다.
- `rst`는 active-high 동기식 reset입니다. 모듈 내부의 미완료 작업과 외부 메모리 모델을 함께 초기화합니다.
- 계산 결과의 순서는 tile 순서를 유지합니다. 계산 파이프라인의 cycle 수는 바꿀 수 있습니다.
- reset 없이 연속 작업을 지원합니다. 작업별 누산 상태가 다음 작업에 섞이면 안 됩니다.

## 외부 host 및 메모리

`start && !busy`에서 `cfg_m, cfg_n, cfg_k`를 저장합니다. busy 중 start는 무시합니다.
차원이 0이거나 최대 범위를 넘으면 메모리 요청 없이 `done=1,error=1`로 거부합니다.
`done`은 1 cycle이고 error는 다음 시작 또는 reset까지 유지합니다.

`mem_req_is_b=0`은 A, 1은 B입니다. 두 메모리는 별도 주소 공간이고 시작 인덱스가 각각 0입니다.
주소는 INT8 원소 인덱스이며 A는 `row*K+k`, B는 `k*N+col`입니다.
읽기 요청을 수락한 뒤 응답을 ready가 될 때까지 유지합니다. 기본 메모리 계약은 **미완료 요청 최대 1개**입니다.
AXI/DRAM 컨트롤러는 이 배포본에 포함하지 않습니다.

출력은 `out_addr=row*N+col`, signed INT32 `out_data`입니다. **주소를 사용해 C에 기록해야 합니다.**
4×4 tile 안을 먼저 출력하므로 전체 주소가 0,1,2,... 순으로만 나오지는 않습니다.
반드시 모든 M×N 주소를 한 번씩 기록하며 마지막 출력 수락 후 완료합니다.

## control → loader: tile reduction step

`req_a_addr`는 tile의 첫 A 행에서 현재 k 위치, `req_a_stride=K`입니다.
`req_b_addr`는 현재 B의 k행과 tile의 첫 출력 열 위치입니다.
`req_rows`, `req_cols`는 가장자리 tile의 유효 행·열 mask입니다.
`req_first`는 k=0, `req_last`는 k=K-1입니다. K=1이면 둘 다 1입니다.

loader는 descriptor를 수락한 뒤 A의 유효 행들과 B의 유효 열들을 읽어 한 packet을 만듭니다.
Memory 팀은 캐시/버퍼/선행 읽기 등을 추가할 수 있지만 descriptor와 packet 순서를 보존합니다.

## loader → sparsity → compute: operand packet

| 신호 | 의미 |
|---|---|
| `op_a[8*r +: 8]` | tile의 r행 A 원소, signed INT8 |
| `op_b[8*c +: 8]` | tile의 c열 B 원소, signed INT8 |
| rows/cols mask | 존재하는 출력 행·열. tile 동안 동일 |
| first | 해당 출력 tile의 누산을 새로 시작 |
| last | 해당 출력 tile의 결과를 생성 |
| `work_mask[r*PE_COLS+c]` | 그 packet에서 해당 PE의 곱셈·누산 실행 여부 |

**출력 소유권 mask(rows/cols)와 work_mask를 구별합니다.** 특정 곱셈을 생략해도 해당 C 원소는
최종 출력해야 합니다. `first=1`이면 work_mask가 0인 lane도 누산을 0으로 초기화합니다.
`last=1`이면 work_mask가 0인 lane도 유지된 누산값을 출력합니다. K=1 및 all-zero tile도 완료해야 합니다.

기준형 sparsity_frontend는 work_mask를 rows×cols로 설정하며 실제 zero-skip은 하지 않습니다.
Sparsity 팀은 연산 mask, packet 압축, 작업 분배 등을 실험할 수 있습니다. first/last가 붙은 빈
packet을 무조건 제거하면 누산 초기화나 완료가 사라집니다. 빈 시작·끝의 의미를 보존해야 합니다.
현재 packet은 한 k의 outer product입니다. 서로 다른 k를 lane별로 재분배하는 설계는 compute 팀과
추가 태그/누산 목적지를 함께 설계해야 하며, 기존 인터페이스가 자동으로 지원하는 기능은 아닙니다.

## compute → writer: 결과 packet

결과는 `result_data[32*(r*PE_COLS+c) +: 32]`에 놓고 `result_mask`로 유효 출력을 표시합니다.
연산 stage 수와 latency는 고정하지 않습니다. 마지막 입력이 수락된 뒤 정확히 1개의 결과 packet을
내보내고 writer가 수락할 때까지 유지합니다. controller는 handshake를 기다리므로 고정 cycle 지연에 의존하지 않습니다.

## 측정 event

`event_mac[p]`는 해당 상승 에지에 PE p가 **실제로 실행한** MAC의 enable입니다.
`event_nonzero_mac[p]`는 그중 두 피연산자가 모두 0이 아닌 연산입니다.
파이프라인을 추가하면 실제 실행 stage에 맞춰 event도 이동시킵니다. zero-skip 시 생략한 연산은 세지 않습니다.
event는 기능 제어용 ready/valid 신호가 아닙니다.

현재 `event_operand_wait`는 loader가 바쁜 동안 그 출력 소비자가 ready인데 공급 packet이 없는 cycle입니다.
`event_compute_stall`은 loader의 packet이 다음 단계에 의해 막힌 cycle입니다. sparsity_frontend에 큐를 넣으면
이 값은 그 경계의 대기이며 MAC 내부 대기 전체를 뜻하지 않습니다. 병목을 더 세분화하려면 측정 정의를 함께 확장합니다.
