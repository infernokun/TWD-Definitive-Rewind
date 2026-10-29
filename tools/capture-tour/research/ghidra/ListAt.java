// Prints the instructions of the code around each given address: walks back to the previous int3 (0xCC)
// padding, disassembles from there and prints until the given address + 0x40. Args: outfile addr [...]
// @category Telltale

import ghidra.app.cmd.disassemble.DisassembleCommand;
import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.Instruction;

import java.io.File;
import java.io.PrintWriter;

public class ListAt extends GhidraScript {
    @Override
    protected void run() throws Exception {
        String[] args = getScriptArgs();
        try (PrintWriter w = new PrintWriter(new File(args[0]))) {
            for (int i = 1; i < args.length; i++) {
                Address a = toAddr(Long.parseLong(args[i].replace("0x", ""), 16));
                Address s = a;
                for (int k = 0; k < 0x200; k++) {
                    if ((getByte(s.subtract(1)) & 0xff) == 0xCC) break;
                    s = s.subtract(1);
                }
                new DisassembleCommand(s, null, true).applyTo(currentProgram, monitor);
                w.println("\n// ==== " + a + " (code from " + s + ")");
                Instruction ins = getInstructionAt(s);
                while (ins != null && ins.getAddress().compareTo(a.add(0x60)) < 0) {
                    String extra = "";
                    for (Address r : ins.getReferencesFrom().length > 0 ? new Address[] {ins.getReferencesFrom()[0].getToAddress()} : new Address[0]) {
                        String str = null;
                        try {
                            byte[] b = new byte[48];
                            currentProgram.getMemory().getBytes(r, b);
                            int n = 0;
                            while (n < b.length && b[n] >= 32 && b[n] < 127) n++;
                            if (n >= 3 && n < b.length && b[n] == 0) str = new String(b, 0, n);
                        } catch (Exception e) { }
                        extra = "  -> " + r + (str != null ? " \"" + str + "\"" : "");
                    }
                    w.println(ins.getAddress() + "  " + ins + extra);
                    ins = ins.getNext();
                }
            }
        }
    }
}
