// Runs every JUnit 4 test class found below a class directory (classes with at least one @Test method).
import java.io.File;
import java.lang.reflect.Method;
import java.lang.reflect.Modifier;
import java.util.ArrayList;
import java.util.List;
import org.junit.runner.JUnitCore;
import org.junit.runner.Result;
import org.junit.runner.notification.Failure;

public class RunAll {
    public static void main(String[] args) throws Exception {
        File root = new File(args[0]);
        List<Class<?>> classes = new ArrayList<>();
        collect(root, root, classes);
        if (classes.isEmpty()) {
            System.out.println("No test classes found in " + root);
            System.exit(2);
        }
        JUnitCore core = new JUnitCore();
        core.addListener(new org.junit.internal.TextListener(System.out) {
            @Override public void testRunFinished(Result result) { }
        });
        Result r = core.run(classes.toArray(new Class<?>[0]));
        for (Failure f : r.getFailures()) {
            System.out.println("FAILED: " + f.getTestHeader());
            System.out.println(f.getTrace());
        }
        System.out.println(String.format("Tests: %d, failures: %d, ignored: %d, classes: %d, time: %.1fs",
            r.getRunCount(), r.getFailureCount(), r.getIgnoreCount(), classes.size(), r.getRunTime() / 1000.0));
        System.exit(r.wasSuccessful() ? 0 : 1);
    }

    static void collect(File root, File dir, List<Class<?>> out) throws Exception {
        File[] files = dir.listFiles();
        if (files == null) return;
        for (File f : files) {
            if (f.isDirectory()) { collect(root, f, out); continue; }
            String n = f.getName();
            if (!n.endsWith(".class") || n.contains("$")) continue;
            String rel = root.toPath().relativize(f.toPath()).toString();
            String cn = rel.substring(0, rel.length() - 6).replace(File.separatorChar, '.');
            Class<?> c = Class.forName(cn, false, RunAll.class.getClassLoader());
            if (Modifier.isAbstract(c.getModifiers()) || !Modifier.isPublic(c.getModifiers())) continue;
            boolean has = false;
            for (Method m : c.getMethods()) if (m.isAnnotationPresent(org.junit.Test.class)) { has = true; break; }
            if (has) out.add(c);
        }
    }
}
