// this module keeps track of global popcount and thresholding

module neuron_processor #(
    parameter int PARALLEL_INPUTS  = 4,
    parameter int PARALLEL_NEURONS = 1,
    parameter int NUM_INPUTS       = 10   // number of nodes in previous layer  
) (
    input logic clk,
    input logic rst,

    input logic [PARALLEL_INPUTS-1:0] inputs,
    input logic [PARALLEL_INPUTS-1:0] weights,
    input logic [               31:0] threshold,

    input logic          valid_in,
    output logic         valid_out,
    output logic         out

);

    typedef enum logic [1:0] {
        START,
        ACCUMULATE,
        RESTART,
        XXX = 'x
    } state_t;
    state_t state_r;

    // global popcount
    logic [31:0] popcount_r;
    logic [31:0] iteration_r;

    // popcount DUT signals
    logic [PARALLEL_INPUTS-1:0] popcount_in;
    logic [(1+$clog2(NUM_INPUTS))-1:0] popcount_out;
    logic popcount_valid_out;

    // FSM signals
    logic out_r;
    logic valid_out_r;

    assign out = out_r;
    assign valid_out = valid_out_r;

    always_ff @( posedge clk or posedge rst ) begin : processor_fsm
        if (rst) begin
            out_r <= '0;
            valid_out_r <= '0;
            popcount_r <= '0;
            iteration_r <= '0;
            state_r <= START;

        end else begin
            out_r <= '0;
            valid_out_r <= '0;

            case (state_r)
                START: begin
                    out_r <= '0;
                    valid_out_r <= '0;
                    // reset popcount for this neuron
                    popcount_r <= '0;
                    // reset iteration count too
                    iteration_r <= '0;

                    // wait for first valid data
                    if (valid_in) begin
                        state_r <= ACCUMULATE;
                    end
                end

                ACCUMULATE: begin
                    // we are done
                    if (iteration_r >= ((NUM_INPUTS + PARALLEL_INPUTS - 1) / PARALLEL_INPUTS)) begin
                        state_r <= RESTART;
                    end else if (popcount_valid_out) begin
                        iteration_r <= iteration_r + 1;
                        popcount_r <= popcount_r + popcount_out;
                        state_r <= ACCUMULATE;
                    end else begin
                        state_r <= ACCUMULATE;
                    end
                    
                end

                RESTART: begin
                    valid_out_r <= 1'b1;
                    if (popcount_r > threshold) begin
                        out_r <= 1'b1;
                    end else begin
                        out_r <= 1'b0;
                    end

                    state_r <= START;
                end
            endcase            
        end
    end

    assign popcount_in = inputs ~^ weights;

    popcount #(
        .NUM_INPUTS(PARALLEL_INPUTS)
    ) DUT (
        .clk(clk),
        .rst(rst),
        .valid_in(valid_in),
        .in(popcount_in),
        .valid_out(popcount_valid_out),
        .out(popcount_out)
    );


endmodule