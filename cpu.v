module Add_16 (
        output signed [15:0] Output,
        output carryOut,
        input signed [15:0] A,
        input signed [15:0] B,
        input carry
);
        assign {carryOut, Output} = A + B + carry;
endmodule //Add_16

module Sub_16 (
        output signed [15:0] Output,
        output carryOut,
        input signed [15:0] A,
        input signed [15:0] B,
        input carry
);
        assign {carryOut, Output} = A + (~B) + carry;
endmodule //Sub_16

module Mult_16 (
        output signed [15:0] outLow,            
        output signed [15:0] outHigh,  
        input signed [15:0] A,
        input signed [15:0] B,
        input signed [15:0] carryIn          
);
        wire [31:0] rawProduct;
        assign rawProduct = A * B;
        
        wire [31:0] finalResult;
        assign finalResult = rawProduct + carryIn;
        
        assign outLow = finalResult[15:0];
        assign outHigh = finalResult[31:16];
endmodule //Mult_16

module Divider_Cell (
        output signed d_out,     
        output signed b_out,    
        input signed a_in,     
        input signed b_in,         
        input signed b_right, 
        input signed p_ctrl
);
        wire xor_b;
        assign xor_b = b_in ^ p_ctrl;
        
        // Full Subtractor Logic
        assign d_out = a_in ^ xor_b ^ b_right;
        assign b_out = (~a_in & xor_b) | (~a_in & b_right) | (xor_b & b_right);
endmodule //Divider_Cell

module Div_16 (
            output signed [15:0] Quotient,
        output signed [15:0] Remainder,
        input signed [15:0] A,                     
        input signed [15:0] B,     
        input signed [15:0] remainder_in 
);
        wire signed [16:0] r_data [0:16];
        wire signed [16:0] r_borrow [0:16];
        wire signed [16:0] row_sign;

        assign row_sign[0] = 1'b0;
        
        assign r_data[0] = {remainder_in, A[15]}; 

        genvar row, col;
        generate
                for (row = 0; row < 16; row = row + 1) begin : row_loop
                        assign row_sign[row+1] = r_borrow[row][16];
                        assign Quotient[15-row] = ~row_sign[row+1];
                        assign r_borrow[row][0] = row_sign[row];

                        for (col = 0; col < 16; col = col + 1) begin : col_loop
                                Divider_Cell cell_inst (
                                        .d_out(r_data[row+1][col+1]),
                                        .b_out(r_borrow[row][col+1]),
                                        .a_in(r_data[row][col]),
                                        .b_in(B[col]),
                                        .b_right(r_borrow[row][col]),
                                        .p_ctrl(row_sign[row])
                                );
                        end
                        
                        if (row < 15) begin
                                assign r_data[row+1][0] = A[14-row];
                        end else begin
                                assign r_data[row+1][0] = 1'b0;
                        end
                end
        endgenerate

        wire signed [15:0] raw_remainder;
        assign raw_remainder = r_data[16][16:1];
        assign Remainder = row_sign[16] ? (raw_remainder + B) : raw_remainder;
endmodule // Div_16

module Bsl_16 (
        output [15:0] Output,   
        output [15:0] carryOut,    
        input    [15:0] A,
        input    [15:0] carryIn,     
        input    [15:0] Shift_Amount
);

        reg [31:0] fullOutput;

        always @(*) begin
                fullOutput = {carryIn, A};

                fullOutput = fullOutput << Shift_Amount;
        end

        assign Output = {fullOutput[15:0]};
        assign carryOut = {fullOutput[31:16]};
endmodule//Bsl_16

module Bsr_16 (
        output [15:0] Output,        
        output [15:0] carryOut,    
        input    [15:0] A,
        input    [15:0] carryIn,     
        input    [15:0] Shift_Amount
);

        reg [31:0] fullOutput;

        always @(*) begin
                fullOutput = {A, carryIn};

                fullOutput = fullOutput >> Shift_Amount;
        end

        assign Output = {fullOutput[31:16]};
        assign carryOut = {fullOutput[15:0]};
endmodule//Bsr_16

module ALU_16 (
    output signed [15:0] ALUOutput,
    output signed [15:0] ALUCarry,

    input signed [15:0] a,
    input signed [15:0] b,
    input signed [15:0] carry,
    input [2:0] state,
    input clock
);
    //wires    
    wire signed [15:0] addWire;
    wire addCarry;

    wire signed [15:0] subWire;
    wire subCarry;

    wire signed [15:0] mulWire;
    wire signed [15:0] mulCarry;

    wire [15:0] bslWire;
    wire [15:0] bslCarry;

    wire [15:0] bsrWire;
    wire [15:0] bsrCarry;
    //declaring all wires

    //div stuff
    // --------------------------------------
    wire [15:0] abs_a = a[15] ? (-a) : a;
    wire [15:0] abs_b = b[15] ? (-b) : b;

    wire [15:0] raw_divWire;
    wire [15:0] raw_divRemainder;
    
    Div_16 div (
        .Quotient(raw_divWire),
        .Remainder(raw_divRemainder),
        .A(abs_a),
        .B(abs_b),
        .remainder_in(16'd0) 
    );
    
    wire div_q_sign = a[15] ^ b[15];
    wire div_r_sign = a[15];
    
    wire signed [15:0] divWire            = div_q_sign ? (-raw_divWire) : raw_divWire;
    wire signed [15:0] divRemainder = div_r_sign ? (-raw_divRemainder) : raw_divRemainder;
    // --------------------------------------

    reg signed [15:0] rOutput;
    reg signed [15:0] rCarry;

    Add_16 add ( 
        .Output(addWire), 
        .carryOut(addCarry),
        .A(a),
        .B(b),
        .carry(carry[0]) 
    );
    Sub_16 sub (
        .Output(subWire),
        .carryOut(subCarry),
        .A(a),
        .B(b),
        .carry(carry[0]) 
        );
    Mult_16 mul (
        .outLow(mulWire), 
        .outHigh(mulCarry), 
        .A(a), 
        .B(b), 
        .carryIn(carry) 
    );
    Bsl_16 bsl (
        .Output(bslWire),
        .carryOut(bslCarry),
        .A(a),
        .carryIn(carry),
        .Shift_Amount(b)
    );
    Bsr_16 bsr (
        .Output(bsrWire),
        .carryOut(bsrCarry),
        .A(a),
        .carryIn(carry),
        .Shift_Amount(b)
    );
    //computing all the sums for all operations

     always @(*) begin
        case (state)
            3'd0: begin rOutput = addWire; rCarry = addCarry; end

            3'd1: begin rOutput = subWire; rCarry = subCarry; end

            3'd2: begin rOutput = mulWire; rCarry = mulCarry; end

            3'd3: begin rOutput = divWire; rCarry = divRemainder; end

            3'd4: begin rOutput = bslWire; rCarry = bslCarry; end

            3'd5: begin rOutput = bsrWire; rCarry = bsrCarry; end

            default: begin rOutput = 16'd0; rCarry = 16'b0; end
        endcase
    end
    //only letting 1 solution through as dictacted by state

    assign ALUCarry = rCarry; 
    assign ALUOutput = rOutput;
    //fowarding to output
endmodule//ALU

module RAM_16 (
    output [15:0] dataOut,
    input [15:0] dataIn,
    input [15:0] address,
    input writeEnable,
    input clock    
);
    reg [15:0] ram [0:65535]; 

    initial begin
        //program.txt
        $readmemb("D:/programs/Cpu folder/cpuPrograms(3.5)/random.txt", ram); 
    end

    always @(posedge clock) begin
        if(writeEnable) begin 
            ram[address] <= dataIn; 
        end 
    end

    assign dataOut = ram[address];
endmodule

module Control_Unit(
    output reg signed  [15:0] Output1,
    //output reg signed  [15:0] Output2,

    input wire clock,

    input signed [15:0] Input1
    //input signed [15:0] Input2,
    //input signed [15:0] Input3,
    //input signed [15:0] Input4
);

    reg [15:0] opCode = 16'd0;

    reg signed [15:0] Accumulator = 16'd0;

    reg signed [15:0] Carry_Reg = 16'd0;

    reg signed [15:0] Register_A = 16'd0;

    reg signed [15:0] Register_B = 16'd0;

    reg signed [15:0] Register_C = 16'd0;

    reg [15:0] Program_Counter = 16'd0;

    reg signed [15:0] dataBus;//ik its not a wire 

    reg [15:0] Jump_Register;

    reg load_flag = 1'b0;

    localparam FETCH = 1'b0;
    localparam EXECUTE = 1'b1;

    reg state_reg = FETCH;

    reg [2:0] ALU_state = 3'd7;

    wire signed [15:0] ALU_Output;
    wire signed [15:0] ALU_Carry; 

    reg [15:0] RAM_dataIn = 16'd0;
    reg RAM_writeEnable = 16'd0;
    reg [15:0] RAM_address_wire = 16'd0;

    wire [15:0] RAM_dataOut;

    ALU_16 ALU (
        .ALUOutput(ALU_Output),
        .ALUCarry(ALU_Carry),

        .a(Register_A),
        .b(Register_B),
        .carry(Register_C),
        .state(ALU_state),
        .clock(clock)
    );

    RAM_16 RAM (
        .dataOut(RAM_dataOut),

        .dataIn(RAM_dataIn),
        .address(RAM_address_wire),
        .writeEnable(RAM_writeEnable),
        .clock(clock)
    );
    
    always @(*) begin

        RAM_writeEnable = 1'b0;
        ALU_state = 3'd7;

        if (state_reg == FETCH) begin
                RAM_address_wire = Program_Counter;
                //during fetch cycle, get the opcode
        end else begin

            if (opCode == 16'b1000000000000100 || opCode == 16'b1000000000000011) begin //if writing data to ram or reciving data from ram, connect reg A to Ram address
            //Register A is used as pointer
                RAM_address_wire = Register_A;
            end else begin
                RAM_address_wire = Program_Counter;
                // to index program
            end

            case(opCode)

                16'b1000000000000100: dataBus = RAM_dataOut; // RAM out to bus
                16'b1110000000000001: dataBus = Accumulator;  // Acc to bus
                16'b1110000000000010: dataBus = Carry_Reg;   // Carry to bus
                16'b1110000000000011: dataBus = Program_Counter; // PC to bus
                16'b0100000000000111: dataBus = Input1; // Input to bus
                16'b0100000000001000: dataBus = Register_A; //Reg A to bus
                16'b0100000000001001: dataBus = Register_B; //Reg B to bus
                16'b0100000000001010: dataBus = Register_C; //Reg C to bus

                16'b0010000000000001: begin
                    RAM_address_wire = Program_Counter + 1; 
                    load_flag = 1'b1; //load constant next cycle
                end 
            endcase
                 
            if (opCode == 16'b1000000000000011) begin
                RAM_dataIn = dataBus;
                RAM_writeEnable = 1'b1;
            end //write to RAM

            case (opCode)
                // ALU Operations
                16'b0000000000000001: ALU_state = 3'd0; // add
                16'b0000000000000010: ALU_state = 3'd1; // sub
                16'b0000000000000011: ALU_state = 3'd2; // mul
                16'b0000000000000100: ALU_state = 3'd3; // div
                16'b0000000000000101: ALU_state = 3'd4; // bsl
                16'b0000000000000110: ALU_state = 3'd5; // bsr

                default:              ALU_state = 3'd7; // this ALU state does nothing
            endcase

            

        end
    end

    always@(posedge clock) begin
        if (state_reg == FETCH) begin
                opCode <= RAM_dataOut;
                state_reg <= EXECUTE;
                //pull opcode from ram and set CPU to execute
        end
        else begin
                state_reg <= FETCH;
                //fetch next cycle
                if (load_flag == 1'b1) begin
                    dataBus = RAM_dataOut;
                    load_flag <= 1'b0;
                    Program_Counter <= Program_Counter + 2;
                    //since load flag is on, take the constant from ram. pc is incremented by 2 so its not interpreted as a opcode.
                end else begin
                    Program_Counter <= Program_Counter + 1;
                    //default state
                end

                case (opCode)

                        16'b0000000000000111: Carry_Reg <= 16'd0; // Clear carry
                        16'b0000000000001000: Carry_Reg <= 16'd1; // Set carry high(for sub)

                        16'b0000000000000001, 16'b0000000000000010,
                        16'b0000000000000011, 16'b0000000000000100,
                        16'b0000000000000101, 16'b0000000000000110: begin
                                Accumulator <= ALU_Output;
                                Carry_Reg   <= ALU_Carry;
                                Register_C  <= ALU_Carry;
                                //if ALU commands, keep output from ALU. 
                        end

                        // Bus to Registers
                        16'b1100000000000001: Register_A <= dataBus;//Set Reg A to Bus
                        16'b1100000000000010: Register_B <= dataBus;//Set Reg B to Bus
                        16'b1100000000000011: Register_C <= dataBus;//Set Reg C to Bus
                        16'b1100000000000100:  Jump_Register <= dataBus; //set jump register to bus


                        // Jumps / Program Counter updates
                        16'b1100000000000101: Program_Counter <= dataBus; // Unconditional Jump
                        16'b1100000000000110: begin                       // Conditional carry Jump (jump if carry)
                                if (Carry_Reg == 16'd1) begin
                                        Program_Counter <= Jump_Register;
                                end
                        end
                        16'b1100000000000111: begin                       // Conditional not carry Jump (jump if no carry)
                                if (Carry_Reg == 16'd0) begin
                                        Program_Counter <= Jump_Register;
                                end
                        end

                        // System Outputs
                        16'b0100000000000101: begin Output1 <= dataBus; end //Foward Bus to output
                endcase
        end
    end
endmodule

module Main;
    reg clock;

    wire signed [15:0] Output1;
    wire signed [15:0] Output2;

    reg signed [15:0] Input1 = 16'd15;
    reg signed [15:0] Input2;
    reg signed [15:0] Input3;
    reg signed [15:0] Input4;

    Control_Unit CU (
        .Output1(Output1),

        .clock(clock),
        .Input1(Input1)
    );

    initial begin
        clock = 0;
    end

    always begin
        #5 clock = ~clock;
    end

    always @(posedge clock) begin
    
    $display("[Time %0t] PC: %d | Load_Flag: %d |Data Bus: %d | Registers: %d,%d,%d | State: %s | Opcode Fetched: %b", 
             $time, 
             CU.Program_Counter,
             CU.load_flag,
             CU.dataBus, 
             CU.Register_A,
             CU.Register_B,
             CU.Carry_Reg,
             (CU.state_reg == 1'b0) ? "EXECUTE" : "FETCH", 
             CU.opCode);
     end

    initial begin
        $display("========================================");
        $display("Started Program.");
        $display("...");

        fork:simulation_control
                begin
                        wait(CU.opCode == 16'b1111111111111111);
                        $display("...");
                        $display("Reached Halt Instruction. Stopping execution.");
                        disable simulation_control;
                end
                begin
                        #5000;
                        $display("...");
                        $display("Stopping program after extended runtime.");
                        disable simulation_control;
                end
        join

        $display("========================================");
        $display("Final CPU State");
        $display("Program Counter:  %d", CU.Program_Counter);
        $display("Data Bus:        %d", CU.dataBus);
        $display("Accumulator:     %d", CU.Accumulator);
        $display("Register_A       %d", CU.Register_A);
        $display("Register_B:      %d", CU.Register_B);
        $display("Jump Register:   %d", CU.Jump_Register);
        $display("Input1:          %d", Input1);
        $display("Output1:         %d", Output1);
        $display("========================================");

        $finish;

    end

endmodule
