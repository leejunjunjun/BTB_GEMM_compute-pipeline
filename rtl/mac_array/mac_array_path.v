`timescale 1ns/1ps
// PE_ROWS x PE_COLS output-stationary MAC array, NOT a systolic array.
// a[r] is broadcast across a row; b[c] is broadcast down a column.
// Dense baseline: multiplication+accumulation in the same clock stage.
module mac_array #(parameter PE_ROWS=4,PE_COLS=4)(
    input clk,rst,input op_valid,output op_ready,
    input [8*PE_ROWS-1:0] op_a,input [8*PE_COLS-1:0] op_b,
    input [4*PE_COLS-1:0] op_b_tag,
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
    assign op_ready=(!result_valid || result_ready) && !rst;
    genvar r,c;
    generate for(r=0;r<PE_ROWS;r=r+1) begin: row
        for(c=0;c<PE_COLS;c=c+1) begin: col
            localparam I=r*PE_COLS+c;
            assign mask[I]=op_rows[r] && op_cols[c];
            product product_unit (.a(op_a[r*8 +: 8]), .b(op_b[c*8 +: 8]), .b_tag(op_b_tag[c*4 +: 4]), .p(product[I]));
            assign next_sum[I]=(op_first?32'sd0:acc[I])+(work_mask[I]?{{16{product[I][15]}},product[I]}:32'sd0);
            assign event_mac[I]=op_valid && op_ready && mask[I] && work_mask[I];
            assign event_nonzero_mac[I]=event_mac[I] && (op_a[r*8 +: 8]!=0) && (op_b_tag[c*4 +: 4]!=4'b0000);
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

module mul (
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
    input  wire signed [7:0]  a,
    input  wire signed [7:0]  b,
    input  wire        [3:0]  b_tag,
    output reg  signed [15:0] p
);
    wire mul_enable = (b_tag == 4'b0001);
    wire signed [15:0] mul_p;
    mul mul_unit (.enable(mul_enable), .a(a), .b(b), .p(mul_p));

    wire signed [15:0] a_ext = {{8{a[7]}}, a};

    always @* begin
        if (b_tag[3]) begin
            p = a_ext <<< b_tag[2:0];
        end else begin
            case (b_tag[2:0])
                3'b001: p = mul_p;
                3'b010: p = a_ext;
                3'b011: p = -a_ext;
                default: p = 16'sd0;
            endcase
        end
    end
endmodule
