# BTB GEMM Compute/Pipeline

- MAC array의 compute/pipelining 개선을 통해 area, power, cycle을 평가한다.
- 현재 후보는 accumulator duplication, PE folding, product module passing 및 pipelining이다.
- RTL 변경 시 docs/INTERFACES.md의 인터페이스 계약과 docs/METRICS.md의 측정 정의를 따른다.
- 기술 질문에는 구현 방식이 일치하는 matrix multiplier 논문을 근거로 제시한다. 신경망이나 영상 응용에 특화된 연구는 제외한다.
- 추가로 검토할 설계 방향이 있으면 제안한다.
