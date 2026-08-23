module exp_accumulator (
    input        clk,
    input        rst,
    input        start,
    input [31:0] exp_in,
    input        exp_valid,
    input [1:0] read_addr,
    output reg   done,
    output reg [31:0] sum,
    output [31:0] exp_out
);

    localparam N = 4;

    reg [1:0]  count;
    reg [31:0] exp_mem [0:N-1];

    // FP32 adder output
    wire [31:0] adder_out;

    fp32_adder adder (
        .a      (sum),
        .b      (exp_in),
        .result (adder_out)
    );

assign exp_out = exp_mem[read_addr];

    always @(posedge clk)
    begin

        // Reset
        if (rst)
        begin
            sum   <= 32'h00000000;
            count <= 2'd0;
            done  <= 1'b0;
        end

        // Start a new row
        else if (start)
        begin
            sum   <= 32'h00000000;
            count <= 2'd0;
            done  <= 1'b0;
        end

        // Accept exponential value
        else if (exp_valid)
        begin

            // Store exponential
            exp_mem[count] <= exp_in;

            // Accumulate using FP32 adder
            sum <= adder_out;

            // Move to next location
            if (count < N-1)
            begin
                count <= count + 1'b1;
            end

            // Last exponential
            else
            begin
                done <= 1'b1;
            end

        end

    end

endmodule