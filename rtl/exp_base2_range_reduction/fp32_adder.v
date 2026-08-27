module fp32_adder(a , b , result);
input  [31:0]  a , b;
output [31:0] result;
// unpacking 
wire sign_a, sign_b;
wire [7:0] exp_a, exp_b;
wire [22:0] fraction_a, fraction_b;
wire [23:0] mantissa_a, mantissa_b;

assign sign_a = a[31];
assign sign_b = b[31];

assign exp_a = a[30:23];
assign exp_b = b[30:23];

assign fraction_a = a[22:0];
assign fraction_b = b[22:0];

assign mantissa_a = {1'b1, fraction_a};
assign mantissa_b = {1'b1, fraction_b};
// larger operand and align
reg [7:0] exp_large;
reg [7:0] exp_diff;
reg [23:0] mantissa_large;
reg [23:0] mantissa_small_aligned;
reg sign_large;

always @(*)
    begin
        if(exp_a > exp_b)
            begin
                exp_large = exp_a;
                exp_diff = exp_a - exp_b;
                mantissa_large =  mantissa_a;
                mantissa_small_aligned = mantissa_b >> exp_diff;
                sign_large = sign_a;
            end
        else if(exp_a < exp_b)
            begin
                exp_large = exp_b;
                exp_diff = exp_b - exp_a;
                mantissa_large =  mantissa_b;
                mantissa_small_aligned = mantissa_a >> exp_diff;
                sign_large = sign_b;
            end   
        else 
            begin
                // same exponent 
                exp_large = exp_a;
                exp_diff = 0 ;
                if(mantissa_a >= mantissa_b)
                    begin
                        mantissa_large = mantissa_a;
                        mantissa_small_aligned = mantissa_b;
                        sign_large = sign_a;
                    end
                else
                    begin
                            mantissa_large = mantissa_b;
                            mantissa_small_aligned = mantissa_a;
                            sign_large = sign_b;
                    end    
            end    
    end
// decide add / sub
reg [24:0] mantissa_result;
reg result_sign;
reg do_sub;
always @(*)
    begin
        if(sign_a == sign_b) // add
            begin
                do_sub = 1'b0; // not a substraction
                mantissa_result = {1'b0 , mantissa_large} + { 1'b0 ,mantissa_small_aligned} ;
                result_sign = sign_a;
            end
        else // sub
            begin
                do_sub = 1'b1;
                 mantissa_result = {1'b0 , mantissa_large} - { 1'b0 ,mantissa_small_aligned} ;
                 result_sign = sign_large;
            end
    end

// ============================================================
// NORMALIZATION
// ============================================================

reg [7:0] result_exp;

reg [23:0] normalized_mantissa;

always @(*) begin
    // Default values
    result_exp = exp_large;
    normalized_mantissa = mantissa_result[23:0];

    if(mantissa_result == 0)
        begin
             normalized_mantissa = 0;
              result_exp = 0;
        end
    else if (!do_sub) 
        begin // ADDITION NORMALIZATION

            if (mantissa_result[24] == 1'b1) begin
                normalized_mantissa = mantissa_result[24:1];
                result_exp = exp_large + 1;
            end

        end
    else 
        begin // SUBTRACTION NORMALIZATION

            // 0.xxxxx → 1.xxxxx

            while ((normalized_mantissa != 0) &&
                (normalized_mantissa[23] == 1'b0)) begin

                normalized_mantissa =
                    normalized_mantissa << 1;

                result_exp =
                    result_exp - 1;
            end
    end
end


// ============================================================
// PACKING
// ============================================================

wire [22:0] result_fraction;

assign result_fraction =  normalized_mantissa[22:0];
assign result = { result_sign, result_exp, result_fraction};  
endmodule