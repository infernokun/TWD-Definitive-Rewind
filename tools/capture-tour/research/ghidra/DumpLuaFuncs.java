// Finds where the engine registers Lua functions by name and decompiles their implementations.
// For each name: every defined string equal to it; for each reference to that string:
//  - a data reference (a {name, function} registration table): the pointer next to it is the C function;
//  - a code reference: the function containing it (registration code or a user of the name).
// Writes <outdir>/<name>.c.  Args: outdir name [name ...]
// @category Telltale

import ghidra.app.decompiler.DecompInterface;
import ghidra.app.decompiler.DecompileResults;
import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.data.StringDataInstance;
import ghidra.program.model.listing.Data;
import ghidra.program.model.listing.DataIterator;
import ghidra.program.model.listing.Function;
import ghidra.program.model.symbol.Reference;

import java.io.File;
import java.io.PrintWriter;
import java.util.*;

public class DumpLuaFuncs extends GhidraScript {
    private DecompInterface dec;

    private String decompile(Function f) {
        DecompileResults r = dec.decompileFunction(f, 120, monitor);
        if (r != null && r.decompileCompleted() && r.getDecompiledFunction() != null) {
            return r.getDecompiledFunction().getC();
        }
        return "// decompile failed for " + f.getName() + " @ " + f.getEntryPoint() + "\n";
    }

    @Override
    protected void run() throws Exception {
        String[] args = getScriptArgs();
        File out = new File(args[0]);
        out.mkdirs();
        Set<String> wanted = new HashSet<>(Arrays.asList(args).subList(1, args.length));
        dec = new DecompInterface();
        dec.openProgram(currentProgram);

        // Every place the exact NUL-terminated name occurs (with a NUL before it), defined as a string or not.
        Map<String, List<Address>> strings = new HashMap<>();
        for (String name : wanted) {
            byte[] pat = ("\0" + name + "\0").getBytes("US-ASCII");
            Address start = currentProgram.getMinAddress();
            while (start != null && !monitor.isCancelled()) {
                Address hit = currentProgram.getMemory().findBytes(start, pat, null, true, monitor);
                if (hit == null) break;
                strings.computeIfAbsent(name, k -> new ArrayList<>()).add(hit.add(1));
                start = hit.add(1);
            }
        }

        for (String name : wanted) {
            try (PrintWriter w = new PrintWriter(new File(out, name + ".c"))) {
                List<Address> addrs = strings.getOrDefault(name, Collections.emptyList());
                w.println("// " + name + ": " + addrs.size() + " string(s)");
                Set<Function> done = new HashSet<>();
                for (Address a : addrs) {
                    List<Address> froms = new ArrayList<>();
                    for (Reference ref : getReferencesTo(a)) {
                        froms.add(ref.getFromAddress());
                    }
                    // No recorded references: look for the address stored as a 64-bit pointer.
                    if (froms.isEmpty()) {
                        long v = a.getOffset();
                        byte[] ptr = new byte[8];
                        for (int i = 0; i < 8; i++) ptr[i] = (byte) (v >>> (8 * i));
                        Address s = currentProgram.getMinAddress();
                        while (s != null && froms.size() < 8) {
                            Address hit = currentProgram.getMemory().findBytes(s, ptr, null, true, monitor);
                            if (hit == null) break;
                            froms.add(hit);
                            s = hit.add(1);
                        }
                        w.println("// " + a + ": no references; stored as a pointer at " + froms);
                    }
                    for (Address from : froms) {
                        Function f = getFunctionContaining(from);
                        if (f == null) {
                            // data: look for a function pointer right after the name pointer
                            for (int off : new int[] {8, -8, 16}) {
                                try {
                                    long p = currentProgram.getMemory().getLong(from.add(off));
                                    Address target = toAddr(p);
                                    Function tf = getFunctionAt(target);
                                    if (tf == null) tf = createFunction(target, null);
                                    if (tf != null && done.add(tf)) {
                                        w.println("\n// ---- data ref at " + from + " (+" + off + ") -> " + tf.getName() + " @ " + target);
                                        w.println(decompile(tf));
                                    }
                                } catch (Exception e) {
                                    // not a pointer
                                }
                            }
                        } else if (done.add(f)) {
                            w.println("\n// ---- code ref at " + from + " in " + f.getName() + " @ " + f.getEntryPoint());
                            w.println(decompile(f));
                        }
                        if (done.size() > 6) break;
                    }
                }
            }
            println("wrote " + name);
        }
        dec.dispose();
    }
}
