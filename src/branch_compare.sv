module branch_compare (
    input  logic [31:0] a,
    input  logic [31:0] b,

    input  logic [1:0] BranchTypeD,
    input  logic BranchCondD,

    output logic TakenD
);

    logic BrEq, BrLt;

    assign BrEq = (a == b);
    assign BrLt = ($signed(a) < $signed(b));

    always_comb begin
        TakenD = 1'b0;

        case (BranchTypeD)
            2'b01: TakenD = BranchCondD ? !BrEq : BrEq; // BEQ/BNE
            2'b10: TakenD = BranchCondD ? (!BrLt && !BrEq) : !BrLt;    // BGT/BGE
            default: TakenD = 1'b0;
        endcase
    end

endmodule