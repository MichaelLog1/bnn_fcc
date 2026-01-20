`timescale 1ns / 100ps

module neuron_processor_tb;

    localparam bit PARALLELIZE_LAYERS = 1'b0;
    localparam int PARALLEL_NEURONS = 1;
    localparam int PARALLEL_INPUTS = 1;
    localparam int NUM_INPUTS = 2;

    logic clk = 1'b0;
    logic rst;

    logic [PARALLEL_INPUTS-1:0] inputs;
    logic [PARALLEL_INPUTS-1:0] weights;
    logic [               31:0] threshold;

    logic inputs_valid;
    logic weights_valid;

    logic out;

    neuron_processor #(
        .PARALLEL_INPUTS (PARALLEL_INPUTS),
        .PARALLEL_NEURONS(PARALLEL_NEURONS),
        .NUM_INPUTS(NUM_INPUTS)
    ) DUT (
        .clk(clk),
        .rst(rst),

        .inputs    (inputs),
        .weights   (weights),
        .threshold(threshold),

        .inputs_valid (inputs_valid),
        .weights_valid(weights_valid),
        .out_valid(out_valid),
        .out(out)
    );

    function automatic int popcount_xnor(
        int current_count,
        input logic [PARALLEL_INPUTS-1:0] a,
        input logic [PARALLEL_INPUTS-1:0] b
    );
        popcount_xnor = $countones(a ~^ b);
    endfunction
    
    initial begin : generate_clock
        forever #5 clk <= ~clk;
    end

    initial begin : apply_tests
        $timeformat(-9, 0, " ns", 0);

        rst           <= 1'b1;
        inputs        <= '0;
        weights       <= '0;
        inputs_valid  <= 1'b0;
        weights_valid <= 1'b0;
        threshold     <= 32'b10;


        repeat (5) @(posedge clk);
        @(negedge clk);
        rst <= 1'b0;
        repeat (5) @(posedge clk);

        @(posedge clk);
        inputs_valid  <= 1'b1;
        weights_valid <= 1'b1;
        inputs        <= 1'b1;
        weights       <= 1'b1;

        @(posedge clk);
        inputs_valid  <= 1'b1;
        weights_valid <= 1'b1;
        inputs        <= 1'b0;
        weights       <= 1'b1;

        @(posedge clk);
        inputs_valid  <= 1'b0;
        weights_valid <= 1'b1;
        inputs        <= 1'b0;
        weights       <= 1'b1;

        @(posedge clk);
        inputs_valid  <= 1'b1;
        weights_valid <= 1'b1;
        inputs        <= 1'b1;
        weights       <= 1'b1;
        
        @(posedge clk iff out_valid);
        disable generate_clock;
        $display("Tests completed.");
    end

    initial begin : check_results
        int expected = 0;

        forever begin
            @(posedge clk);

            if (inputs_valid && weights_valid) begin
                expected = popcount_xnor(expected, inputs, weights);

                $display("[%0t] XNOR=%b popcount=%0d",
                        $time, inputs ~^ weights, expected);

                // Example assertion (optional)
                // assert (expected == DUT.population_count)
                //   else $error("Mismatch!");
            end
            if (out_valid) begin
                if (expected >= threshold) begin
                    assert (out === 1'b1)
                        else $error("[%0t] ERROR: expected >= threshold (%0d > %0d) but out=%b",
                                    $time, expected, threshold, out);
                end else begin
                    assert (out === 1'b0)
                        else $error("[%0t] ERROR: expected < threshold (%0d <= %0d) but out=%b",
                                    $time, expected, threshold, out);
                end

                $display("[%0t] expected=%0d threshold=%0d out=%b",
                        $time, expected, threshold, out);
            end
        end
    end

endmodule