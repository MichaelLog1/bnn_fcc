Interface:

Parameters - 
    PARALLEL_INPUTS  : 1   # parallelizable inputs
    PARALLEL_NEURONS : 1   # parallelizable neuron processors

Inputs - 
    input     : [PW-1:0]
    weight    : [PW-1:0]
    threshold : 32 bits

    # These may not be needed, just speculating
    input_valid  : 1   # asserted when input is valid
    weight_valid : 1   # asserted when weight is valid

Outputs - 
    y : 1 bit


Description:

Takes in a weight, input, and threshold. Checks if the weight and input are equivalent in value. If so, increment an internal population count. If that population count is above the threshold, output 1, else output 0;

Considerations:

1. Input buffering

Ideally, the Neuron processor would take an array of both inputs and weights with a length equivalent to the amount of inputs to the neuron. For a neuron with 8 inputs, this would be the ideal setup:

                                          |-----------------------|
                        input[7:0]  ----> |                       |
                        weight[7:0] ----> |          NP           | ----> y
                        threshold   ----> |                       |
                                          |-----------------------|

However, in most cases we will not be able to give the NP an array of inputs of that size. Therefore, the NP needs to be able to keep track of how many inputs it is supposed to have, and aggregate the similarity values (x xnor w) over many iterations.

Implementations:

1/20/26

I created an fsmd to mimic a software implementation of the neuron processor algorithm discussed in lecture. This algorithm works for Pw > 1, but doesn't consider multiple neuron processors running in parallel, or how different layers will be computed. This algorithm computes one neuron's activation.

// initialize population count
count = 0, i = 0

// we should count the xnor values more than once if we dont cover all inputs in a single iteration
for (i < ceil(N/PW); i++):
    // wait for data to be valid
    while (data_not_ready);

    x = inputs xnor weights

    // algorithm to count the '1's in a binary value
    while (x > 0):
        if (x and 1):
            count ++;
        n = n >> 1

return count