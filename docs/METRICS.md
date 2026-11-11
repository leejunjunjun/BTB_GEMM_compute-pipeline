# 성능 측정 정의

카운터는 테스트벤치에 있으며 하드웨어의 counter register 면적을 포함하지 않습니다.
RTL의 event 출력 비교·배선은 합성 top에 포함됩니다. 면적 비교 시 같은 top과 event 설정을 유지합니다.

| 항목 | 정의 |
|---|---|
| cycles | start 수락 후 busy가 1인 cycle 수, 마지막 출력 및 제어 종료 포함 |
| mac_cycles | 한 개 이상의 PE에서 MAC을 실행한 cycle |
| mac_slots | 모든 PE의 실행 MAC 수 합계 |
| nonzero_mac_slots | 두 피연산자가 0이 아닌 실행 MAC 수 |
| PE utilization | `mac_slots / (PE_ROWS × PE_COLS × cycles)` |
| nonzero utilization | `nonzero_mac_slots / (PE 수 × cycles)` |
| a_reads/b_reads | 외부 요청이 수락된 A/B INT8 원소 수 |
| request_stall | mem_req_valid=1, mem_req_ready=0 |
| response_stall | mem_rsp_ready=1, mem_rsp_valid=0 |
| operand_wait | loader가 바쁘고 출력 소비자가 ready인데 packet이 없는 cycle |
| compute_stall | loader 출력 packet이 다음 단계에 막힌 cycle |
| output_stall | out_valid=1, out_ready=0 |

서로 다른 stall은 겹칠 수 있으므로 합계를 total cycle로 해석하지 않습니다.
PE utilization은 MAC issue/enable 기준이며 multiplier 내부 모든 게이트의 스위칭 비율이나 전력 측정값이 아닙니다.
zero-skip은 MAC 수를 줄여 utilization 수치를 낮출 수도 있습니다. 속도는 cycle, 비용은 area 및 timing과 함께 봅니다.

기준형에서 반드시 성립하는 식:

```text
MAC slots = M*N*K
MAC cycles = ceil(M/PE_ROWS)*ceil(N/PE_COLS)*K
A reads = M*K*ceil(N/PE_COLS)
B reads = N*K*ceil(M/PE_ROWS)
```

테스트벤치가 위 식과 측정값의 일치를 검사합니다. `--optimized`에서는 이 식만 해제하며
모든 C 원소의 정답·주소·중복·미출력 검사와 프로토콜 검사는 유지합니다.

메모리 모델은 빠른 경우에도 요청 이후 응답을 생성하는 cycle이 필요합니다.
단일 8비트 포트에서 A/B를 순서대로 읽으므로 기본 PE utilization은 낮을 수 있습니다.
이는 합성 주파수 문제가 아니라 이 기준형의 데이터 공급 구조에서 발생한 대기입니다.
메모리 지연을 테스트별로 바꾸면 input starvation의 영향을 분리해 볼 수 있습니다.

10ns 시뮬레이션 clock은 기능 검증을 위한 시간 단위입니다.
실제 성능 비교는 `latency = cycles × 해당 구현에서 검증된 clock period`로 계산합니다.
파이프라인으로 cycle 수가 늘어도 timing 개선으로 실행 시간이 줄 수 있습니다.
pre-route timing을 post-route timing이나 보드 실측으로 표시하지 않습니다.

같은 입력·메모리 정책·배열 크기·clock 제약에서 기준형과 최적화를 비교합니다.
난수 stall은 동일 seed와 생성 규칙을 사용하되 요청 시점이 달라지면 각 요청이 겪는 지연도 달라질 수 있습니다.
순수 속도비는 stalls=0의 고정 조건에서 먼저 비교하고, 난수 조건은 견고성 검증 및 여러 seed 통계에 사용합니다.
