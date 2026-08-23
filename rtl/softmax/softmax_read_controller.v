module softmax_read_controller (
    input        clk,
    input        rst,
    input        start,

    output reg [1:0] read_addr,
    output reg       valid,
    output reg       done
);

    always @(posedge clk)
    begin

        // Default: valid is only HIGH for one clock
        valid <= 1'b0;

        // --------------------------------------------------------
        // RESET
        // --------------------------------------------------------

        if (rst)
        begin
            read_addr <= 2'd0;
            valid     <= 1'b0;
            done      <= 1'b0;
        end

        // --------------------------------------------------------
        // START
        // --------------------------------------------------------

        else if (start)
        begin
            read_addr <= 2'd0;
            valid     <= 1'b1;
            done      <= 1'b0;
        end

        // --------------------------------------------------------
        // PROCESS
        // --------------------------------------------------------

        else if (!done)
        begin

            if (read_addr < 2'd3)
            begin
                read_addr <= read_addr + 1'b1;
                valid     <= 1'b1;
            end

            else
            begin
                read_addr <= read_addr;
                valid     <= 1'b0;
                done      <= 1'b1;
            end

        end

    end

endmodule