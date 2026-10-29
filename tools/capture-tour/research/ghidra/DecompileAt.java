// Decompiles the functions containing the given addresses, using the PE .pdata function table to find
// each function's start (works without full auto-analysis). Args: outfile addr [addr ...] (hex)
// @category Telltale

import ghidra.app.cmd.disassemble.DisassembleCommand;
import ghidra.app.decompiler.DecompInterface;
import ghidra.app.decompiler.DecompileResults;
import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.Function;
import ghidra.program.model.mem.MemoryBlock;

import java.io.File;
import java.io.PrintWriter;

public class DecompileAt extends GhidraScript {
    @Override
    protected void run() throws Exception {
        String[] args = getScriptArgs();
        MemoryBlock pdata = currentProgram.getMemory().getBlock(".pdata");
        long base = currentProgram.getImageBase().getOffset();
        DecompInterface dec = new DecompInterface();
        dec.openProgram(currentProgram);
        try (PrintWriter w = new PrintWriter(new File(args[0]))) {
            for (int i = 1; i < args.length; i++) {
                long target = Long.parseLong(args[i].replace("0x", ""), 16);
                Address start = null;
                // RUNTIME_FUNCTION: u32 begin rva, u32 end rva, u32 unwind rva
                for (long o = 0; o + 12 <= pdata.getSize(); o += 12) {
                    Address e = pdata.getStart().add(o);
                    long b = (currentProgram.getMemory().getInt(e) & 0xffffffffL) + base;
                    long en = (currentProgram.getMemory().getInt(e.add(4)) & 0xffffffffL) + base;
                    if (b <= target && target < en) {
                        start = toAddr(b);
                        break;
                    }
                }
                w.println("\n// ==== " + args[i] + " in function starting " + start);
                if (start == null) continue;
                new DisassembleCommand(start, null, true).applyTo(currentProgram, monitor);
                Function f = getFunctionAt(start);
                if (f == null) f = createFunction(start, null);
                if (f == null) { w.println("// could not create function"); continue; }
                DecompileResults r = dec.decompileFunction(f, 180, monitor);
                w.println(r != null && r.decompileCompleted() ? r.getDecompiledFunction().getC() : "// decompile failed");
            }
        }
        dec.dispose();
    }
}
