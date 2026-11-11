`timescale 1ns/1ps
// loader가 A 한 조각을 읽어 두고, 서로 다른 열 타일의 B와 짝지어
// op를 REUSE개씩 연달아 보낸다 (A,B0) → (A,B1) → (A,B0) → ...
// PE마다 acc를 REUSE개 두고, op가 들어올 때마다 bank를 번갈아 써서
// 여러 출력 타일을 동시에 누산한다. REUSE=1이면 baseline과 동일하게 동작
//global variable A_reuse, B_reuse가 추가됨. reuse 횟수 정함.
module mac_array #(parameter PE_ROWS=4,PE_COLS=4, A_reuse=1, B_reuse=4) 
(
    input clk,rst,input op_valid,output op_ready,
    input [8*PE_ROWS-1:0] op_a,input [8*PE_COLS-1:0] op_b,
    input [PE_ROWS-1:0] op_rows,input [PE_COLS-1:0] op_cols,
    input op_first,op_last,
    input [PE_ROWS*PE_COLS-1:0] work_mask,
    output reg result_valid,input result_ready,
    output reg [32*PE_ROWS*PE_COLS-1:0] result_data,
    output reg [PE_ROWS*PE_COLS-1:0] result_mask,
    output [PE_ROWS*PE_COLS-1:0] event_mac,event_nonzero_mac
);
    localparam P=PE_ROWS*PE_COLS;
    localparam REUSE = A_reuse * B_reuse;   // 동시에 acc하는 출력 타일 수
    localparam ACC_IDX_W = (REUSE > 1) ? $clog2(REUSE) : 1;  
    // REUSE=1일 때 폭이 0이 되는 것을 방지하기 위해 삼항연산자 사용.
    // log는 REUSE를 고려한 비트폭 2진수를 구하기 위함.


    // bank 선택 카운터를 구현할 때,
    // op를 받을 때마다 0 → 1 → ... → REUSE-1 → 0 순서로 순환한다

    /////// N 또는 M열이 A_reuse, B_reuse로 정확히 나누어 떨어지지 않을때 idx 순환 조건 ////////
    // 예를 들어, Reuse가 2이고 B가 20열이면 B의 4개열씩 각 0 1 0 1 0 acc에 들어가서 계산
    // 이러면 5번째 B (16열~20열)은 매칭될 세트가 없어 0번 acc 뒤에 바로 0번 acc에 계산
    // (다시 말해, 1번 acc를 사용하지 않음)
    // 이를 해결하기 위해 op_first 신호와 op_last 신호로 index를 계산하는 로직이 바로 아래

    reg [ACC_IDX_W-1:0] acc_idx; //바로 앞 op에서 사용한 bank
    reg prev_last; //바로 앞 op의 op_last
    reg [ACC_IDX_W-1:0] grp_last; //이번 묶음의 마지막 bank번호
    wire group_start = op_first && prev_last; //op_last 뒤에 나오는 op_first는 묶음의 첫 시작
    wire [ACC_IDX_W-1:0] cur_idx = group_start ? {ACC_IDX_W{1'b0}} : op_first ? acc_idx + 1'b1 : ((acc_idx == grp_last) ? {ACC_IDX_W{1'b0}} : acc_idx + 1'b1);
    //이번 op의 bank 번호
    //묶음 시작이면 0번쨰, 묶음 시작이 아닌 op_first이면 저번 bank+1, 마지막까지하면 다시 0

    always @(posedge clk) begin
        if (rst) begin acc_idx <= 0; prev_last <= 1'b1; grp_last <= 0; end
        else if (op_valid && op_ready) begin
            acc_idx   <= cur_idx;
            prev_last <= op_last;
            if (op_first) grp_last <= cur_idx;
        end
    end

    reg signed [31:0] acc[0:P-1][0:REUSE-1];   // [PE 번호][bank 번호]
    wire signed [15:0] product[0:P-1];
    wire signed [31:0] next_sum[0:P-1];
    wire [P-1:0] mask;
    assign op_ready=(!result_valid || result_ready) && !rst;
    genvar r,c;
    generate for(r=0;r<PE_ROWS;r=r+1) begin: row
        for(c=0;c<PE_COLS;c=c+1) begin: col
            localparam I=r*PE_COLS+c;
            assign mask[I]=op_rows[r] && op_cols[c];
            assign product[I]=$signed(op_a[r*8 +: 8])*$signed(op_b[c*8 +: 8]);
            // 현재 bank의 누산값에 곱을 더한다 (op_first면 0부터 시작)
            assign next_sum[I]=(op_first?32'sd0:acc[I][cur_idx])+(work_mask[I]?{{16{product[I][15]}},product[I]}:32'sd0);
            assign event_mac[I]=op_valid && op_ready && mask[I] && work_mask[I];
            assign event_nonzero_mac[I]=event_mac[I] && (op_a[r*8 +: 8]!=0) && (op_b[c*8 +: 8]!=0);
        end
    end endgenerate
    integer i,j;
    always @(posedge clk) begin
        if(rst) begin
            result_valid<=0;result_data<=0;result_mask<=0;
            for(i=0;i<P;i=i+1)
                for(j=0;j<REUSE;j=j+1) acc[i][j]<=0;   // 모든 bank 초기화
        end else begin
            if(result_valid && result_ready) result_valid<=0;
            if(op_valid && op_ready) begin
                for(i=0;i<P;i=i+1) begin
                    acc[i][cur_idx]<=mask[i]?next_sum[i]:32'sd0;   // 현재 bank에만 기록
                    if(op_last) result_data[32*i +: 32]<=mask[i]?next_sum[i]:32'sd0;
                end
                
                if(op_last) begin result_valid<=1;result_mask<=mask;end
                
            end
        end
    end
endmodule