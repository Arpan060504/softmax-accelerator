`timescale 1ns/1ps

module softmax_top (

    input        clk,
    input        rst,
    input        start,

    input  [31:0] x0,
    input  [31:0] x1,
    input  [31:0] x2,
    input  [31:0] x3,

    output reg [31:0] softmax0,
    output reg [31:0] softmax1,
    output reg [31:0] softmax2,
    output reg [31:0] softmax3,

    output reg        softmax_valid,
    output reg        done

);

    // ============================================================
    // FSM
    // ============================================================

    reg [3:0] state;

    localparam IDLE      = 4'd0;
    localparam EXP       = 4'd1;
    localparam RECIP     = 4'd2;
    localparam READ      = 4'd3;
    localparam NORMALIZE = 4'd4;
    localparam FINISH    = 4'd5;


    // ============================================================
    // EXP + ACCUMULATOR
    // ============================================================

    wire [31:0] exp_sum;
    wire        exp_done;

    reg  [1:0]  read_addr;
    wire [31:0] exp_out;


    softmax_exp_accumulator exp_acc (

        .clk       (clk),
        .rst       (rst),
        .start     (start),

        .x0        (x0),
        .x1        (x1),
        .x2        (x2),
        .x3        (x3),

        .read_addr (read_addr),

        .sum       (exp_sum),
        .done      (exp_done),
        .exp_out   (exp_out)

    );


    // ============================================================
    // RECIPROCAL
    // ============================================================

    wire [31:0] reciprocal_value;

    reciprocal_unit reciprocal_unit_inst (

        .x          (exp_sum),
        .reciprocal (reciprocal_value)

    );


    // ============================================================
    // NORMALIZATION
    // ============================================================

    wire [31:0] normalized_value;

    softmax_normalizer normalizer (

        .exp_value      (exp_out),
        .reciprocal_sum (reciprocal_value),
        .softmax_value  (normalized_value)

    );


    // ============================================================
    // CONTROL
    // ============================================================

    always @(posedge clk)
    begin

        if (rst)
        begin

            state         <= IDLE;

            read_addr     <= 2'd0;

            softmax0      <= 32'd0;
            softmax1      <= 32'd0;
            softmax2      <= 32'd0;
            softmax3      <= 32'd0;

            softmax_valid <= 1'b0;
            done          <= 1'b0;

        end

        else
        begin

            // valid is a one-cycle pulse
            softmax_valid <= 1'b0;


            case (state)

                // =================================================
                // IDLE
                // =================================================

                IDLE:
                begin

                    done <= 1'b0;

                    if (start)
                    begin

                        read_addr <= 2'd0;

                        state <= EXP;

                    end

                end


                // =================================================
                // WAIT FOR EXP + ACCUMULATOR
                // =================================================

                EXP:
                begin

                    if (exp_done)
                    begin

                        // reciprocal_value is combinational
                        state <= RECIP;

                    end

                end


                // =================================================
                // RECIPROCAL
                // =================================================

                RECIP:
                begin

                    // Give one clock for reciprocal path
                    state <= READ;

                end


                // =================================================
                // READ EXP FROM RAM
                // =================================================

                READ:
                begin

                    state <= NORMALIZE;

                end


                // =================================================
                // NORMALIZE
                // =================================================

                NORMALIZE:
                begin

                    case (read_addr)

                        2'd0:
                            softmax0 <= normalized_value;

                        2'd1:
                            softmax1 <= normalized_value;

                        2'd2:
                            softmax2 <= normalized_value;

                        2'd3:
                            softmax3 <= normalized_value;

                    endcase


                    softmax_valid <= 1'b1;


                    if (read_addr == 2'd3)
                    begin

                        state <= FINISH;

                    end

                    else
                    begin

                        read_addr <= read_addr + 1'b1;

                        state <= READ;

                    end

                end


                // =================================================
                // FINISH
                // =================================================

                FINISH:
                begin

                    done <= 1'b1;

                    state <= IDLE;

                end


                // =================================================
                // DEFAULT
                // =================================================

                default:
                begin

                    state <= IDLE;

                    done <= 1'b0;

                end

            endcase

        end

    end

endmodule