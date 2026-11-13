// KStub – turns Kotlin library sources into compile-only API stubs, using the Kotlin compiler's own parser.
//
//   stub <list-file> <out-dir>
//       list-file lines: <fragment>\t<relative path>\t<absolute source path>
//       Writes <out-dir>/<fragment>/<relative path>. Function/accessor bodies become TODO(), default values
//       become TODO(), init blocks disappear, private and internal declarations are removed (private
//       constructors are kept so that instantiability is unchanged). Everything else – signatures, modifiers,
//       annotations (minus lint-only ones), expect/actual, imports – is copied verbatim.
//       Also prints "OPTIN <fq name>" for every annotation class marked @RequiresOptIn.
//   drop <stub-file> <line>[,<line>...] <log-file>
//       Removes the innermost member/top-level declaration (or import) covering each line. Used by the
//       driver to remove declarations that cannot compile without unavailable dependencies.
import org.jetbrains.kotlin.cli.jvm.compiler.EnvironmentConfigFiles
import org.jetbrains.kotlin.cli.jvm.compiler.KotlinCoreEnvironment
import com.intellij.openapi.util.Disposer
import com.intellij.psi.PsiElement
import com.intellij.psi.PsiWhiteSpace
import com.intellij.psi.PsiComment
import org.jetbrains.kotlin.config.CompilerConfiguration
import org.jetbrains.kotlin.cli.extensionsStorage
import org.jetbrains.kotlin.lexer.KtTokens
import org.jetbrains.kotlin.psi.*
import java.io.File

class Edit(val start: Int, val end: Int, val text: String)

private val LINT_ONLY = setOf(
    "IntRange", "FloatRange", "Size", "ColorInt", "ColorLong", "Px", "Dimension", "DrawableRes", "StringRes",
    "IdRes", "AnyRes", "LayoutRes", "RawRes", "DimenRes", "ColorRes", "FontRes", "XmlRes", "StyleRes", "AttrRes",
    "BoolRes", "IntegerRes", "ArrayRes", "AnimRes", "AnimatorRes", "MenuRes", "PluralsRes", "TransitionRes",
    "StyleableRes", "NavigationRes", "InterpolatorRes", "FractionRes", "RequiresPermission", "RequiresApi",
    "ChecksSdkIntAtLeast", "IntDef", "LongDef", "StringDef", "CheckResult", "CallSuper", "MainThread", "UiThread",
    "WorkerThread", "AnyThread", "BinderThread", "VisibleForTesting", "RestrictTo", "Discouraged", "GuardedBy",
    "Keep", "HalfFloat", "FrequentlyChangingValue", "RememberInComposition", "CheckReturnValue", "DoNotInline",
    "ReplaceWith_", "Sampled", "TargetApi", "SuppressLint", "OpenForTesting", "EmptySuper", "ContentView",
    "ReturnThis", "DeprecatedSinceApi", "GravityInt", "InspectableProperty", "LayoutScopeMarker_"
)

lateinit var factory: KtPsiFactory

fun main(args: Array<String>) {
    val disposable = Disposer.newDisposable()
    val cfg = CompilerConfiguration()
    @OptIn(org.jetbrains.kotlin.compiler.plugin.ExperimentalCompilerApi::class)
    cfg.extensionsStorage = org.jetbrains.kotlin.compiler.plugin.CompilerPluginRegistrar.ExtensionStorage()
    val env = KotlinCoreEnvironment.createForProduction(disposable, cfg, EnvironmentConfigFiles.JVM_CONFIG_FILES)
    factory = KtPsiFactory(env.project, markGenerated = false)
    when (args[0]) {
        "stub" -> stubAll(File(args[1]), File(args[2]))
        "drop" -> drop(File(args[1]), args[2].split(",").map { val (l, c) = it.split(":"); l.toInt() to c.toInt() }.toSet(), File(args[3]))
        "dropbatch" -> File(args[1]).readLines().filter { it.isNotBlank() }.forEach { line ->
            val (f, pos) = line.split("\t")
            drop(File(f), pos.split(",").map { val (l, c) = it.split(":"); l.toInt() to c.toInt() }.toSet(), File(args[2]))
        }
        "dropuntyped" -> dropUntyped(File(args[1]), File(args[2]))
        else -> error("unknown mode")
    }
}

fun parse(f: File, text: String = f.readText()): KtFile = factory.createFile(f.name, text.replace("\r\n", "\n"))

fun stubAll(list: File, out: File) {
    var n = 0
    for (line in list.readLines()) {
        if (line.isBlank()) continue
        val (frag, rel, abs) = line.split("\t")
        val src = File(abs)
        val text = src.readText().replace("\r\n", "\n")
        val kt = parse(src, text)
        val edits = ArrayList<Edit>()
        for (d in kt.declarations) handleDecl(d, edits, topLevel = true)
        // lint-only annotations on the file (e.g. @file:RestrictTo) are irrelevant
        kt.fileAnnotationList?.annotationEntries?.forEach { a -> if (lintOnly(a)) edits += Edit(a.textRange.startOffset, a.textRange.endOffset, "") }
        collectOptIn(kt)
        val res = apply(text, edits)
        val target = File(out, "$frag/$rel")
        target.parentFile.mkdirs()
        target.writeText(res)
        n++
    }
    System.err.println("stubbed $n files")
}

fun collectOptIn(kt: KtFile) {
    val pkg = kt.packageFqName.asString()
    fun visit(d: KtDeclaration, prefix: String) {
        if (d is KtClass) {
            val fq = if (prefix.isEmpty()) d.name!! else prefix + "." + d.name
            if (d.isAnnotation() && d.annotationEntries.any { it.shortName?.asString() == "RequiresOptIn" }) println("OPTIN $fq")
            d.body?.declarations?.forEach { visit(it, fq) }
        }
    }
    kt.declarations.forEach { visit(it, pkg) }
}

fun lintOnly(a: KtAnnotationEntry): Boolean {
    val n = a.shortName?.asString() ?: return false
    return n in LINT_ONLY
}

fun KtModifierListOwner.isPrivateOrInternal(): Boolean =
    hasModifier(KtTokens.PRIVATE_KEYWORD) || hasModifier(KtTokens.INTERNAL_KEYWORD)

/** Removes a declaration together with its trailing newline. */
fun removeDecl(d: PsiElement, edits: MutableList<Edit>) {
    var start = d.textRange.startOffset
    var end = d.textRange.endOffset
    // include KDoc/comments directly in front, they are attached to the declaration anyway
    val next = d.nextSibling
    if (next is PsiWhiteSpace && next.text.startsWith("\n")) end = next.textRange.startOffset + 1
    edits += Edit(start, end, "")
}

fun stripAnnotations(owner: KtAnnotated, edits: MutableList<Edit>) {
    for (a in owner.annotationEntries) if (lintOnly(a)) edits += Edit(a.textRange.startOffset, a.textRange.endOffset, "")
}

fun handleDecl(d: KtDeclaration, edits: MutableList<Edit>, topLevel: Boolean, inAnnotationClass: Boolean = false) {
    when (d) {
        is KtSecondaryConstructor -> {
            stripAnnotations(d, edits)
            d.valueParameters.forEach { p -> handleParam(p, edits, inAnnotationClass) }
            d.bodyExpression?.let { edits += Edit(it.textRange.startOffset, it.textRange.endOffset, "{}") }
            return
        }
        is KtEnumEntry -> {
            stripAnnotations(d, edits)
            d.body?.declarations?.forEach { handleDecl(it, edits, false) }
            return
        }
        else -> {}
    }
    if (d is KtAnonymousInitializer) { removeDecl(d, edits); return }
    // private and internal declarations are kept (stubbed like everything else): they are invisible to other
    // modules anyway, and keeping them lets public declarations without explicit types still resolve.
    if (d is KtObjectDeclaration && d.name == "ComposeVersion") return  // read by the Compose compiler
    stripAnnotations(d, edits)
    when (d) {
        is KtNamedFunction -> handleFunction(d, edits)
        is KtProperty -> handleProperty(d, edits)
        is KtClassOrObject -> handleClass(d, edits)
        is KtTypeAlias -> {}
        else -> {}
    }
}

fun handleParam(p: KtParameter, edits: MutableList<Edit>, keepDefault: Boolean, inlineOwner: Boolean = false) {
    stripAnnotations(p, edits)
    if (keepDefault) return
    val dv = p.defaultValue ?: return
    val repl = when (dv) {
        is KtLambdaExpression -> {
            val ps = dv.functionLiteral.valueParameterList
            if (ps != null) "{ ${ps.text} -> TODO() }" else "{ TODO() }"
        }
        is KtCallableReferenceExpression -> dv.text
        else -> {
            // The JVM inliner expects "default value -> store" in the $default bridge of inline functions,
            // so TODO() (which throws) cannot be used there.
            val t = p.typeReference?.text
            if (inlineOwner && t != null) { if (t.trim().endsWith("?")) "null" else "(null as ($t)?)!!" } else "TODO()"
        }
    }
    edits += Edit(dv.textRange.startOffset, dv.textRange.endOffset, repl)
}

fun handleFunction(f: KtNamedFunction, edits: MutableList<Edit>) {
    val inl = f.hasModifier(KtTokens.INLINE_KEYWORD)
    f.valueParameters.forEach { handleParam(it, edits, false, inl) }
    val body = f.bodyExpression ?: return
    if (f.hasBlockBody()) {
        edits += Edit(body.textRange.startOffset, body.textRange.endOffset, "{ TODO() }")
    } else if (f.hasDeclaredReturnType()) {
        edits += Edit(body.textRange.startOffset, body.textRange.endOffset, "TODO()")
    } // else: keep the expression – its type is the function's type
}

fun KtProperty.inExpectOrInterface(): Boolean {
    var e: PsiElement? = parent
    while (e != null && e !is KtFile) {
        if (e is KtClassOrObject) {
            if (e.hasModifier(KtTokens.EXPECT_KEYWORD)) return true
            if (e is KtClass && e.isInterface()) return true
        }
        e = e.parent
    }
    return false
}

fun handleProperty(p: KtProperty, edits: MutableList<Edit>) {
    val typed = p.typeReference != null
    val isConst = p.hasModifier(KtTokens.CONST_KEYWORD)
    val del = p.delegate
    val usesField = p.accessors.any { a -> a.bodyExpression?.text?.contains(Regex("\\bfield\\b")) == true }
    val hasGetter = p.getter?.bodyExpression != null
    val needsField = del == null && (!hasGetter || usesField)
    p.initializer?.let { init ->
        if (typed && !isConst) edits += Edit(init.textRange.startOffset, init.textRange.endOffset, "TODO()")
    }
    if (del != null && typed) {
        val setterMods = p.setter?.modifierList?.text?.let { "$it " } ?: ""
        val accessors = if (p.isVar) "\n        get() = TODO()\n        ${setterMods}set(value) {}" else "\n        get() = TODO()"
        var start = del.textRange.startOffset
        val prev = del.prevSibling
        if (prev is PsiWhiteSpace) start = prev.textRange.startOffset
        var end = del.textRange.endOffset
        // bodyless accessors ("private set", "internal set") are replaced together with the delegate
        for (acc in p.accessors) if (acc.bodyExpression == null) end = maxOf(end, acc.textRange.endOffset)
        edits += Edit(start, end, accessors)
        return
    }
    val eligibleForInit = typed && del == null && p.initializer == null && needsField && !p.isLocal &&
        !p.hasModifier(KtTokens.ABSTRACT_KEYWORD) && !p.hasModifier(KtTokens.EXPECT_KEYWORD) &&
        !p.hasModifier(KtTokens.LATEINIT_KEYWORD) && !p.hasModifier(KtTokens.EXTERNAL_KEYWORD) &&
        p.receiverTypeReference == null && !p.inExpectOrInterface()
    if (eligibleForInit) {
        // initialised in an (removed) init block or constructor
        val tr = p.typeReference!!
        edits += Edit(tr.textRange.endOffset, tr.textRange.endOffset, " = TODO()")
    }
    val keepField = needsField && (p.initializer != null || eligibleForInit)
    for (acc in p.accessors) {
        stripAnnotations(acc, edits)
        val body = acc.bodyExpression ?: continue
        if (acc.isGetter) {
            val r = if (keepField) "field" else "TODO()"
            if (acc.hasBlockBody()) edits += Edit(body.textRange.startOffset, body.textRange.endOffset, "{ return $r }")
            else if (typed || acc.returnTypeReference != null) edits += Edit(body.textRange.startOffset, body.textRange.endOffset, r)
        } else {
            val pn = acc.parameter?.name ?: "value"
            val r = if (keepField) "{ field = $pn }" else "{}"
            if (acc.hasBlockBody()) edits += Edit(body.textRange.startOffset, body.textRange.endOffset, r)
            else edits += Edit(body.textRange.startOffset, body.textRange.endOffset, if (keepField) "run { field = $pn }" else "Unit")
        }
    }
}

fun KtParameter.removeModifiers(edits: MutableList<Edit>, vararg tokens: org.jetbrains.kotlin.lexer.KtModifierKeywordToken) {
    val ml = modifierList ?: return
    for (t in tokens) ml.getModifier(t)?.let { m ->
        var end = m.textRange.endOffset
        val nx = m.nextSibling
        if (nx is PsiWhiteSpace) end = nx.textRange.endOffset
        edits += Edit(m.textRange.startOffset, end, "")
    }
}

fun handleClass(c: KtClassOrObject, edits: MutableList<Edit>) {
    val isAnnotation = c is KtClass && c.isAnnotation()
    val pc = c.primaryConstructor
    val cls = c as? KtClass
    val hiddenCtor = false
    val extraMembers = StringBuilder()
    if (hiddenCtor) {
        // A non-public primary constructor is not part of the API: keep it (so the class stays non-instantiable
        // from outside) but without parameters, which often have non-public types. Public properties declared
        // in it move into the class body.
        for (p in pc!!.valueParameters) {
            if (!p.hasValOrVar()) continue
            if (p.hasModifier(KtTokens.PRIVATE_KEYWORD) || p.hasModifier(KtTokens.INTERNAL_KEYWORD)) continue
            val anns = p.annotationEntries.filter { !lintOnly(it) }.joinToString(" ") { it.text }
            val mods = listOf(KtTokens.PUBLIC_KEYWORD, KtTokens.PROTECTED_KEYWORD, KtTokens.OPEN_KEYWORD, KtTokens.OVERRIDE_KEYWORD,
                KtTokens.ACTUAL_KEYWORD, KtTokens.FINAL_KEYWORD).filter { p.hasModifier(it) }.joinToString(" ") { it.value }
            val kw = if (p.isMutable) "var" else "val"
            val acc = if (p.isMutable) "\n        get() = TODO()\n        set(value) {}" else "\n        get() = TODO()"
            extraMembers.append("\n    $anns $mods $kw ${p.name}: ${p.typeReference?.text}$acc\n")
        }
        val pl = pc.valueParameterList!!
        edits += Edit(pl.textRange.startOffset, pl.textRange.endOffset, "(__kstubHidden: kotlin.Unit?)")
        stripAnnotations(pc, edits)
    } else if (pc != null) {
        stripAnnotations(pc, edits)
        pc.valueParameters.forEach { p ->
            handleParam(p, edits, isAnnotation)
            if (false && p.hasValOrVar() && (p.hasModifier(KtTokens.PRIVATE_KEYWORD) || p.hasModifier(KtTokens.INTERNAL_KEYWORD)) && !isAnnotation &&
                cls != null && !cls.isData() && !cls.hasModifier(KtTokens.VALUE_KEYWORD) && !cls.hasModifier(KtTokens.INLINE_KEYWORD)) {
                // non-public property: keep only the constructor parameter
                p.removeModifiers(edits, KtTokens.PRIVATE_KEYWORD, KtTokens.INTERNAL_KEYWORD, KtTokens.ACTUAL_KEYWORD,
                    KtTokens.OVERRIDE_KEYWORD, KtTokens.OPEN_KEYWORD, KtTokens.FINAL_KEYWORD)
                p.valOrVarKeyword?.let { k ->
                    var end = k.textRange.endOffset
                    val nx = k.nextSibling
                    if (nx is PsiWhiteSpace) end = nx.textRange.endOffset
                    edits += Edit(k.textRange.startOffset, end, "")
                }
            }
        }
    }
    val body = c.body
    if (body == null) {
        if (extraMembers.isNotEmpty()) edits += Edit(c.textRange.endOffset, c.textRange.endOffset, " {$extraMembers}")
        return
    }
    for (d in body.declarations) {
        if (hiddenCtor && d is KtSecondaryConstructor) {
            val call = d.getDelegationCall()
            if (call.isCallToThis) call.valueArgumentList?.let { edits += Edit(it.textRange.startOffset, it.textRange.endOffset, "(__kstubHidden = null)") }
        }
        handleDecl(d, edits, false, isAnnotation)
    }
    if (extraMembers.isNotEmpty()) {
        val lb = body.lBrace
        if (lb != null) edits += Edit(lb.textRange.endOffset, lb.textRange.endOffset, extraMembers.toString())
    }
}

fun apply(text: String, edits: List<Edit>): String {
    val sorted = edits.sortedWith(compareBy<Edit> { it.start }.thenByDescending { it.end })
    val sb = StringBuilder()
    var pos = 0
    for (e in sorted) {
        if (e.start < pos) continue // nested in an already replaced range
        sb.append(text, pos, e.start)
        sb.append(e.text)
        pos = e.end
    }
    sb.append(text, pos, text.length)
    return sb.toString()
}

// ------------------------------------------------------------------------------------------------ drop
fun drop(f: File, positions: Set<Pair<Int, Int>>, log: File) {
    val text = f.readText()
    val kt = parse(f, text)
    val lineStarts = ArrayList<Int>()
    lineStarts += 0
    text.forEachIndexed { i, ch -> if (ch == '\n') lineStarts += i + 1 }
    val edits = ArrayList<Edit>()
    val logged = StringBuilder()
    val done = HashSet<PsiElement>()
    for ((ln, col) in positions.sortedWith(compareBy({ it.first }, { it.second }))) {
        if (ln - 1 >= lineStarts.size) continue
        val off = minOf(lineStarts[ln - 1] + col - 1, text.length - 1)
        var el: PsiElement? = kt.findElementAt(off)
        var target: PsiElement? = null
        while (el != null && el !is KtFile) {
            if (el is KtValueArgumentList && (el.parent is KtConstructorDelegationCall || el.parent is KtSuperTypeCallEntry) &&
                el.text != "(__kstubHidden = null)") { target = el; break }
            if (el is KtImportDirective) { target = el; break }
            if (el is KtAnnotationEntry && el.parent?.parent !is KtFileAnnotationList) { target = el; break }
            if (el is KtDeclaration && el !is KtParameter && el !is KtPropertyAccessor && el !is KtTypeParameter &&
                (el.parent is KtFile || el.parent is KtClassBody)) { target = el; break }
            if (el is KtFileAnnotationList) { target = el; break }
            if (el is KtPackageDirective) { target = null; break }
            el = el.parent
        }
        if (target == null || !done.add(target)) continue
        val firstLine = target.text.lineSequence().first().take(160)
        logged.append("${f.path}:$ln: ${target.javaClass.simpleName}: $firstLine\n")
        if (target is KtValueArgumentList && target.arguments.isNotEmpty() && target.arguments.all { it.getArgumentExpression()?.text == "TODO()" })
            edits += Edit(target.textRange.startOffset, target.textRange.endOffset, "(__kstubHidden = null)")
        else if (target is KtValueArgumentList) edits += Edit(target.textRange.startOffset, target.textRange.endOffset,
            target.arguments.joinToString(", ", "(", ")") { a ->
                val n = a.getArgumentName()?.asName?.asString()
                (if (a.getSpreadElement() != null) "*" else "") + (if (n != null) "$n = " else "") + "TODO()" })
        else if (target is KtAnnotationEntry || target is KtFileAnnotationList) edits += Edit(target.textRange.startOffset, target.textRange.endOffset, "")
        else removeDecl(target, edits)
    }
    f.writeText(apply(text, edits))
    log.appendText(logged.toString())
}

// Backend crashes on kept (untyped) expression bodies: remove such declarations from one file,
// non-public ones first.
fun dropUntyped(f: File, log: File) {
    val text = f.readText()
    val kt = parse(f, text)
    val cands = ArrayList<KtDeclaration>()
    kt.accept(object : KtTreeVisitorVoid() {
        override fun visitNamedFunction(function: KtNamedFunction) {
            val b = function.bodyExpression
            if (b != null && !function.hasBlockBody() && !function.hasDeclaredReturnType() && b.text != "TODO()" &&
                (function.parent is KtFile || function.parent is KtClassBody)) cands += function
            // do not descend: local declarations are gone anyway
        }
        override fun visitProperty(property: KtProperty) {
            if (property.typeReference == null && (property.parent is KtFile || property.parent is KtClassBody) &&
                (property.initializer != null || property.getter?.bodyExpression != null || property.delegate != null)) cands += property
        }
    })
    val hidden = cands.filter { it.isPrivateOrInternal() }
    val chosen = if (hidden.isNotEmpty()) hidden else cands
    val edits = ArrayList<Edit>()
    val sb = StringBuilder()
    for (d in chosen) { removeDecl(d, edits); sb.append("${f.path}: backend: ${d.text.lineSequence().first().take(140)}\n") }
    f.writeText(apply(text, edits))
    log.appendText(sb.toString())
    println("removed ${chosen.size}")
}
