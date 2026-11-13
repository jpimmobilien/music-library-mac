// Erzeugt org.hamcrest.CoreMatchers wie der Original-Build von hamcrest 1.3 (core-matchers.xml),
// aber ohne QDox: Parameternamen werden nicht übernommen (für Aufrufer ohne Bedeutung).
import org.hamcrest.generator.*;
import java.io.*;
public class GenCoreMatchers {
  public static void main(String[] a) throws Exception {
    String[] classes = {"AllOf","AnyOf","CombinableMatcher","DescribedAs","Every","Is","IsAnything",
      "IsCollectionContaining","IsEqual","IsInstanceOf","IsNot","IsNull","IsSame","StringContains",
      "StringStartsWith","StringEndsWith"};
    File out = new File(a[0], "org/hamcrest/CoreMatchers.java"); out.getParentFile().mkdirs();
    try (Writer w = new FileWriter(out)) {
      SugarGenerator g = new SugarGenerator();
      g.addWriter(new HamcrestFactoryWriter("org.hamcrest", "CoreMatchers", w));
      for (String c : classes) g.addFactoryMethods(new ReflectiveFactoryReader(Class.forName("org.hamcrest.core." + c)));
      g.generate(); g.close();
    }
  }
}
