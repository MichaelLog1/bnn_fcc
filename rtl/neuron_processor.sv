module neuron_processor #(
    parameter int PARALLEL_INPUTS  = 1,
    parameter int PARALLEL_NEURONS = 1,
    parameter int NUM_INPUTS       = 2   // number of nodes in previous layer  
) (
    input logic clk,
    input logic rst,

    input logic [PARALLEL_INPUTS-1:0] inputs,
    input logic [PARALLEL_INPUTS-1:0] weights,
    input logic [               31:0] threshold,

    input logic          weights_valid,
    input logic          inputs_valid,

    output logic         rd_en,
    output logic         out_valid,
    output logic         out

);

    typedef enum logic [1:0] {
        WAIT_FOR_DATA,
        WHILE,
        FINISH
    } state_t;
    state_t state_r, next_state;

    // population counter
    int count_r;
    int next_count;

    // keeps track of how many iterations of the NP we need to cover all neuron inputs
    int iterations_r;
    int next_iterations;

    logic [PARALLEL_INPUTS-1:0] xnor_r;

    // output registers
    logic out_r;
    logic out_valid_r;
    logic rd_en_r;

    always_ff @(posedge(clk) or posedge(rst)) begin
        if (rst) begin
            state_r <= WAIT_FOR_DATA;
            count_r <= 0;
            iterations_r <= ((NUM_INPUTS + PARALLEL_INPUTS - 1) / PARALLEL_INPUTS);
        end
        else begin
            state_r <= next_state;
            count_r <= next_count;
            iterations_r <= next_iterations;
        end
    end

    always_comb begin
        // default values for output flipflops
        out_r <= 1'b0;
        out_valid_r <= 1'b0;
        rd_en_r <= 1'b0;
        // default values for counters
        next_state <= state_r;
        next_count <= count_r;
        next_iterations <= iterations_r;

        case (state_r)

            WAIT_FOR_DATA: begin
                rd_en_r <= 1'b1;
                // wait for inputs and weights to be valid, 
                // will be asserted by whatever is retrieving them from memory
                if (inputs_valid && weights_valid) begin
                    next_state <= WHILE;
                    xnor_r <= (inputs ~^ weights);
                    next_iterations <= iterations_r - 1;
                end
            end

            WHILE: begin
                if (xnor_r == '0) begin
                    // we're done with this iteration
                    next_state <= FINISH;
                end else if (xnor_r[0]) begin // check lowest bit
                    next_count <= count_r + 1; // increment count if the value is one
                end
                xnor_r <= xnor_r >> 1; // shift right to examine next bit
            end

            FINISH: begin
                // go back to start and wait for valid signals to be asserted to start again
                next_state <= WAIT_FOR_DATA;

                // no iterations left to cover all neuron inputs
                if (iterations_r <= 0) begin
                    // we're done! Reset count to 0 and iterations to defauly value
                    next_count <= '0;
                    next_iterations <= ((NUM_INPUTS + PARALLEL_INPUTS - 1) / PARALLEL_INPUTS);
                    
                    // assert out_valid for one cycle
                    if (count_r >= threshold) begin
                        out_r <= 1'b1;
                        out_valid_r <= 1'b1;
                    end else begin
                        out_r <= 1'b0;
                        out_valid_r <= 1'b1;
                    end
                end
            end
        endcase

        assign out = out_r;
        assign out_valid = out_valid_r;
        assign rd_en = rd_en_r;
    end


endmodule