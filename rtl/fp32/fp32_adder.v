`timescale 1ns/1ps

module fp32_adder(
    input  wire [31:0] a,
    input  wire [31:0] b,
    output reg  [31:0] result
);

    wire sign_a = a[31];
    wire sign_b = b[31];
    wire [7:0] exp_a = a[30:23];
    wire [7:0] exp_b = b[30:23];
    wire [22:0] fraction_a = a[22:0];
    wire [22:0] fraction_b = b[22:0];

    wire [23:0] mantissa_a = (exp_a == 8'd0) ? 24'd0 : {1'b1, fraction_a};
    wire [23:0] mantissa_b = (exp_b == 8'd0) ? 24'd0 : {1'b1, fraction_b};

    reg [7:0] exp_large;
    reg [7:0] exp_diff;
    reg [23:0] mantissa_large;
    reg [23:0] mantissa_small_aligned;
    reg sign_large;

    reg [24:0] mantissa_result;
    reg result_sign;
    reg do_sub;

    reg [4:0] shift_amt;
    reg [23:0] norm_mantissa;
    reg signed [9:0] final_exp;

    always @(*) begin
        // ----------------------------------------------------
        // 1. Zero bypass
        // ----------------------------------------------------
        if (a[30:0] == 31'd0) begin
            result = b;
        end else if (b[30:0] == 31'd0) begin
            result = a;
        end else begin

            // ------------------------------------------------
            // 2. Alignment
            // ------------------------------------------------
            if (exp_a > exp_b) begin
                exp_large = exp_a;
                exp_diff  = exp_a - exp_b;
                mantissa_large = mantissa_a;
                mantissa_small_aligned = (exp_diff >= 24) ? 24'd0 : (mantissa_b >> exp_diff);
                sign_large = sign_a;
            end else if (exp_a < exp_b) begin
                exp_large = exp_b;
                exp_diff  = exp_b - exp_a;
                mantissa_large = mantissa_b;
                mantissa_small_aligned = (exp_diff >= 24) ? 24'd0 : (mantissa_a >> exp_diff);
                sign_large = sign_b;
            end else begin
                exp_large = exp_a;
                exp_diff  = 8'd0;
                if (mantissa_a >= mantissa_b) begin
                    mantissa_large = mantissa_a;
                    mantissa_small_aligned = mantissa_b;
                    sign_large = sign_a;
                end else begin
                    mantissa_large = mantissa_b;
                    mantissa_small_aligned = mantissa_a;
                    sign_large = sign_b;
                end
            end

            // ------------------------------------------------
            // 3. Add / Sub operation
            // ------------------------------------------------
            if (sign_a == sign_b) begin
                do_sub = 1'b0;
                mantissa_result = {1'b0, mantissa_large} + {1'b0, mantissa_small_aligned};
                result_sign = sign_a;
            end else begin
                do_sub = 1'b1;
                mantissa_result = {1'b0, mantissa_large} - {1'b0, mantissa_small_aligned};
                result_sign = sign_large;
            end

            // ------------------------------------------------
            // 4. Normalization
            // ------------------------------------------------
            if (mantissa_result == 25'd0) begin
                result = 32'h00000000;
            end else if (!do_sub) begin
                if (mantissa_result[24]) begin
                    result = {result_sign, exp_large + 8'd1, mantissa_result[23:1]};
                end else begin
                    result = {result_sign, exp_large, mantissa_result[22:0]};
                end
            end else begin
                // Priority encoder for leading zero count
                casez (mantissa_result[23:0])
                    24'b1???????????????????????: shift_amt = 5'd0;
                    24'b01??????????????????????: shift_amt = 5'd1;
                    24'b001?????????????????????: shift_amt = 5'd2;
                    24'b0001????????????????????: shift_amt = 5'd3;
                    24'b00001???????????????????: shift_amt = 5'd4;
                    24'b000001??????????????????: shift_amt = 5'd5;
                    24'b0000001?????????????????: shift_amt = 5'd6;
                    24'b00000001????????????????: shift_amt = 5'd7;
                    24'b000000001???????????????: shift_amt = 5'd8;
                    24'b0000000001??????????????: shift_amt = 5'd9;
                    24'b00000000001?????????????: shift_amt = 5'd10;
                    24'b000000000001????????????: shift_amt = 5'd11;
                    24'b0000000000001???????????: shift_amt = 5'd12;
                    24'b00000000000001??????????: shift_amt = 5'd13;
                    24'b000000000000001?????????: shift_amt = 5'd14;
                    24'b0000000000000001????????: shift_amt = 5'd15;
                    24'b00000000000000001???????: shift_amt = 5'd16;
                    24'b000000000000000001??????: shift_amt = 5'd17;
                    24'b0000000000000000001?????: shift_amt = 5'd18;
                    24'b00000000000000000001????: shift_amt = 5'd19;
                    24'b000000000000000000001???: shift_amt = 5'd20;
                    24'b0000000000000000000001??: shift_amt = 5'd21;
                    24'b00000000000000000000001?: shift_amt = 5'd22;
                    24'b000000000000000000000001: shift_amt = 5'd23;
                    default:                     shift_amt = 5'd0;
                endcase

                norm_mantissa = mantissa_result[23:0] << shift_amt;
                final_exp = $signed({2'b00, exp_large}) - $signed({5'd0, shift_amt});

                if (final_exp <= 0) begin
                    result = 32'h00000000;
                end else begin
                    result = {result_sign, final_exp[7:0], norm_mantissa[22:0]};
                end
            end
        end
    end

endmodule