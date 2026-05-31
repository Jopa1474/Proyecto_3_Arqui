`timescale 1ns/1ps
module datapath_tb;

logic clk, rst;

datapath dut (.clk, .rst);

initial clk = 0;
always #5 clk = ~clk;

 
integer cycle_count;
logic halt_seen;

 
initial begin
    $dumpfile("sim/datapath_tb.vcd");      
    $dumpvars(0, datapath_tb);

    $display("Datapath Test - Iniciando");

    cycle_count = 0;
    halt_seen   = 0;

    rst = 1;
    repeat(3) @(posedge clk);
    rst = 0;
end

 
// Conteo de ciclos + finalización automática
always @(posedge clk) begin
    if (!rst && !halt_seen) begin
        cycle_count <= cycle_count + 1;

        if (dut.halted) begin
            halt_seen <= 1;

            $display("Programa finalizado en %0d ciclos", cycle_count);
            $display("PC final = %08h", dut.pc_out);

            $writememh("mem/mem_init.mem", dut.dmem.mem);
            $display(">>> mem_init.mem escrito");
 
            #10;
            $finish;
        end
    end
end

 
// Por ciclo
always @(posedge clk) begin
    if (!rst && !halt_seen) begin
        $display("--------------- CICLO %0d ----------------", cycle_count);

        $display("PC=%08h | IF=%06h | ID=%06h | halted=%b",
            dut.pc_out, dut.instr_if, dut.instr, dut.halted);

        $display("EX:  alu=%08h  vault=%08h  fwdA=%b fwdB=%b  pc_src=%b",
            dut.alu_result_ex, dut.vault_result_ex,
            dut.ForwardA, dut.ForwardB, dut.pc_src_s);

        $display("MEM: addr=%08h  wdata=%08h  rdata=%08h  mw=%b mr=%b",
            dut.alu_result_mem, dut.write_data_mem,
            dut.read_data, dut.mem_write_mem, dut.mem_read_mem);

        $display("WB:  rd=r%-2d  wdata=%08h  we=%b",
            dut.rd_wb, dut.result_wb, dut.reg_write_wb);

        $display("SR:  auth=%b  vf=%b  exc=%b  cause=%03b",
            dut.sr[0], dut.sr[1], dut.sr[2], dut.sr[5:3]);

        $display("r0 =%08h  r1 =%08h  r2 =%08h  r3 =%08h",
            dut.rf.regs[0],  dut.rf.regs[1],
            dut.rf.regs[2],  dut.rf.regs[3]);

        $display("r4 =%08h  r5 =%08h  r6 =%08h  r7 =%08h",
            dut.rf.regs[4],  dut.rf.regs[5],
            dut.rf.regs[6],  dut.rf.regs[7]);

        $display("r8 =%08h  r9 =%08h  r10=%08h  r11=%08h",
            dut.rf.regs[8],  dut.rf.regs[9],
            dut.rf.regs[10], dut.rf.regs[11]);

        $display("r12=%08h  r13=%08h  r14=%08h  r15=%08h",
            dut.rf.regs[12], dut.rf.regs[13],
            dut.rf.regs[14], dut.rf.regs[15]);

        $display("MEM[0..3]: %08h %08h %08h %08h",
            dut.dmem.mem[0], dut.dmem.mem[1],
            dut.dmem.mem[2], dut.dmem.mem[3]);

        $display("VAULT[0]: %08h %08h %08h %08h",
            dut.key_vault.vault[0][0], dut.key_vault.vault[0][1],
            dut.key_vault.vault[0][2], dut.key_vault.vault[0][3]);
        $display("VAULT[1]: %08h %08h %08h %08h",
            dut.key_vault.vault[1][0], dut.key_vault.vault[1][1],
            dut.key_vault.vault[1][2], dut.key_vault.vault[1][3]);

        $display("BRANCH DEBUG: instr=%h pc_id=%h imm_d=%h imm_shifted=%h target=%h cond=%b TakenD=%b",
            dut.instr,
            dut.pc_id,
            dut.imm_d,
            dut.imm_shifted_d,
            dut.PCBranchD,
            dut.cond_bit,
            dut.TakenD
        );
        $display("HAZ: load_use=%b branch_stall=%b auth_stall=%b PCWrite=%b IFID=%b nop=%b",
            dut.haz.load_use_stall,
            dut.haz.branch_stall,
            dut.haz.auth_stall,
            dut.pc_write,
            dut.if_id_en,
            dut.nop
        );

    end
end

 
// Eventos importantes
always @(posedge clk) begin
    if (!rst && dut.mem_write_mem)
        $display(">>> MEM WRITE  addr=%08h  data=%08h",
            dut.alu_result_mem, dut.write_data_mem);
end

always @(posedge clk) begin
    if (!rst && dut.sr[2])
        $display(">>> SEC EXCEPTION  cause=%03b", dut.sr[5:3]);
end

always @(posedge clk) begin
    if (!rst && dut.halted)
        $display(">>> HALT DETECTADO  PC=%08h  ciclo=%0d", dut.pc_out, cycle_count); 
end

always @(posedge clk) begin
    if (!rst)
        $display("SIC=%0d auth=%b vf=%b",
            dut.auth.sic.count,
            dut.auth.auth_reg,
            dut.auth.vf_reg);
end

endmodule