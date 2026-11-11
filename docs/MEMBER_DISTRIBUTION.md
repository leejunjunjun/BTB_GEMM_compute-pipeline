# BTB GEMM 회원 배포본

검증된 v2의 RTL과 실행 도구를 그대로 담은 경량본입니다.
4×4(16 PE), signed INT8 입력·INT32 누산, C=A×B입니다.
진행자의 실행 로그·합성 결과·체크포인트·전체 검증 기록은 제외했습니다.
입력 데이터와 정답은 실행 시 자동 생성됩니다.

## 시작하기

Python 3와 Vivado Simulator가 필요합니다. 이 폴더에서 실행합니다.
설치 경로가 다르면 --vivado-bin을 변경합니다.

```powershell
python scripts/run.py --vivado-bin C:/Xilinx/Vivado/2022.2/bin --suite --build build/baseline
```

PASS를 확인한 뒤 팀별 RTL을 수정합니다.

| 팀 | 수정할 파일 |
|---|---|
| Memory/Dataflow | rtl/operand_loader.v |
| Compute/Pipeline | rtl/mac_array.v |
| Sparsity | rtl/sparsity_frontend.v |

[인터페이스 계약](docs/INTERFACES.md)과 [측정 정의](docs/METRICS.md)를 지킵니다.
기본형은 dense GEMM이며 추가 파이프라인·캐시·zero-skip은 참가자 구현 대상입니다.

## 수정 후 검증·비교

```powershell
python scripts/run.py --vivado-bin C:/Xilinx/Vivado/2022.2/bin --suite --optimized --build build/candidate
python scripts/compare.py build/baseline/results.json build/candidate/results.json --out build/comparison.csv
```

결과는 build/ 아래에 생성됩니다. summary.csv는 cycle·MAC 수·메모리 대기,
per_pe.csv는 PE별 MAC 수입니다. --optimized에서도 정답과 handshake 검사는 유지됩니다.
최종 제출 전에는 기준형과 수정본 모두 --suite --extended로 실행하여 같은 조건에서 비교합니다.
기준 결과를 보존하고 candidate 실행으로 덮어쓰지 마세요.

## 합성·타이밍 분석

```powershell
python scripts/synth.py --vivado-bin C:/Xilinx/Vivado/2022.2/bin --cleanup-workaround
```

4×4 기본 타깃 xczu2cg-sfvc784-1-e, clock 10ns, 입출력 delay 2ns입니다.
build/synth/에 결과를 생성합니다. --cleanup-workaround는 Windows Vivado 2022.2의
임시 폴더 삭제 오류용이며 문제가 없는 환경에서는 생략합니다.
배선 전 타이밍 추정이며 실제 보드 주파수 보장은 아닙니다.

계획서의 Yosys/OpenSTA를 사용할 때는 진행자가 도구와 Liberty 파일을 준비한 뒤 실행합니다.
이 경로는 v2에서 실행 검증하지 않았습니다.

```text
python scripts/asic.py --liberty /path/to/cells.lib --sta --period-ns 10
```

tb/rv_delay.v와 scripts/stress.py는 run.py가 사용하는 검증 의존 파일입니다.
기본 합성에는 포함되지 않으며 최적화 대상 RTL도 아닙니다.
