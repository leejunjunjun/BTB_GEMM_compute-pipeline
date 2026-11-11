`timescale 1ns/1ps
// PE_ROWS x PE_COLS output-stationary MAC array, NOT a systolic array.
// a[r] is broadcast across a row; b[c] is broadcast down a column.
// Dense baseline: multiplication+accumulation in the same clock stage.
module mac_array #(parameter PE_ROWS=4,PE_COLS=4)(
    input clk,rst,input op_valid,output op_ready,
    input [8*PE_ROWS-1:0] op_a,input [8*PE_COLS-1:0] op_b,
    input [3*PE_ROWS*PE_COLS-1:0] op_opcode,
    input [PE_ROWS-1:0] op_rows,input [PE_COLS-1:0] op_cols,
    input op_first,op_last,
    input [PE_ROWS*PE_COLS-1:0] work_mask,
    output reg result_valid,input result_ready,
    output reg [32*PE_ROWS*PE_COLS-1:0] result_data,
    output reg [PE_ROWS*PE_COLS-1:0] result_mask,
    output [PE_ROWS*PE_COLS-1:0] event_mac,event_nonzero_mac
);
    localparam P=PE_ROWS*PE_COLS;
    reg signed [31:0] acc[0:P-1];
    wire signed [15:0] product[0:P-1];
    wire signed [31:0] next_sum[0:P-1];
    wire [P-1:0] mask;
    wire signed [7:0] a[0:P-1];
    wire signed [7:0] b[0:P-1];
    wire signed [15:0] pro_out[0:P-1];
    assign op_ready=(!result_valid || result_ready) && !rst;
    genvar r,c;
    generate for(r=0;r<PE_ROWS;r=r+1) begin: row
        for(c=0;c<PE_COLS;c=c+1) begin: col
            localparam I=r*PE_COLS+c;
            assign mask[I]=op_rows[r] && op_cols[c];
            assign a[I] = $signed(op_a[r*8 +: 8]);
            assign b[I] = $signed(op_b[c*8 +: 8]);
            product PRO (.a(a[I]), .b(b[I]), .opcode(op_opcode[3*I +: 3]), .p(pro_out[I]));
            assign product[I]=pro_out[I];
            assign next_sum[I]=(op_first?32'sd0:acc[I])+(work_mask[I]?{{16{product[I][15]}},product[I]}:32'sd0);
            assign event_mac[I]=op_valid && op_ready && mask[I] && work_mask[I];
            assign event_nonzero_mac[I]=event_mac[I] && (op_a[r*8 +: 8]!=0) && (op_b[c*8 +: 8]!=0);
        end
    end endgenerate
    integer i;
    always @(posedge clk) begin
        if(rst) begin
            result_valid<=0;result_data<=0;result_mask<=0;
            for(i=0;i<P;i=i+1) acc[i]<=0;
        end else begin
            if(result_valid && result_ready) result_valid<=0;
            if(op_valid && op_ready) begin
                for(i=0;i<P;i=i+1) begin
                    acc[i]<=mask[i]?next_sum[i]:32'sd0;
                    if(op_last) result_data[32*i +: 32]<=mask[i]?next_sum[i]:32'sd0;
                end
                if(op_last) begin result_valid<=1;result_mask<=mask;end
            end
        end
    end
endmodule

module mul_signed_8x8 (
    input  wire enable,
    input  wire signed [7:0]  a,
    input  wire signed [7:0]  b,
    output wire signed [15:0] p
);

    // Combinational enable: isolate operands before Booth recoding and CSA.
    // Disabled output is zero; no clock or state is introduced.
    wire signed [7:0] active_a = enable ? a : 8'sd0;
    wire signed [7:0] active_b = enable ? b : 8'sd0;

    // Radix-4 Booth:
    // 000, 111 :  0
    // 001, 010 : +a
    // 011      : +2a
    // 100      : -2a
    // 101, 110 : -a
    // 10 bits are needed to represent +256 when a = -128.

    function signed [9:0] booth_pp;
        input signed [7:0] multiplicand;
        input        [2:0] code;

        reg signed [9:0] a_ext;
        begin
            a_ext = {{2{multiplicand[7]}}, multiplicand};

            case (code)
                3'b000, 3'b111: booth_pp = 10'sd0;
                3'b001, 3'b010: booth_pp = a_ext;
                3'b011:         booth_pp = a_ext <<< 1;
                3'b100:         booth_pp = -(a_ext <<< 1);
                3'b101, 3'b110: booth_pp = -a_ext;
                default:        booth_pp = 10'sd0;
            endcase
        end
    endfunction

    wire signed [9:0] pp0;
    wire signed [9:0] pp1;
    wire signed [9:0] pp2;
    wire signed [9:0] pp3;

    assign pp0 = booth_pp(active_a, {active_b[1:0], 1'b0});
    assign pp1 = booth_pp(active_a, active_b[3:1]);
    assign pp2 = booth_pp(active_a, active_b[5:3]);
    assign pp3 = booth_pp(active_a, active_b[7:5]);

    // Sign extension and alignment: shifts of 0, 2, 4, 6.
    wire [15:0] row0;
    wire [15:0] row1;
    wire [15:0] row2;
    wire [15:0] row3;

    assign row0 = {{6{pp0[9]}}, pp0};
    assign row1 = {{4{pp1[9]}}, pp1, 2'b0};
    assign row2 = {{2{pp2[9]}}, pp2, 4'b0};
    assign row3 = {pp3, 6'b0};
    // CSA stage 1: three rows -> two rows.
    wire [15:0] sum1, carry1;
    assign sum1   = row0 ^ row1 ^ row2;
    assign carry1 = ((row0 & row1) | (row1 & row2) | (row2 & row0)) << 1;
    // CSA stage 2: three rows -> two rows.
    wire [15:0] sum2, carry2;
    assign sum2   = sum1 ^ carry1 ^ row3;
    assign carry2 = ((sum1 & carry1) | (carry1 & row3) | (row3   & sum1)) << 1;
    // Final carry-propagate adder.
    assign p = sum2 + carry2;

endmodule

module product (
    input  wire signed [7:0] a,
    input  wire signed [7:0] b,
    input  wire [2:0] opcode,
    output reg signed [15:0] p
);

// ============================================================================
// Opcode 정의
// ============================================================================
//  Opcode | 연산          | 동작 설명
// --------+---------------+--------------------------------------------
//   000   | MULTIPLY      | p = a * b
//   001   | SHIFT_A       | |a| = 2^n 일 때, b를 n-bit Shift
//   010   | BYPASS_B      | a = +1 일 때, p = b
//   011   | NEGATE_B      | a = -1 일 때, p = -b
//   100   | ZERO          | p = 0
//   101   | SHIFT_B       | |b| = 2^n 일 때, a를 n-bit Shift
//   110   | BYPASS_A      | b = +1 일 때, p = a
//   111   | NEGATE_A      | b = -1 일 때, p = -a
//
// ----------------------------------------------------------------------------
// Opcode Bit-field 구성
// ----------------------------------------------------------------------------
//  opcode[1:0] : 연산 종류 선택
//      00 : MULTIPLY / ZERO
//      01 : SHIFT
//      10 : BYPASS
//      11 : NEGATE
//  opcode[2]   : Operand 선택 및 ZERO 제어
//      SHIFT / BYPASS / NEGATE 연산:
//          0 : A가 특수 Operand → B에 연산 적용
//          1 : B가 특수 Operand → A에 연산 적용
//      MULTIPLY / ZERO 연산:
//          0 : MULTIPLY
//          1 : ZERO
//  참고:
//      - Opcode는 sparsity_frontend에서 생성된다고 가정함.
//      - SHIFT는 선택된 Operand가 ±2^n인 경우에 사용함.
//      - SHIFT 결과의 부호는 Factor의 Sign Bit로 보정함.
//      - BYPASS / NEGATE는 선택된 Operand가 +1 / -1일 때 사용함.
//
// ============================================================================

    function [2:0] power_shift;
        input [7:0] magnitude;
        begin
            case (magnitude)
                8'h02: power_shift = 3'd1;
                8'h04: power_shift = 3'd2;
                8'h08: power_shift = 3'd3;
                8'h10: power_shift = 3'd4;
                8'h20: power_shift = 3'd5;
                8'h40: power_shift = 3'd6;
                8'h80: power_shift = 3'd7;
                default: power_shift = 3'd0;
            endcase
        end
    endfunction

    wire mul_enable = (opcode == 3'b000);
    wire signed [15:0] mul_p;
    mul_signed_8x8 u_mul (.enable(mul_enable), .a(a), .b(b), .p(mul_p));

    wire        [7:0]  factor = (opcode[1:0] == 2'b01) ? (opcode[2] ? b : a) : 8'd0;
    wire        [7:0]  magnitude = factor[7] ? (~factor + 8'd1) : factor;
    wire        [2:0]  shift_amount = power_shift(magnitude);
    wire signed [7:0]  shift_source = (opcode[1:0] == 2'b01) ? (opcode[2] ? a : b) : 8'sd0;
    wire signed [15:0] shift_operand = {{8{shift_source[7]}}, shift_source};
    wire signed [15:0] shifted = shift_operand <<< shift_amount;

    wire signed [7:0]  bypass_source = opcode[2] ? a : b;
    wire signed [15:0] bypass_operand = {{8{bypass_source[7]}}, bypass_source};

    wire signed [15:0] negate_operand = (opcode[1:0] == 2'b11) ? bypass_operand : 16'sd0;
    wire signed [15:0] negated = -negate_operand;

    always @* begin
        case (opcode[1:0])
            2'b00: p = opcode[2] ? 16'sd0 : mul_p;
            2'b01: p = factor[7] ? -shifted : shifted;
            2'b10: p = bypass_operand;
            2'b11: p = negated;
            default: p = 16'sd0;
        endcase
    end
endmodule