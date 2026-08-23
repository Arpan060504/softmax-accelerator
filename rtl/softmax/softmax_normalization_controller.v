module softmax_normalization_controller (
    input        clk,
    input        rst,
    input        start,

    // Exponential value read from RAM
    input  [31:0] exp_value,

    // 1 / sum(exp)
    input  [31:0] reciprocal,

    // RAM read interface
    output reg [1:0] read_addr,

    // Normalized output
    output [31:0] softmax_value,

    // Indicates that softmax_value is valid
    output reg softmax_valid,

    // Indicates all 4 values are processed
    output reg done
);

    // ============================================================
    // NORMALIZATION DATAPATH
    // ============================================================

    softmax_normalization_stage normalizer (
        .exp_value     (exp_value),
        .reciprocal    (reciprocal),
        .softmax_value (softmax_value)
    );


    // ============================================================
    // CONTROL
    // ============================================================

    always @(posedge clk)
    begin

        if (rst)
        begin
            read_addr     <= 2'd0;
            softmax_valid <= 1'b0;
            done          <= 1'b0;
        end

        else
        begin

            // Default: output is invalid
            softmax_valid <= 1'b0;

            // ----------------------------------------------------
            // START
            // ----------------------------------------------------

            if (start)
            begin
                read_addr     <= 2'd0;
                softmax_valid <= 1'b1;
                done          <= 1'b0;
            end

            // ----------------------------------------------------
            // NORMAL OPERATION
            // ----------------------------------------------------

            else if (!done)
            begin

                if (read_addr < 2'd3)
                begin
                    read_addr     <= read_addr + 1'b1;
                    softmax_valid <= 1'b1;
                end

                else
                begin
                    // Last value was processed
                    read_addr     <= read_addr;
                    softmax_valid <= 1'b0;
                    done          <= 1'b1;
                end

            end

        end

    end

endmodule