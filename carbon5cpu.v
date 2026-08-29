module Add_32 (
    output signed [0:31] Output,
    output carryOut,
    input signed [0:31] A,
    input signed [0:31] B,
    input carry
);
    assign {carryOut, Output} = A + B + carry;
endmodule //Add_32

module Sub_32 (
    output signed [0:31] Output,
    output carryOut,
    input signed [0:31] A,
    input signed [0:31] B,
    input carry
);
    assign {carryOut, Output} = A + (~B) + carry;
endmodule //Sub_32

module Mult_32 (
    output signed [0:31] outLow,            
    output signed [0:31] outHigh,  
    input signed [0:31] A,
    input signed [0:31] B,
    input signed [0:31] carryIn          
);
    wire signed [63:0] rawProduct;
    assign rawProduct = A * B;
    
    wire signed [63:0] finalResult;
    assign finalResult = rawProduct + {{32{carryIn[0]}}, carryIn};
    
    assign outLow  = finalResult[31:0];
    assign outHigh = finalResult[63:32];
endmodule //Mult_32

module Div_32 (
    output signed [0:31] Quotient,
    output signed [0:31] Remainder,
    input signed [0:31] A,                     
    input signed [0:31] B,     
    input signed [0:31] remainder_in 
);
    // Directly synthesizes to optimized simulator primitives
    assign Quotient  = (B != 0) ? (A / B) : 32'd0;
    assign Remainder = (B != 0) ? (A % B) : 32'd0;
endmodule //Div_32

module Bsl_32 (
    output [0:31] Output,   
    output [0:31] carryOut,    
    input  [0:31] A,
    input  [0:31] carryIn,     
    input  [0:31] Shift_Amount
);
    reg [63:0] fullOutput;

    always @(*) begin
        fullOutput = {carryIn, A};
        fullOutput = fullOutput << Shift_Amount;
    end

    assign Output   = fullOutput[31:0];
    assign carryOut = fullOutput[63:32];
endmodule //Bsl_32

module Bsr_32 (
    output [0:31] Output,        
    output [0:31] carryOut,    
    input  [0:31] A,
    input  [0:31] carryIn,     
    input  [0:31] Shift_Amount
);
    reg [63:0] fullOutput;

    always @(*) begin
        fullOutput = {A, carryIn};
        fullOutput = fullOutput >> Shift_Amount;
    end

    assign Output   = fullOutput[63:32];
    assign carryOut = fullOutput[31:0];
endmodule //Bsr_32

module ALU_32 (
    output signed [0:31] ALUOutput,
    output signed [0:31] ALUCarry,
    output reg ZeroFlag,
    output reg CarryFlag,
    output reg NegativeFlag,

    input signed [0:31] a,
    input signed [0:31] b,
    input signed [0:31] carry,
    input [0:2] state
);
    wire signed [0:31] addOut, subOut, multOutLow, multOutHigh, divQuotient, divRemainder, bslOut, bslCarry, bsrOut, bsrCarry;
    wire signed addCarry, subCarry;

    Add_32 addUnit(.Output(addOut), .carryOut(addCarry), .A(a), .B(b), .carry(carry[0]));

    Sub_32 subUnit(.Output(subOut), .carryOut(subCarry), .A(a), .B(b), .carry(carry[0]));

    Mult_32 multUnit(.outLow(multOutLow), .outHigh(multOutHigh), .A(a), .B(b), .carryIn(carry));

    wire [0:31] abs_a = a[0] ? (-a) : a;
    wire [0:31] abs_b = b[0] ? (-b) : b;

    wire [0:31] raw_divWire;
    wire [0:31] raw_divRemainder;

    Div_32 div (.Quotient(raw_divWire), .Remainder(raw_divRemainder), .A(abs_a), .B(abs_b), .remainder_in(32'd0));

    Bsl_32 bslUnit(.Output(bslOut), .carryOut(bslCarry), .A(a), .carryIn(carry), .Shift_Amount(b));

    Bsr_32 bsrUnit(.Output(bsrOut), .carryOut(bsrCarry), .A(a), .carryIn(carry), .Shift_Amount(b));

    reg signed [0:31] rOutput;
    reg signed [0:31] rCarry;

    always @(*) begin
        case (state)
            3'd0: begin rOutput = addOut;  rCarry = {{31{1'b0}}, addCarry}; end
            3'd1: begin rOutput = subOut;  rCarry = {{31{1'b0}}, subCarry}; end
            3'd2: begin rOutput = multOutLow;  rCarry = multOutHigh; end
            3'd3: begin rOutput = raw_divWire;  rCarry = raw_divRemainder; end
            3'd4: begin rOutput = bslOut;  rCarry = bslCarry; end
            3'd5: begin rOutput = bsrOut;  rCarry = bsrCarry; end
            default: begin rOutput = 32'd0; rCarry = 32'd0; end
        endcase

        if (rOutput == 32'd0) begin
            ZeroFlag = 1'b1;
        end else begin
            ZeroFlag = 1'b0;
        end

        if (rOutput[0] == 1'b1) begin
            NegativeFlag = 1'b1;
        end else begin
            NegativeFlag = 1'b0;
        end

        if (rCarry != 32'd0) begin
            CarryFlag = 1'b1;
        end else begin
            CarryFlag = 1'b0;
        end
    end

    assign ALUCarry  = rCarry; 
    assign ALUOutput = rOutput;
endmodule //ALU_32

module RAM_32 (
    output [31:0] dataOut,
    input [31:0] dataIn,
    input [31:0] address,
    input writeEnable,
    input clock    
);
    reg [31:0] ram [0:65535]; // 64 kb - could support 4 gb, but that would be too much for a sim

    always @(posedge clock) begin
        if(writeEnable) begin 
            ram[address] <= dataIn; 
        end 
    end

    assign dataOut = ram[address];
endmodule //RAM_32

// 1024-word Instruction ROM module
module Instruction_ROM_32 #(
    parameter FILE_NAME = "instructions_default.mem"
) (
    output reg [7:0] instruction,
    input [31:0] address,
    input clock
);
    reg [7:0] rom [0:1023];

    initial begin
        $readmemb(FILE_NAME, rom);
    end

    always @(posedge clock) begin
        instruction <= rom[address];
    end
endmodule //Instruction_ROM_32

module Central_Unit (
    output reg signed [31:0] output1,
    input wire clock,
    input signed [31:0] Input1
);

    // THREAD 1 REGISTERS
    reg [7:0]         opCode_T1              = 8'd0;
    reg signed [31:0] Accumulator_T1         = 32'd0;
    reg signed [31:0] Carry_Reg_T1           = 32'd0;
    reg signed [31:0] Register_A_T1          = 32'd0;
    reg signed [31:0] Register_B_T1          = 32'd0;
    reg signed [31:0] Register_C_T1          = 32'd0;
    reg [2:0]         ALU_State_T1           = 3'd7;
    reg [31:0]        Program_Counter_T1     = 32'd0;
    reg [31:0]        Jump_Register_T1       = 32'd0;
    reg               load_flag_T1           = 1'b0;
    reg               alu_load_flag_T1       = 1'b0;
    reg signed [31:0] dataBus_T1             = 32'd0;

    // THREAD 2 REGISTERS
    reg [7:0]         opCode_T2              = 8'd0;
    reg signed [31:0] Accumulator_T2         = 32'd0;
    reg signed [31:0] Carry_Reg_T2           = 32'd0;
    reg signed [31:0] Register_A_T2          = 32'd0;
    reg signed [31:0] Register_B_T2          = 32'd0;
    reg signed [31:0] Register_C_T2          = 32'd0;
    reg [2:0]         ALU_State_T2           = 3'd7;
    reg [31:0]        Program_Counter_T2     = 32'd0;
    reg [31:0]        Jump_Register_T2       = 32'd0;
    reg               load_flag_T2           = 1'b0;
    reg               alu_load_flag_T2       = 1'b0;
    reg signed [31:0] dataBus_T2             = 32'd0;

    //current thread
    reg thread = 1'b0; // 0: Thread 1 Decode / Thread 2 Execute
                       // 1: Thread 2 Decode / Thread 1 Execute

    //next opcode
    wire [7:0] inst_T1;
    wire [7:0] inst_T2;

    //ALU wires
    wire signed [31:0] ALU_Output;
    wire signed [31:0] ALU_Carry;
    wire               Negative_Flag;
    wire               Zero_Flag;
    wire               Carry_Flag;
    wire signed [31:0] current_Reg_A = (thread == 1'b1) ? Register_A_T1 : Register_A_T2;
    wire signed [31:0] current_Reg_B = (thread == 1'b1) ? Register_B_T1 : Register_B_T2;
    wire signed [31:0] current_Reg_C = (thread == 1'b1) ? Register_C_T1 : Register_C_T2;
    wire [2:0]         current_State = (thread == 1'b1) ? ALU_State_T1  : ALU_State_T2;

    //RAM wires
    reg  [31:0] RAM_address_wire;
    reg  [31:0] RAM_dataIn;
    reg  RAM_writeEnable;
    wire [31:0] RAM_dataOut;


    //different modules in the cpu
    Instruction_ROM_32 #(
        .FILE_NAME("D:/programs/Cpu folder/thread1Program.txt")
    ) instRom_T1 (
        .instruction(inst_T1),
        .address(Program_Counter_T1),
        .clock(clock)
    );

    Instruction_ROM_32 #(
        .FILE_NAME("D:/programs/Cpu folder/thread2Program.txt")
    ) instRom_T2 (
        .instruction(inst_T2),
        .address(Program_Counter_T2),
        .clock(clock)
    );

    ALU_32 ALU (
        .ALUOutput(ALU_Output),
        .ALUCarry(ALU_Carry),
        .a(current_Reg_A),
        .b(current_Reg_B),
        .carry(current_Reg_C),
        .state(current_State),
        .CarryFlag(Carry_Flag),
        .ZeroFlag(Zero_Flag),
        .NegativeFlag(Negative_Flag)
    );

    RAM_32 ram (
        .dataOut(RAM_dataOut),
        .dataIn(RAM_dataIn),
        .address(RAM_address_wire),
        .writeEnable(RAM_writeEnable),
        .clock(clock)
    );

    //CU logic
    always @(posedge clock) begin
        //update the current opcode
        opCode_T1 = inst_T1;
        opCode_T2 = inst_T2;

        //reset mem wires
        RAM_address_wire <= 32'd0;
        RAM_dataIn       <= 32'd0;

        if (thread == 1'b0) begin

            //Thread 1 decode block
            case (opCode_T1)
                8'b00000001: begin ALU_State_T1 <= 3'd0; alu_load_flag_T1 <= 1'b1; end // ADD
                8'b00000010: begin ALU_State_T1 <= 3'd1; alu_load_flag_T1 <= 1'b1; end // SUB
                8'b00000011: begin ALU_State_T1 <= 3'd2; alu_load_flag_T1 <= 1'b1; end // MUL
                8'b00000100: begin ALU_State_T1 <= 3'd3; alu_load_flag_T1 <= 1'b1; end // DIV
                8'b00000101: begin ALU_State_T1 <= 3'd4; alu_load_flag_T1 <= 1'b1; end // BSL
                8'b00000110: begin ALU_State_T1 <= 3'd5; alu_load_flag_T1 <= 1'b1; end // BSR

                8'b00101001: load_flag_T1 <= 1'b1; // Load constant next cycle

                8'b00001000: begin // RAM Write Enable
                    RAM_writeEnable  <= 1'b1;
                    RAM_address_wire <= Register_A_T1;
                    RAM_dataIn       <= Register_B_T1;
                end

                8'b00001001: begin // RAM read
                    RAM_address_wire <= Register_A_T1;
                end

                default: begin 
                    ALU_State_T1    <= 3'd7;
                    RAM_writeEnable <= 1'b0;
                end
            endcase


            //Thread 2 execute block
            if (load_flag_T2 == 1'b1) begin //load constant
                dataBus_T2 <= {{24{1'b0}}, inst_T2};
                load_flag_T2       <= 1'b0;
                
            end 

            Program_Counter_T2 <= Program_Counter_T2 + 1;//update program counter

            if (alu_load_flag_T2 == 1'b1) begin
                Accumulator_T2 = ALU_Output;
                Carry_Reg_T2   = ALU_Carry;
                Register_C_T2  = ALU_Carry;
                alu_load_flag_T2 <= 1'b0;
            end //if a ALU op was done, update registers before next block

            case (opCode_T2)
                8'b00100001: dataBus_T2 <= RAM_dataOut;
                8'b00100010: dataBus_T2 <= Accumulator_T2;
                8'b00100011: dataBus_T2 <= Carry_Reg_T2;
                8'b00100100: dataBus_T2 <= Register_A_T2;
                8'b00100101: dataBus_T2 <= Register_B_T2;
                8'b00100110: dataBus_T2 <= Register_C_T2;
                8'b00100111: dataBus_T2 <= Program_Counter_T2;
                8'b00101000: dataBus_T2 <= Input1;

                8'b01000000: Carry_Reg_T2 <= 32'd0;
                8'b01000001: Carry_Reg_T2 <= 32'd1;

                8'b00010000: Register_A_T2    <= dataBus_T2;
                8'b00010001: Register_B_T2    <= dataBus_T2;
                8'b00010010: Register_C_T2    <= dataBus_T2;
                8'b00010011: Jump_Register_T2 <= dataBus_T2;

                8'b10000000: Program_Counter_T2 <= Jump_Register_T2;
                8'b10000001: if (Zero_Flag == 1'b1)     Program_Counter_T2 <= Jump_Register_T2;
                8'b10000010: if (Carry_Flag == 1'b1)    Program_Counter_T2 <= Jump_Register_T2;
                8'b10000011: if (Negative_Flag == 1'b1) Program_Counter_T2 <= Jump_Register_T2;
                8'b11110000: output1 <= dataBus_T2;
            endcase
        end else begin

            //Thread 2 decode block

            case (opCode_T2)
                8'b00000001: begin ALU_State_T2 <= 3'd0; alu_load_flag_T2 <= 1'b1; end // ADD
                8'b00000010: begin ALU_State_T2 <= 3'd1; alu_load_flag_T2 <= 1'b1; end // SUB
                8'b00000011: begin ALU_State_T2 <= 3'd2; alu_load_flag_T2 <= 1'b1; end // MUL
                8'b00000100: begin ALU_State_T2 <= 3'd3; alu_load_flag_T2 <= 1'b1; end // DIV
                8'b00000101: begin ALU_State_T2 <= 3'd4; alu_load_flag_T2 <= 1'b1; end // BSL
                8'b00000110: begin ALU_State_T2 <= 3'd5; alu_load_flag_T2 <= 1'b1; end // BSR

                8'b00101001:load_flag_T2 <= 1'b1;// Load constant next cycle

                8'b00001000: begin // RAM Write Enable
                    RAM_writeEnable  <= 1'b1;
                    RAM_address_wire <= Register_A_T2;
                    RAM_dataIn       <= Register_B_T2;
                end

                8'b00001001: RAM_address_wire <= Register_A_T2; // RAM read

                default: begin 
                    ALU_State_T2    <= 3'd7;
                    RAM_writeEnable <= 1'b0;
                end
            endcase


            //Thread 1 execute block

            if (load_flag_T1 == 1'b1) begin //load contsant
                dataBus_T1 <= {{24{1'b0}}, inst_T1};
                load_flag_T1       <= 1'b0;
            end 
            Program_Counter_T1 <= Program_Counter_T1 + 1;

            if (alu_load_flag_T1 == 1'b1) begin
                Accumulator_T1 = ALU_Output;
                Carry_Reg_T1   = ALU_Carry;
                Register_C_T1  = ALU_Carry;
                alu_load_flag_T1 <= 1'b0; // the use of a = instead of a <= is deliberate to ensure that opcodes dont use old data
            end

            case (opCode_T1)
                8'b00100001: dataBus_T1 <= RAM_dataOut;
                8'b00100010: dataBus_T1 <= Accumulator_T1;
                8'b00100011: dataBus_T1 <= Carry_Reg_T1;
                8'b00100100: dataBus_T1 <= Register_A_T1;
                8'b00100101: dataBus_T1 <= Register_B_T1;
                8'b00100110: dataBus_T1 <= Register_C_T1;
                8'b00100111: dataBus_T1 <= Program_Counter_T1;
                8'b00101000: dataBus_T1 <= Input1;

                8'b01000000: Carry_Reg_T1 <= 32'd0;
                8'b01000001: Carry_Reg_T1 <= 32'd1;

                8'b00010000: Register_A_T1    <= dataBus_T1;
                8'b00010001: Register_B_T1    <= dataBus_T1;
                8'b00010010: Register_C_T1    <= dataBus_T1;
                8'b00010011: Jump_Register_T1 <= dataBus_T1;

                8'b10000000: Program_Counter_T1 <= Jump_Register_T1;
                8'b10000001: if (Zero_Flag == 1'b1)     Program_Counter_T1 <= Jump_Register_T1;
                8'b10000010: if (Carry_Flag == 1'b1)    Program_Counter_T1 <= Jump_Register_T1;
                8'b10000011: if (Negative_Flag == 1'b1) Program_Counter_T1 <= Jump_Register_T1;
                8'b11110000: output1 <= dataBus_T1;
            endcase
        end

        // Toggle execution thread context every clock cycle
        thread <= ~thread;

    end
endmodule

`timescale 1ns / 1ns

module Main;
    reg clock;

    wire signed [31:0] output1;
    reg signed  [31:0] Input1 = 32'd0;
    

    //create the acutal Cpu
    Central_Unit CU (
        .output1(output1),
        .clock(clock),
        .Input1(Input1)
    );
    
    initial begin
        clock = 0;
    end

    always begin
        #5 clock = ~clock;
    end

    always @(posedge clock) begin //update every clock cycle
        $display("[Time %0t] Thread: T%0d | T1 PC: %0d (Op: %8b, Bus: %0d, Accumulator: %0d, Reg A: %0d, Reg B: %0d) | T2 PC: %0d (Op: %8b, Bus: %0d, Accumulator: %0d, Reg A: %0d, Reg B: %0d) | test: %d", 
                 $time, 
                 CU.thread,
                 CU.Program_Counter_T1,
                 CU.opCode_T1,
                 CU.dataBus_T1,
                 CU.Accumulator_T1,
                 CU.Register_A_T1,
                 CU.Register_B_T1,
                 CU.Program_Counter_T2,
                 CU.opCode_T2,
                 CU.dataBus_T2,
                 CU.Accumulator_T2,
                 CU.Register_A_T2,
                 CU.Register_B_T2,
                 CU.ALU_State_T2);
    end

    // Simulation Execution & Halt Control
    initial begin
        $display("Started Sim.");
        $display("========================================");

        fork : simulation_control
            //listens for halt instruction
            begin
                wait (CU.opCode_T1 == 8'b11111111 || CU.opCode_T2 == 8'b11111111);
                $display("...");
                $display("Reached Halt Instruction. Stopping execution.");
                disable simulation_control;
            end

            //timeout incase no halt is reached
            begin
                #10000;
                $display("...");
                $display("Stopping program after extended runtime timeout.");
                disable simulation_control;
            end
        join

        // display cpu end state
        $display("========================================");
        $display("Final CPU State");
        $display("----------------------------------------");
        $display("THREAD 1 STATE:");
        $display("  Program Counter : %d", CU.Program_Counter_T1);
        $display("  Opcode          : 8'b%8b", CU.opCode_T1);
        $display("  Data Bus        : %d", CU.dataBus_T1);
        $display("  Accumulator     : %d", CU.Accumulator_T1);
        $display("  Register A      : %d", CU.Register_A_T1);
        $display("  Register B      : %d", CU.Register_B_T1);
        $display("  Register C      : %d", CU.Register_C_T1);
        $display("  Jump Register   :  %d", CU.Jump_Register_T1);
        $display("----------------------------------------");
        $display("THREAD 2 STATE:");
        $display("  Program Counter : %d", CU.Program_Counter_T2);
        $display("  Opcode          : 8'b%8b", CU.opCode_T2);
        $display("  Data Bus        : %d", CU.dataBus_T2);
        $display("  Accumulator     : %d", CU.Accumulator_T2);
        $display("  Register A      : %d", CU.Register_A_T2);
        $display("  Register B      : %d", CU.Register_B_T2);
        $display("  Register C      : %d", CU.Register_C_T2);
        $display("  Jump Register   :  %d", CU.Jump_Register_T2);
        $display("----------------------------------------");
        $display("GLOBAL I/O:");
        $display("  Input1          : %d", Input1);
        $display("  Output1         : %d", output1);
        $display("========================================");
        $finish;
    end
endmodule