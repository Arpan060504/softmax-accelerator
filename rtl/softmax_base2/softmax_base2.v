`timescale 1ns/1ps

module softmax_base2 #(
    parameter integer N = 4
)(
    input  wire        clk,
    input  wire        rst,
    input  wire        start,

    input  wire [31:0] x0,
    input  wire [31:0] x1,
    input  wire [31:0] x2,
    input  wire [31:0] x3,

    output wire [31:0] softmax0,
    output wire [31:0] softmax1,
    output wire [31:0] softmax2,
    output wire [31:0] softmax3,

    output wire        done
);

    // ============================================================
    // 0. MAX RANGE REDUCTION: y_i = x_i - max(x)
    // ============================================================
    wire [31:0] y0, y1, y2, y3;

    exp_range_reducer u_max_range_reducer (
        .x0(x0), .x1(x1), .x2(x2), .x3(x3),
        .y0(y0), .y1(y1), .y2(y2), .y3(y3)
    );

    // ============================================================
    // 1. RANGE REDUCTION: y = k*ln(2) + r
    // ============================================================
    wire signed [7:0] k0, k1, k2, k3;
    wire [31:0] r0, r1, r2, r3;

    exp_kr_reducer u_reducer0 (.y(y0), .k(k0), .r(r0));
    exp_kr_reducer u_reducer1 (.y(y1), .k(k1), .r(r1));
    exp_kr_reducer u_reducer2 (.y(y2), .k(k2), .r(r2));
    exp_kr_reducer u_reducer3 (.y(y3), .k(k3), .r(r3));

    // ============================================================
    // 2. exp(r)
    // ============================================================
    wire [31:0] exp_r0, exp_r1, exp_r2, exp_r3;

    exp_r_lut u_exp_r0 (.r(r0), .exp_r(exp_r0));
    exp_r_lut u_exp_r1 (.r(r1), .exp_r(exp_r1));
    exp_r_lut u_exp_r2 (.r(r2), .exp_r(exp_r2));
    exp_r_lut u_exp_r3 (.r(r3), .exp_r(exp_r3));

    // ============================================================
    // 3. exp(y) = 2^k * exp(r)
    // ============================================================
    wire [31:0] exp0, exp1, exp2, exp3;

    exp_power_of_two u_exp0 (.exp_r(exp_r0), .k(k0), .exp_out(exp0));
    exp_power_of_two u_exp1 (.exp_r(exp_r1), .k(k1), .exp_out(exp1));
    exp_power_of_two u_exp2 (.exp_r(exp_r2), .k(k2), .exp_out(exp2));
    exp_power_of_two u_exp3 (.exp_r(exp_r3), .k(k3), .exp_out(exp3));

    // ============================================================
    // 4. ACCUMULATION FSM
    // ============================================================
    localparam [2:0]
        S_IDLE = 3'd0,
        S_EXP0 = 3'd1,
        S_EXP1 = 3'd2,
        S_EXP2 = 3'd3,
        S_EXP3 = 3'd4,
        S_DONE = 3'd5;

    reg [2:0] state;
    reg [31:0] exp_selected;
    reg        exp_valid;

    wire [31:0] exp_sum;
    wire        exp_done;
    wire [31:0] exp_out_unused;

    softmax_exp_accumulator #(.N(N)) u_accumulator (
        .clk       (clk),
        .rst       (rst),
        .start     (start),
        .exp_in    (exp_selected),
        .exp_valid (exp_valid),
        .read_addr (2'b00),
        .exp_out   (exp_out_unused),
        .sum       (exp_sum),
        .done      (exp_done)
    );

    always @(*) begin
        case (state)
            S_EXP0:  begin exp_selected = exp0; exp_valid = 1'b1; end
            S_EXP1:  begin exp_selected = exp1; exp_valid = 1'b1; end
            S_EXP2:  begin exp_selected = exp2; exp_valid = 1'b1; end
            S_EXP3:  begin exp_selected = exp3; exp_valid = 1'b1; end
            default: begin exp_selected = 32'h00000000; exp_valid = 1'b0; end
        endcase
    end

    always @(posedge clk) begin
        if (rst) begin
            state <= S_IDLE;
        end else begin
            case (state)
                S_IDLE: if (start) state <= S_EXP0;
                S_EXP0: state <= S_EXP1;
                S_EXP1: state <= S_EXP2;
                S_EXP2: state <= S_EXP3;
                S_EXP3: state <= S_DONE;
                S_DONE: if (start) state <= S_EXP0; else state <= S_DONE;
                default: state <= S_IDLE;
            endcase
        end
    end

    // ============================================================
    // 5. RECIPROCAL & NORMALIZATION
    // ============================================================
    wire [31:0] reciprocal;

    softmax_reciprocal u_reciprocal (
        .sum        (exp_sum),
        .reciprocal (reciprocal)
    );

    softmax_normalizer u_normalizer (
        .exp0       (exp0),
        .exp1       (exp1),
        .exp2       (exp2),
        .exp3       (exp3),
        .reciprocal (reciprocal),
        .softmax0   (softmax0),
        .softmax1   (softmax1),
        .softmax2   (softmax2),
        .softmax3   (softmax3)
    );

    assign done = exp_done;

endmodule